#!/bin/bash -
#title           :mongo.sh
#description     :This script will deploy Mongo application using helm or K8s on CFC.
#version         :0.2
#usage                 :bash mongo.sh
#==============================================================================
#!/bin/bash

#set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

PATH=/usr/bin:/bin:/usr/sbin:/sbin:${PATH}
export PATH
umask 022

if [ "`id -u`" != 0 ]; then
	echo "Must run as root"
	exit 1
fi

source bin/utils/logging.sh
source bin/utils/helm.sh
source bin/utils/utils.sh

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

release=mongodb
namespace=`grep namespace bin/common_values.yaml | awk '{print $2}'`

set +e
isExistingRelease ${release}
exists=$?

set +o nounset
mongo_charts_dir="$(dirname $(cd $(dirname $0) && pwd))/helmbuilds/${release}"

# Get the helm version
mongo_helm=`ls -v ${mongo_charts_dir}/mongodb-*.tgz | tail -n 1`
set -o nounset

# PVs health check
PVs=$(kubectl get pv | grep mongo-connections-persistent-storage-mongo- | awk '{ print $1,$4 }')
PVs_N=( $PVs )
PVs_N=${#PVs_N[@]}
if [[ $PVs_N -ne 6 ]]; then
    logErr "Persistent Volumes not found. Please provision the PVs: mongo-persistent-storage-mongo-0, mongo-persistent-storage-mongo-1 and mongo-persistent-storage-mongo-2. Exiting."
    exit 1
fi

# Helm install
if [[ -f ${mongo_helm} ]];then
    getReleaseValue ${release} x509Enabled
    if [[ -n ${HELM_DATA} ]];then
        x509Enabled=${HELM_DATA}
    else
        x509Enabled=true
    fi
    deploy ${release} $mongo_helm --values=bin/common_values.yaml --set x509Enabled=${x509Enabled}
    if [ $? -eq 0 ];then
        logInfo "Mongodb deployment completed"
    else
        logErr "Failed to deploy mongo"
    fi
else
    logErr "Can't find chart in $mongo_charts_dir"
fi


# if [ ${exists} -ne 0 ]; then
    # verify ${release} ${namespace}
# fi
# sleep 30

# logIt ""
# logInfo "Mongo PODs started successfully! Setting up ReplicaSet..."
# Sleeping to ensure all mongodb-sidecar container have started successfuly
# sleep 30
# logIt ""
# kubectl get pods -n $namespace | grep mongo
logInfo "Done!"
logInfo "Check the MongoDB RS by performing: "
logIt "kubectl exec -it mongo-0 -- mongo mongo-0.mongo:27017 --eval \"rs.status()\""

logInfo "Done!"
