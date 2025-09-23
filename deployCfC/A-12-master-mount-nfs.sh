#! /bin/bash
#title		:A-12-master-setupNfsRedirect.sh
#description	:This script will setup the redirect to the nfs server.
#version	:0.1
#usage		:bash A-12-master-setupNfsRedirect.sh
#==============================================================================

. ./00-all-config.sh

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

if [ ${is_master_HA} != true ]; then
	echo "master HA NFS mounts unnecessary - skipping"
	exit 0
fi

TARGET_FILE=/etc/fstab

echo
declare -a MOUNTS=("${DOCKER_REGISTRY}" "${CP_AUDIT}")
declare -a HA_MOUNT_DETAILS=("${master_HA_mount_registry}" "${master_HA_mount_audit}")

if [ "${HA_MOUNT_DETAILS[0]}" = "" ]; then
	echo "Optional high avability NFS mounts not provided.  Skipping mount steps - must be performed manually."
	exit 0
fi

resolve_ip ${HOSTNAME}
set -o errexit
MASTER_IP=${resolve_ip_return_result}

NFS_OPTIONS="rw,hard,nfsvers=4,tcp,timeo=200,clientaddr=${MASTER_IP} 0 0"

checkFstab () {
	set +o errexit
	grep -v '^#' ${TARGET_FILE} | grep -q "[ 	]${1}[ 	]"
	if [ $? -eq 0 ]; then
		set -o errexit
		replaceMountInFstab ${1} ${2}
	else
		set -o errexit
		addMountToFstab ${1} ${2}
	fi
}

makeMountDirectories () {
	if [ ! -d ${1} ]; then
		echo "Creating directory ${1}"
		mkdir -p ${1}
	fi
}

addMountToFstab () {
	echo "Adding ${1} to ${TARGET_FILE}"
	echo "${2} ${1} nfs ${NFS_OPTIONS}" >> ${TARGET_FILE}
}

replaceMountInFstab () {
	echo "Updating ${1} in ${TARGET_FILE}"
	sed -i "/^#/b; s%.*${1}.*%${2} ${1} nfs ${NFS_OPTIONS}%" ${TARGET_FILE}
}

diffFstab () {
	set +o errexit
	diff ${TARGET_FILE}.${DATE} ${TARGET_FILE}
	set -o errexit
}

mountDir () {
	echo "Mounting ${1}"
	mount ${1}
}

umountDir () {
	echo "Unmounting ${1}"
	umount ${1} || { echo "No need to umount" ; : ; }
}

cp -p ${TARGET_FILE} ${TARGET_FILE}.${DATE}
COUNT=0
for entry in "${MOUNTS[@]}"
do
	echo
	echo "Checking mount ${MOUNTS[$COUNT]}"
	makeMountDirectories ${MOUNTS[$COUNT]}
	umountDir ${MOUNTS[$COUNT]}
	checkFstab ${MOUNTS[$COUNT]} ${HA_MOUNT_DETAILS[$COUNT]}
	diffFstab
	mountDir ${MOUNTS[$COUNT]}
	COUNT=$(expr $COUNT + 1)
done

