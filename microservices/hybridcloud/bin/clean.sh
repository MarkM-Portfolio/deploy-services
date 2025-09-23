#!/bin/bash -
#title           :clean.sh
#description     :Clean up script.
#version         :0.1
#usage		       :bash clean.sh
#==============================================================================

PATH=/usr/bin:/bin:/usr/sbin:/sbin:${PATH}
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

# Support different invocation locations associated with this script at different times
bin_dir="`dirname \"$0\"`"
echo
cd "${bin_dir}" > /dev/null
echo "Changed location to bin:"
echo "  `pwd`"
echo "  (relative path:  ${bin_dir})"

echo "Remove middleware"
middleware=("zookeeper" "solr-basic" "mongodb" "redis" "redis-sentinel" "haproxy")

for component in "${middleware[@]}"
do
        echo "Removing $component"
        helm delete $component --purge
done

applications=("orient-web-client" "orient-indexing-service" "orient-analysis-service" "itm-services" "orient-retrieval-service" "people-scoring" "mail-service" "people-datamigration" "people-relationship" "people-idmapping" "appregistry-client" "appregistry-service" "connections-env" "middleware-graphql" "mw-proxy" "community-suggestions" "elasticsearch" "sanity" )

echo "Remove Applications"

for app in "${applications[@]}"
do
        echo "Removing $app"
        helm delete $app --purge
done

