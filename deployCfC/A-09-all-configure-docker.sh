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

if [ ${skip_docker_deployment} = true ]; then
	echo "Not configuring Docker"
else
	if [ -e /proc/sys/fs/may_detach_mounts ]; then
		if [ ${skip_os_tuning} = true ]; then
			may_detach_mounts=$(cat /proc/sys/fs/may_detach_mounts)
			if [ "${may_detach_mounts}" != 1 ]; then
				echo "Found a value of ${may_detach_mounts} in file /proc/sys/fs/may_detach_mounts. This value must be set to 1."
				exit 22
			fi
		else
			echo 1 > /proc/sys/fs/may_detach_mounts
			echo fs.may_detach_mounts=1 > /usr/lib/sysctl.d/99-docker.conf
		fi
	fi

	systemctl stop docker
	FILE=${DOCKER_CONFIG_DIR}/${DOCKER_CONFIG_FILE}
	echo
	if [ -f ${FILE} ]; then
		echo "${FILE} exists"
		if [ ! -f ${FILE}.${DATE} ]; then
			echo "Creating backup ${FILE}.${DATE}"
			cp -p ${FILE} ${FILE}.${DATE}
		fi
	else
		mkdir -p ${DOCKER_CONFIG_DIR}
	fi
	if [ "${docker_storage_block_device}" = "" ]; then
		echo "Configuring Docker with the devicemapper storage driver: loop-lvm"
		echo "{" > ${FILE}
		echo "  \"storage-driver\": \"devicemapper\"" >> ${FILE}
		echo "}" >> ${FILE}

	else
		# Check if Docker is already configured with block device (eg upgrade case)
		if echo `lsblk` | grep -A 1 $(basename $docker_storage_block_device) | grep -q docker-thinpool; then
			echo "Found Docker is set up already with block device"
		else
			# If exists, move everything inside /var/lib/docker so that Docker can use the new LVM pool
			counter=1
			number_retries=3
			retry_delay=30
			while [ ${counter} -le ${number_retries} ]; do
				if [ -e ${DOCKER} ]; then
					if [ -e ${DOCKER}.bk ]; then
						echo "renaming ${DOCKER}.bk to ${DOCKER}.bk.${DATE}.${RANDOM}"
						mv ${DOCKER}.bk ${DOCKER}.bk.${DATE}.${RANDOM}
					fi
					mkdir -p ${DOCKER}.bk
					echo "Moving all content from ${DOCKER} to ${DOCKER}.bk"
					touch ${DOCKER}/${DATE}
					set +o errexit
					mv ${DOCKER}/* ${DOCKER}.bk
					if [ $? -eq 0 ]; then
						break
					else
						echo "Unexpected error moving Docker overlay files in preparation to configure devicemapper direct-lvm mode"
						if [ ${counter} -le ${number_retries} ]; then
							echo "Retrying in ${retry_delay}s (${counter}/${number_retries})"
							sleep ${retry_delay}
						else
							echo "No more retries (${counter}/${number_retries})"
						fi
						counter=`expr ${counter} + 1`
					fi
					set -o errexit
				else
					break
				fi
			done
			set -o errexit
			if [ ${counter} -gt ${number_retries} ]; then
				echo
				echo "Failure moving Docker overlay files in preparation to configure devicemapper direct-lvm mode"
				echo "Diagnostic output follows:"
				echo
				ps auxwwww
				echo
				lsof
				echo
				echo "Reboot, run uninstall, and then install again"
				exit 9
			fi

			# Store the block device used in config file so it can be verified when uninstalling			
			mkdir -p ${CONFIG_DIR}
			echo "block.device=${docker_storage_block_device}" >> ${CONFIG_DIR}/${HOSTNAME}			
			
			echo "Configuring Docker with the devicemapper storage driver: direct-lvm"
			# Set up direct-lvm docker storage driver
			set +o errexit
			pvcreate ${docker_storage_block_device}
			if [ $? -ne 0 ]; then
				echo "Unable to create physical volume on ${docker_storage_block_device}. Please ensure this is a valid block device and not associated with any other physical volume."
				exit 22
			fi
			vgcreate docker	${docker_storage_block_device}
			if [ $? -ne 0 ]; then
				echo "Unable to create a volume group from ${docker_storage_block_device}"
				exit 22
			fi
			set -o errexit
			lvcreate --wipesignatures y -n thinpool docker -l 95%VG
			lvcreate --wipesignatures y -n thinpoolmeta docker -l 1%VG
			lvconvert -y --zero n -c 512K --thinpool docker/thinpool --poolmetadata docker/thinpoolmeta

			# Set logical volume auto expansion
			echo "activation {" > /etc/lvm/profile/docker-thinpool.profile
			echo "  thin_pool_autoextend_threshold=80" >> /etc/lvm/profile/docker-thinpool.profile
			echo "  thin_pool_autoextend_percent=20" >> /etc/lvm/profile/docker-thinpool.profile
			echo "}" >> /etc/lvm/profile/docker-thinpool.profile
			lvchange --metadataprofile docker-thinpool docker/thinpool

			# enable monitoring so that auto expansion works
			lvs -o+seg_monitor

			# Set docker storage driver
			echo "{" > ${FILE}
			echo "    \"storage-driver\": \"devicemapper\"," >> ${FILE}
			echo "    \"storage-opts\": [" >> ${FILE}
			echo "    \"dm.thinpooldev=/dev/mapper/docker-thinpool\"," >> ${FILE}
			echo "    \"dm.use_deferred_removal=true\"," >> ${FILE}
			echo "    \"dm.use_deferred_deletion=true\"" >> ${FILE}
			echo "    ]" >> ${FILE}
			echo "}" >> ${FILE}
		fi
	fi
	systemctl start docker
	docker info
	echo "Docker devicemapper storage configuration complete"
fi

checkDockerLoggingDriver
if [ $? -ne 0 ]; then
	echo "Docker Logging Driver check failed"
	exit 99
else
	echo "Docker Logging Driver check successful"
fi
set -o errexit

checkDockerDeviceMapper
if [ $? -ne 0 ]; then
	echo "Docker devicemapper configuration check failed"
	exit 99
else
	echo "Docker devicemapper configuration check successful"
fi
set -o errexit

echo
echo "Running Docker hello-world test validation"
runDockerHelloWorldTest || exit 1
set -o errexit

