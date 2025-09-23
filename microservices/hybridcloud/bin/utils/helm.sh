#!/bin/bash -
#title           :helm.sh
#description     :Bash helm lib.
#version         :0.1
#usage           :source helm.sh
#==============================================================================
#!/bin/bash

deploy() {
	# $1 release name
	# $2 chart
	# $... flags
	local release=$1
	local chart=$2
	local flags="${@:3}"

	set +e
	isExistingRelease $1
	local exists=$?
	if [ ${exists} -eq 0 ]; then
		logIt "${release} is already installed."
		
		if [[ $1 == "elasticsearch" ]]; then
			logIt "This release will be deleted and reinstalled"

			getReleaseNamespace ${release}
			local namespace=${HELM_DATA}
			local selector="component=elasticsearch,role=data"

			logIt "Deleting ${release}..."
			delete $1
			forceDeletePods ${selector} ${namespace}
			forceDeleteStatefulset es-data ${namespace}			

			logIt "Installing ${release}..."
			helm install ${chart} --name=${release} ${flags}
		else
			logIt "This release will be upgraded"
			upgrade ${release} ${chart} ${flags}
		fi
		
	else
		logIt "Installing ${release}..."
		helm install ${chart} --name=${release} ${flags}
	fi
	set -e
}

upgrade() {
	local release=$1
	local chart=$2
	local flags="${@:3}"
	helm upgrade ${release} ${chart} ${flags}
	local rc=$?
	logIt "Helm upgrade result for ${release}: ${rc}"
	set +e
	isStatefulset ${release}
	if [ $? -eq 0 ]; then
		logIt "${release} is a statefulset"
		set -e
		getReleaseNamespace ${release}
		local namespace=${HELM_DATA}
		logIt "Recreating ${release} pods"
		recreatePodsSequentially ${release} ${namespace}
	fi
	logIt "${release} upgrade completed successfully"
	set -e
}

delete() {
	local release=$1
	helm delete ${release} --purge
}

isExistingRelease() {
	helm list | grep $1 -q
}

getReleaseValue() {
	local release=$1
	local field=$2
	HELM_DATA=$(helm get values -a ${release} | grep ${field} | awk -F": " '{ print $2 }')
}

isStatefulset() {
	local release=$1
	helm status ${release} | grep StatefulSet -q
}

deletePod() {
	local pod=$1
	local namespace=$2
	kubectl delete pod ${pod} -n ${namespace}
}

forceDeletePods() {
	local selector=$1
	local namespace=$2
	kubectl delete pod --grace-period=0 --force --selector=${selector} -n ${namespace}
}

forceDeleteStatefulset() {
	local statefulset=$1
	local namespace=$2
	kubectl delete statefulset ${statefulset} --grace-period=0 --force -n ${namespace}	
}

isPodReady() {
	local pod=$1
	local namespace=$2
	kubectl get -o template pod/${pod} --template={{.status.containerStatuses}} -n ${namespace} | grep 'ready:true' -q
}

getDesiredPodsNumber() {
	local release=$1
	HELM_DATA=$(helm status $release | awk '{ print $2 }' | grep "DESIRED" -B0 -A999999999 | sed -n 2p)
}

getReleaseNamespace() {
	local release=$1
	HELM_DATA=$(cut -d ":" -f 2 <<< $(helm get values $1 | grep namespace))
}

getReleasePodNames() {
	local release=$1
	local namespace=$2
	if [ ${release} = 'elasticsearch' ]; then
		HELM_DATA=$(kubectl get pod -n ${namespace} | awk '{ print $1 }' | grep es-data)
	else
		HELM_DATA=$(kubectl get pod -l release=${release} -n ${namespace} | awk '{ print $1 }' | tail -n +2)
	fi
}

recreatePodsSequentially() {
	local release=$1
	local namespace=$2
	getDesiredPodsNumber ${release}
	local desiredPods=${HELM_DATA}
	getReleasePodNames ${release} ${namespace}
	local podNames=(${HELM_DATA//\\n/ })
	logIt "Total number of pods for release ${release}: ${#podNames[@]}"
	logIt "List of pods to recreate ${podNames[@]}"

	for (( idx=${#podNames[@]}-1 ; idx>=0 ; idx-- )) ; do
		local pod="${podNames[idx]}"
		logIt "Recreating pod ${pod}..."
		set +e
		deletePod ${pod} ${namespace}
		waitUntilPodExists ${pod} ${namespace}
		set -e
		waitPodReadiness ${pod} ${namespace}
		logIt "Pod ${pod} has been recreated successfully"
	done
}

waitPodReadiness() {
	set +e
	local pod=$1
	local namespace=$2

	local i=1
	local attemps=60
	local sleepTime=5
	sleep 10
	logIt "Waiting until pod ${pod} is ready..."
	while [ $i -lt ${attemps} ]
	do
		isPodReady ${pod} ${namespace}
		if [ $? -eq 0 ]; then
			logIt "Pod ${pod} ready"
			break
		else
			let i=i+1
			logIt "Pod ${pod} is not ready yet, trying again in ${sleepTime} seconds"
			if [[ i -eq ${attemps} ]]; then
				logErr "Pod ${pod} could not be restarted after ${attemps} attemps with a delay of ${sleepTime} seconds"
				exit 1
			fi
			sleep ${sleepTime}
		fi
	done
	set -e
}

podExists() {
	local pod=$1
	local namespace=$2

	kubectl get pod -n ${namespace} | grep ${pod} -q
}

waitUntilPodExists() {
	local pod=$1
	local namespace=$2

	local i=1
	local attemps=30
	local sleepTime=2
	while [ $i -lt ${attemps} ]
	do
		podExists ${pod} ${namespace}
		if [ $? -eq 0 ]; then
			logIt "Pod ${pod} created"
			break
		else
			let i=i+1
			logIt "Pod ${pod} is not created yet, trying again in ${sleepTime} seconds"
			if [[ i -eq ${attemps} ]]; then
				logErr "Pod ${pod} could not be started"
				exit 1
			fi
			sleep ${sleepTime}
		fi
	done
}
