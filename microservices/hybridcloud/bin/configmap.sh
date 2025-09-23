#!/bin/bash -
#title           :configmap_install.sh
#description     :This script will deploy configmap using helm.
#version         :0.1
#usage           :bash configmap_install.sh
#==============================================================================
#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

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

component="connections-env"

charts_dir="$(dirname $(cd $(dirname $0) && pwd))/helmbuilds/$component"

# Get the helm version
helm_component=`ls -v ${charts_dir}/${component}-*.tgz | tail -n 1`

if [[ -f ${helm_component} ]];then
	deploy $component $helm_component --values=bin/common_values.yaml
	if [ $? -eq 0 ];then
		logInfo "Helm deployment for $component done"
	else
		logErr "Failed to deploy $component using helm"
	fi
else
	echo "Can't find chart in $charts_dir"
fi
#done
