#!/bin/bash

set -o errexit
set -o xtrace

# Uncomment this section and fill in the values to run this script manually
FTP3USER=brendan_furey@ie.ibm.com
FTP3PASS=
upgrade_docker=true		# true or false
docker_version=18.06		# e.g. 17.03 or 18.06
upgrade_k8s=true			# true or false
k8s_version=1.11.9			# e.g. 1.11.1, 1.11.*, latest
remaining_master_list=
worker_list=
es_worker_list=
USER=root
ssh_password=Pa88w0rd
primary_master=
secondary_master=

if [ -z "${USER}" ]; then
	USER="root"
fi

if [ "${USER}" == "root" ]; then
	homeFolder="/${USER}"
else
 	homeFolder="/home/${USER}"
fi

distributor=`lsb_release -i | awk '{ print $3 }'`
if [ "${distributor}" = RedHatEnterpriseServer ]; then
	YUM="sudo FTP3USER=${FTP3USER} FTP3PASS=${FTP3PASS} ${homeFolder}/ibm-yum.sh"
elif [ "${distributor}" = CentOS ]; then
	YUM="yum"
fi

# Expects notation of W.X.Y.Z
# return is in comparison_result
# returns 1 for less than, 0 for equals, 2 for greater than
compareVersions () {
	set -o errexit
	set -o pipefail
	set -o nounset

	set +o nounset
	if [ "$2" = "" ]; then
		echo "usage:  compareVersions version1 version1"
		exit 207
	fi
	set -o nounset
	v1="$1"
	v2="$2"

	comparison_result=""
	if [[ ${v1} > ${v2} ]]; then
		comparison_result=2
	fi
	if [[ ${v1} < ${v2} ]]; then
		if [ "${comparison_result}" != "" ]; then
			# special condition such as 1.01.2 compared to 1.1.2 results
			# in both < and > being true which is actually =
			comparison_result=0
		else
			comparison_result=1
		fi
	fi
	if [[ ${v1} = ${v2} ]]; then
		if [ "${comparison_result}" != "" ]; then
			echo "Unknown error event"
			exit 209
		nstalled_docker_version=$(sudo docker version --format '{{.Server.Version}}' | grep $docker_version)echo ${installed_docker_version}else
			comparison_result=0
		fi
	fi

	set +o nounset
}

function docker_upgrade() {

	YUM="$1"
	export FTP3USER=$2
	export FTP3PASS=$3
	docker_version=$4	
	
	installed_docker_version=$(sudo docker version --format '{{.Server.Version}}')
	if [[ ${installed_docker_version} =~ "${docker_version}" ]]; then
		echo "docker already at required level. Skipping upgrade. Installed: ${installed_docker_version}. Selected : ${docker_version}"
	else
		# Upgrade docker
		sudo systemctl stop docker
		echo "Upgrading docker from ${installed_docker_version} to ${docker_version}."
		sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
		sudo yum-config-manager --disable docker*
		sudo yum-config-manager --enable docker-ce-stable
		${YUM} -y upgrade --setopt=obsoletes=0 docker-ce-${docker_version}*
		${YUM} makecache fast
		sudo systemctl start docker
		sudo systemctl enable docker.service
		sudo yum-config-manager --disable docker*
	fi 
}

# function resets errexit to non-ignore so calling script must reset if desired
# returns 0 or non-0 for success and failure, respectively
function runDockerHelloWorldTest () {

	set +o errexit

	number_retries=3
	retry_wait_time=30
	counter=1
	while [ ${counter} -le ${number_retries} ]; do
		sudo docker run hello-world
		if [ $? -ne 0 ]; then
			if [ ${counter} -eq ${number_retries} ]; then
				echo "	FAILED"
			else
				echo "	FAILED, retrying in ${retry_wait_time}s"
				sleep ${retry_wait_time}
			fi
			counter=`expr ${counter} + 1`
		else
			echo "	OK"
			return 0
		fi
	done
	echo "Maximum attempts reached, giving up"
	return 1
}

function setup_yum() {

	FTP3USER=$1
	FTP3PASS=$2
	homeFolder=$3
	
	if [ -f /${homeFolder}/ibm-yum.sh ]; then
		rm -f /${homeFolder}/ibm-yum.sh
	fi
	cd /${homeFolder}

	set +o errexit
	wget --tries=1 --user=${FTP3USER} --password=${FTP3PASS} ftp://ftp3.linux.ibm.com/redhat/ibm-yum.sh
	if [ $? -ne 0 ]; then
		echo
		echo "Failed to get ibm-yum.sh from ftp3.linux.ibm.com. Trying a different repo..."
		wget --tries=1 --user=${FTP3USER} --password=${FTP3PASS} ftp://ftp3-ca.linux.ibm.com/redhat/ibm-yum.sh
		if [ $? -ne 0 ]; then
			echo "Failed to get ibm-yum.sh from ftp3-ca.linux.ibm.com. Giving up"
			exit 1
		else
			sed -i -e 's/ftp3.linux.ibm.com/ftp3-ca.linux.ibm.com/g' /${homeFolder}/ibm-yum.sh
			yum clean all
			rm -rf /etc/yum.repos.d/ibm-yum-*.repo
		fi
	fi
	set -o errexit
	chmod 777 /${homeFolder}/ibm-yum.sh
}


function drain_node() {

	nodeName=$1
	kubectl drain ${nodeName} --delete-local-data --ignore-daemonsets
} 

function uncordon_node() {

        nodeName=$1
        kubectl uncordon ${nodeName}
}

function k8s_upgrade() {

	YUM="$1"
	k8s_version=$2
	export FTP3USER=$3
	export FTP3PASS=$4

	distributor=`lsb_release -i | awk '{ print $3 }'`
	if [ "${distributor}" = RedHatEnterpriseServer ]; then
		sudo sed -i -e '/rhel-swap/s/^\([^#]\)/#/' /etc/fstab
	elif [ "${distributor}" = CentOS ]; then
		sudo sed -i -e '/centos-swap/s/^\([^#]\)/#/' /etc/fstab
	fi
	sudo mount -a
	echo "[kubernetes]" | sudo tee /etc/yum.repos.d/kubernetes.repo > /dev/null
	echo "name=Kubernetes" | sudo tee -a /etc/yum.repos.d/kubernetes.repo > /dev/null
	echo "baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64" | sudo tee -a /etc/yum.repos.d/kubernetes.repo > /dev/null
	echo "enabled=1" | sudo tee -a /etc/yum.repos.d/kubernetes.repo > /dev/null
	echo "gpgcheck=1" | sudo tee -a /etc/yum.repos.d/kubernetes.repo > /dev/null
	echo "repo_gpgcheck=1" | sudo tee -a /etc/yum.repos.d/kubernetes.repo > /dev/null
	echo "gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg" | sudo tee -a /etc/yum.repos.d/kubernetes.repo> /dev/null
	echo "exclude=kube*" | sudo tee -a /etc/yum.repos.d/kubernetes.repo > /dev/null
	selinux=$(sudo getenforce)
	if [ "${selinux}" = "Enforcing" ]; then
		sudo setenforce 0
		sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
	fi
	sudo yum-config-manager --enable kubernetes*
	if [ "${k8s_version}" = "latest" ]; then
		${YUM} upgrade -y kubelet kubeadm kubectl --disableexcludes=kubernetes
	else
		${YUM} upgrade -y kubelet-${k8s_version}* kubeadm-${k8s_version}* kubectl-${k8s_version}* --disableexcludes=kubernetes
	fi
	sudo systemctl enable kubelet && sudo systemctl start kubelet
	sudo yum-config-manager --disable kubernetes*
}

# Make sure K8s version for HA is v1.11 or higher
if [ "${remaining_master_list}" != "" ]; then
	if [[ ${k8s_version} =~ "1.8" ]]; then
		echo
		echo "Kubernetes v1.8 not supported for HA cluster."
		exit 1
	fi
fi

# Ensure haproxy_lb_list is specified if doing master HA
if [ "${remaining_master_list}" != "" ] && [ "${haproxy_lb_list}" = "" ]; then
	echo
	echo "A value for haproxy_lb_list needs to be specified when more than one master is being deployed."
	exit 1
fi

# Concatenate workers and remove trailing space if only one worker
if [ "${worker_list}" != "" ] && [ "${es_worker_list}" != "" ] ; then
	worker_list="`echo ${worker_list},${es_worker_list} | sed 's/ $//'`"
fi

# Hostname validation and array set up
echo
echo "Validating hostnames.."
if [ "${remaining_master_list}" != "" ]; then
	IFS=',' read -r -a masterArray <<< "${remaining_master_list}"
	for master in ${masterArray[@]}; do
		resolve_ip ${master}
		if [ $? -ne 0 ]; then
			echo "Unable to resolve ${master}"
			exit 1
		fi
		set -o errexit
	done
fi
if [ "${worker_list}" != "" ]; then
    	IFS=',' read -r -a workerArray <<< "${worker_list}"
	for worker in ${workerArray[@]}; do
		resolve_ip ${worker}
		if [ $? -ne 0 ]; then
			echo "Unable to resolve ${worker}"
			exit 1
		fi
		set -o errexit
	done
fi
if [ "${haproxy_lb_list}" != "" ]; then
    	IFS=',' read -r -a haproxyArray <<< "${haproxy_lb_list}"
	for lb in ${haproxyArray[@]}; do
		resolve_ip ${lb}
		if [ $? -ne 0 ]; then
			echo "Unable to resolve ${lb}"
			exit 1
		fi
		set -o errexit
	done
fi

echo "Hostname validation complete."

# Set up YUM
if [ "${FTP3USER}" = "" -o "${FTP3PASS}" = "" ]; then
	echo "FTP3USER and FTP3PASS are required for YUM"
	exit 1
else
	echo
	echo "Configuring ibm-yum on $(hostname -f)"
	setup_yum ${FTP3USER} ${FTP3PASS} ${homeFolder}
	
	# Install sshpass on primary master
	echo
	echo "Installing sshpass on $(hostname -f)"
	${YUM} install -y sshpass

	if [ "${remaining_master_list}" != "" ]; then
		for master in ${masterArray[@]}; do
			echo
			echo "Configuring ibm-yum on $master"
			typeset -f setup_yum | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "$(cat); setup_yum ${FTP3USER} ${FTP3PASS} ${homeFolder} || exit 1"
		done
	fi
	if [ "${worker_list}" != "" ]; then
		for worker in ${workerArray[@]}; do
			echo
			echo "Configuring ibm-yum on $worker"
			typeset -f setup_yum | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${worker} "$(cat); setup_yum ${FTP3USER} ${FTP3PASS} ${homeFolder} || exit 1"
		done
	fi
	if [ "${haproxy_lb_list}" != "" ]; then
		for lb in ${haproxyArray[@]}; do
			echo
			echo "Configuring ibm-yum on $lb"
			typeset -f setup_yum | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@$lb "$(cat); setup_yum ${FTP3USER} ${FTP3PASS} ${homeFolder} || exit 1"
		done
	fi
fi

drain_node $(hostname)

# Upgrade Docker
if [ ${upgrade_docker} = true ]; then
	echo "Upgrading Docker on $(hostname -f)"
	docker_upgrade "${YUM}" ${FTP3USER} ${FTP3PASS} ${docker_version}
	echo
	echo "Validating Docker on $(hostname -f)"
	runDockerHelloWorldTest || exit 1
	set -o errexit
	if [ "${remaining_master_list}" != "" ]; then
		for master in ${masterArray[@]}; do
			echo
			echo "Installing Docker on $master"
			typeset -f docker_upgrade | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "$(cat); docker_upgrade \"${YUM}\" ${FTP3USER} ${FTP3PASS} ${docker_version} || exit 1"
			echo
			echo "Validating Docker on $master"
			typeset -f runDockerHelloWorldTest | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "$(cat); runDockerHelloWorldTest || exit 1"
			set -o errexit
		done
	fi
	if [ "${worker_list}" != "" ]; then
		for worker in ${workerArray[@]}; do
			echo
			echo "Installing Docker on $worker"
			typeset -f docker_upgrade | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${worker} "$(cat); docker_upgrade \"${YUM}\" ${FTP3USER} ${FTP3PASS} ${docker_version} || exit 1"
			echo
			echo "Validating Docker on $worker"
			typeset -f runDockerHelloWorldTest | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${worker} "$(cat); runDockerHelloWorldTest || exit 1"
			set -o errexit
		done
	fi	

fi

# Upgrade K8s
if [ ${upgrade_k8s} = true ]; then

	pwd
	echo
	echo "Upgrading Kubernetes on $(hostname -f)"
	k8s_upgrade "${YUM}" ${k8s_version} ${FTP3USER} ${FTP3PASS} || exit 1
	
	sudo systemctl restart kubelet
	sudo systemctl daemon-reload

	if [ ${primary_master} = true ]; then
		sudo kubeadm config view | tee kubeadm-config.yaml
	
		sed -i "s|^kubernetesVersion: .*$|kubernetesVersion: v${k8s_version}|" kubeadm-config.yaml

		sudo kubeadm upgrade apply ${k8s_version} --config=kubeadm-config.yaml -f
	fi

	if [ ${secondary_master} = true ]; then

                sudo kubeadm upgrade apply ${k8s_version} -f
        fi

	sudo yum-config-manager --disable kubernetes*

fi
	
# Uncordon Node
uncordon_node ${HOSTNAME}
