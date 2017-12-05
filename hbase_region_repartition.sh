#!/bin/bash
if [ $# -eq 0 ]
  then
    echo "Usage : $0 TABLE_NAME [THRESHOLD_MERGE (default 5%)] [LIMIT_NUMBER_REGIONS_TO_MERGE] "
    exit 2
fi

THE_TABLE=$1
sep=':'
case $THE_TABLE in
  (*"$sep"*)
    NAMESPACE=${THE_TABLE%%"$sep"*}
    TABLE=${THE_TABLE#*"$sep"}
    ;;
  (*)
    NAMESPACE="default"
    TABLE=${THE_TABLE}
    ;;
esac

THRESHOLD_MERGE=${2:-5}
MAX_REGIONS_TO_MERGE=${3:-25}
kinit -kt /etc/security/keytabs/hbase.headless.keytab hbase

# get target region size defined in table desc
# if it's not, then exit
echo "get region size"
REGION_SIZE=$(echo "describe '$THE_TABLE'" | hbase shell | grep $TABLE | grep -v describe | grep -v Table | sed -e "s/.*{MAX_FILESIZE => '\([^']*\)'.*/\1/")
re='^[0-9]+$'
if ! [[ $REGION_SIZE =~ $re ]] ; then
   echo "Error: region size is not a number" >&2; exit 1
fi

rm -f /tmp/file*

# get regions sizes
echo "get regions sizes"
hdfs dfs -du /apps/hbase/data/data/$NAMESPACE/$TABLE | awk -F"/" ' { t = $1; $1 = $NF; $2 = t; print $NF"\t"$2;} ' > /tmp/file1

# get adjacent regions from HBase
# get rid of "OFFLINE => true" messages occuring when regions are splitting
echo "get adjacent regions"
REGIONS=$(echo "scan 'hbase:meta',{COLUMNS => 'info:regioninfo', FILTER=>\"PrefixFilter('$THE_TABLE')\"}" | hbase shell | grep "$THE_TABLE," | grep -v "^scan");
echo "$REGIONS" | grep -v OFFLINE | sed -e 's/.*{ENCODED => \([^,]*\).*/\1/' > /tmp/file2

# Use awk to put the region from file2 as an extra column in front of file1.
# remove lines starting with blank (ie which are NOT in /tmp/file2)
# Sort the result by that column.
# Then remove that prefix column
awk 'FNR == NR { lineno[$1] = NR; next}
     {print lineno[$1], $0;}' /tmp/file2 /tmp/file1 | sed '/^[ ]/d' | sort -k 1,1n | cut -d' ' -f2- > /tmp/file3

# add region percentage of max region size for each region
awk '{ printf $1"\t"$2"\t""%.0f", $2*100/'$REGION_SIZE'; print ""}' /tmp/file3 > /tmp/file4

echo "$TABLE contains $(cat /tmp/file3 | wc -l) regions"

# awk script takes all adjacent regions with both occupation less than threshold
# and export it in /tmp/file5 to be executed in hbase shell
/tmp/a.awk -v THRESHOLD=$THRESHOLD_MERGE < /tmp/file4 > /tmp/file5
head -n $MAX_REGIONS_TO_MERGE /tmp/file5 > /tmp/file6

read -p "$(cat /tmp/file6 | wc -l) COMMANDS TO BE EXECUTED, PROCEED ? y/n " -n 1 -r
echo ""

# add "exit" command at the end of the command file
echo exit >> /tmp/file6

if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    exit 1
else
  echo "executing $(cat /tmp/file6)"
  hbase shell /tmp/file6
fi

# Look for compactions now that we execute some merging,
# we're not supposed to execute the script on compacting regions
while true
do
  COMPACTIONS=$(echo "status 'detailed'" | hbase shell | sed -n '/'$TABLE'/{n;p}' | grep -v " compactionProgressPct=1.0" | sed -e 's/.*numberOfStorefiles=\([^,]*\).*compactionProgressPct=\(.*\).*/Compaction of \1 storeFiles completed at \2 %/')
  if [[ "$COMPACTIONS" == '' ]]; then
    echo "NO MORE COMPACTIONS, ENDING PROCESS"
    break
    exit 0
  else
    echo ""
    echo "$COMPACTIONS"
    sleep 10
  fi
done
echo "end"
