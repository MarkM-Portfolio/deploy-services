#! /bin/bash

#title		:configure-ha-storage.sh
#description	:This script will run the pv creation on the masters and pv serup on the nfs server
#version	:0.1
#usage		:configure-ha-storage.sh
####

conn_locn=$1
nfs_server=$2
root_password=$3
HA_MOUNT_REGISTRY=""
HA_MOUNT_AUDIT=""
ssh_args="-o StrictHostKeyChecking=no"
pwd=$(pwd)
ip=""

if [[ "$1" = "-h" ]] || [[ "$1" = "--help" ]] || [ $# -lt 1 ] || [ $# -gt 5 ]; then
	echo "${usage}"
	exit 1
fi

if [ $# -eq 4 ]; then
	HA_MOUNT_REGISTRY=$4
	HA_MOUNT_REGISTRY=`echo ${HA_MOUNT_REGISTRY} | cut -d ":" -f2`
fi

if [ $# -eq 5 ]; then	
	HA_MOUNT_REGISTRY=$4
	HA_MOUNT_REGISTRY=`echo ${HA_MOUNT_REGISTRY} | cut -d ":" -f2`
	HA_MOUNT_AUDIT=$5
	HA_MOUNT_AUDIT=`echo ${HA_MOUNT_AUDIT} | cut -d ":" -f2`
fi

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace
umask 022

ssh_args="-o StrictHostKeyChecking=no"

function setupNfsServer () {
	echo "Copy NFS setup script to server"
	$conn_locn/deployCfC/sshpass/bin/sshpass -p ${root_password} ssh ${ssh_args} root@${nfs_server} "rm -f /opt/nfsSetup.sh"
	$conn_locn/deployCfC/sshpass/bin/sshpass -p ${root_password} scp $pwd/microservices/hybridcloud/doc/samples/nfsSetup.sh root@${nfs_server}:/opt/nfsSetup.sh
	$conn_locn/deployCfC/sshpass/bin/sshpass -p ${root_password} scp $pwd/microservices/hybridcloud/doc/samples/fullPVs_NFS.yml root@${nfs_server}:/opt/fullPVs_NFS.yml

	IFS=$'\n'
	pvs=($(grep /pv $pwd/microservices/hybridcloud/doc/samples/fullPVs_NFS.yml | cut -d: -f2 | cut -d" " -f2))
	echo "Create pv storage on nfs server"
	for pv in ${pvs[@]}; do
		$conn_locn/deployCfC/sshpass/bin/sshpass -p ${root_password} ssh ${ssh_args} root@${nfs_server} "mkdir -p ${pv}"
	done
	pvs=($(grep /pv $pwd/microservices/hybridcloud/doc/samples/fullPVs_NFS.yml | cut -d/ -f2 | cut -d" " -f2))
	$conn_locn/deployCfC/sshpass/bin/sshpass -p ${root_password} ssh ${ssh_args} root@${nfs_server} "chmod -R 777 /${pvs[0]}/"

	echo "Export volumes"
	cp $pwd/microservices/hybridcloud/doc/samples/fullPVs_NFS.yml $pwd/
	$conn_locn/deployCfC/sshpass/bin/sshpass -p ${root_password} ssh ${ssh_args} root@${nfs_server} "cd /opt/ ; chmod +x nfsSetup.sh ; ./nfsSetup.sh"

	echo "Create mounts"
	if [[ "${HA_MOUNT_REGISTRY}" != "" ]]; then
		echo "Create HA_MOUNT_REGISTRY directory"
		$conn_locn/deployCfC/sshpass/bin/sshpass -p ${root_password} ssh ${ssh_args} root@${nfs_server} "mkdir -p ${HA_MOUNT_REGISTRY}"
	fi
	if [[ "${HA_MOUNT_AUDIT}" != "" ]]; then
		echo "Create HA_MOUNT_AUDIT directory"
		$conn_locn/deployCfC/sshpass/bin/sshpass -p ${root_password} ssh ${ssh_args} root@${nfs_server} "mkdir -p ${HA_MOUNT_AUDIT}"
	fi

	echo "Export mounts"
	cp $pwd/microservices/hybridcloud/doc/samples/nfsSetup.sh $pwd/microservices/hybridcloud/doc/samples/nfsMountSetup.sh
	sed -i -e 's#VOLUMES=$(cat.*#'"MOUNTS=($HA_MOUNT_REGISTRY $HA_MOUNT_AUDIT)"'#' $pwd/microservices/hybridcloud/doc/samples/nfsMountSetup.sh
	sed -i 's/VOLUMES/{MOUNTS[@]}/' $pwd/microservices/hybridcloud/doc/samples/nfsMountSetup.sh
	sed -i 's/VOLUME/MOUNT/' $pwd/microservices/hybridcloud/doc/samples/nfsMountSetup.sh
	$conn_locn/deployCfC/sshpass/bin/sshpass -p ${root_password} ssh ${ssh_args} root@${nfs_server} "rm -f /opt/nfsMountSetup.sh"
	$conn_locn/deployCfC/sshpass/bin/sshpass -p ${root_password} scp $pwd/microservices/hybridcloud/doc/samples/nfsMountSetup.sh root@${nfs_server}:/opt/nfsMountSetup.sh
	$conn_locn/deployCfC/sshpass/bin/sshpass -p ${root_password} ssh ${ssh_args} root@${nfs_server} "cd /opt/ ; chmod +x /opt/nfsMountSetup.sh ; ./nfsMountSetup.sh"

	echo "Configure fullPVs_NFS to use storage server"
	hostnameIp=`$conn_locn/deployCfC/sshpass/bin/sshpass -p ${root_password} ssh ${ssh_args} root@${nfs_server} "hostname -i"`
	sed -i "s/___NFS_SERVER_IP___/${hostnameIp}/g" $pwd/microservices/hybridcloud/doc/samples/fullPVs_NFS.yml
	cp $pwd/microservices/hybridcloud/doc/samples/fullPVs_NFS.yml $pwd
}

usage() {
	logIt ""
	logIt "Usage: ./configure-ha-storage.sh conn_locn nfsServer_FQHN root_password HA_MOUNT_REGISTRY_PATH HA_MOUNT_AUDIT_PATH"
	logIt "This script will run the pv creation and the nfs setup on the storage server."
	logIt ""
	logIt "Sample Usage:"
	logIt "./configure-ha-storage.sh /opt storageServer.swg.usma.ibm.com pass storageServer.swg.usma.ibm.com:/CFC_IMAGE_REPO"
	logIt "./configure-ha-storage.sh /opt storageServer.swg.usma.ibm.com pass storageServer.swg.usma.ibm.com:/CFC_IMAGE_REPO storageServer.swg.usma.ibm.com:/CFC_AUDIT"
	logIt ""
	exit 1
}

setupNfsServer
