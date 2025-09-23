#!/bin/bash -
#title           :solr.sh
#description     :This script will deploy solr using helm or K8s on CFC.
#version         :0.3
#usage		       :bash solr.sh
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

source bin/utils/logging.sh
source bin/utils/helm.sh
source bin/utils/utils.sh

release=solr-basic

isExistingRelease solr-basic
exists=$?

solr_charts_dir="$(dirname $(cd $(dirname $0) && pwd))/helmbuilds/${release}"
# Get the helm version
solr_helm=`ls -v ${solr_charts_dir}/solr-*.tgz | tail -n 1`
namespace=`grep namespace bin/common_values.yaml | awk '{print $2}'`

# Helm install 
if [[ -f ${solr_helm} ]];then
    # Fixed in ICp 2.1.0.2 (ICp issue #4409)
    delete ${release}
    deploy ${release} $solr_helm --values=bin/common_values.yaml
	if [ $? -eq 0 ];then
        logInfo "Helm deploy done"
    else
        logErr "Failed to deploy solr"
    fi        
else
    echo "Can't find chart in $solr_charts_dir"
fi

# if [ ${exists} -ne 0 ]; then
#     verify ${release} ${namespace}
# fi

logInfo "Done!"
