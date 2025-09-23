#!/bin/bash

PATH=/usr/local/bin:$PATH
export PATH
umask 022

PRG=`basename ${0}`
ACTION=""
NAMESPACE=""
BACKUP_GZ_FILE_NAME=""

USAGE="
usage:	${PRG}

  Required arguments:
    --action=< backup | restore >
    --namespace=<kubernetes namepsace. Eg: connections, default, etc...>
    --backup_gz_file_name=< Backup file name to be created or restored. If you are performing a 'restore' action, this file must exist in mongo-0 instance volume, at the path /data/db. >

  Usage examples:

    Creating backup:
      ./${PRG} --action=backup --namespace=default --backup_gz_file_name=mongodb-backup.gz

    Restoring backup:
      ./${PRG} --action=restore --namespace=connections --backup_gz_file_name=mongodb-backup.gz
"

for arg in $*; do

  echo ${arg} | grep -q -e --action=
  if [ $? -eq 0 ]; then
    ACTION=`echo ${arg} | awk -F= '{ print $2 }'`
  fi

  echo ${arg} | grep -q -e --namespace=
  if [ $? -eq 0 ]; then
    NAMESPACE=`echo ${arg} | awk -F= '{ print $2 }'`
    if [[ $(kubectl get namespaces | grep ${NAMESPACE} | wc -l) -lt 1 ]]; then
      echo "${USAGE}"
      exit 1
    fi
  fi

  echo ${arg} | grep -q -e --backup_gz_file_name=
  if [ $? -eq 0 ]; then
    BACKUP_GZ_FILE_NAME=`echo ${arg} | awk -F= '{ print $2 }'`
    BACKUP_GZ_FILE=/data/db/${BACKUP_GZ_FILE_NAME}

    if [ "$ACTION" == "restore" ]; then
      kubectl exec -i mongo-0 -c mongo -n ${NAMESPACE} -- ls ${BACKUP_GZ_FILE} &> /dev/null
      if [ $? -ne 0 ]; then
        echo ""
        echo "File '$BACKUP_GZ_FILE' not found in the container mongo-0. Script execution aborted."
        exit 1
      fi
    fi

  fi
done

if [ -z "$ACTION" ] || [ -z "$NAMESPACE" ] || [ -z "$BACKUP_GZ_FILE_NAME" ]; then
  echo "${USAGE}"
  exit 1
fi

{
X509=$(helm get values -a mongodb | grep x509Enabled | awk -F ' ' '{print $2}')
} &> /dev/null
mongoRun() {
  KUBECTL_POD=$1
  MONGO_SCRIPT_CMD=$2

  if [ -z "$KUBECTL_POD" ] || [ -z "$MONGO_SCRIPT_CMD" ]; then
    echo "Internal error. Please contact technical support - mongoRun depends on 2 arguments: KUBECTL_POD and MONGO_SCRIPT_CMD"
    echo 'usage: '
    echo 'mongoRun "mongo-0" "rs.status().members"'
    exit 1
  fi

  KUBECTL_ATASH_CMD="kubectl exec -it $KUBECTL_POD -c mongo -n $NAMESPACE --"
  MONGO_CONN_CMD=""
  MONGO_AUTH_CMD=""
  if [ "$X509" == "true" ]; then
    MONGO_CONN_CMD="mongo --ssl --sslPEMKeyFile /etc/mongodb/x509/user_admin.pem --sslCAFile /etc/mongodb/x509/mongo-CA-cert.crt --host $KUBECTL_POD.mongo.$NAMESPACE.svc.cluster.local"
    MONGO_AUTH_CMD='db.getSiblingDB("$external").auth({mechanism: "MONGODB-X509",user: "C=IE,ST=Ireland,L=Dublin,O=IBM,OU=Connections-Middleware-Clients,CN=admin,emailAddress=admin@mongodb"})'
  else
    MONGO_CONN_CMD="mongo --host $KUBECTL_POD.mongo.$NAMESPACE.svc.cluster.local"
  fi

  eval $(echo "$KUBECTL_ATASH_CMD $MONGO_CONN_CMD --eval '$MONGO_AUTH_CMD; $MONGO_SCRIPT_CMD'")
}

backupRun() {

  KUBECTL_ATASH_CMD="kubectl exec -it mongo-0 -c mongo -n $NAMESPACE --"
  RESTORE_EXTRA_ARGS=""
  if [ "$ACTION" == "backup" ]; then
    BACKUP_CMD="mongodump"
  else
    BACKUP_CMD="mongorestore"
    RESTORE_EXTRA_ARGS="--nsExclude 'admin.*'"
  fi

  echo "Performing ${BACKUP_CMD}..."

  if [ "$X509" != "true" ]; then
    eval $(echo "$KUBECTL_ATASH_CMD ${BACKUP_CMD} -v --host ${RS_PRIMARY_INSTANCE}.mongo.${NAMESPACE}.svc.cluster.local --archive=${BACKUP_GZ_FILE} --gzip $RESTORE_EXTRA_ARGS")
  else
    BACKUP_CMD_X509_EXTRA_ARGS="--ssl --sslPEMKeyFile /etc/mongodb/x509/user_admin.pem --sslCAFile /etc/mongodb/x509/mongo-CA-cert.crt --authenticationMechanism=MONGODB-X509 --authenticationDatabase '\$external' -u 'C=IE,ST=Ireland,L=Dublin,O=IBM,OU=Connections-Middleware-Clients,CN=admin,emailAddress=admin@mongodb'"
    eval $(echo "$KUBECTL_ATASH_CMD ${BACKUP_CMD} -v --host ${RS_PRIMARY_INSTANCE}.mongo.${NAMESPACE}.svc.cluster.local --archive=${BACKUP_GZ_FILE} --gzip $RESTORE_EXTRA_ARGS $BACKUP_CMD_X509_EXTRA_ARGS")
  fi
}

fatalErrLog() {
  echo "ERR: Failed to $1. Is MongoDB ReplicaSet healthy under '${NAMESPACE}' namespace?"
  echo ""
  echo "Please, check it out by performing: "

  if [ "$X509" != "true" ]; then
    echo "  kubectl exec -n ${NAMESPACE} -it mongo-0 -c mongo -- mongo mongo-0.mongo:27017 --eval \"rs.status()\" | grep \"id\|name\|health\|stateStr\|ok\""
  else
    echo "  kubectl exec -it mongo-0 -c mongo -n ${NAMESPACE} -- mongo --ssl --sslPEMKeyFile /etc/mongodb/x509/user_admin.pem --sslCAFile /etc/mongodb/x509/mongo-CA-cert.crt --host mongo-0.mongo.${NAMESPACE}.svc.cluster.local --authenticationMechanism=MONGODB-X509 --authenticationDatabase '\$external' -u "C=IE,ST=Ireland,L=Dublin,O=IBM,OU=Connections-Middleware-Clients,CN=admin,emailAddress=admin@mongodb" --eval \"rs.status().members\" | grep \"id\|name\|health\|stateStr\|ok\""
  fi

  echo ""
  exit 1
}

echo ""
echo "Executiong MongoDB '$ACTION' on '$NAMESPACE' namespace. File name: '$BACKUP_GZ_FILE'..."
echo ""

echo ""
echo "Identifying primary mongoDB instance..."
SCRIPT="rs.status().members"
RS_PRIMARY_INSTANCE=$(mongoRun "mongo-0" $SCRIPT 2>&1 | grep -B 3 PRIMARY | head -1 | awk -F ':' '{print substr($2,3,7)}')

if [ -z $RS_PRIMARY_INSTANCE ]; then
  fatalErrLog "find out primary mongoDB instance"
fi
echo "PRIMARY instance: " $RS_PRIMARY_INSTANCE

if [ "$ACTION" == "backup" ]; then
  echo ""
  echo "Locking out MongoDB RS..."
  SCRIPT="db.fsyncLock()"
  mongoRun $RS_PRIMARY_INSTANCE $SCRIPT

  if [ $? -ne 0 ]; then
    fatalErrLog "lock database"
  fi
fi

echo ""
backupRun

if [ $? -ne 0 ]; then
  fatalErrLog "perform ${BACKUP_CMD}"
fi

echo ""
echo "Logging out the involved DBs..."
SCRIPT='db.adminCommand("listDatabases")'
mongoRun $RS_PRIMARY_INSTANCE $SCRIPT > /tmp/${BACKUP_GZ_FILE_NAME}.${ACTION}.dbs

if [ "$ACTION" == "backup" ]; then
  echo ""
  echo "Unlocking MongoDB RS..."
  SCRIPT="db.fsyncUnlock()"
  mongoRun $RS_PRIMARY_INSTANCE $SCRIPT

  if [ $? -ne 0 ]; then
    fatalErrLog "unlock database"
  fi
fi


echo ""
echo "Action $ACTION completed!"
if [ "$ACTION" == "backup" ]; then

  PV=($(kubectl get pv -n ${NAMESPACE} -o wide | grep -e "${NAMESPACE}\/.*mongo-0"))
  V_PATH=($(kubectl get pv ${PV[0]} -n ${NAMESPACE} -o yaml | grep path:))

  echo "Please, check the file '${BACKUP_GZ_FILE}' created into the PV '${PV[0]}'"
  echo ""
  echo ""
  echo "Full path: ${V_PATH[1]}/${BACKUP_GZ_FILE_NAME}"
fi

echo ""
echo "See/compare the DBs affected by performing: "
echo "cat /tmp/${BACKUP_GZ_FILE_NAME}.${ACTION}.dbs"
echo ""
echo "Script $PRG execution completed!"
