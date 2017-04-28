#!/bin/bash
AMBARI_HOST=sandbox.hortonworks.com
CLUSTER_NAME=Sandbox
AMBARI_USER=admin
AMBARI_PASSWORD=admin
AMBARI_PORT=8080
AMBARI_PROTOCOL=http
# set to empty if non secure
AMBARI_SECURE="-s"
TIMENOW=`date +%Y%m%d_%H%M%S`
RESULT_DIR=/root/configs
mkdir -p $RESULT_DIR
for CONFIG_TYPE in `curl -k -s -u $AMBARI_USER:$AMBARI_PASSWORD $AMBARI_PROTOCOL://$AMBARI_HOST:$AMBARI_PORT/api/v1/clusters/$CLUSTER_NAME/?fields=Clusters/desired_configs | grep '" : {' | grep -v Clusters | grep -v desired_configs | cut -d'"' -f2`; do
  echo "backuping $CONFIG_TYPE"
  /var/lib/ambari-server/resources/scripts/configs.sh -u $AMBARI_USER -p $AMBARI_PASSWORD -port $AMBARI_PORT $AMBARI_SECURE get $AMBARI_HOST $CLUSTER_NAME $CONFIG_TYPE | grep '^"' | grep -v '^"properties" : {' | sed "1i ##### $CONFIG_TYPE #####" >> $RESULT_DIR/all.conf.$TIMENOW
done
