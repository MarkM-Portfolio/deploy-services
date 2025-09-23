#! /bin/bash
# Initial author: on Sun Feb  5 15:26:49 GMT 2017
#
# History:
# --------
# Sun Feb  5 15:26:49 GMT 2017
#	Initial version
#
#

. ./00-all-config.sh

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

cd ${WORKING_DIR}

if [ "${add_infra_worker}" != "" ]; then
	label="infrastructure"
else
	label="generic"
fi

if [ ${HOSTNAME} = ${BOOT} ]; then
	failed=false
	for worker in ${WORKER_LIST}; do
		for item in ${add_worker}; do
			if [ ${item} = ${worker} ]; then
				echo "Found ${label} worker in ${label} worker list (${item})"
				resolve_ip ${item}	# result in resolve_ip_return_result
				worker_ip=${resolve_ip_return_result}

				set -o xtrace
				mkdir -p "${cfc_deployment_directory_cwd}"
				cd "${cfc_deployment_directory_cwd}"
				set +o errexit
				docker run ${manual_docker_command} -e LICENSE=accept ${ansible_temp_location_args} ${cfc_debug1} ${docker_prod_args} -v "${cfc_deployment_directory_path}" ${docker_registry}${docker_stream}/${icp_image_name}:${cfc_image_version}${cfc_image_name_suffix} install ${cfc_debug2} -l ${worker_ip}
				error_status=$?
				set -o errexit
				cd ${WORKING_DIR}
				set +o xtrace

				if [ ${error_status} -ne 0 ]; then
					echo "Error detected, continuing"
					failed=true
				fi
			fi
		done
	done

	if [ ${failed} = true ]; then
		echo "Error(s) detected, admin must cleanup failed worker node addition"
		exit 3
	fi

	# Label the new node
	number_retries=20
	retry_wait_time=5
	counter=1
	while [ ${counter} -le ${number_retries} ]; do
		echo "Checking if ${worker_ip} is ready (${counter}/${number_retries})"
		set +o errexit
		kubectl get nodes | grep "${worker_ip}" | grep -w "Ready"
		exit_status=$?
		set -o errexit
		if [ ${exit_status} -ne 0 ]; then
			echo "${worker_ip} is not ready yet, retrying in ${retry_wait_time}s"
			sleep ${retry_wait_time}
			counter=`expr ${counter} + 1`
		else
			echo "Labeling ${add_worker} with type=${label}"
			echo "Taint ${add_worker} with node-role.kubernetes.io=${label}:PreferNoSchedule"
			break
		fi
	done
	if [ ${counter} -gt ${number_retries} ]; then
		echo "Maximum attempts reached, please check the health of ${add_worker}"
		exit 1
	fi
	kubectl label nodes "${worker_ip}" type=${label} --overwrite	# --overwrite required so command does not fail if a node has been removed and then added again with same label

	if [ "${add_infra_worker}" != "" ]; then
		kubectl taint nodes "${worker_ip}" dedicated=${label}:NoSchedule --overwrite # --overwrite required as with previous node label command i.e. so command does not fail if a node has been removed and then added again with same taint key value pair.
	fi


fi
