#!/bin/bash -
#title           :install_components.sh
#description     :This script will deploy applicationis using helm.
#version         :0.1
#usage                 :bash install_components.sh
#==============================================================================
#!/bin/bash

set -o errexit
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

deployComponents() {

	for component in $@; do
        charts_dir="$(dirname $(cd $(dirname $0) && pwd))/helmbuilds/$component"

        # Get the helm version
        helm_component=`ls -v ${charts_dir}/${component}-*.tgz | tail -n 1`
        if [[ ${component} == "sanity" ]]; then
            
            if [[ -f ${helm_component} ]];then
                deploy $component $helm_component --values=bin/common_values.yaml
                if [ $? -ne 0 ];then
                    logErr "Failed to deploy $component using helm"
                    exit 1
                fi
            fi
        else
            if [[ -f ${helm_component} ]];then
                if [[ $helm_component =~ itm-services ]]; then
                    deploy $component $helm_component --values=bin/common_values.yaml --set service.nodePort=31100
                    if [ $? -ne 0 ];then
                        logErr "Failed to deploy $component using helm"
                        exit 1
                    fi
                elif [[ $helm_component =~ web-client ]]; then
                    deploy $component $helm_component --values=bin/common_values.yaml --set service.nodePort=30001
                    if [ $? -ne 0 ];then
                        logErr "Failed to deploy $component using helm"
                        exit 1
                    fi
                elif [[ $helm_component =~ mail-service ]]; then
                    deploy $component $helm_component --values=bin/common_values.yaml --set service.nodePort=32721
                    if [ $? -ne 0 ];then
                        logErr "Failed to deploy $component using helm"
                        exit 1
                    fi
                                elif [[ $helm_component =~ community-suggestions ]]; then
                    deploy $component $helm_component --values=bin/common_values.yaml --set service.nodePort=32200
                    if [ $? -ne 0 ];then
                        logErr "Failed to deploy $component using helm"
                        exit 1
                    fi
                else
                    deploy $component $helm_component --values=bin/common_values.yaml
                    if [ $? -eq 0 ];then
                        logInfo "Helm deployment for $component done"
                    else
                        logErr "Failed to deploy $component using helm"
                    fi
                fi
            else
                echo "Can't find chart in $charts_dir"
            fi
        fi
	done
}

components=("$@")
deployComponents ${components[@]}
