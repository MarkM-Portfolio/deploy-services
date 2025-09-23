#! /bin/bash
# Initial author: on Thur 11th May 2017
#
# History:
# --------
# Thur 11th May 2017 15:26:49 GMT 2017
#	Initial version

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

update_dir="`dirname \"$0\"`"
cd "${update_dir}" > /dev/null

set +o nounset
# Default admin credentials
if [ "${ADMIN_USER}" = "" ]; then
	ADMIN_USER=admin
else
	echo "Overriding ADMIN_USER=${ADMIN_USER}"
fi
if [ "${ADMIN_PASSWD}" = "" ]; then
	ADMIN_PASSWD=admin
else
	echo "Overriding ADMIN_PASSWD=${ADMIN_PASSWD}"
fi
set -o nounset
export ADMIN_USER ADMIN_PASSWD
LOG_FILE=/var/log/cfc.log
PRG=`basename ${0}`
HOSTNAME=`hostname -f`


USAGE="
usage:  ${PRG}
	[--help]

Example:
	bash fixpack_01.sh
"

(

echo
set +o nounset
if [ "$1" = --help ]; then
	echo "${USAGE}"
	exit 0
fi
set -o nounset

# Update / Add configmap with Redis values. No checks if existing system
# has been incorrectly configured.
ic_host=`kubectl get configmap ${HOSTNAME} -o jsonpath='{.data.ic-host}'`

./update-configmaps.sh "connections-env" "redis-options" "{ host: haproxy-redis, port: 6379 }"
./update-configmaps.sh "connections-env" "redis-auth-enabled"	"true"
./update-configmaps.sh "connections-env" "ic-auth-token-name"	"LtpaToken2"
./update-configmaps.sh "connections-env" "redis-sentinel-node-service-name" "redis-sentinel"
./update-configmaps.sh "connections-env" "redis-sentinel-node-service-port" "26379"
./update-configmaps.sh "connections-env" "redis-node-service-name" "haproxy-redis"

# As per GIT Task #3649
./update-configmaps.sh "connections-env" "orient-cnx-interservice-port" "443"
./update-configmaps.sh "connections-env" "orient-cnx-interservice-scheme" "https"

#Declare Components and deploy in order.
declare -a arr=("mongodb-rs-setup" "mongodb" "solr" "redis" "haproxy" "zookeeper" "orient-web-client" "indexing-service" "retrieval-service" "analysis-service" "people-relationship" "people-scoring" "mail-service" "itm-services" "people-datamigration")

for fix in ${arr[@]}; do
	echo
	echo
	echo "Checking ${fix} is present in fixpack_01"
	if [ ! -d ${fix} ]; then
		echo "Ignoring ${fix} as not present in this iFix"
	else
		echo
		echo "Deploying ${fix}"
		bash deployUpdates.sh ${fix}
	fi

done

) 2>&1 | tee -a ${LOG_FILE}
