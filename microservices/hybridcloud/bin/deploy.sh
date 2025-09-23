#!/bin/bash -

#title           :deploy.sh

#description     :This script will deploy the helm charts on CFC.

#version         :0.1

#usage		       :bash deploy.sh

#==============================================================================

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

PATH=/usr/bin:/bin:/usr/sbin:/sbin:${PATH}
source utils/utils.sh
source utils/logging.sh

export PATH
umask 022

if [ "`id -u`" != 0 ]; then
        echo "Must run as root"
        exit 1
fi

ICP_CONFIG_DIR=/opt/ibm/connections
ICP_CONFIG_FILE=config.json
jq=${ICP_CONFIG_DIR}/jq/bin/jq

conn_locn=$(cat $ICP_CONFIG_DIR/$ICP_CONFIG_FILE | $jq -r '.connections_location')
if [ ! -d "${conn_locn}" ]; then
        echo "Cannot determine ICp install directory"
        exit 2
fi
RUNTIME_BINS=${conn_locn}/runtime

PATH=${PATH}:${RUNTIME_BINS}/bin
export PATH

namespace=`grep namespace common_values.yaml | awk '{print $2}'`

# Support different invocation locations associated with this script at different times
repo_top_dir="`dirname \"$0\"`/.."
echo
cd "${repo_top_dir}" > /dev/null
echo "Changed location to repo top level dir:"
echo "  `pwd`"
echo "  (relative path:  ${repo_top_dir})"

function contains() {
    local n=$#
    local value=${!n}
    for ((i=1;i < $#;i++)) {
        if [ "${!i}" == "${value}" ]; then
            echo true
            return 0
        fi
    }
    echo false
    return 1
}

function refreshSanity() {

	configMapName=sanity-config
	configMapKey=services-to-check
	services=""

	IFS='/'
	read -ra servicesSanity <<< "$1"    # str is read into an array as tokens separated by IFS

	if [[ "$(kubectl get configmap -o jsonpath={.items[*].metadata.name} -n ${namespace})" =~ .*sanity-config.* ]]; then
	        
		services=`kubectl get configmap ${configMapName} -n ${namespace} -o jsonpath='{.data.services-to-check}'`
		
		read -ra currentServices <<< "$services"		
	
		for j in "${servicesSanity[@]}"; do    # access each element of array
		if [ $(contains "${currentServices[@]}" "$j") == 'false' ]; then
        	     	echo "Adding $j to the services being monitored by sanity."
	        	services="$services/$j"
		fi
		done                
	else
		echo "Services are blank.  First time install."
		
		for j in "${servicesSanity[@]}"; do    # access each element of array        	
	               	echo "Adding $j to the services being monitored by sanity."
	  	      	services="$services/$j"		
		done

		services=${services#?};
		
	fi
	
	sed -i "s|^servicesToCheck: .*$|servicesToCheck: ${services}|"  bin/common_values.yaml

}

INSTALL_STACK=''

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -ip|--installStack)
      starter_stack=true
      INSTALL_STACK="$2"
      echo "Script performed with -ip|--installStack. The stack ${INSTALL_STACK} will be deployed."
      shift
      ;;
    *)
esac
shift
done

declare -a components=()
set +o nounset
if [[ "$INSTALL_STACK" == 'customizer' ]]; then
	components=("redis" "redis-sentinel" "mongodb" "appregistry-client" "appregistry-service" "haproxy" "mw-proxy" "sanity")
        servicesSanityMonitors="mongo/redis-server/redis-sentinel/appregistry-client/appregistry-service/haproxy-redis/haproxy-redis-events/mw-proxy"
elif [[ "$INSTALL_STACK" == 'elasticsearch' ]]; then
 	components=("elasticsearch" "sanity")
	servicesSanityMonitors="elasticsearch"
elif [[ "$INSTALL_STACK" == 'orientme' ]]; then
	components=("mongodb" "redis" "redis-sentinel" "solr" "zookeeper" "appregistry-client" "appregistry-service" "haproxy" "community-suggestions" "itm-services" "mail-service" "orient-web-client" "orient-indexing-service" "orient-analysis-service" "orient-retrieval-service" "people-scoring" "people-datamigration" "people-relationship" "middleware-graphql" "people-idmapping" "sanity")
 	servicesSanityMonitors="mongo/redis-server/redis-sentinel/solr/zookeeper/appregistry-client/appregistry-service/haproxy-redis/haproxy-redis-events/community-suggestions/itm-services/mail-service/orient-web-client/indexingservice/analysisservice/retrievalservice/people-scoring/people-relation/middleware-graphql/people-idmapping"
elif [[ "$INSTALL_STACK" == '' ]]; then
	components=("mongodb" "redis" "redis-sentinel" "solr" "zookeeper" "elasticsearch" "appregistry-client" "appregistry-service" "haproxy" "mw-proxy" "itm-services" "community-suggestions" "mail-service" "orient-web-client" "orient-indexing-service" "orient-analysis-service" "orient-retrieval-service" "people-scoring" "people-relationship" "people-datamigration" "people-idmapping" "middleware-graphql" "sanity")
	servicesSanityMonitors="mongo/redis-server/redis-sentinel/solr/zookeeper/appregistry-client/appregistry-service/haproxy-redis/haproxy-redis-events/community-suggestions/itm-services/mail-service/orient-web-client/indexingservice/analysisservice/retrievalservice/people-scoring/people-relation/middleware-graphql/people-idmapping/mw-proxy/elasticsearch"
else
	echo "$INSTALL_STACK does not exists"
	exit 1
fi
set -o nounset

echo "Deploying configmap"
bash ./bin/configmap.sh

releases=()
pids=''

if [ $(contains "${components[@]}" 'mongodb') == 'true' ]; then
	echo "Deploying mongodb"
	bash ./bin/mongo-secret.sh
	bash ./bin/mongo.sh &
	pids="$pids $!"
	releases+=('mongodb')
	components=(${components[@]//*mongodb*})
fi

if [ $(contains "${components[@]}" 'zookeeper') == 'true' ]; then
	echo "Deploying Zookeeper"
	bash ./bin/zookeeper.sh &
	pids="$pids $!"
	releases+=('zookeeper')
	components=(${components[@]//*zookeeper*})
fi

if [ $(contains "${components[@]}" 'solr') == 'true' ]; then
	echo "Deploying solr"
	bash ./bin/solr.sh &
	pids="$pids $!"
	releases+=('solr-basic')
	components=(${components[@]//*solr*})
fi

if [ $(contains "${components[@]}" 'redis') == 'true' ]; then
	echo "Deploying redis, sentinel and haproxy"
	bash ./bin/redis.sh &
	pids="$pids $!"
	releases+=('redis' 'redis-sentinel' 'haproxy')
	components=(${components[@]//*redis*})
	components=(${components[@]//*redis-sentinel*})
	components=(${components[@]//*haproxy*})
fi

waitForProcessesToComplete ${pids}

if [ ${#releases[@]} -ne 0 ]; then
	verifyInParallel ${namespace} ${releases[@]}
else
        echo "No infrastructure components required"
fi

refreshSanity $servicesSanityMonitors

echo "Deploy components through helm"
bash ./bin/install_components.sh "${components[@]}"

