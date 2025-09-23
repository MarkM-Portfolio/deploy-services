#!/bin/bash -
#title           :utils.sh
#description     :Bash utils lib to install pink.
#version         :0.1
#usage           :source utils.sh
#==============================================================================
#!/bin/bash

retryProgressBar() {
  sleep 1
  printf "\rStatus check attempt ${1} of ${2} seconds for ${3}..."
}

verify() {
    local release=$1
    local namespace=$2
	# Trackin PODs deploy until get done...
	i="1"
	MINs=10 # max minutes it can take
	((ATTEMPTS=$MINs*60))

	# got it from: https://github.com/kubernetes/kubernetes/blob/f5d9c430e9168cf5c41197b8a4e457981cb031df/pkg/kubelet/images/types.go
	# And here: https://github.com/kubernetes/kubernetes/blob/cdf0cae9e4d604665a8559b9403b69791dcff853/pkg/kubelet/events/event.go
	CONTAINER_ERRs=['ImagePullBackOff','ImageInspectError','ErrImagePull','ErrImageNeverPull','RegistryUnavailable','InvalidImageName','Failed','ExceededGracePeriod','InspectFailed','BackOff','FailedDetachVolume','FailedMount','FailedUnMount','HostPortConflict','NodeSelectorMismatching','InsufficientFreeCPU','InsufficientFreeMemory','OutOfDisk','HostNetworkNotSupported','ContainerGCFailed','ImageGCFailed','FailedNodeAllocatableEnforcement','UnsupportedMountOption','InvalidDiskCapacity','FreeDiskSpaceFailed','Unhealthy','FailedSync','FailedValidation','FailedPostStartHook','FailedPreStopHook','UnfinishedPreStopHook']

	while [ $i -lt $ATTEMPTS ]
	do
        PODsDONE=$(helm status ${release} | awk '{ print $3 }' | grep "CURRENT" -B0 -A999999999 | sed -n 2p)

        if [[ $PODsDONE -ne 3 ]]; then
            # will check the status and log it each 10 seconds
            PODs_ST=$(kubectl get pod -n ${namespace} -l release=${release} | tail -n +2 | awk '{ print $3 }')
            for POD_ST in "${PODs_ST[@]}"
            do
            if [[ ${CONTAINER_ERRs[*]} =~ $POD_ST ]]; then
                logErr "One or more PODs got the error $POD_ST. Please, describe the POD (kubectl describe pod <pode_name> -n $namespace) for details"
                kubectl get pods -n ${namespace} -l release=${release} | tail -n +2
                exit 1
            fi
            done
            else
                break
            fi

            let i=i+1
            if [[ i -eq $ATTEMPTS ]]; then
                logIt ""
                kubectl get pods -n ${namespace} -l release=${release} | tail -n +2
                logErr "${release} PODs never got status 'Running' after $ATTEMPTS seconds. Please check the POD's healthy. Exiting."
                exit 1
            fi

        retryProgressBar ${i} ${ATTEMPTS} ${release}
	done
}

verifyInParallel() {
    local namespace=$1
    local releases=${@:2}

    local pids=''
    local result=''

    for release in ${releases[@]}
    do
        verify ${release} ${namespace} &
        local pids="$pids $!"
    done

    waitForProcessesToComplete ${pids}
    return $?
}

waitForProcessesToComplete() {
    local pids="$@"
    local result=''

    for pid in $pids; do
        wait $pid || let "result=1"
    done

    if [ "$result" == "1" ];
    then
        return 1
    else
        return 0
    fi
}
