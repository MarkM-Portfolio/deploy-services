#! /bin/bash

#title           :configurationDriver.sh
#description     :This script runs the redis and reverse proxy configures neededto connect Blue to Pink.
#version         :0.1
#usage           :configurationDriver.sh <Path to zip base dir containing the install.sh> <ConnectionsHostname> <ConnectionsServerRootPassword> <CfC_Master> <wasAdminUser> <wasAdminPassword>
####

USAGE="
USAGE: configurationDriver.sh <Path to zip base dir containing the install.sh> <ConnectionsHostname> <ConnectionsServerRootPassword> <HTTPServerPath> <CfC_Master> <wasAdminUser> <wasAdminPassword> <wasPath>

EXAMPLE: configurationDriver.sh /opt/hybrid/microservices/hybridcloud connectionsDMGR.example.com connections-root-password /opt/IBM/HTTPServer cfc-master.example.com wasAdminUser wasAdminPassword /opt/IBM/WebSphere

Note: the master must be the master node for non-HA or the master VIP for HA
"

if [[ "$1" = "-h" ]] || [[ "$1" = "--help" ]]; then
	echo "${USAGE}"
        exit 1
fi

if [ $# -lt 8 ] || [ $# -gt 8 ]; then
	echo "Error! Must fix arguments!"
	echo "${USAGE}"
	exit 1
fi 

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

umask 022

templatesFolder=""
connectionsHostname=$2
echo "CONNECTIONS HOSTNAME = $connectionsHostname"
connectionsRootPassword=$3
http_server_path=""
master=$5
wasAdminUser=$6
wasAdminPassword=$7
wasPath=""
conn_locn=""
ICP_CONFIG_DIR=/opt/ibm/connections
ICP_CONFIG_FILE=config.json
jq=${ICP_CONFIG_DIR}/jq/bin/jq


if [[ "$1" == */ ]]; then
	templatesFolder="$1"
else
	templatesFolder=$1"/"
fi

if [[ "$8" == */ ]]; then
	wasPath="$8"
else
	wasPath=$8"/"
fi 

if [[ "$4" == */ ]]; then
	http_server_path="$4"
else
	http_server_path=$4"/"
fi

function error_cleanup () {
	echo
	echo "Failed to setup SSH keys across all nodes.  Address problem and re-run."
	echo
	echo "$2"
	echo
	exit 1
}

function resolve_ip() {
        set +o errexit
        set -o pipefail
        set +o nounset

        if [ "$1" = "" ]; then
                echo "usage:  resolve_ip sHost"
                exit 100
        fi
        host=$1
        set -o nounset
        resolve_ip_return_result=""

        if [ "`echo ${host} | sed 's/\.//g' | sed 's/[0-9]*//'`" = "" ]; then
                # ipv4 address, already theoretically resolved
                # not handling ipv6 yet
                # but make sure it is a valid ipv4 address
                octet_count=0
                for octet in `echo ${host} | sed 's/\./ /g'`; do
                        if [ ${octet} -lt 1 -o ${octet} -gt 255 ]; then
                                echo "IP address has invalid octet ranges:  ${host}"
                                return 101
                        fi
                        octet_count=`expr ${octet_count} + 1`
                done
                if [ ${octet_count} -ne 4 ]; then
                        echo "IP address has invalid number of octets:  ${host}"
                        return 101
                fi

                resolve_ip_return_result="${host}"
                return 0
        fi

        resolve_ip_return_result=`host ${host} | grep "has address" | head -1 | awk '{ print $NF }'`
        if [ "${resolve_ip_return_result}" = "" ]; then
                echo "${host} is not resolvable with host, trying alternative"
                resolve_ip_return_result=`ping -c 1 ${host} 2>&1 | grep '^PING ' | grep 'bytes of data.$' | awk '{ print $3 }' | sed -e 's/(//' -e 's/)//'`
                if [ "${resolve_ip_return_result}" = "" ]; then
                        echo "${host} is not resolvable with ping, giving up"
                        return 102
                fi
        fi
}

function getPort (){
        service=$1
        kubectl get svc --all-namespaces | grep $service > /tmp/foundNamespace.csv
        namespace=`cat /tmp/foundNamespace.csv | awk '{print $1}'`
        serviceDetail=`kubectl get svc ${service} --namespace ${namespace}`
        port=`echo ${serviceDetail} | cut -d":" -f2 | cut -d"/" -f1`
        echo ${port}
}

ssh_args="-o StrictHostKeyChecking=no"
function setup_ssh () {
        set +o errexit
        node=$1
        resolve_ip ${node}      # result in resolve_ip_return_result
        if [ $? -ne 0 ]; then
                echo "Unable to resolve ${node}"
                exit 1
        else
                ip=${resolve_ip_return_result}
        fi
	echo "Starting key setup"
	# Get ICp connections installation location
	conn_locn=$(cat $ICP_CONFIG_DIR/$ICP_CONFIG_FILE | $jq -r '.connections_location')
	if [ ! -d "${conn_locn}" ]; then
		echo "Cannot determine ICp install directory"
		exit 2
	else
	       	echo "Conn_Locn = $conn_locn"
	fi
        $conn_locn/sshpass/bin/sshpass -p ${connectionsRootPassword} ssh-copy-id ${ssh_args} -i keys_dir/ssh_key root@${ip} || error_cleanup 4 "ssh_key copy failure to node ${node} (no prompt)"
        set -o errexit
        ssh ${ssh_args} -i keys_dir/ssh_key root@${ip} "echo Successful ssh key setup for root@${host}"
        echo
}

mkdir -p keys_dir
set +o errexit
echo y | ssh-keygen -t rsa -f keys_dir/ssh_key -P '' || error_cleanup 2 "ssh-keygen failure (no prompt)"
set -o errexit
chmod 600 keys_dir/ssh_key
setup_ssh ${connectionsHostname}
set -o errexit

keys="-i keys_dir/ssh_key"

echo "Start HTTPServer"
ssh -o StrictHostKeyChecking=no ${keys} root@${connectionsHostname} "${http_server_path}bin/envvars-std"
ssh -o StrictHostKeyChecking=no ${keys} root@${connectionsHostname} "${http_server_path}bin/apachectl start"
ssh -o StrictHostKeyChecking=no ${keys} root@${connectionsHostname} "rm -rf /opt/configureReverseProxy.sh"
scp -i keys_dir/ssh_key configureReverseProxy.sh root@${connectionsHostname}:/opt/configureReverseProxy.sh

echo "Configure lotus connections"
echo "Stop clusters to let system update configuration of lotus connection"
scp -i keys_dir/ssh_key configureBlue-stopCluster.py.erb root@${connectionsHostname}:/opt/configureBlue-stopCluster.py.erb
echo "connectionsHostname = $connectionsHostname"
clusterLocation=`ssh -o StrictHostKeyChecking=no ${keys} root@${connectionsHostname} "ls ${wasPath}AppServer/profiles/Dmgr01/config/temp/download/cells/"`
files=`ssh -o StrictHostKeyChecking=no ${keys} root@${connectionsHostname} "ls ${wasPath}AppServer/profiles/Dmgr01/config/temp/download/cells/${clusterLocation}/clusters/"`
clusters=($files)
for cluster in "${clusters[@]}"
do
	ssh -o StrictHostKeyChecking=no ${keys} root@${connectionsHostname} "${wasPath}AppServer/profiles/Dmgr01/bin/wsadmin.sh -lang jython -f /opt/configureBlue-stopCluster.py.erb ${cluster} -user ${wasAdminUser} -password ${wasAdminPassword}"
done
ssh -o StrictHostKeyChecking=no ${keys} root@${connectionsHostname} "${wasPath}AppServer/profiles/AppSrv01/bin/stopNode.sh -username ${wasAdminUser} -password ${wasAdminPassword}"
ssh -o StrictHostKeyChecking=no ${keys} root@${connectionsHostname} "${wasPath}AppServer/profiles/AppSrv02/bin/stopNode.sh -username ${wasAdminUser} -password ${wasAdminPassword}"
ssh -o StrictHostKeyChecking=no ${keys} root@${connectionsHostname} "rm -rf /opt/configureLotusConnections.sh"
pwd=$(pwd)
scp -i keys_dir/ssh_key configureLotusConnections.sh root@${connectionsHostname}:/opt/configureLotusConnections.sh
ssh -o StrictHostKeyChecking=no ${keys} root@${connectionsHostname} "bash /opt/configureLotusConnections.sh ${wasAdminUser} ${wasAdminPassword} ${wasPath}"

echo "Ensure connections blue is up for redis configuration"
ssh -o StrictHostKeyChecking=no ${keys} root@${connectionsHostname} "${wasPath}AppServer/profiles/AppSrv01/bin/startNode.sh"
ssh -o StrictHostKeyChecking=no ${keys} root@${connectionsHostname} "${wasPath}AppServer/profiles/AppSrv02/bin/startNode.sh"
scp -i keys_dir/ssh_key configureBlue-startCluster.py.erb root@${connectionsHostname}:/opt/configureBlue-startCluster.py.erb
for cluster in "${clusters[@]}"
do
        ssh -o StrictHostKeyChecking=no ${keys} root@${connectionsHostname} "${wasPath}AppServer/profiles/Dmgr01/bin/wsadmin.sh -lang jython -f /opt/configureBlue-startCluster.py.erb ${cluster} -user ${wasAdminUser} -password ${wasAdminPassword}"
done

mailPort=""
orientPort=""
itmPort=""
appregistryClientPort=""
appregistryServicePort=""
communitySuggestionsPort=""

getPort "mail-service"
mailPort=${port}
getPort "orient-web-client"
orientPort=${port}
getPort "itm-services"
itmPort=${port}
getPort "haproxy-redis"
redisPort=${port}
getPort "appregistry-client"
appregistryClientPort=${port}
getPort "appregistry-service"
appregistryServicePort=${port}
getPort "community-suggestions"
communitySuggestionsPort=${port}

echo "master = ${master}"
echo "redisPort = ${redisPort}"
echo "connectionsHostname = ${connectionsHostname}"
bash configureRedis.sh -cfc ${master} -po $redisPort -ic http://$connectionsHostname || exit 1
bash configureRedis.sh -cfc ${master} -po $redisPort -ic https://$connectionsHostname || exit 1

echo "Configure Reverse Proxy"
 
ssh ${ssh_args} -i keys_dir/ssh_key root@${connectionsHostname} "cd /opt/ ; chmod 755 configureReverseProxy.sh ; yes | ./configureReverseProxy.sh http://${master} $orientPort $itmPort $appregistryClientPort $appregistryServicePort $communitySuggestionsPort ${http_server_path}/ -y" || exit 1

echo "Configuration Complete"

