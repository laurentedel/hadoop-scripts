#!/bin/bash
AMBARI_HOST=sandbox.hortonworks.com
CLUSTER_NAME=Sandbox
AMBARI_USER=admin
AMBARI_PASSWORD=admin
AMBARI_PORT=8080
timeNow=`date +%Y%m%d_%H%M%S`
RESULT_DIR=/root/migrationHDP/configs.sh/$timeNow
mkdir -p $RESULT_DIR
for CONFIG_TYPE in `curl -s -u $AMBARI_USER:$AMBARI_PASSWORD http://$AMBARI_HOST:$AMBARI_PORT/api/v1/clusters/$CLUSTER_NAME/?fields=Clusters/desired_configs | grep '" : {' | grep -v Clusters | grep -v desired_configs | cut -d'"' -f2`; do
  echo "backuping $CONFIG_TYPE"
  /var/lib/ambari-server/resources/scripts/configs.sh -u $AMBARI_USER -p $AMBARI_PASSWORD -port $AMBARI_PORT get $AMBARI_HOST $CLUSTER_NAME $CONFIG_TYPE | grep '^"' | grep -v '^"properties" : {' | sed "1i ##### $CONFIG_TYPE #####" >> $RESULT_DIR/all.conf
done
