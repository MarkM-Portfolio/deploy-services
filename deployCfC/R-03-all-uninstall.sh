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

if [ ${HOSTNAME} != ${BOOT} ]; then
	set +o nounset
	if [ "${DEPLOYFCF_OK}" != true ]; then
		echo "Cannot run $0 in standalone mode to reduce chance"
		echo "of accidental loss of data. Run from boot node."
		exit 2
	fi
	set -o nounset
fi

mkdir -p ${CONFIG_DIR}
touch ${CONFIG_DIR}/${HOSTNAME}

# Verify block device
if [ "${docker_storage_block_device}" != "" ]; then
	installed_block_device=`sed -n 's/^block.device=//p' ${CONFIG_DIR}/${HOSTNAME}`
	if [[ -z "${installed_block_device}" ]]; then
		echo "WARNING: Unable to determine what block device was selected during install."
	else
		if [ "${docker_storage_block_device}" != "${installed_block_device}" ]; then
			echo "Found that block device ${installed_block_device} was used during the install and ${docker_storage_block_device} is being used for the uninstall."
			echo "Please use the same value for uninstall to ensure no accidental data loss."
			exit 1
		fi
	fi
fi

# Execute uninstall
cd ${DEPLOY_CFC_DIR}
set +o errexit
set -o xtrace
uninstallKibana && \
	bash A-07-all-uninstall-cfc.sh $* && \
	bash A-07-all-uninstall-docker.sh $*
error_status=$?
if [ ${debug} = false ]; then
	set +o xtrace
fi
if [ ${error_status} -ne 0 ]; then
	echo "Error detected, continuing"
fi

echo "Killing dangling processes"
echo
ps ax | grep hyperkube | grep -v grep | awk '{ print $1 }' | xargs -r -l ps -uwww -p
echo
ps ax | grep hyperkube | grep -v grep | awk '{ print $1 }' | xargs -r kill -TERM
echo
ps ax | grep hyperkube | grep -v grep | awk '{ print $1 }' | xargs -r kill -KILL
echo
ps ax | grep hyperkube | grep -v grep | awk '{ print $1 }' | xargs -r -l ps -uwww -p
echo

# Invoke on all non-boot nodes (which would not include nodes co-located with boot)
set -o errexit
if [ ${HOSTNAME} = ${BOOT} ]; then
	echo
	echo "=== Entering intermediate uninstall section"
	echo

	cd ${WORKING_DIR}
	set +o errexit
	node_list=""
	for node in ${PROXY_LIST} ${WORKER_LIST} ${MASTER_LIST}; do
		if [ ${node} != ${HOSTNAME} ]; then
			echo ${node_list} | grep -q "${node}"
			if [ $? -eq 1 ]; then
				node_list="${node_list} ${node}"
			fi
		fi
	done
	set -o errexit

	set +o nounset
	if [ "${SEMAPHORE_PREFIX}" = "" ]; then
		echo "SEMAPHORE_PREFIX not set"
		echo "Suggestion:  export SEMAPHORE_PREFIX=${DATE}"
		exit 50
	fi
	set -o nounset

	set +o errexit
	for node in ${node_list}; do
		ssh_command ${node} "cd ${DEPLOY_CFC_DIR} && export DEPLOYFCF_OK=true && export SEMAPHORE_PREFIX=${SEMAPHORE_PREFIX} && /bin/bash $0 $*"
		if [ $? -ne 0 ]; then
			echo "Unable to SSH using password or keys, continuing anyway..."
		fi
		ssh_command ${node} "cat ${CONFIG_DIR}/${node}" > ${CONFIG_DIR}/${node}
	done
	set -o errexit

	echo
	echo "=== Leaving intermediate uninstall section"
	echo
fi

# Cleanup
set +o errexit
echo
echo "Unmounting any leftover Docker container mounts and proc filesystems"
if [ "`mount | grep /var/lib/kubelet`" != "" ]; then
	mount | grep /var/lib/kubelet | awk '{ print $3 }' | xargs -t -l umount
fi
if [ "`mount | grep ${DOCKER} | grep /overlay/`" != "" ]; then
	mount | grep ${DOCKER} | grep /overlay/ | awk '{ print $3 }' | xargs -t -l umount
fi
if [ "`mount | grep ${DOCKER} | grep /devicemapper/`" != "" ]; then
	mount | grep ${DOCKER} | grep /devicemapper/ | awk '{ print $3 }' | xargs -t -l umount
fi
if [ "`mount | grep ${DOCKER}`" != "" ]; then
	mount | grep ${DOCKER} | awk '{ print $3 }' | xargs -t -l umount
fi
if [ "`mount | grep /run/docker`" != "" ]; then
	mount | grep /run/docker | awk '{ print $3 }' | xargs -t -l umount
fi

echo
echo "Uninstalling from crontab"
tmp_file=`mktemp || exit 102`
for script in logrotate.sh; do
	set +o errexit
	crontab -l > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo "Detected existing crontab:"
		crontab -l
		crontab -l | egrep -v ${RUNTIME_BINS}/bin/${script} >> ${tmp_file}
	fi
	set -o errexit
	echo "Installing crontab:"
	cat ${tmp_file}
	set +o errexit
	crontab ${tmp_file}
	if [ $? -ne 0 ]; then
		echo "Unable to install crontab"
		exit 104
	fi
	set -o errexit
	rm -f ${tmp_file}
done
set -o errexit

echo
pink_uninstall_list="${WORKING_DIR}/mongo-secret ${WORKING_DIR}/elasticsearch ${WORKING_DIR}/solr-secrets"
for item in ${pink_uninstall_list}; do
	printf "Checking ${item}... "
	if [ -e ${item} ]; then
		mv ${item} ${item}.${DATE}
		if [ ${clean} -ge 3 ]; then
			echo "removing ${item} (${DATE})"
			rm -rf ${item}.${DATE}
		else
			echo "renaming ${item} to ${item}.${DATE} - delete if you are sure you don't need it"
		fi
	else
		echo "does not exist"
	fi
done

echo
misc_uninstall_list="${RUNTIME_BINS}/bin/kubectl ${RUNTIME_BINS}/bin/helm ${RUNTIME_BINS}/bin/calicoctl ${RUNTIME_BINS}/bin/logrotate.sh ${RUNTIME_BINS}/runtime/etc/logrotate.d/connections-docker-container /etc/logrotate.d/connections-docker-container"
for item in ${misc_uninstall_list}; do
	printf "Removing ${item}... "
	if [ -e ${item} ]; then
		rm -f ${item}
		echo done
	else
		echo "already removed"
	fi
done

echo
echo "Removing helm, kubectl, calicoctl"
# Remove old installs
rm -rf /usr/local/helm /usr/local/kubectl /usr/local/calicoctl /usr/local/etc/logrotate.d
rm -f /usr/local/bin/helm /usr/local/bin/kubectl /usr/local/bin/calicoctl /usr/local/bin/logrotate.sh 
rm -rf ${RUNTIME_BINS}/helm ${RUNTIME_BINS}/kubectl ${RUNTIME_BINS}/calicoctl

echo
cfc_uninstall_list_subdir="${semaphore_targets}"
uninstall_dir=${SEMAPHORE_PREFIX}.uninstall
for item in ${cfc_uninstall_list_subdir}; do
	printf "Checking ${item}... "
	if [ -d "${item}" ]; then
		pushd ${item} > /dev/null
		touch ${SEMAPHORE_PREFIX}.${HOSTNAME}
		mkdir -p ${uninstall_dir}
		ls -1 | grep -v '\.uninstall$' | while read contents; do
			if [ ${clean} -ge 2 ]; then
				echo "removing ${contents} (${DATE})"
			else
				echo "moving contents of ${item} to ${item}/${uninstall_dir} - delete if you are sure you don't need it"
			fi
			mv "${contents}" "${uninstall_dir}/${contents}"
		done
		if [ ${clean} -ge 2 ]; then
			set +o errexit
			rm -rf ${uninstall_dir}
			set -o errexit
		fi
		popd > /dev/null
	elif [ -e "${item}" ]; then
		echo "Unexpected situation - ${item} exists but is not a directory"
		exit 40
	else
		echo "does not exist"
	fi
done

echo
if [ ${skip_ssh_key_generation} = false -o "${pregenerated_private_key_file}" != "" ]; then
	ssh_key_uninstall_list="${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}"
else
	echo "Skipping SSH key uninstall steps"
	ssh_key_uninstall_list=""
fi
cfc_uninstall_list="${INSTALL_DIR}/cluster/images ${INSTALL_DIR}/cluster ${ssh_key_uninstall_list} /var/lib/elasticsearch /var/lib/etcd /var/lib/helm /var/lib/kubelet /var/lib/mysql /var/run/calico /var/run/secrets /var/run/kubernetes /root/.kube /root/.helm /root/.ansible /root/.cache/pip `eval echo ~${user}`/.ansible /opt/ibm/cfc/cloudant /opt/ibm/cfc/logging /opt/ibm/cfc /etc/cfc /var/lib/dockershim /opt/kubernetes /opt/cni"
for item in ${cfc_uninstall_list}; do
	printf "Checking ${item}... "
	if [ -e ${item} ]; then
		mv ${item} ${item}.${DATE}
		remove=false
		if [ ${clean} -ge 2 ] && [ ${item} = /var/lib/elasticsearch ]; then
			remove=true
		fi
		if [ ${clean} -ge 2 ] && [ ${item} = ${INSTALL_DIR}/cluster/images ]; then
			remove=true
		fi
		if [ ${clean} -ge 2 ] && [ ${item} = /opt/ibm/cfc/cloudant ]; then
			remove=true
		fi
		if [ ${clean} -ge 2 ] && [ ${item} = /opt/ibm/cfc/logging ]; then
			remove=true
		fi
		if [ ${clean} -ge 3 ]; then
			remove=true
		fi
		if [ ${remove} = true ]; then
			echo "removing ${item} (${DATE})"
			rm -rf ${item}.${DATE}
		else
			echo "renaming ${item} to ${item}.${DATE} - delete if you are sure you don't need it"
		fi
	else
		echo "does not exist"
	fi
done

# Delete /opt/ibm/connections dir
echo
echo "Removing /opt/ibm/connections"
rm -rf /opt/ibm/connections

# Cleanup potentially bad cert (issue #6399)
echo
echo "Removing master cert"
rm -f /etc/docker/certs.d/master.cfc:8500/ca.crt

echo
docker_bk_dir_array=(${DOCKER}.bk*)
docker_uninstall_list="${DOCKER} ${docker_bk_dir_array[@]} /etc/docker /var/run/docker /var/run/docker.sock /var/run/docker.pid /root/.docker /var/log/containers /var/log/pods ${DOCKER_EXT_PROXY_DIR}/${DOCKER_EXT_PROXY_CONFIG_FILE}"
for item in ${docker_uninstall_list}; do
	printf "Checking ${item}... "
	if [ -e ${item} ]; then
		mv ${item} ${item}.${DATE}
		remove=false
		if [ ${clean} -ge 2 ] && [ ${item} = ${DOCKER} -o ${#docker_bk_dir_array[@]} -ne 0 ]; then
			remove=true
		fi
		if [ ${clean} -ge 3 ]; then
			remove=true
		fi
		if [ ${remove} = true ]; then
			counter=1
			max_tries=2
			while [ ${counter} -le ${max_tries} ]; do
				echo "removing ${item} (${DATE}) (${counter}/${max_tries})"
				set +o errexit
				rm -rf ${item}.${DATE}
				exit_status=$?
				set -o errexit
				counter=`expr ${counter} + 1`
				if [ ${exit_status} -eq 0 ]; then
					break
				else
					sleep 5
					printf "	... "
				fi
			done
			if [ ${counter} -gt ${max_tries} ]; then
				echo "unable to remove ${item}.${DATE} - ignoring, reboot required to complete uninstall"
				echo "uninstall.reboot.required=true" >> ${CONFIG_DIR}/${HOSTNAME}
			fi
		else
			echo "renaming ${item} to ${item}.${DATE} - delete if you are sure you don't need it"
		fi
	else
		echo "does not exist"
	fi
done

echo
if [ ${skip_ssh_key_generation} = false ]; then
	echo "Removing SSH key related files"
	for location in /root `eval echo ~${user}`; do
		AUTH_KEYS=${location}/.ssh/authorized_keys
		if [ -f ${AUTH_KEYS} ]; then
			echo
			rm -f ${AUTH_KEYS}.${DATE}
			cp -p ${AUTH_KEYS} ${AUTH_KEYS}.${DATE}
			for node in ${HOST_LIST}; do
				short_host=`echo ${node} | awk -F. '{ print $1 }'`
				sed -i "/root@${short_host}/d" ${AUTH_KEYS}
				sed -i "/${user}@${short_host}/d" ${AUTH_KEYS}
			done
			if [ ${location} != /root ]; then
				chown ${user} ${AUTH_KEYS}
			fi
			set +o errexit
			diff ${AUTH_KEYS}.${DATE} ${AUTH_KEYS}
			set -o errexit
		fi
		KNOWN_HOSTS=${location}/.ssh/known_hosts
		if [ -f ${KNOWN_HOSTS} ]; then
			echo
			rm -f ${KNOWN_HOSTS}.${DATE}
			cp -p ${KNOWN_HOSTS} ${KNOWN_HOSTS}.${DATE}
			for node in ${HOST_LIST}; do
				short_host=`echo ${node} | awk -F. '{ print $1 }'`
				resolve_ip ${node}	# result in resolve_ip_return_result
				if [ $? -ne 0 ]; then
					echo "Unable to resolve ${node}"
					exit 22
				else
					node_ip=${resolve_ip_return_result}
				fi
				ssh-keygen -f ${KNOWN_HOSTS} -R ${node}
				ssh-keygen -f ${KNOWN_HOSTS} -R ${short_host}
				ssh-keygen -f ${KNOWN_HOSTS} -R ${node_ip}
			done
			if [ ${location} != /root ]; then
				chown ${user} ${KNOWN_HOSTS}
			fi
			set +o errexit
			diff ${KNOWN_HOSTS}.${DATE} ${KNOWN_HOSTS}
			set -o errexit
		fi
	done
else
	echo "Not removing SSH key related files"
fi

echo
echo "Removing /etc/hosts modifications"
FILE=/etc/hosts
rm -f ${FILE}.${DATE}
cp -p ${FILE} ${FILE}.${DATE}
if [ ${skip_hosts_modification} = false ]; then
	for node in ${HOST_LIST}; do
		if [ ${node} != ${HOSTNAME} ]; then
			sed -i "/${node}/d" ${FILE}
		fi
	done
fi
sed -i 's/^[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*[ 	]*master.cfc$//' ${FILE}
sed -i 's/^[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*[ 	]*mycluster.icp$//' ${FILE}
sed -i 's/master.cfc//' ${FILE}
sed -i 's/mycluster.icp//' ${FILE}
set +o errexit
diff ${FILE}.${DATE} ${FILE}
set -o errexit

# XYZZY:  assumes co-located boot with master
echo
if [ ${BOOT} = ${HOSTNAME} -a "${uninstall}" != "" ]; then
	echo "The non-data preserving uninstall mode does not alter persistent storage."
	echo "Persistent storage cleanup is left to the admin."
	echo
fi

exit 0

