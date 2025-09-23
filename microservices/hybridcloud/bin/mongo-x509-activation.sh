#!/bin/bash

PATH=/opt/ibm/connections/jq/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH}
export PATH
umask 022

ICP_CONFIG_DIR=/opt/ibm/connections
ICP_CONFIG_FILE=config.json
jq=${ICP_CONFIG_DIR}/jq/bin/jq

conn_locn=$(cat $ICP_CONFIG_DIR/$ICP_CONFIG_FILE | $jq -r '.connections_location')
if [ ! -d "${conn_locn}" ]; then
        echo "Cannot determine ICp install directory"
        exit 1
fi
RUNTIME_BINS=${conn_locn}/runtime

PATH=${PATH}:${RUNTIME_BINS}/bin
export PATH

PRG=`basename ${0}`

logIt() { echo "$(date +[%d/%m/%Y" "%T" "%Z]) $@"; }
logInfo() { logIt "INFO: " "$@"; }
logErr() { logIt "ERRO: " "$@"; }

command -v jq >/dev/null 2>&1 || { echo >&2 "'jq' must be installed and available in the PATH environment variable. Script aborted."; exit 1; }

NAMESPACE=""
ACTIVATE=""
CHART_NAME=""
CHART_ADDR=""

USAGE="
usage:  ${PRG}

  Required arguments:
    --namespace=<Kubernetes namepsace. Eg: connections, default, etc...>
    --x509Enabled=< true | false >
    --chartName=< Helm chart name used to install MongoDB. You can find out by performing: 'helm list | grep -i mongo' >
    --chartPath=< Full path to the chart file *.tgz >

  Usage examples:

    Activating X509:
      ./${PRG} --namespace=connections --x509Enabled=true --chartName=mongodb --chartPath=/root/Downloads/deployment/helm/mongodb/mongodb-0.1.0.tgz

    Deactivating X509:
      ./${PRG} --namespace=connections --x509Enabled=false --chartName=mongodb --chartPath=/root/Downloads/deployment/helm/mongodb/mongodb-0.1.0.tgz
"

for arg in $*; do

  echo ${arg} | grep -q -e --namespace=
  if [ $? -eq 0 ]; then
    NAMESPACE=`echo ${arg} | awk -F= '{ print $2 }'`
    if [[ $(kubectl get namespaces | grep ${NAMESPACE} | wc -l) -lt 1 ]]; then
      logErr "Namespace '${NAMESPACE}' informed in the argument '--namespace=' not found in this kubernetes cluster."
      echo "${USAGE}"
      exit 1
    fi
  fi

  echo ${arg} | grep -q -e --x509Enabled=
  if [ $? -eq 0 ]; then
    ACTIVATE=`echo ${arg} | awk -F= '{ print $2 }'`
    if [[ ${ACTIVATE} != "true" && ${ACTIVATE} != "false"  ]]; then
      logErr "Argument '--x509Enabled' must be 'true' or 'false'"
      echo "${USAGE}"
      exit 1
    fi
  fi

  echo ${arg} | grep -q -e --chartName=
  if [ $? -eq 0 ]; then
    CHART_NAME=`echo ${arg} | awk -F= '{ print $2 }'`
    if [[ $(helm list | grep ${CHART_NAME} | wc -l) -lt 1 ]]; then
      logErr "Helm chart '${CHART_NAME}' informed in the argument '--chartName=' not found. Is it installed?"
      echo "${USAGE}"
      exit 1
    fi
  fi

  echo ${arg} | grep -q -e --chartPath=
  if [ $? -eq 0 ]; then
    CHART_ADDR=`echo ${arg} | awk -F= '{ print $2 }'`
    if [ ! -f ${CHART_ADDR} ]; then
      logErr "Chart '${CHART_ADDR}' informed in the argument '--chartPath=' not found."
      echo "${USAGE}"
      exit 1
    fi
  fi

done

if [[ -z "${NAMESPACE}" ]] || [[ -z "${ACTIVATE}" ]] || [[ -z "${CHART_NAME}" ]] || [[ -z "${CHART_ADDR}" ]]; then
  logErr "One or more required arguments not found"
  echo "${USAGE}"
  exit 1
fi

# Number of PODs Running
NUMB_PATTERN='^[0-9]+$'
N_PODS_DESIRED=$(kubectl get statefulset mongo -n ${NAMESPACE} | grep mongo | awk -F" "  '{ print $2}')
N_PODS_RUNNING=$(kubectl get statefulset mongo -n ${NAMESPACE} | grep mongo | awk -F" "  '{ print $3}')

if [ $? -ne 0 ] || ! [[ ${N_PODS_DESIRED} =~ ${NUMB_PATTERN} ]] || ! [[ ${N_PODS_RUNNING} =~ ${NUMB_PATTERN} ]]; then
  logErr "Attempt to check mongoDB Statefulstes failed. Is it installed? Script aborted"
  exit 1
fi

if [[ ${N_PODS_RUNNING} -eq 0 ]]; then
  logErr "No POD with status 'Running' found for mongoDB."
  exit 2
fi

if [[ ${N_PODS_RUNNING} -lt ${N_PODS_DESIRED} ]]; then 
  logErr "Some PODs still not Running. Desired: ${N_PODS_DESIRED}, Running: ${N_PODS_RUNNING}"
  exit 3
fi

# Check if X509 is currently activated
X509_ACTIVATE=$(helm get values -a ${CHART_NAME} | grep x509Enabled | awk -F": " '{ print $2 }')

# check if action requested it's not already applied
if [[ "${X509_ACTIVATE}" == "${ACTIVATE}" ]]; then
  logInfo "MongoDB already have x509Enabled=${X509_ACTIVATE}. No action needed."
  exit 10
fi

# If activating, first check if RS is health
if [[ "${ACTIVATE}" == "true" ]]; then
  N_HEALTH_DAEMONS=$(kubectl exec -it mongo-0 -c mongo -n ${NAMESPACE} -- mongo mongo-0.mongo:27017 --eval "rs.status()" | grep "id\|name\|health\|stateStr\|ok" | grep health | grep 1 | wc -l)
  if [[ ${N_HEALTH_DAEMONS} -lt ${REPLICAS} ]]; then 
    logErr "Mongo ReplicaSet has Deamons not health. Desired: ${REPLICAS}, Health: ${N_HEALTH_DAEMONS}"
    exit 3
  fi
fi

# Retrieve helm replacement arguments used for the latest deployed chart
REP_VALUES_TMP_FILE=$(mktemp /tmp/REP_VALUES_TMP_FILE.XXXXXX)
helm get values ${CHART_NAME} > ${REP_VALUES_TMP_FILE}
if [ $? -ne 0 ]; then
  logErr "Command to retrieve helm replacement values used for the chart name '${CHART_NAME}' failed."
  exit 1
fi

# If K8s secret 'mongo-secret' are not managed via chart (CfC envs), update it flag with kubectl
SECRET_VIA_CHART=$(helm get values -a ${CHART_NAME} | grep createSecret | awk -F": " '{ print $2 }')
if [[ "${SECRET_VIA_CHART}" != "true" ]]; then

  SECRET_CONTROLLER=$(helm get values -a mongodb | grep k8sSecretController | awk -F": " '{ print $2 }')
  MONGO_SEC_TMP_FILE=$(mktemp /tmp/MONGO_SEC_TMP_FILE.XXXXXX)

  kubectl get secret ${SECRET_CONTROLLER} -n ${NAMESPACE} -o json > ${MONGO_SEC_TMP_FILE}
  if [ $? -ne 0 ]; then
    logErr "Failed to export k8s secret with the name '${SECRET_CONTROLLER}'. Does it exist? Script aborted."
    exit 1
  fi

  # k8s secret must be in base64
  FLAG_VAL_AS_64=$(echo -n "${ACTIVATE}" | base64)

  # Create / Update flag in the temp file:
  X509_KEY="mongo-x509-auth-enabled"
 
  BUILDER=$(cat ${MONGO_SEC_TMP_FILE} | jq '.data+={"'${X509_KEY}'":"'${FLAG_VAL_AS_64}'"}')
  if [ $? -ne 0 ]; then
    logErr "Failed to create/update [${X509_KEY}: ${FLAG}] onto K8s secret '${SECRET_CONTROLLER}'. Please, check your k8s secret controllers. Script aborted."
    exit 1
  fi
  echo $BUILDER | jq . > ${MONGO_SEC_TMP_FILE}-patched

  # apply the change
  kubectl apply -f ${MONGO_SEC_TMP_FILE}-patched

  if [ $? -ne 0 ]; then
    logErr "Failed to create/update [${X509_KEY}: ${FLAG}] onto K8s secret '${SECRET_CONTROLLER}'. Please, check your k8s secret controllers. Script aborted."
    exit 1
  fi
fi


# Redeploy with the desired action
helm delete ${CHART_NAME} --purge
if [ $? -ne 0 ]; then
  logErr "Redeploy of the chart name '${CHART_NAME}' failed."
  exit 1
fi
helm install ${CHART_ADDR} --name ${CHART_NAME} --values ${REP_VALUES_TMP_FILE} --set x509Enabled=${ACTIVATE}
if [ $? -ne 0 ]; then
  logErr "Redeploy of the chart name '${CHART_NAME}' failed."
  exit 1
fi

logInfo "Done!"
