#!/bin/bash -
#title           :update-configmaps.sh
#description     :This script will update K8 configmaps on CFC.
#version         :0.1
#usage		       :bash update-configmaps.sh <ConfigMaps Name> <Key Name> <Key Value>
#==============================================================================

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

logErr() {
  logIt "ERRO: " "$@"
}

logInfo() {
  logIt "INFO: " "$@"
}

logIt() {
    echo "$@"
}

usage() {
  logIt ""
  logIt "Usage: update-configmap.sh <ConfigMaps Name> <Key Name> <Key Value> "
  logIt ""
  logIt "update-configmap.sh connections-env redis-auth-enabled true"
  logIt ""
  logIt "or for values that contain spaces e.g.{ host: redis, port: 6379 } than wrap value in double quotes e.g."
  logIt ""
  logIt "update-configmap.sh connections-env redis-options \"{ host: redis, port: 6379 }\""
  logIt ""
}


if [ "$#" != "3" ]; then
  usage
  exit 1
fi

configMapName=$1
configMapKey=$2
configMapValue=$3

commonProcedure() {

  set +o errexit
  if [ "`kubectl get configmaps ${configMapName}`" = "" ]; then
    logIt "Hint - This script is intended to execute on existing environments and configmap that requires updating is already configured."
    exit 2
  fi
  set -o errexit
}


updateConfigMap() {

  kubectl get configmaps ${configMapName} -o json \
    | sed "s@\"${configMapKey}\".*@\"${configMapKey}\" : \"${configMapValue}\",@" \
    | kubectl replace -f -

  if [ $? -ne 0 ]; then
    exit 3
  fi
  set -o errexit
}

addKeyToConfigMap() {
  keyvaluepair="\"${configMapKey}\": \"${configMapValue}\","
  echo ${keyvaluepair}
  kubectl get configmaps ${configMapName} -o yaml \
    | sed "/^data:/a \\  ${configMapKey}: \"${configMapValue}\"" \
    | kubectl replace -f -

  if [ $? -ne 0 ]; then
    exit 3
  fi
  set -o errexit
}

#Check at least configmaps in K8 exist. If not present than this script should not run.
commonProcedure

if [ "`kubectl get configmaps connections-env -o jsonpath={.data.${configMapKey}}`" = "" ]; then
  addKeyToConfigMap
else
  updateConfigMap
fi;
