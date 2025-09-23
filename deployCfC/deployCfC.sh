#! /bin/bash
# Initial author: on Sun Feb  5 15:26:49 GMT 2017
#
# History:
# --------
# Sun Feb  5 15:26:49 GMT 2017
#	Initial version
#
#

. `dirname $0`/00-all-config.sh

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace


# Non-documented command to check sudo capabilities
if [ "$1" = --root_check ]; then
	if [ "`id -u`" = 0 ]; then
		exit 0
	else
		exit 101
	fi
fi

# Ensure from this point forward the script is running as root
if [ "`id -u`" != 0 ]; then
	echo
	echo "${DEPLOY_CFC_DIR}/${PRG} was run as non-root, re-running as root using sudo"

	exec sudo ${DEPLOY_CFC_DIR}/${PRG} $*
fi


# Begin deployment
if [ ${HOSTNAME} != ${BOOT} ]; then
	echo
	echo "${PRG} can only run from the boot node"
	echo
	echo "Current host ${HOSTNAME} must be the boot node, must be a fully qualified domain name, and must match hostname provided to --boot argument ${BOOT}"
	exit 3
fi

echo "Deployment invoked @ `date` on ${HOSTNAME}" | tee -a ${LOG_FILE}

SEMAPHORE_PREFIX=${DATE}
export SEMAPHORE_PREFIX


# Uninstall and worker removal
topology_reduction_step_list=""
if [ "${remove_worker}" != "" ]; then
	topology_reduction_step_list="R-01-boot-remove-worker.sh"
elif [ ${clean} -gt 0 ]; then
	# Version checking
	set +o errexit
	bash ${DEPLOY_CFC_DIR}/H-01-boot-version-checking.sh $* 2>&1 | tee -a ${LOG_FILE}
	exit_status=$?
	if [ ${exit_status} -ne 0 ]; then
		echo "Version checking failed"
		exit ${exit_status}
	fi
	set -o errexit

	topology_reduction_step_list="A-06-boot-copy.sh R-03-all-uninstall.sh"
	echo
	echo
	echo "Uninstall in ${uninstall} mode does not preserve configuration"
	echo "Note:  ${uninstall} mode does not destroy persistent data storage"
	echo
	echo "Are you certain to proceed?"
	echo
	printf "Enter \"yes\" to confim:  "
	read answer
	if [ "${answer}" != yes ]; then
		echo
		echo "Uninstall terminated.  No changes to systems."
		echo
		exit 0
	fi
fi
set -o errexit

if [ "${topology_reduction_step_list}" != "" ]; then
	for script in ${topology_reduction_step_list}; do
		echo "Starting ${script} @ `date` on ${HOSTNAME}" | tee -a ${LOG_FILE}
		echo
		echo "=== Executing @ local"
		set +o errexit
		bash ${script} $* 2>&1 | tee -a ${LOG_FILE}
		exit_status=$?
		if [ ${exit_status} -ne 0 ]; then
			echo "${script} failed on ${HOSTNAME}"
			exit ${exit_status}
		fi
		set -o errexit
		echo "Ending ${script} @ `date` on ${HOSTNAME}" | tee -a ${LOG_FILE}
	done

	terminate_uninstall=false
	for host in ${HOST_LIST}; do
		if grep -q uninstall.reboot.required=true ${CONFIG_DIR}/${host}; then
			echo
			echo "*** WARNING ***"
			echo "Reboot required on ${host} to complete uninstall"
			terminate_uninstall=true
			# Clean config file incase user is told to reboot and uninstall again
			sed -i '/uninstall.reboot.required=true/d' ${CONFIG_DIR}/${host}
		fi
	done	    
	echo
	if [ ${terminate_uninstall} = true ]; then
		exit 99
	fi

	echo "Uninstall complete"
	echo
	exit 0
fi


# Objective:
# 'A' stage must complete across all node types before 'B' stage, etc.
# boot steps must complete before master, worker, proxy node steps.
# Only subset of scripts run on existing nodes when adding worker node.

add_worker_list="A-04-all-setup-hosts.sh A-05-boot-setup-ssh-keys.sh A-06-boot-copy.sh"
if [ "${add_worker}" != "" ]; then
	step_list="${add_worker_list}"
else
	step_list=`ls -1 A-[0-9]*.sh`
fi
for script in ${step_list}; do
	echo "Starting ${script} @ `date` on ${HOSTNAME}" | tee -a ${LOG_FILE}
	echo
	echo "=== Executing @ local"
	set +o errexit
	bash ${script} $* 2>&1 | tee -a ${LOG_FILE}
	if [ $? -ne 0 ]; then
		echo "${script} failed on ${HOSTNAME}"
		exit 1
	fi
	set -o errexit
	echo "Ending ${script} @ `date` on ${HOSTNAME}" | tee -a ${LOG_FILE}
done

for host in ${HOST_LIST}; do
	step_list=`ls -1 A-[0-9]*.sh`
	if [ "${add_worker}" != "" ]; then
		step_list="${add_worker_list}"
		for new_worker in ${add_worker}; do
			for worker in ${WORKER_LIST}; do
				if [ ${new_worker} = ${worker} -a ${new_worker} = ${host} ]; then
					echo "=== Found a new worker ${new_worker}"
					step_list=`ls -1 A-[0-9]*.sh`
				fi
			done
		done
	fi
	for script in ${step_list}; do
		if [ ${host} != ${BOOT} ]; then
			echo "Starting ${script} @ `date` on ${host}" | tee -a ${LOG_FILE}
			echo
			echo "=== Executing @ ${host}"
			set +o errexit
			ssh_command ${host} "cd ${DEPLOY_CFC_DIR} && export SEMAPHORE_PREFIX=${SEMAPHORE_PREFIX} && /bin/bash ${script} $*" 2>&1 | tee -a ${LOG_FILE}
			if [ $? -ne 0 ]; then
				echo "${script} failed on ${host}"
				exit 2
			fi
			set -o errexit
			echo "Ending ${script} @ `date` on ${host}" | tee -a ${LOG_FILE}
		fi
	done
done


# Later stages do not have non-concurrency requirements, but also only run them at
# initial deployment
if [ "${add_worker}" != "" ]; then
	step_list="B-20-boot-prep-cfc.sh R-02-boot-add-worker.sh"
else
	step_list=`ls -1 B-[0-9]*.sh`
fi
for script in ${step_list}; do
	echo "Starting ${script} @ `date` on ${HOSTNAME}" | tee -a ${LOG_FILE}
	echo
	echo "=== Executing @ local"
	set +o errexit
	bash ${script} $* 2>&1 | tee -a ${LOG_FILE}
	if [ $? -ne 0 ]; then
		echo "${script} failed on ${HOSTNAME}"
		exit 3
	fi
	set -o errexit
	echo "Ending ${script} @ `date` on ${HOSTNAME}" | tee -a ${LOG_FILE}
done

for script in ${step_list}; do
	for host in ${HOST_LIST}; do
		if [ ${host} != ${BOOT} ]; then
			echo "Starting ${script} @ `date` on ${host}" | tee -a ${LOG_FILE}
			echo
			echo "=== Executing @ ${host}"
			set +o errexit
			ssh_command ${host} "cd ${DEPLOY_CFC_DIR} && export SEMAPHORE_PREFIX=${SEMAPHORE_PREFIX} && /bin/bash ${script} $*" 2>&1 | tee -a ${LOG_FILE}
			if [ $? -ne 0 ]; then
				echo "${script} failed on ${host}"
				exit 4
			fi
			set -o errexit
			echo "Ending ${script} @ `date` on ${host}" | tee -a ${LOG_FILE}
		fi
	done
done

# C steps
if [ "${add_worker}" != "" ]; then
	step_list=""
else
	step_list=`ls -1 C-[0-9]*.sh`
fi

for script in ${step_list}; do
	for host in ${HOST_LIST}; do
		if [ ${host} != ${BOOT} ]; then
			echo "Starting ${script} @ `date` on ${host}" | tee -a ${LOG_FILE}
			echo
			echo "=== Executing @ ${host}"
			set +o errexit
			ssh_command ${host} "cd ${DEPLOY_CFC_DIR} && export SEMAPHORE_PREFIX=${SEMAPHORE_PREFIX} && /bin/bash ${script} $*" 2>&1 | tee -a ${LOG_FILE}
			if [ $? -ne 0 ]; then
				echo "${script} failed on ${host}"
				exit 4
			fi
			set -o errexit
			echo "Ending ${script} @ `date` on ${host}" | tee -a ${LOG_FILE}
		fi
	done
done

for script in ${step_list}; do
	echo "Starting ${script} @ `date` on ${HOSTNAME}" | tee -a ${LOG_FILE}
	echo
	echo "=== Executing @ local"
	set +o errexit
	bash ${script} $* 2>&1 | tee -a ${LOG_FILE}
	if [ $? -ne 0 ]; then
		echo "${script} failed on ${HOSTNAME}"
		exit 3
	fi
	set -o errexit
	echo "Ending ${script} @ `date` on ${HOSTNAME}" | tee -a ${LOG_FILE}
done

(
	# XYZZY:  assumes co-located boot with master
	if ${is_master_HA}; then
		echo
		echo "Validating all master nodes are configured for high availability"

		SEMAPHORE=${SEMAPHORE_PREFIX}.1
		for semaphore in ${semaphore_targets}; do
			if [ -f ${semaphore} ]; then
				echo "Undetermined failure configuring master nodes - semaphore ${semaphore} still exists"
				exit 5
			fi
		done

		setSemaphore ${SEMAPHORE}		# return in semaphore_init
		if [ ${semaphore_init} != true ]; then
			echo "All master nodes are not configured for high availability, problem interfacing with etcd, or some other issue (${semaphore_init})"
			exit 6
		fi
		deleteSemaphore ${SEMAPHORE}

		echo
		echo "All master nodes configured for high availability"
	fi

	echo
	echo
	echo "=== IBM Cloud private deployment completed successfully"

	if ${is_master_HA}; then
		master_ip=${master_HA_vip}
	else
		resolve_ip ${MASTER_LIST}	# result in resolve_ip_return_result
		master_ip=${resolve_ip_return_result}
		set -o errexit
	fi

        if grep -q ic_server_behind_proxy=true ${CONFIG_DIR}/${HOSTNAME}; then
		echo
		echo "*** WARNING ***"
		echo "Redis has not been configured. This could be due to a firewall, an unresponsive server or some other issue that needs to be investigated. Please configure redis manually using the steps in the documentation."
	fi

	if grep -q regenerate_passwords=true ${CONFIG_DIR}/${HOSTNAME}; then
		echo
		echo "*** WARNING ***"
		echo "Elasticsearch certs have been regenerated. Please follow the online documentation to re-import the certs to WebSphere if you are using Elasticsearch Metrics."
	fi	    

	echo
	echo "IBM Cloud private Admin UI:  https://${master_ip}:8443"
	echo "Default username/password is ${ADMIN_USER}/${ADMIN_PASSWD}"

	echo
) 2>&1 | tee -a ${LOG_FILE}

