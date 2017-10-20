#! /usr/bin/env python
##
## The goal here is to define the host mapping file
## from an existing cluster, so we can build the
## same cluster on the exact same machines
##
## For that we need two things which are
## 1. The blueprint, giving (anonymous) hostgroups -> components
## 2. Host components, so we can build hosts -> components
##
## We could then map those two to have our hostmapping file
## which is basically hostgroups -> hosts
##

import requests
import json
import datetime
import getpass

AMBARI_DOMAIN='127.0.0.1'
AMBARI_PORT='8080'
AMBARI_USER_ID='admin'
AMBARI_USER_PW='admin'
restAPI='/api/v1'

# Get cluster name
BASE_API="http://"+AMBARI_DOMAIN+":"+AMBARI_PORT+restAPI;
r=requests.get(BASE_API+"/clusters", auth=(AMBARI_USER_ID, AMBARI_USER_PW))
json_data=json.loads(r.text)
THE_CLUSTER=json_data['items'][0]['Clusters']['cluster_name']
CLUSTER_API=BASE_API+"/clusters/"+THE_CLUSTER

# Get Hosts & Host-Components
url=CLUSTER_API+"/host_components";
r=requests.get(url, auth=(AMBARI_USER_ID, AMBARI_USER_PW))
json_data=json.loads(r.text)
components = json_data["items"]
# got a list of each association host/component so we build the components list for each host
hostmapping1 = {}
for elt in components:
    host=elt['HostRoles']['host_name']
    component = elt['HostRoles']['component_name']
    hostmapping1.setdefault(host, set()).add(component)

hostmapping2={}
for k, v in hostmapping1.items():
    hostmapping2[k]=sorted(set(v))

hostmapping = {}
for k, v in hostmapping2.items():
    hostmapping.setdefault(','.join(v), set()).add(k)

# Get the blueprint so we have all the hostgroups
# We add the cardinality so we can have a check when doing the mapping
url=CLUSTER_API+"?format=blueprint";
r=requests.get(url, auth=(AMBARI_USER_ID, AMBARI_USER_PW))
json_blueprint=json.loads(r.text)
hostgroups = json_blueprint["host_groups"]

blueprint1 = {}
for elt in hostgroups:
    hostgroup=elt['name']
    cardinality=elt['cardinality']
    for component in elt['components']:
        blueprint1.setdefault(hostgroup+"#"+cardinality, set()).add(component['name'])

blueprint2={}
for k, v in blueprint1.items():
    v.discard('AMBARI_SERVER')
    blueprint2[k]=sorted(set(v))

blueprint = {}
for k, v in blueprint2.items():
    blueprint.setdefault(','.join(v), set()).add(k)

# Mapping hostmapping and blueprint
hostgroups=list()
for comp,hostgroup in blueprint.items():
    if comp in hostmapping.keys():
        blueprint_nb = int(''.join(blueprint[comp]).rpartition('#')[-1])
        # If we got the same cardinality between
        # hostmapping and blueprint for that component list
        if blueprint_nb == len(hostmapping[comp]):
            theHostGroup = ''.join(blueprint[comp]).rpartition('#')[0]
            hg={}
            hg['name'] = theHostGroup
            hg['hosts'] = list()
            for host in hostmapping[comp]:
                host2 = {}
                host2['fqdn'] = host
                hg['hosts'].append(host2)
            hostgroups.append(hg)
        else:
          print("ko: hostmapping (",len(hostmapping[comp]) ,") and blueprint hostgroup count (",blueprint_nb ,") doesn't match")

        # Then we unset this key in blueprint and in hostmapping, we got to have 0 at the end
        del blueprint[comp]
        del hostmapping[comp]
    else:
      print "[ERROR] The components list <" + comp + "> doesn't exist in hostmapping?"

# Do we have keys remaining in blueprint and hostmapping?
if blueprint:
    print "[ERROR] blueprint is not fully consumed"

if hostmapping:
    print "[ERROR] hostmapping is not fully consumed"

# [TBD] Ending the remaining process by matching with proposals?

HOSTMAPPING={}
HOSTMAPPING['host_groups'] = hostgroups
HOSTMAPPING['Clusters'] = {"cluster_name": components[0]['HostRoles']['cluster_name']}

# find if cluster is secured
url_sec=CLUSTER_API+"?fields=Clusters/security_type"
s=requests.get(url_sec, auth=(AMBARI_USER_ID, AMBARI_USER_PW))
json_data_s=json.loads(s.text)
sec = json_data_s['Clusters']['security_type']
if sec == "KERBEROS":
    HOSTMAPPING['security'] = {"type": "KERBEROS"}
    url_kerberos=CLUSTER_API+"/configurations/service_config_versions?service_name=KERBEROS&is_current=true"
    k=requests.get(url_kerberos, auth=(AMBARI_USER_ID, AMBARI_USER_PW))
    json_data_k=json.loads(k.text)

    # json_data_k["items"][0]['configurations'] contains kerberos-env and krb5-conf, without order garantee
    # so finding the index of kerberos-env first to have the array element we need
    #TODO exception if idx is not found!
    idx = next(index for (index, d) in enumerate(json_data_k["items"][0]['configurations']) if d["type"] == "kerberos-env")
    
    security = json_data_k["items"][0]['configurations'][idx]['properties']["kdc_type"]
    if security == 'mit-kdc':
        principal = json_data_k["items"][0]['user'] + "/admin@" + json_data_k["items"][0]['configurations'][idx]['properties']['realm']
    if security == 'active-directory':
        principal = json_data_k["items"][0]['user'] + "@" + json_data_k["items"][0]['configurations'][idx]['properties']['realm']

    KDC_ADMIN = raw_input("Enter KDC admin principal [" + principal + "]: ") or principal
    while True:
        KDC_PASSWD = getpass.getpass("Enter KDC admin password [admin]: ") or "admin"
        KDC_PASSWD2 = getpass.getpass("Enter KDC admin password again: ") or "admin"
        if KDC_PASSWD != KDC_PASSWD2:
            print("[ERROR] passwords doesn't match")
        else:
            break
    while True:
        DEFAULT_PASSWD = getpass.getpass("Enter default password for all required passwords which are not specified in the blueprint or cluster creation template configurations [hadoop]: ") or "hadoop"
        DEFAULT_PASSWD2 = getpass.getpass("Enter default password again: ") or "hadoop"
        if DEFAULT_PASSWD != DEFAULT_PASSWD2:
            print("[ERROR] passwords doesn't match")
        else:
            break
    DEFAULT_BLUEPRINT_NAME="blueprint_" + datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    BLUEPRINT_NAME = raw_input("Enter Blueprint name [" + DEFAULT_BLUEPRINT_NAME + "]: ") or DEFAULT_BLUEPRINT_NAME

    HOSTMAPPING['default_password'] = DEFAULT_PASSWD
    HOSTMAPPING['credentials'] = '[{"alias": "kdc.admin.credential","principal": "' + KDC_ADMIN + '","key": "' + KDC_PASSWD + '","type": "TEMPORARY"}]'
    HOSTMAPPING['blueprint'] = BLUEPRINT_NAME

# Dumping that :)
with open('hostmap.json', 'w+') as outfile:
    json.dump(HOSTMAPPING, outfile)

with open('blueprint.json', 'w+') as outfile:
    json.dump(json_blueprint, outfile)

print("blueprint.json and hostmap.json exported in the current directory")
quit()
