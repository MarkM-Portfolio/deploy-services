#!/bin/bash -
#title           :redis.sh
#description     :This script will deploy Redis application using helm or K8s on CFC.
#version         :0.1
#usage                 :bash redis.sh
#==============================================================================
#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

PATH=/usr/bin:/bin:/usr/sbin:/usr/local/bin:/sbin:${PATH}
export PATH
umask 022

source bin/utils/logging.sh
source bin/utils/helm.sh

components=("redis" "redis-sentinel" "haproxy")

for component in ${components[@]}; do
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
done
