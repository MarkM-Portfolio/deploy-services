#!/bin/bash -
#title           :setup.sh
#description     :This script will configure and setup K8 on CFC.
#version         :0.1
#usage		       :bash setup.sh
#==============================================================================

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

DEPLOY_CFC_DIR=${conn_locn}
CONFIG_DIR=${DEPLOY_CFC_DIR}/config
HOSTNAME=`hostname -f`

# XYZZY: work-around for HA, and also related to boot/master co-location requirement
master_hostname=master.cfc
#master_hostname=localhost

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
  logIt "Usage: ./setup.sh [OPTION]"
  logIt "This script will configure and setup K8 on CFC"
  logIt ""
  logIt "The options are: "
  logIt "-a  | --artifactory    It indicates that the docker images must be pulled from the given artifactory"
  logIt "     -u | --user    Will be used when -a or --artifactory argument is provided. If not provided, an user interation might be necessary in order to authenticate on artifactory. This argument is mandatory combined with the -p | --pass. otherwise it will be ignored"
  logIt "     -p | --pass    Will be used when -a or --artifactory argument is provided. If not provided, an user interation might be necessary in order to authenticate on artifactory. This argument is mandatory combined with the -u | --user. otherwise it will be ignored"
  logIt "-fs | --filesystem     It indicates that the docker images must be loaded from the file system"
  logIt "-n | --namespace     It indicates the namespace in which the services will be deployed. Default namespace will be connections"
  logIt ""
  logIt "eg.:"
  logIt "./setup.sh -fs"
  logIt "./setup.sh -a \$ARTIFACTORY_HOST_AND_PORT"
  logIt "./setup.sh -a \$ARTIFACTORY_HOST_AND_PORT -u \$ARTIFACTORY_USER -p \$ARTIFACTORY_PASS"
  logIt ""
  logIt "./setup.sh -uc | --icp_user - docker images will be pulled from the filesystem. If not provided will check if the environment variable CFC_ADMIN_USER has been set, if not will default to admin. If admin is not a valid username, will be prompted for username to authenticate."
  logIt "./setup.sh -ucp | --icp_user_pass - docker images will be pulled from the filesystem. If not provided will check if the environement variable CFC_ADMIN_PASSWORD has been set, if not will default to admin. If admin is not a valid password, will be prompted for password to authenticate."
  logIt ""
}

commonProcedure() {

  set +o errexit
  if [ "`kubectl get pv`" = "" ]; then
	echo "Must setup persistent storage before proceeding"
	exit 6
  fi
  set -o errexit

  # Authenticate to CfC registry with default user and pass
  set +o errexit
  number_retries=3
  retry_wait_time=30
  counter=1
  retries_entering_password=4
  counter_retries_entering_password=1

  while [ ${counter} -le ${number_retries} ]; do
    docker login -u ${icp_user} -p ${icp_user_pass} ${master_hostname}:8500
    exit_status=$?
    if [ ${exit_status} -ne 0 ]; then
      printf "	FAILED"
      if [ ${counter} -lt ${number_retries} ]; then
        echo ", retrying in ${retry_wait_time}s"
        sleep ${retry_wait_time}
      else
        echo
      fi
    else
      break
    fi
    counter=`expr ${counter} + 1`
  done

  if [ ${counter} -ge ${number_retries} ]; then
    while [ ${counter_retries_entering_password} -lt ${retries_entering_password} ]; do
      echo "Please confirm username and password before running setup"
      enterUserCredentials
      docker login -u ${icp_user} -p ${icp_user_pass} ${master_hostname}:8500
      if [ $? -ne 0 ]; then
        printf "User credentials incorrect, please re-enter"
      else
        break
      fi
      counter_retries_entering_password=`expr ${counter_retries_entering_password} + 1`
    done
  fi  
  set -o errexit

  if [ ${counter_retries_entering_password} -ge ${retries_entering_password} ]; then
    echo "Maximum attempts reached, giving up"
    exit 1
  fi
  if [ ${counter} -gt 1 ]; then
    printf "Waiting for server to stabilize after retries..."
    sleep 30
    echo "proceeding"
  fi

  # create the secret docker registry for YMLs be able to pull the images
  set +o errexit
  kubectl delete secret myregkey -n ${NAMESPACE}
  set -o errexit
  kubectl create secret docker-registry myregkey -n ${NAMESPACE} --docker-server=${master_hostname}:8500 --docker-username=${icp_user} --docker-password=${icp_user_pass} --docker-email=connections@us.ibm.com

}

enterUserCredentials() {

  printf "Enter username: "
  read icp_user

  printf "Enter password: "
  read -s icp_user_pass

}

pullingFromArtifactory() {

  # Authenticate to artifactory
  set +o errexit
  number_retries=10
  retry_wait_time=30
  counter=1
  while [ ${counter} -le ${number_retries} ]; do
    if [ -z "$ARTIFACTORY_USER" ]; then
      docker login $ARTIFACTORY_HOST_AND_PORT
      exit_status=$?
    else
      docker login $ARTIFACTORY_HOST_AND_PORT -u $ARTIFACTORY_USER -p $ARTIFACTORY_PASS
      exit_status=$?
    fi
    if [ ${exit_status} -ne 0 ]; then
      printf "	FAILED"
      if [ ${counter} -lt ${number_retries} ]; then
        echo ", retrying in ${retry_wait_time}s"
        sleep ${retry_wait_time}
      else
        echo
      fi
    else
      break
    fi
    counter=`expr ${counter} + 1`
  done
  set -o errexit
  if [ ${counter} -gt ${number_retries} ]; then
    echo "Maximum attempts reached, giving up"
    exit 1
  fi
  if [ ${counter} -gt 1 ]; then
    printf "Waiting for server to stabilize after retries..."
    sleep 30
    echo "proceeding"
  fi

  # Process common procedures
  commonProcedure

  # Pull, tag and push images
  declare -a arr=("orientme/orient-web-client" "middleware/redis" "middleware/redis-sentinel" "middleware/mongodb" "middleware/mongodb-rs-setup" "middleware/zookeeper" "indexing-service" "middleware/solr-basic" "retrieval-service" "analysis-service" "people/people-relationship" "people/people-idmapping" "people/people-scoring" "people/people-datamigration" "mail-service" "itm/itm-services" "appregistry-client" "appregistry-service" "middleware-graphql" "mw-proxy" "community-suggestions" "elasticsearch")

  for i in "${arr[@]}"
  do
    docker pull $ARTIFACTORY_HOST_AND_PORT/$i
    img=$(echo $i | awk '{split($0,img,"/"); print img[2]}')
    docker tag $ARTIFACTORY_HOST_AND_PORT/$i ${master_hostname}:8500/default/$img
    docker push ${master_hostname}:8500/default/$img
  done

}

pullingFromFileSystem() {

  set -o errexit

  # Process common procedures
  commonProcedure

  # Pull, tag and push images
  logInfo "Loading local registry with images"

  docker load -i ../images/orientme/orient-web-client.tar
  docker tag orientme_orient-web-client_DIGEST ${master_hostname}:8500/connections/orientme/orient-web-client
  docker push ${master_hostname}:8500/connections/orientme/orient-web-client

  docker load -i ../images/middleware/haproxy.tar
  docker tag middleware_haproxy_DIGEST ${master_hostname}:8500/connections/middleware/haproxy
  docker push ${master_hostname}:8500/connections/middleware/haproxy

  docker load -i ../images/middleware/redis.tar
  docker tag middleware_redis_DIGEST ${master_hostname}:8500/connections/middleware/redis
  docker push ${master_hostname}:8500/connections/middleware/redis

  docker load -i ../images/middleware/redis-sentinel.tar
  docker tag middleware_redis-sentinel_DIGEST ${master_hostname}:8500/connections/middleware/redis-sentinel
  docker push ${master_hostname}:8500/connections/middleware/redis-sentinel

  docker load -i ../images/middleware/mongodb.tar
  docker tag middleware_mongodb_DIGEST ${master_hostname}:8500/connections/middleware/mongodb
  docker push ${master_hostname}:8500/connections/middleware/mongodb

  docker load -i ../images/middleware/mongodb-rs-setup.tar
  docker tag middleware_mongodb-rs-setup_DIGEST ${master_hostname}:8500/connections/middleware/mongodb-rs-setup
  docker push ${master_hostname}:8500/connections/middleware/mongodb-rs-setup

  docker load -i ../images/middleware/zookeeper.tar
  docker tag middleware_zookeeper_DIGEST ${master_hostname}:8500/connections/middleware/zookeeper
  docker push ${master_hostname}:8500/connections/middleware/zookeeper

  docker load -i ../images/indexing-service.tar
  docker tag indexing-service_DIGEST ${master_hostname}:8500/connections/indexing-service
  docker push ${master_hostname}:8500/connections/indexing-service

  docker load -i ../images/middleware/solr-basic.tar
  docker tag middleware_solr-basic_DIGEST ${master_hostname}:8500/connections/middleware/solr-basic
  docker push ${master_hostname}:8500/connections/middleware/solr-basic

  docker load -i ../images/retrieval-service.tar
  docker tag retrieval-service_DIGEST ${master_hostname}:8500/connections/retrieval-service
  docker push ${master_hostname}:8500/connections/retrieval-service

  docker load -i ../images/analysis-service.tar
  docker tag analysis-service_DIGEST ${master_hostname}:8500/connections/analysis-service
  docker push ${master_hostname}:8500/connections/analysis-service

  docker load -i ../images/people/people-relationship.tar
  docker tag people_people-relationship_DIGEST ${master_hostname}:8500/connections/people/people-relationship
  docker push ${master_hostname}:8500/connections/people/people-relationship

  docker load -i ../images/people/people-idmapping.tar
  docker tag people_people-idmapping_DIGEST ${master_hostname}:8500/connections/people/people-idmapping
  docker push ${master_hostname}:8500/connections/people/people-idmapping

  docker load -i ../images/people/people-scoring.tar
  docker tag people_people-scoring_DIGEST ${master_hostname}:8500/connections/people/people-scoring
  docker push ${master_hostname}:8500/connections/people/people-scoring

  docker load -i ../images/people/people-datamigration.tar
  docker tag people_people-datamigration_DIGEST ${master_hostname}:8500/connections/people/people-datamigration
  docker push ${master_hostname}:8500/connections/people/people-datamigration

  docker load -i ../images/mail-service.tar
  docker tag mail-service_DIGEST ${master_hostname}:8500/connections/mail-service
  docker push ${master_hostname}:8500/connections/mail-service

  docker load -i ../images/itm/itm-services.tar
  docker tag itm_itm-services_DIGEST ${master_hostname}:8500/connections/itm/itm-services
  docker push ${master_hostname}:8500/connections/itm/itm-services

  docker load -i ../images/appregistry-client.tar
  docker tag appregistry-client_DIGEST ${master_hostname}:8500/connections/appregistry-client
  docker push ${master_hostname}:8500/connections/appregistry-client

  docker load -i ../images/appregistry-service.tar
  docker tag appregistry-service_DIGEST ${master_hostname}:8500/connections/appregistry-service
  docker push ${master_hostname}:8500/connections/appregistry-service

  docker load -i ../images/middleware-graphql.tar
  docker tag middleware-graphql_DIGEST ${master_hostname}:8500/connections/middleware-graphql
  docker push ${master_hostname}:8500/connections/middleware-graphql

  docker load -i ../images/mw-proxy.tar
  docker tag mw-proxy_DIGEST ${master_hostname}:8500/connections/mw-proxy
  docker push ${master_hostname}:8500/connections/mw-proxy

  docker load -i ../images/community-suggestions.tar
  docker tag community-suggestions_DIGEST ${master_hostname}:8500/connections/community-suggestions
  docker push ${master_hostname}:8500/connections/community-suggestions

  docker load -i ../images/elasticsearch.tar
  docker tag elasticsearch_DIGEST ${master_hostname}:8500/connections/elasticsearch
  docker push ${master_hostname}:8500/connections/elasticsearch

  docker load -i ../images/sanity.tar
  docker tag sanity_DIGEST ${master_hostname}:8500/connections/sanity
  docker push ${master_hostname}:8500/connections/sanity

  # work-around for issue 8842
  if [ ! -f /opt/ibm/cfc/version ]; then
	echo "Unable to determine ICp version"
	exit 99
  fi
  icp_version_major=`awk -F. '{ print $1 }' /opt/ibm/cfc/version`
  if [ ${icp_version_major} -ge 2 ]; then
	icp_install_dir=`grep '^icp.install.directory=' ${CONFIG_DIR}/${HOSTNAME} | tail -1 | awk -F= '{ print $2 }'`
	if [ "${icp_install_dir}" = "" ]; then
		echo "Unable to determine ICp installation directory"
		exit 99
	fi
	echo
	echo "Resetting auth-pdp"
	kubectl -s 127.0.0.1:8888 delete ds auth-pdp -n kube-system
	kubectl -s 127.0.0.1:8888 apply -f ${icp_install_dir}/cluster/cfc-components/platform-iam/platform-auth-pdp-ds.yaml
  fi
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -fs|--filesystem)
      logInfo "Script performed with -f|--filesystem. Images will be pulled from from file system"
      pullingFromFileSystem
      exit $?
      ;;
    -a|--artifactory)
      logInfo "Script performed with -a|--artifactory. Images will be pulled from the given artifactory: $2"
      ARTIFACTORY_HOST_AND_PORT="$2"
      shift
      ;;
    -u|--user)
      ARTIFACTORY_USER="$2"
      shift
      ;;
    -p|--pass)
      ARTIFACTORY_PASS="$2"
      shift
      ;;
    -n|--namespace)
      logInfo "Script performed with -n|--namespace. Services will be deployed in the $2 namespace"
      NAMESPACE="$2"
      shift
      ;;
    -uc|--icp_user)
      icp_user="$2"
      shift
      ;;
    -ucp|--icp_user_password)
      icp_user_pass="$2"
      shift
      ;;  
    *)
      usage
      exit 2
      ;;
esac
shift
done

# If arrived until here, it's not filesystem, this if no artifactory too, so throw up usage function
if [ -z "$ARTIFACTORY_HOST_AND_PORT" ]; then
  usage
  exit 3
else
  pullingFromArtifactory
  exit $?
fi
