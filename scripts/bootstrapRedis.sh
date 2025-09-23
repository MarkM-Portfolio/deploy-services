#!/bin/bash -
#title           :bootstrap.sh
#description     :bootstrap Redis HA.
#version         :0.2
#usage		       :bash bootstrapRedis.sh
#==============================================================================


set -o pipefail
set -o nounset

logErr() {
  logIt "ERRO: " "$@"
}

logInfo() {
  logIt "INFO: " "$@"
}

logIt() {
    echo "$@"
}

function retryProgressBar {
  sleep 1
  printf "\rStatus check attempt ${1} of ${2} seconds..."
}

usage() {
	logIt ""
	logIt "Usage: ./bootstrapRedis.sh [OPTION]"
	logIt "This script will restore the Redis High Availability Cluster to a healthy state from a broken state "
	logIt ""
	logIt "Options are:"
	logIt "-n | --namespace	Services will be deployed in the specified namespace.  Optional. Default: connections"
	logIt "-h | --help	prints this message."
	logIt ""
	logIt "eg.:"
	logIt "./bootstrapRedis.sh"
	logIt "./bootstrapRedis.sh -n staging"
	logIt "A number of scenarios can result in the unavailability of Redis within Orient Me"
	logIt "Examples (NB : not a complete list)"
	logIt " - Redis Sentinel unable to elect a new Master"
	logIt " - Redis Master goes down without any good slaves to fail over to"
	logIt " - Multiple worker nodes are in a shutdown state causing not enough Sentinels to become available to form a quorum"
	logIt ""
	exit 1
}

bootstrapRedis () {

	# Support different invocation locations associated with this script at different times
	repo_top_dir="`dirname \"$0\"`/.."
	echo
	cd "${repo_top_dir}" > /dev/null
	echo "Changed location to repo top level dir:"
	echo "  `pwd`"
	echo "  (relative path:  ${repo_top_dir})"

	echo "Removing Redis, HAProxy and Redis Sentinel"
	helm del --purge redis
	helm del --purge redis-sentinel
	helm del --purge haproxy

	echo "Removing Redis and Redis Sentinel - force"
	kubectl delete pod --grace-period=0 --force --selector=app=redis-sentinel -n ${NAMESPACE}
	kubectl delete pod --grace-period=0 --force --selector=app=redis-server -n ${NAMESPACE}

	echo "Force delete Redis Pods"
	kubectl delete pod redis-server-0 --grace-period=0 --force -n ${NAMESPACE}
	kubectl delete pod redis-server-1 --grace-period=0 --force -n ${NAMESPACE}
	kubectl delete pod redis-server-2 --grace-period=0 --force -n ${NAMESPACE}

	echo "Removing HAProxy Pods - force"
	kubectl delete pod --grace-period=0 --force --selector=name=haproxy -n ${NAMESPACE}

	echo "Force delete Statefulset"
	kubectl delete statefulset redis-server --grace-period=0 --force -n ${NAMESPACE}

	echo "Force delete Deployments"
	kubectl delete deployment redis-sentinel --grace-period=0 --force -n ${NAMESPACE}
	kubectl delete deployment haproxy --grace-period=0 --force -n ${NAMESPACE}

	echo "Force delete Services"
	kubectl delete svc redis-server --grace-period=0 --force -n ${NAMESPACE}
	kubectl delete svc redis-sentinel --grace-period=0 --force -n ${NAMESPACE}
 	kubectl delete svc haproxy-redis --grace-period=0 --force -n ${NAMESPACE}


	# Tracking PODs Removal...
	i="1"
	MINs=5 # max minutes it can take
	((ATTEMPTS=$MINs*60))

	while [ $i -lt $ATTEMPTS ]
	do

        	echo "Ensuring Redis Servers are deleted"
		PODs=$(kubectl get pods -n ${NAMESPACE} | grep redis-server-)
		if [[ -z $PODs ]]; then
	  		logInfo "Not Found running redis-server pods. " 	
		 	break
		fi

		let i=i+1
		if [[ i -eq $ATTEMPTS ]]; then
 			logIt ""
		    	kubectl get pods -n ${NAMESPACE} | grep redis-server-
    			logErr "PODs not deleted after $ATTEMPTS seconds. Exiting."
    			exit 1
		fi

		retryProgressBar ${i} ${ATTEMPTS}

	done	


	echo "Ensuring Redis Sentinels pods are deleted"
	i="1"
	MINs=5 # max minutes it can take
	((ATTEMPTS=$MINs*60))

	while [ $i -lt $ATTEMPTS ]
	do

        	echo "Ensuring Redis Sentinels are deleted"
		PODs=$(kubectl get pods -n ${NAMESPACE} | grep redis-sentinel-)
		if [[ -z $PODs ]]; then
  	 		logInfo "Not Found running redis-sentinel pods. " 	
		 	break
		fi

		let i=i+1
	  	if [[ i -eq $ATTEMPTS ]]; then
			logIt ""
	    		kubectl get pods -n ${NAMESPACE} | grep redis-sentinel-
    			logErr "PODs not deleted after $ATTEMPTS seconds. Exiting."
    			exit 1
	  	fi

		retryProgressBar ${i} ${ATTEMPTS}

	done




	echo "Ensuring HA proxy pods are deleted"
	i="1"
	MINs=5 # max minutes it can take
	((ATTEMPTS=$MINs*60))

	while [ $i -lt $ATTEMPTS ]
	do

        	echo "Ensuring HAproxy are deleted"
		PODs=$(kubectl get pods -n ${NAMESPACE} | grep haproxy)
		if [[ -z $PODs ]]; then
  	 		logInfo "Not Found running haproxy pods. " 	
	 		break
		fi

		let i=i+1
	  	if [[ i -eq $ATTEMPTS ]]; then
			logIt ""
	    		kubectl get pods -n ${NAMESPACE} | grep haproxy-
    			logErr "PODs not deleted after $ATTEMPTS seconds. Exiting."
    			exit 1
	  	fi

		retryProgressBar ${i} ${ATTEMPTS}

	done

	sleep 30

	components=("redis" "redis-sentinel" "haproxy")

	bash ./bin/install_components.sh "${components[@]}"

}

while [[ $# -gt 0 ]]
do
	key="$1"
	
	case $key in
	    -n|--namespace)
	     echo "Script performed with -n|--namespace. Services will be deployed in the $2 namespace"
	     NAMESPACE="$2"
	     if [[ ${NAMESPACE} = "default" || ${NAMESPACE} = "kube-system" ]]; then
		echo "Must set namespace to an existing namespace other than default or kube-system"
		exit 1
	     else
		echo "Checking if ${NAMESPACE} namespace exists"
		kubectl get namespace ${NAMESPACE}
		if [ $? -ne 0 ]; then
			echo "Unable to find namespace ${NAMESPACE}. Be sure to use the same namespace that was used during deployCfC."	
			
			exit 1
		fi

		sed -i "s/connections/${NAMESPACE}/" common_values.yaml
	     fi
	     shift
	     ;; 
	    -h|--help)
	     usage	     
	     ;;  
    	*)
	usage
	;;
	esac
shift
done

set +o nounset

if [ -z "$NAMESPACE" ]; then
  NAMESPACE='connections'
fi

set -o nounset


bootstrapRedis

exit 0
