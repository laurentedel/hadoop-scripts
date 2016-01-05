# hadoop-scripts

This script was defined to merge tiny regions in HBase : when dealing with a high throughput writing environment, regions can easily multiply even if you sized regions accordingly.
In my case I did calculate 20 GB region size for having around 250 regions. I wasn't expecting this number getting much more than the double with splitting, so I was surprised when regions exceeded 1300 !

Then, having a look on regions, I realized lot of them were tiny regions, so I decided to merge them to get a more decent regions number.

The idea is to launch the script with `./hbase_region_repartition.sh TABLE_NAME THRESHOLD MAX_REGIONS`

*THRESHOLD* means we want to merge adjacent regions not exceeding THRESHOLD percent of region size defined
*MAX_REGIONS* means that we don't want to merge more than MAX_REGIONS at a time
