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

mkdir -p ${CONFIG_DIR}
touch ${CONFIG_DIR}/${HOSTNAME}

if [ ${HOSTNAME} = ${BOOT} ]; then
	failed=false
	for worker in ${WORKER_LIST}; do
		for item in ${remove_worker}; do
			for item2 in ${BOOT} ${MASTER_LIST} ${PROXY_LIST}; do
				if [ ${item} = ${item2} ]; then
					echo
					echo "Cannot remove co-located worker node from boot, master, or proxy nodes"
					echo "as that removes IBM Cloud private from the node entirely"
					echo "which disables all co-located nodes along with the worker node."
					echo
					exit 4
				fi
			done
			if [ ${item} = ${worker} ]; then
				echo "Found worker in worker list (${item})"
				resolve_ip ${item}	# result in resolve_ip_return_result
				worker_ip=${resolve_ip_return_result}

				set -o xtrace
				mkdir -p "${cfc_deployment_directory_cwd}"
				cd "${cfc_deployment_directory_cwd}"
				set +o errexit
				docker run ${manual_docker_command} -e LICENSE=accept ${ansible_temp_location_args} ${cfc_debug1} ${docker_prod_args} -v "${cfc_deployment_directory_path}" ${docker_registry}${docker_stream}/${icp_image_name}:${cfc_image_version}${cfc_image_name_suffix} uninstall ${cfc_debug2} -l ${worker_ip}
				error_status=$?
				set -o errexit
				cd ${WORKING_DIR}
				set +o xtrace

				if [ ${error_status} -ne 0 ]; then
					echo "Error detected, continuing"
					failed=true
				fi

				# Cleanup potentially bad cert (issue #6399)
				rm -f /etc/docker/certs.d/master.cfc:8500/ca.crt
			fi
		done
	done
	if [ ${failed} = true ]; then
		echo "Error(s) detected, admin must cleanup failed worker node removal"
		exit 3
	fi
fi

