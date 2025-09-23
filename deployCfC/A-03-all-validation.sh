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


if [ ${skip_validation_checks} = true ]; then
	echo
	echo "Skipping validation checks"
	exit 0
fi


# return is 0 or non-0 if disk space requiremetns are met or not, respectively
checkDiskSpace () {
	set -o errexit
	set -o pipefail
	set -o nounset

	set +o nounset
	if [ "$2" = "" ]; then
		echo "usage:  checkDiskSpace nMB sFileSystem"
		exit 100
	fi
	space_needed="$1"
	filesystem="$2"
	set -o nounset

	isNum ${space_needed}
	if [ ${is_number} = false ]; then
		echo "${space_needed} is not a number"
		exit 101
	fi

	echo "Minimum space needed in ${filesystem}:  ${space_needed} MB"
	available=`df -B M ${filesystem}/ | awk '/[0-9]%/{print $(NF-2)}' | sed 's/M$//'`
	echo "Detected ${available} MB available in ${filesystem}"
	if [ ${available} -lt ${space_needed} ]; then
		echo "Must have at least ${space_needed} MB space free in the directory ${filesystem}"
		return 1
	else
		echo "Detected enough free space in ${filesystem}"
		echo "OK"
		return 0
	fi
}


function checkSysctl() {
	set -o errexit
	set -o pipefail
	set -o nounset

	set +o nounset
	if [ "$2" = "" ]; then
		echo "usage:  checkSysctl sSetting sValue [sValue2]..."
		exit 100
	fi
	setting="$1"
	shift
	value="$*"
	set -o nounset

	FILE=/etc/sysctl.conf

	echo
	echo "Checking sysctl ${setting} is set to \"${value}\""
	setting_ok=true
	if [ "`sysctl -n ${setting} | awk '$1=$1'`" != "${value}" ]; then
		echo "Runtime sysctl setting ${setting} not configured to \"${value}\""
		setting_ok=false
	fi
	set +o errexit
	if [ `grep "^${setting}[ 	]*=" ${FILE} | awk -F= '{ print $2 }' | awk '$1=$1'` != "${value}" ]; then
		echo "Persistent sysctl setting ${setting} in ${FILE} not configured to \"${value}\""
		setting_ok=false
	fi
	set -o errexit
	if [ ${setting_ok} = false ]; then
		exit 30
	fi
	echo "OK"
}


# Re-run pre-deployment validation
cd ${DEPLOY_CFC_DIR}
bash A-01-all-predeployment-validation.sh $*
cd ${WORKING_DIR}


# Early password validation
if [ "${user_passwd}" != "" ]; then
	echo
	echo "Validating password for ${user}"
	set +o errexit
	for node in ${HOST_LIST}; do
		printf "Checking ${user}@${node} - "
		${sshpass_bin} -p "${user_passwd}" ssh ${ssh_args} -C ${user}@${node} echo OK
		if [ $? -ne 0 ]; then
			echo
			echo "Password validation for ${user} failed"
			exit 200
		fi
	done
	set -o errexit
fi

# Some checks on upgrade case
if [ ${upgrade} = true ]; then
	set +o errexit
	mesos help
	if [ $? -eq 0 ]; then
		echo "Mesos has been detected in your cluster - unable to upgrade"
		exit 200
	fi
	systemctl status flanneld
	if [ $? -eq 0 ]; then
		echo
		echo "flanneld is installed, checking whether it is running"
		echo
		if [ "`systemctl status flanneld | grep Active: | awk '{print $2}'`" == "active" ]; then
			echo "flanneld.service detected in your cluster - unable to upgrade"
			exit 200
		fi
	fi
	set -o errexit
fi

if [ "${set_ic_host}" != "" ]; then
	validate_ic_host "--set_ic_host provided argument" ${set_ic_host} || exit 13
fi
set -o errexit

# Firewalls
if [ ${skip_disable_firewall} = false ]; then
	set +o errexit
	for firewall in ${FIREWALL_PACKAGES}; do
		firewall_running=false
		echo
		echo "Checking ${firewall} status"
		echo
		rpm -q ${firewall}
		if [ $? -eq 0 ]; then
			echo
			echo "${firewall} is installed, checking whether it is running"
			echo
			systemctl status ${firewall}
			if [ $? -eq 0 ]; then
				if [ ${firewall} = firewalld ]; then
					echo "Running supplemental firewall test for ${firewall}"
					firewall-cmd --state 2>&1
					if [ $? -eq 0 ]; then
						firewall_running=true
					fi
				else
					firewall_running=true
				fi
				if [ ${firewall_running} = true ]; then
					echo
					echo "${firewall} is running, must be disabled for installation"
					exit 17
				fi
			else
				echo "${firewall} is not running - OK"
			fi
		fi
	done
	set -o errexit
else
	echo
	echo "Skipping firewall status checks"
	echo
fi


# Check specified interfaces are valid
if [ ${is_master_HA} = true -a ${is_master} = true ]; then
	echo
	echo "Checking ${master_HA_iface}:"
	set +o errexit
	ifconfig ${master_HA_iface}
	if [ $? -ne 0 ]; then
		echo "master HA interface ${master_HA_iface} isn't valid"
		exit 13
	fi
	set -o errexit
	echo "master HA interface is valid"
fi
if [ ${is_proxy_HA} = true -a ${is_proxy} = true ]; then
	echo
	echo "Checking ${proxy_HA_iface}:"
	set +o errexit
	ifconfig ${proxy_HA_iface}
	if [ $? -ne 0 ]; then
		echo "proxy HA interface ${proxy_HA_iface} isn't valid"
		exit 14
	fi
	set -o errexit
	echo "proxy HA interface is valid"
fi


# OS tuning
if [ ${is_master} ]; then
	checkSysctl vm.max_map_count ${VM_MAX_MAP_COUNT}
fi

checkSysctl net.ipv4.ip_forward 1

if [ ${is_master} ]; then
	echo
	echo "Checking lower limit of the ephemeral port range is >= 10240"
	ephemeral_port_range=`sysctl -n net.ipv4.ip_local_port_range`
	echo "Found ephemeral port range:  ${ephemeral_port_range}"
	lower_limit=`echo ${ephemeral_port_range} | awk '{ print $1 }'`
	echo "Found lower limit of ephemeral port range:  ${lower_limit}"
	isNum ${lower_limit}
	if [ ${is_number} = false ]; then
		echo "Lower port range for net.ipv4.ip_local_port_range configured incorrectly:  ${lower_limit}"
		exit 101
	fi
	if [ ${lower_limit} -lt 10240 ]; then
		echo "Lower port range for net.ipv4.ip_local_port_range must be >= 10240"
		exit 102
	fi
	echo "OK"
fi


# SELinux
echo
echo "Checking SELinux"
if [ `getenforce` = Enforcing ]; then
	if [ ${skip_disable_selinux} = true ]; then
		echo "SELinux is enabled - OK for version ${CFC_VERSION}"
	else
		echo "SELinux must be disabled"
		exit 11
	fi
else
	echo "SELinux is not enabled - OK"
fi


# Check ports
set +o errexit

# Some scripts we don't run after initial deployment by default,
# but can run them if needed
echo
if [ ${skip_port_check} = true ]; then
	echo "--skip_port_check flag detected. Skipping port check."
else
	if [ ${upgrade} = true ]; then
		echo "Not running port check when upgrading since ports are expected to be in use"
	else
		TMP=`mktemp ${TMP_TEMPLATE} || exit 15`		# ensure unique
		number_retries=10
		retry_wait_time=30

		echo "Checking ports which should not already be in use"
		counter=1
		while [ ${counter} -le ${number_retries} ]; do
			found_port=false
			netstat -anp > ${TMP}
			for port in ${PORT_LIST}; do
				printf "Checking port ${port} - "
				awk '{ print $4 }' ${TMP} | grep -q ":${port}$"
				if [ $? -eq 0 ]; then
					found_port=true
					echo "ERROR, found open port"
					echo
					grep ":${port} " ${TMP}
					echo
				else
					echo "OK"
				fi
			done

			for k8s_port_range in ${K8S_PORT_RANGES}; do
				echo
				echo "Checking for Kubernetes port range:  ${k8s_port_range}"
				k8s_port_range_start=`echo ${k8s_port_range} | awk -F- '{ print $1 }'`
				k8s_port_range_end=`echo ${k8s_port_range} | awk -F- '{ print $2 }'`
				k8s_port_range_check=`grep '^tcp.*' ${TMP} | awk '{ print $4 }' | awk -F: "\\$NF >= ${k8s_port_range_start} && \\$NF <= ${k8s_port_range_end} { print \\$NF }"`
				if [ $? -eq 0 -a "${k8s_port_range_check}" = "" ]; then
					echo "OK"
				else
					echo
					echo "Might be a false alarm, but may have found an open port in the Kubernetes port range"
					echo
					for port in ${k8s_port_range_check}; do
						grep ":${port} " ${TMP}
					done
					found_port=true
				fi
			done

			echo
			if [ ${found_port} = true ]; then
				echo "Port check failed, retrying in ${retry_wait_time}s"
				sleep ${retry_wait_time}
			else
				echo "Port check succeeded"
				break
			fi
			counter=`expr ${counter} + 1`
		done

		if [ ${found_port} = true ]; then
			echo
			cat ${TMP} >> ${LOG_FILE}
			echo "Ports are open"
			echo "Verify IBM Connections, IBM Cloud private, Kubernetes, and Docker are not installed."
			echo "A reboot may also be required."
			echo "If you are upgrading, ports are expected to be open.  Provide argument --upgrade to perform upgrade."
			exit 16
		fi

		rm ${TMP}
	fi
fi
set -o errexit


# Check mysql
echo
if [ ${skip_mysql_check} = true ]; then
	echo "--skip_mysql_check flag detected. Skipping mysql check."
else
	if [ ${upgrade} = true ]; then
		echo "Not running mysql check when upgrading since mysql is expected to be installed"
	else
		echo "Checking whether mysql is installed"
		if [ -d /var/lib/mysql/mysql ]; then
			echo "mysql is installed, conflicts with IBM Cloud private, fatal error."
			echo "If mysql has been uninstalled, check if /var/lib/mysql exists."
			echo "If so, and you are sure the data is unneeded, remove or rename the directory."
			exit 12
		fi
		echo "OK"
	fi
fi


# Self-provided SSH cert
if [ "${pregenerated_private_key_file}" != "" -a ${HOSTNAME} = ${BOOT} ]; then
	echo
	echo "Validating pre-generated SSH private key file exists"
	if [ ! -f "${pregenerated_private_key_file}" ]; then
		echo "Not a file:  ${pregenerated_private_key_file}"
		exit 20
	fi
	found=true
	if [ ! -f "${pregenerated_private_key_file}" ]; then
		echo "Can't find ${pregenerated_private_key_file}"
		found=false
	fi
	if [ ${found} = false ]; then
		echo "The required self-provided SSH private key file is missing"
		exit 21
	fi
	echo "OK file exists"
fi

# Self-provided config.yaml for support purposes only
if [ "${custom_config}" != "" -a ${HOSTNAME} = ${BOOT} ]; then
	if [ ! -f "${custom_config}" ]; then
		echo "Either ${custom_config} is not a file or it cannot be found"
		echo "The required self-provided custom config.yaml is missing"
		exit 23
	fi
	echo "OK custom config.yaml file exists"
fi


# Basic deployment disk space check
# This is overkill since it assumes all node types co-existing
# If individually (already rounded up 25% or so for growth):
if [ "${skip_disk_space_check}" = false ]; then
	echo
	echo "Checking general disk space requirements"
	#checkDiskSpace 15360 ${DOCKER} || exit 105			# 15GB in MB
	#checkDiskSpace 3072 ${DOCKER_REGISTRY} || exit 105		# 3GB in MB
	#checkDiskSpace 15360 /var/lib/elasticsearch || exit 105	# 15GB in MB
	#checkDiskSpace 7680 /var/lib/etcd || exit 105			# 7.5GB in MB
	# But those are all in /var so assuming they are not separate filesystems
	# and rounding up 20% for more growth.
	#
	# Even though different node types will not have all of these areas
	# consuming space in /var, a PoC 1 VM deployment will.  So this check
	# is overkill to cover that case.  A better approach would be to
	# split this up into separate checks using is_master, etc and tally
	# the numbers before the check.

	if [ ${upgrade} = true ]; then
		checkDiskSpace 20480 /var || exit 105			# 20GB in MB
	else
		checkDiskSpace 40960 /var || exit 105			# 40GB in MB
	fi

	# ICp EE
	if [ "${cfc_ee_url}" != "" ]; then
		echo "Checking disk space needed for Cloud private EE download"
		# Check if ${cfc_ee_url} is a URL for download space
		if [ "${cfc_ee_url}" != "" ]; then
			# CFC_VERSION 1.2.1, will increase for CFC_VERSION 2.1.x
			# issue 7673
			if [ "${temporary_file_location}" != "" ]; then
				# TBD:  ?GB compressed archive for URL form of cfc_ee_url + ?GB for uncompressed archive + 4GB for unarchive
				checkDiskSpace 10240 "${temporary_file_location}" || exit 102		# 10GB in MB
			else
				# 2GB compressed archive for URL form of cfc_ee_url + 4GB for uncompressed archive + 4GB for unarchive
				checkDiskSpace 10240 /tmp || exit 102		# 10GB in MB
				# 4GB for uncompressed archive before it is copied to /tmp
				checkDiskSpace 4096 /root || exit 102		# 4GB in MB
			fi
		fi
		checkDiskSpace 2048 ${WORKING_DIR} || exit 103		# 2GB in MB
	fi
fi


# If using a non-root user, ensure that non-root user can sudo and do so
# without a password
if [ ${user} != root ]; then
	echo
	echo "Checking specified non-root user ${user} can sudo without password"
	set +o errexit
	sudo -u ${user} ${setuid_bin} ${user} sudo -n ${DEPLOY_CFC_DIR}/deployCfC.sh --root_check $*
	if [ $? -ne 0 ]; then
		echo "FAILED"
		exit 101
	else
		echo "OK"
	fi
	set -o errexit
fi


echo
proxyArray=(${PROXY_LIST//,/ })
workerArray=(${WORKER_LIST//,/ })
masterArray=(${MASTER_LIST//,/ })

if [ "${BOOT}" = "${MASTER_LIST}" -a "${BOOT}" = "${WORKER_LIST}" -a "${BOOT}" = "${PROXY_LIST}" ]; then	# If all on 1 VM
		compareVersions ${CFC_VERSION} 2.1.0.1
		if [ ${comparison_result} -eq 1 ]; then
			RAM_MIN=24117248	# Minimum is 24GB for 1 VM deployment, but the full 24GB never reports so using 23GB in KB
		else	# >= 2.1.0.1
			RAM_MIN=32505856	# Minimum is 32GB for 1 VM deployment, but the full 32GB never reports so using 31GB in KB
		fi
else 
	if [[ "${proxyArray[@]}" =~ "${HOSTNAME}" ]]; then	# If proxy
		if [[ "${masterArray[@]}" =~ "${HOSTNAME}" || "${workerArray[@]}" =~ "${HOSTNAME}" || "${HOSTNAME}" == "${BOOT}" ]]; then	# If not standalone proxy
			if [ ${is_master_HA} = true ]; then 	# if not standalone proxy and if it is HA
				RAM_MIN=7602176		# Minimum is 8GB, but the full 8GB never reports so using 7.25GB in KB
			else 	# if its not standalone proxy and its non-HA
				RAM_MIN=7602176		# Minimum is 8GB, but the full 8GB never reports so using 7.25GB in KB
			fi
		else	# If standalone proxy
			RAM_MIN=3670016 	# Minimum is 4GB for standalone proxy node, but the full 4GB never reports so using 3.5GB in KB
		fi
	elif [[ "${masterArray[@]}" =~ "${HOSTNAME}" ]]; then	# If master
		if [ ${is_master_HA} = true ]; then 	# if master HA
			RAM_MIN=7602176		# Minimum is 8GB, but the full 8GB never reports so using 7.25GB in KB
		else 	# if master non-HA
			RAM_MIN=7602176		# Minimum is 8GB, but the full 8GB never reports so using 7.25GB in KB
		fi
	elif [[ "${workerArray[@]}" =~ "${HOSTNAME}" ]]; then	# If worker
		# XYZZY:  figure out an algorithm for worker nodes (see #461)	
		RAM_MIN=7602176		# Minimum is 8GB, but the full 8GB never reports so using 7.25GB in KB
	else 	# If not a master, worker or proxy
		RAM_MIN=7602176		# Minimum is 8GB, but the full 8GB never reports so using 7.25GB in KB
	fi
fi

memory_kb=`grep '^MemTotal:' /proc/meminfo | awk '{ print $2 }'`
echo "Detected installed RAM:  ${memory_kb} KB"
if [ ${memory_kb} -lt ${RAM_MIN} ]; then
	echo "Must have at least ${RAM_MIN} KB RAM"
	if [ ${ignore_hardware_requirements} = true ]; then
		echo "Ignoring incompatible RAM requirement warning"
	else
		echo "Use --ignore_hardware_requirements flag to proceed anyway, but the results are not supported"
		exit 2
	fi
else
	echo "Minimum RAM requirement met"
fi


# Minimum is 2.4 GHz, but the full amount never reports so using 2.35 GHz
echo
CPU_FREQ_MIN=2350	# MHz
cpu_freq=`grep '^cpu MHz' /proc/cpuinfo | head -1 | awk '{ print $NF }' | awk -F. '{ print $1 }'`
echo "Detected CPU frequency:  ${cpu_freq} MHz"
if [ ${cpu_freq} -lt ${CPU_FREQ_MIN} ]; then
	echo "Must have at least ${CPU_FREQ_MIN} MHz CPU"
	#if [ ${ignore_hardware_requirements} = true ]; then
		echo "Ignoring incompatible CPU frequency warning"
	#else
	#	echo "Use --ignore_hardware_requirements flag to proceed anyway"
	#	exit 3
	#fi
else
	echo "Minimum 2.4 GHz CPU frequency requirement met"
fi


# Minimum cores check
echo
if [ "${BOOT}" = "${MASTER_LIST}" -a "${BOOT}" = "${WORKER_LIST}" -a "${BOOT}" = "${PROXY_LIST}" ]; then
	# Cores (for all in 1 VM deployment)
	compareVersions ${CFC_VERSION} 2.1.0.1
	if [ ${comparison_result} -eq 1 ]; then
		MIN_CPU=6
	else	# >= 2.1.0.1
		MIN_CPU=10
	fi
elif [ ${is_master_HA} = true ]; then
	MIN_CPU=4		# Cores (for HA deployment)
else
	MIN_CPU=4		# Cores
fi
num_cores=`nproc`
echo "Detected number of cores:  ${num_cores}"
num_nodes=`echo ${HOST_LIST} | wc -w`
if [ ${num_nodes} -lt 1 ]; then
	echo "Unable to calculate number of nodes in deployment (${num_nodes})"
	exit 3
fi
if [ ${num_cores} -lt ${MIN_CPU} -a ${num_nodes} -eq 1 ]; then
	echo "Must have at least ${MIN_CPU} cores when deploying with ${num_nodes} node(s)"
	if [ ${ignore_hardware_requirements} = true ]; then
		echo "Ignoring incompatible CPU core requirement"
	else
		echo "Use --ignore_hardware_requirements flag to proceed anyway"
		exit 3
	fi
else
	echo "Minimum CPU core requirements met"
fi

# Validate block device input
if [ "${docker_storage_block_device}" != "" ]; then
	# Check if Docker is already configured with block device (eg upgrade case)
	if echo `lsblk` | grep -A 1 $(basename $docker_storage_block_device) | grep -q docker-thinpool; then
		if [ ${upgrade} = true ]; then
			echo "Found Docker is set up already with block device. Skipping block device validation"
		else
			echo "Validation of ${docker_storage_block_device} has failed. Please ensure the block device has no physical volume already created."
			exit 22
		fi
	else	
		echo	
		echo "Starting validation of ${docker_storage_block_device}"
		echo
		# Check if ${docker_storage_block_device} is a block device on the system
		if lsblk -o KNAME | grep -wq "^$(basename ${docker_storage_block_device})$";then
			# Check if physical volume already created on block device
			if echo `pvscan` | grep -w ${docker_storage_block_device}; then
				echo
				echo "Found physical volume already created on ${docker_storage_block_device}"
				echo "To ensure a clean install, please remove the physical volume and try again."
				exit 22
			else # No physcial volume exists
				echo
				echo "Attempting to create physical volume on ${docker_storage_block_device} for validation.."
				set +o errexit
				pvcreate ${docker_storage_block_device}
				if [ $? -ne 0 ]; then
					echo "Unable to create physical volume on ${docker_storage_block_device}. Please ensure this is a valid block device with no physical volume already created."
					exit 22
				fi
				echo
				echo "Validation of block device ${docker_storage_block_device} complete."
				echo "Removing physical volume from ${docker_storage_block_device}"
				pvremove -f ${docker_storage_block_device}
				if [ $? -ne 0 ]; then
					echo "Problem removing physical volume from ${docker_storage_block_device}"
					exit 22
				fi
				dd if=/dev/zero of=${docker_storage_block_device} bs=512 count=10240
				set -o errexit
			fi
			echo
			echo "Validation of ${docker_storage_block_device} complete."
			echo
		else
			echo
			echo "Unable to find block device ${docker_storage_block_device}"
			echo "Please ensure you have provided a block device in the format /dev/XXX"
			echo "Example: --docker_storage_block_device=/dev/sdb"
			echo "Tip: Run the command \"lsblk\" to view available block devices on your system"
			exit 22
		fi
	fi
fi

# XYZZY:  move HA shared volume check here

