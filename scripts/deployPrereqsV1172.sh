#!/bin/bash


# Script designed to work with the following Jenkins job: https://ics-connect-jenkins.swg-devops.com/view/Private%20Cloud/job/Component%20Pack/job/Deploy-Prereqs/

set -o errexit
#set -o xtrace

# Uncomment this section and fill in the values to run this script manually
# (removed) FTP3USER=
# (removed) FTP3PASS=
# remove_prereqs=		# true or false
# install_docker=		# true or false
# docker_version=		# e.g. 19.03.5
# docker_storage_type		# devicemapper-loop-lvm, devicemapper-direct-lvm or overlay2
# docker_storage_block_device=	# leave blank for loop-lvm
# install_k8s=			# true or false
# k8s_version=			# e.g. 1.17.*, latest
# remaining_master_list=
# nginx_reverse_proxy=
# ic_internal=
# haproxy_lb_list=
# haproxy_lb_vip=
# worker_list=
# es_worker_list=
# USER=root
# ssh_password=
# GIT_USER=
# GIT_TOKEN=
# calico_version=		# 3.8
# pods_on_master=		# true or false
# install_helm=			# true or false
# helm_version=			# e.g. v2.12.1
# create_namespace=		# true or false
# create_pvs=			# true or false
# wipe_data=			# true or false
# pvconnections_folder_path=	# default: /pv-connections
# external_nfs_server=
# setup_docker_registry=	# true or false
# external_docker_registry=	# not yet implemented
# configure_firewall=		# true or false
# enable_pod_security_policy= 	# true or false
# enable_sophosav= 		# true or false

if [ "${GIT_USER}" = "" -o "${GIT_TOKEN}" = "" ]; then
	echo "Missing values for GIT_USER and/or GIT_TOKEN."
	exit 1
fi

if [ -z "${USER}" ]; then
	USER="root"
fi

if [ -z "${wipe_data}" ]; then
	wipe_data=false
fi

if [ -z "${enable_sophosav}" ]; then
        enable_sophosav=true
fi

if [ -z "${setup_docker_registry}" ]; then
	setup_docker_registry=false
fi

if [ "${USER}" == "root" ]; then
	homeFolder="/${USER}"
else
 	homeFolder="/home/${USER}"
fi

if [ -z "${pvconnections_folder_path}" ]; then
        if [ "${USER}" == "root" ]; then
                pvconnections_folder_path="/pv-connections"
        else
                pvconnections_folder_path="${homeFolder}/pv-connections"
        fi
fi

k8s_cni_version="0.7.5-00"

# BEGIN - Remove IBM reference to 'yum'
#distributor=`lsb_release -i | awk '{ print $3 }'`
#if [ "${distributor}" = RedHatEnterpriseServer ]; then
#	YUM="sudo FTP3USER=${FTP3USER} FTP3PASS=${FTP3PASS} ${homeFolder}/ibm-yum.sh"
#elif [ "${distributor}" = CentOS ]; then
#	YUM="yum"
#fi
# END - Remove IBM reference to 'yum'

# Use public yum version
YUM="yum"

if [ ${setup_docker_registry} = true ]; then
	docker_registry=$(sudo hostname -f)
fi

if [ ${remove_prereqs} = true -o ${install_docker} = true ]; then
	if [[ ${docker_storage_type} == "devicemapper-direct-lvm" && ${docker_storage_block_device} == "" ]]; then
		echo "ERROR: docker_storage_type is set to devicemapper-direct-lvm but docker_storage_block_device is blank."
		echo "ERROR: A value for docker_storage_block_device must be set if docker_storage_type is devicemapper-direct-lvm."
		exit 1
	fi
fi


function deleteSecretIfExists {

    if [ "$1" = "" ]; then
        echo "INTERNAL ERROR - usage:  deleteSecretIfExists sSecretName"
        exit 107
    fi
    secret_name="$1"
    namespace="$2"

    if [[ "$(kubectl get secrets -o jsonpath={.items[*].metadata.name} -n ${namespace})" =~ .*${secret_name}.* ]]; then
        echo
        echo "Deleting ${secret_name}"
        kubectl delete secret ${secret_name} -n="${namespace}"
        echo
    fi

}


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
		else
			comparison_result=0
		fi
	fi

	set +o nounset
}

function setup_sophosav(){

	pwd
	file="sav-linux-free-9.tgz"
	sudo rm -rf $file
	sudo rm -rf sophos-av

	FILE_TO_DOWNLOAD="https://connections-docker.artifactory.cwp.pnp-hcl.com/artifactory/connections-3rd-party/sophosav/9/sav-linux-free-9.tgz"
	sudo curl -SLOk ${FILE_TO_DOWNLOAD}

	sudo tar -xvzf ${file}

	sudo bash sophos-av/install.sh --automatic --acceptlicence --autostart=True --enableOnBoot=True --live-protection=False --update-free=True /opt/sophos-av

	sudo /opt/sophos-av/bin/savupdate

	sudo /opt/sophos-av/bin/savdstatus --version

	sudo /opt/sophos-av/bin/savdstatus | grep "Sophos Anti-Virus is active and on-access scanning is running"
	if [ $? -ne 0 ]; then
        	echo "Sophos Anti-Virus is either inactive or on-access scanning is not running. Exiting."
        	exit 1
	fi
}



function setup_registry(){

	if [ "$(sudo docker ps -q -f name=registry)" ]; then
		sudo docker container stop registry
		sudo docker container rm -v registry
	fi

	sudo mkdir -p /docker-registry
	sudo mkdir -p /docker-registry/{auth,certs,registry}

	sudo docker run --entrypoint htpasswd registry:2.7.0 -Bbn admin password |  sudo tee /docker-registry/auth/htpasswd > /dev/null

	sudo openssl req -newkey rsa:4096 -nodes -sha256 -keyout ${homeFolder}/key.pem -x509 -days 365 -out ${homeFolder}/cert.pem -subj "/CN=${docker_registry}"

	sudo cp -av ${homeFolder}/key.pem ${homeFolder}/cert.pem /docker-registry/certs

	sudo mkdir -p /etc/docker/certs.d
	sudo mkdir -p /etc/docker/certs.d/${docker_registry}\:5000/

	sudo cp -av ${homeFolder}/cert.pem /etc/docker/certs.d/${docker_registry}\:5000/ca.crt

	sudo docker run -d -p 5000:5000 --restart=always --name registry -v /docker-registry/auth:/auth -v /docker-registry/certs:/certs -v /docker-registry/registry:/var/lib/registry -e "REGISTRY_AUTH=htpasswd" -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" -e "REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd" -e "REGISTRY_HTTP_TLS_CERTIFICATE=/certs/cert.pem" -e "REGISTRY_HTTP_TLS_KEY=/certs/key.pem" registry:2.7.0

	retry=1
	max_retry=3
	success=false
	set +o errexit
	while [ ${retry} -le ${max_retry} ]; do
		sudo docker login -u admin -p password ${docker_registry}:5000
		if [ $? -ne 0 ]; then
			echo "Retrying Docker login (${retry}/${max_retry})"
			sleep 5
		else
			success=true
			break
		fi
		retry=`expr ${retry} + 1`
	done
	set -o errexit
	if [ ${success} = false ]; then
		echo "Docker login failed - max retry attempts reached. Exiting"
		exit 1
	fi

	if [ "${remaining_master_list}" != "" ]; then
		for master in ${masterArray[@]}; do
			echo
			echo "Copying the cert from the docker registry machine to all the remaining masters in the kubernetes cluster: ${master}"
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "sudo mkdir -p /etc/docker/certs.d"
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "sudo mkdir -p /etc/docker/certs.d/${docker_registry}\:5000/"
			sshpass -p ${ssh_password} sudo scp -o StrictHostKeyChecking=no ${homeFolder}/cert.pem root@${master}:/etc/docker/certs.d/${docker_registry}:5000/ca.crt
		done
	fi

	if [ "${worker_list}" != "" ]; then
    		IFS=',' read -r -a workerArray <<< "${worker_list}"
		for worker in ${workerArray[@]}; do
			echo "Copying the cert from the docker registry machine to all the remaining workers in the kubernetes cluster: ${worker}"
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${worker} "sudo mkdir -p /etc/docker/certs.d"
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${worker} "sudo mkdir -p /etc/docker/certs.d/${docker_registry}\:5000/"
			sshpass -p ${ssh_password} sudo scp -o StrictHostKeyChecking=no ${homeFolder}/cert.pem root@${worker}:/etc/docker/certs.d/${docker_registry}:5000/ca.crt
		done
	fi

}

function setup_pvs() {

	wipe_data=$1
	pvconnections_folder_path=$2

	if [ ${wipe_data} = true ]; then
		sudo rm -rf ${pvconnections_folder_path}
	fi

	LIST="connections-persistent-storage-nfs-0.1.1.tgz nfsSetup.sh"

	# Download files with icdeploy@hcl.com (Hint: no icci ID at HCL - icci@us.ibm.com) credentials:
	echo "Downloading connections-volumes helm chart and NFS setup script.."
	TOKEN=${GIT_TOKEN}
	OWNER="connections"
	REPO="deploy-services"

	for file in ${LIST}; do
		sudo rm -rf $FILE
		PATH_FILE="microservices/hybridcloud/doc/samples/${file}"
		FILE="https://git.cwp.pnp-hcl.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
		sudo curl -H "Authorization: token $TOKEN" \
		-H "Accept: application/vnd.github.v3.raw" \
		-O \
		-L $FILE
	done

	# Create volumes.txt (internal step only - its in the zip for customer)
	sudo tar -xvzf connections-persistent-storage-nfs-0.1.1.tgz

	rm -rf volumes.txt
	content=(`cat connections-persistent-storage-nfs/templates/fullPVs_NFS.yaml | grep path: | cut -d'/' -f3-`)
	touch volumes.txt
	for t in "${content[@]}"
	do
		echo "${pvconnections_folder_path}/$t" >> volumes.txt
	done

	# kudos-boards pv
	kudos_minio_pv="kudos-boards-minio"
	echo "${pvconnections_folder_path}/${kudos_minio_pv}" >> volumes.txt

	# Create directories
	echo
	echo "Creating folders required for persistent volumes.."
	VOLUMES=$(cat volumes.txt)
	for VOLUME in $VOLUMES; do
		mkdir -p $VOLUME
		if [[ $VOLUME == *"customizations"* ]]; then
			sudo chmod -R 005 $VOLUME
		else
			sudo chmod -R 700 $VOLUME
		fi

		if [ "${USER}" != "root" ]; then
			if [[ $VOLUME == *"solr"* ]]; then
				sudo chown -R 8983:8983 $VOLUME
			elif [[ $VOLUME == *"zookeeper"* ]]; then
				sudo chown -R 1000:1000 $VOLUME
			elif [[ $VOLUME == *"esdata"* ]]; then
				sudo chown -R 1000:1000 $VOLUME
			elif [[ $VOLUME == *"esbackup"* ]]; then
				sudo chown -R 1000:1000 $VOLUME
			elif [[ $VOLUME == *"mongo"* ]]; then
				sudo chown -R 1001:1001 $VOLUME
			elif [[ $VOLUME == *"customizations"* ]]; then
				sudo chown -R 1001:1001 $VOLUME
			fi
		fi

	done
	echo "Folders created."

	# Install nfs-utils and run nfsSetup.sh
	echo
	echo "Installing nfs-utils"
	${YUM} -y install nfs-utils
	echo
	echo "Running nfsSetup.sh"
	sudo bash nfsSetup.sh
	echo
	echo "Contents of /etc/exports:"
	cat /etc/exports
}

function docker_install() {

	YUM="$1"
	docker_version=$2
	docker_storage_type=$3
	docker_storage_block_device=$4

	# Install prerequisites
	${YUM} -y install yum-utils device-mapper-persistent-data lvm2

	# Install docker
	sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
	sudo yum-config-manager --disable docker*
	sudo yum-config-manager --enable docker-ce-stable
	${YUM} -y install --setopt=obsoletes=0 docker-ce-${docker_version}*
	${YUM} makecache fast
	sudo systemctl start docker
	sudo systemctl enable docker.service
	sudo yum-config-manager --disable docker*
	sudo mkdir -p /etc/docker
	FILE=/etc/docker/daemon.json

	if [ "${docker_storage_type}" == "devicemapper-direct-lvm" ]; then

		echo "You have selected block device: devicemapper-direct-lvm"
		echo "It is assumed that the block device has been configured for use with your master(s) and worker(s).  The automation will not check for this."
		echo "To request a block request:"
		echo " - Log a service request with the VM Administration Team"
		echo " - Include the following details: Create block storage device for the following VMs : <List all hostnames representing k8s master nodes and worker nodes. Allocate 50GB per machine"
		echo " - The VM Administration Team will create the block device and inform you of the block device name.  e.g. /dev/sda1"
		echo "If devicemapper-direct-lvm is selected, you must specify the docker_storage_block_device name."

		# Check if Docker is already configured with block device
		if echo `lsblk` | grep -A 1 $(basename $docker_storage_block_device) | grep -q docker-thinpool; then
			echo "Found Docker is set up already with block device"
		else
			# Stop docker
			sudo systemctl stop docker
			# If exists, move everything inside /var/lib/docker so that Docker can use the new LVM pool
			counter=1
			number_retries=3
			retry_delay=30
			DOCKER=/var/lib/docker
			DATE=`date +%Y%m%d%H%M%S`
			while [ ${counter} -le ${number_retries} ]; do
				if [ -e ${DOCKER} ]; then
					if [ -e ${DOCKER}.bk ]; then
						sudo rm -rf ${DOCKER}.bk
					fi
					sudo mkdir -p ${DOCKER}.bk
					echo "Moving all content from ${DOCKER} to ${DOCKER}.bk"
					sudo touch ${DOCKER}/${DATE}
					set +o errexit
					sudo bash -c "mv ${DOCKER}/* ${DOCKER}.bk"
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
				echo "Reboot, uninstall, and then install again"
				exit 9
			fi
			echo "Configuring Docker with the devicemapper storage driver: direct-lvm"
			# Set up direct-lvm docker storage driver
			set +o errexit
			sudo pvcreate ${docker_storage_block_device}
			if [ $? -ne 0 ]; then
				echo "Unable to create physical volume on ${docker_storage_block_device}. Please ensure this is a valid block device and not associated with any other physical volume."
				exit 22
			fi
			sudo vgcreate docker	${docker_storage_block_device}
			if [ $? -ne 0 ]; then
				echo "Unable to create a volume group from ${docker_storage_block_device}"
				exit 22
			fi
			set -o errexit
			sudo lvcreate --wipesignatures y -n thinpool docker -l 95%VG
			sudo lvcreate --wipesignatures y -n thinpoolmeta docker -l 1%VG
			sudo lvconvert -y --zero n -c 512K --thinpool docker/thinpool --poolmetadata docker/thinpoolmeta
			# Set logical volume auto expansion
			echo "activation {" | sudo tee /etc/lvm/profile/docker-thinpool.profile > /dev/null
			echo "  thin_pool_autoextend_threshold=80" | sudo tee -a /etc/lvm/profile/docker-thinpool.profile > /dev/null
			echo "  thin_pool_autoextend_percent=20" | sudo tee -a /etc/lvm/profile/docker-thinpool.profile > /dev/null
			echo "}" | sudo tee -a /etc/lvm/profile/docker-thinpool.profile > /dev/null
			sudo lvchange --metadataprofile docker-thinpool docker/thinpool
			# enable monitoring so that auto expansion works
			sudo lvs -o+seg_monitor
			# Set docker storage driver
			echo "{" | sudo tee ${FILE} > /dev/null
			echo "    \"storage-driver\": \"devicemapper\"," | sudo tee -a ${FILE} > /dev/null
			echo "    \"storage-opts\": [" | sudo tee -a ${FILE} > /dev/null
			echo "    \"dm.thinpooldev=/dev/mapper/docker-thinpool\"," | sudo tee -a ${FILE} > /dev/null
			echo "    \"dm.use_deferred_removal=true\"," | sudo tee -a ${FILE} > /dev/null
			echo "    \"dm.use_deferred_deletion=true\"" | sudo tee -a ${FILE} > /dev/null
			echo "    ]" | sudo tee -a ${FILE} > /dev/null
			echo "}" | sudo tee -a ${FILE} > /dev/null
			# Start Docker
			sudo systemctl start docker
		fi
	elif [ "${docker_storage_type}" == "devicemapper-loop-lvm" ]; then
			# Stop docker
			sudo systemctl stop docker

			echo "Configuring Docker with the devicemapper storage driver: loop-lvm"
			echo "{" | sudo tee ${FILE} > /dev/null
			echo "  \"storage-driver\": \"devicemapper\"" | sudo tee -a ${FILE} > /dev/null
			echo "}" | sudo tee -a ${FILE} > /dev/null

			# Start Docker
			sudo systemctl start docker
	elif [ "${docker_storage_type}" == "overlay2" ]; then

			echo "You have selected block device: overlay2"
	                echo "It is assumed that the block device has been configured for use with your master(s) and worker(s).  The automation will not check for this."
        	        echo "To request a block request:"
                	echo " - Log a service request with the VM Administration Team"
	                echo " - Include the following details: Create block storage device for the following VMs : <List all hostnames representing k8s master nodes and worker nodes. Allocate 50GB per machine.  Ensure d_type is enabled and the block device is mounted to /var/lib/docker"
        	        echo " - The VM Administration Team will create the block device and inform you of the block device name.  e.g. /dev/sda1"
                	echo "If overlay2 is selected, it is not necessary to specify the docker_storage_block_device name as the block device will be mounted to /var/lib/docker."

			# Stop docker
			sudo systemctl stop docker

			# If exists, copy everything inside /var/lib/docker to a temporary location
			counter=1
			number_retries=3
			retry_delay=30
			DOCKER=/var/lib/docker
			DATE=`date +%Y%m%d%H%M%S`
			while [ ${counter} -le ${number_retries} ]; do
				if [ -e ${DOCKER} ]; then
					if [ -e ${DOCKER}.bk ]; then
						sudo rm -rf ${DOCKER}.bk
					fi
					sudo mkdir -p ${DOCKER}.bk
					echo "Copying all content from ${DOCKER} to ${DOCKER}.bk"
					sudo touch ${DOCKER}/${DATE}
					set +o errexit
					sudo bash -c "cp -au ${DOCKER} ${DOCKER}.bk"
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
				echo "Failure copying Docker overlay files to a temporary location."
				echo "Diagnostic output follows:"
				echo
				ps auxwwww
				echo
				lsof
				echo
				echo "Reboot, uninstall, and then install again"
				exit 9
			fi

			echo "Configuring Docker with the devicemapper storage driver: overlay2"
			echo "{" | sudo tee ${FILE} > /dev/null
			echo "  \"storage-driver\": \"overlay2\"," | sudo tee -a ${FILE} > /dev/null
			echo "    \"storage-opts\": [" | sudo tee -a ${FILE} > /dev/null
			echo "    \"overlay2.override_kernel_check=true\"" | sudo tee -a ${FILE} > /dev/null
			echo "    ]" | sudo tee -a ${FILE} > /dev/null
			echo "}" | sudo tee -a ${FILE} > /dev/null

			# Start Docker
			sudo systemctl start docker
	fi
	echo "Docker devicemapper storage configuration complete"
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

function k8s_install() {

	YUM="$1"
	k8s_version=$2
	k8s_cni_version=$3

	sudo swapoff -a
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
		${YUM} install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
	else
		if [[ ${k8s_cni_version} == "" ]]; then
			${YUM} install -y kubelet-${k8s_version}* kubeadm-${k8s_version}* kubectl-${k8s_version}* --disableexcludes=kubernetes
		else
			${YUM} install -y kubelet-${k8s_version}* kubeadm-${k8s_version}* kubectl-${k8s_version}* kubernetes-cni-${k8s_cni_version}* --disableexcludes=kubernetes
		fi
	fi
	sudo systemctl enable kubelet && sudo systemctl start kubelet
	sudo yum-config-manager --disable kubernetes*
	echo "net.bridge.bridge-nf-call-ip6tables = 1" | sudo tee /etc/sysctl.d/k8s.conf > /dev/null
	echo "net.bridge.bridge-nf-call-iptables = 1" | sudo tee -a /etc/sysctl.d/k8s.conf > /dev/null
	sudo sysctl --system
}

# return 0 if argument has ipv4 format, returns non-0 otherwise
# function resets errexit to ignore so calling script must reset if desired
function is_ipv4() {

	set +o errexit

	if [ "$1" = "" ]; then
		echo "usage:  is_ipv4 sHost"
		exit 108
	fi
	host=$1
	resolve_ip_return_result=""

	if [ "`echo ${host} | sed 's/\.//g' | sed 's/[0-9]*//'`" = "" ]; then
		# ipv4 address, already theoretically resolved
		# not handling ipv6 yet
		# but make sure it is a valid ipv4 address
		octet_count=0
		for octet in `echo ${host} | sed 's/\./ /g'`; do
			if [ ${octet} -lt 1 -o ${octet} -gt 255 ]; then
				echo "IP address has invalid octet ranges:  ${host}"
				return 101
			fi
			octet_count=`expr ${octet_count} + 1`
		done
		if [ ${octet_count} -ne 4 ]; then
			echo "IP address has invalid number of octets:  ${host}"
			return 102
		fi
	else
		return 103
	fi
	return 0
}

# return is in resolve_ip_return_result
# function resets errexit to ignore so calling script must reset if desired
function resolve_ip() {
	set +o errexit

	if [ "$1" = "" ]; then
		echo "usage:  resolve_ip sHost"
		exit 100
	fi
	host=$1
	resolve_ip_return_result=""

	is_ipv4 ${host}
	if [ $? -eq 0 ]; then
		resolve_ip_return_result="${host}"
		return 0
	fi

	resolve_ip_return_result=`host ${host} | grep "has address" | head -1 | awk '{ print $NF }'`
	if [ "${resolve_ip_return_result}" = "" ]; then
		echo "${host} is not resolvable with host, trying alternative"
		resolve_ip_return_result=`ping -c 1 ${host} 2>&1 | grep '^PING ' | grep 'bytes of data.$' | awk '{ print $3 }' | sed -e 's/(//' -e 's/)//'`
		if [ "${resolve_ip_return_result}" = "" ]; then
			echo "${host} is not resolvable with ping, giving up"
			return 102
		else
			echo "OK"
		fi
	fi
	return 0
}

function create_keepalived_conf () {

	state=$1
	priority=$2
	ha_fronting_master=$3

	# Below configuration is added so that floating/shared IP can be assigned to one of the load balancers
	grep -q -F 'net.ipv4.ip_nonlocal_bind=1' /etc/sysctl.conf || echo "net.ipv4.ip_nonlocal_bind=1" | sudo tee -a /etc/sysctl.conf > /dev/null
	sudo sysctl -p

	echo "global_defs {" | sudo tee /etc/keepalived/keepalived.conf > /dev/null
	echo "# Keepalived process identifier" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "lvs_id haproxy_DH" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "}" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "# Script used to check if HAProxy is running" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "vrrp_script check_haproxy {" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "script \"killall -0 haproxy\"" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "interval 2" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "weight 2" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "}" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "# Virtual interface" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "# The priority specifies the order in which the assigned interface to take over in a failover" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "vrrp_instance VI_01 {" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "state ${state}" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "interface eth0" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "virtual_router_id 51" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "priority ${priority}" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "# The virtual ip address shared between the two loadbalancers" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "virtual_ipaddress {" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "${ha_fronting_master}" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "}" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "track_script {" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "check_haproxy" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "}" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
	echo "}" | sudo tee -a /etc/keepalived/keepalived.conf > /dev/null
}

function install_haproxy () {

	YUM="$1"

	${YUM} install gcc pcre-static pcre-devel openssl-devel -y
	sudo rm -rf haproxy-1.8.3 haproxy.tar.gz
	sudo wget http://www.haproxy.org/download/1.8/src/haproxy-1.8.3.tar.gz -O ~/haproxy.tar.gz
	sudo tar xzvf ~/haproxy.tar.gz -C ~/
	cd ~/haproxy-1.8.3
	sudo make TARGET=linux2628 USE_PCRE=1 USE_OPENSSL=1 ARCH=$(uname -m) PCRE_LIB=/usr/lib64 SSL_LIB=/usr/lib64
	sudo make install
	sudo mkdir -p /etc/haproxy
	sudo mkdir -p /var/lib/haproxy
	sudo touch /var/lib/haproxy/stats
	sudo ln -sf /usr/local/sbin/haproxy /usr/sbin/haproxy
	sudo \cp ./examples/haproxy.init /etc/init.d/haproxy
	sudo chmod 755 /etc/init.d/haproxy
	sudo systemctl daemon-reload
	sudo systemctl enable haproxy
	sudo id -u haproxy &>/dev/null || sudo useradd haproxy
	sudo mkdir -p /etc/haproxy/ssl
	cd /etc/haproxy/ssl
	sudo openssl req -x509 -nodes -days 1825 -newkey rsa:2048 -keyout /etc/haproxy/ssl/nginx-selfsigned.key -out /etc/haproxy/ssl/nginx-selfsigned.crt -batch
	sudo cat /etc/haproxy/ssl/nginx-selfsigned.crt /etc/haproxy/ssl/nginx-selfsigned.key | sudo tee /etc/haproxy/ssl/haproxy.pem
}

function install_nginx () {

	YUM="$1"
	ic_internal=$2
	ha_fronting_master=$3

	# Add repo
	echo "[nginx]" | sudo tee /etc/yum.repos.d/nginx.repo > /dev/null
	echo "name=nginx repo" | sudo tee -a /etc/yum.repos.d/nginx.repo > /dev/null
	echo "baseurl=https://nginx.org/packages/mainline/rhel/7/\$basearch/" | sudo tee -a /etc/yum.repos.d/nginx.repo > /dev/null
	echo "gpgcheck=0" | sudo tee -a /etc/yum.repos.d/nginx.repo > /dev/null
	echo "enabled=1" | sudo tee -a /etc/yum.repos.d/nginx.repo > /dev/null

	# Install
	${YUM} install nginx -y

	# Disable the repo
	sudo yum-config-manager --disable nginx*

	# SSL
	sudo mkdir -p /etc/nginx
	sudo mkdir -p /etc/nginx/ssl
	sudo openssl req -x509 -nodes -days 1825 -newkey rsa:2048 -keyout /etc/nginx/ssl/nginx-selfsigned.key -out /etc/nginx/ssl/nginx-selfsigned.crt -batch

	# create conf file
	echo "" | sudo tee /etc/nginx/nginx.conf > /dev/null
	echo "user  nginx;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "worker_processes  1;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "worker_rlimit_nofile 30000;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "error_log  /var/log/nginx/error.log warn;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "pid        /var/run/nginx.pid;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "events {" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "    worker_connections  16384;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "}" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "http {" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "    include     /etc/nginx/mime.types;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "    include     /etc/nginx/fastcgi_params;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        index    index.html index.htm index.php;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "    default_type  application/octet-stream;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "    log_format  main  '\$remote_addr - \$remote_user [\$time_local] \"\$request\" '" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                      '\$status \$body_bytes_sent \"\$http_referer\" '" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                      '\"\$http_user_agent\" \"\$http_x_forwarded_for\"';" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "    access_log  /var/log/nginx/access.log  main;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "    sendfile        on;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "    #tcp_nopush     on;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "    keepalive_timeout  65;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "    gzip  on;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        gunzip on;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        gzip_types application/atom+xml application/atomcat+xml  application/javascript application/json application/octet-stream application/x-javascript application/xhtml+xml application/xml text/css text/javascript text/plain text/xml  text/xsl;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        gzip_proxied no-cache no-store private expired auth;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        gzip_min_length 1000;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        gzip_comp_level 2;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "    include /etc/nginx/conf.d/*.conf;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        proxy_redirect          off;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        proxy_set_header        Host            \$host;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        proxy_set_header        X-Real-IP       \$remote_addr;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        proxy_connect_timeout   65;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        proxy_send_timeout      65;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        proxy_read_timeout      300;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        proxy_buffers           4 256k;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        proxy_buffer_size       128k;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        proxy_busy_buffers_size 256k;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        proxy_buffering         off;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        large_client_header_buffers  8 64k;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        client_header_buffer_size    64k;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        client_max_body_size    1024m;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        server {" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                listen          443 ssl;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                #server_name MW_PROXY_SERVICE;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                server_name ${ha_fronting_master};" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                ssl_certificate /etc/nginx/ssl/nginx-selfsigned.crt;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                ssl_certificate_key /etc/nginx/ssl/nginx-selfsigned.key;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                    ssl_session_cache    shared:SSL:1m;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                    ssl_session_timeout  5m;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo '                    ssl_ciphers  HIGH:!aNULL:!MD5;' | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                    ssl_prefer_server_ciphers  on;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                proxy_ssl_session_reuse on;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                proxy_ssl_protocols TLSv1.2;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                rewrite_log on;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                location / {" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                location ~ ^/(files/customizer|files/app|communities/service/html|forums/html|search/web|social/home|mycontacts|wikis/home|blogs|news|activities/service/html|profiles/html|viewer)  {" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                        proxy_pass http://${ha_fronting_master}:30301;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                }" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                        proxy_pass https://${ic_internal}:443;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                }" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        }" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        server {" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                listen          80;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                rewrite_log on;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                #server_name MW_PROXY_SERVICE;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                server_name ${ha_fronting_master};" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                location / {" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                location ~ ^/(files/customizer|files/app|communities/service/html|forums/html|search/web|homepage/web|social/home|mycontacts|wikis/home|blogs|news|activities/service/html|profiles/html|viewer)  {" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                        proxy_pass http://${ha_fronting_master}:30301;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                }" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                        proxy_pass http://${ic_internal}:80;" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "                }" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "        }" | sudo tee -a /etc/nginx/nginx.conf > /dev/null
	echo "}" | sudo tee -a /etc/nginx/nginx.conf > /dev/null

	# Disable the firewall between the Kubernetes masters and the NGINX server:
	sudo setsebool -P httpd_can_network_connect true

	# Modify the service configuration to support starting the NGINX server using systemctl
	sudo mkdir -p /etc/systemd/system/nginx.service.d
	echo "[Service]" | sudo tee /etc/systemd/system/nginx.service.d/nofile_limit.conf > /dev/null
	echo "LimitNOFILE=16384" | sudo tee -a /etc/systemd/system/nginx.service.d/nofile_limit.conf > /dev/null
	sudo systemctl daemon-reload

	# Start nginx
	sudo systemctl start nginx
}

function configure_haproxy () {

	primary_master=$1
	_array=( $2 )

	echo "global" | sudo tee /etc/haproxy/haproxy.cfg > /dev/null
	echo "   log /dev/log local0" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "   log /dev/log local1 notice" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "   chroot /var/lib/haproxy" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "   stats timeout 30s" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "   user haproxy" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "   group haproxy" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "   daemon" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "defaults" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    mode                    tcp" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    log                     global" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option                  httplog" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option                  dontlognull" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option                  http-server-close" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option                  redispatch" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    retries                 3" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    timeout http-request    10s" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    timeout queue           1m" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    timeout connect         10s" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    timeout client          1m" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    timeout server          1m" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    timeout http-keep-alive 10s" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    timeout check           10s" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    maxconn                 3000" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "frontend http_stats" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "   bind *:8080" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "   mode http" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "   stats uri /haproxy?stats" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "frontend localhost" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    bind *:80" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    bind *:443 ssl crt /etc/haproxy/ssl/haproxy.pem" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    mode http" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "frontend haproxy_mwproxy" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    bind *:30301" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    mode tcp" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option tcplog" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    maxconn 100000" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    timeout client  10800s" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    default_backend masters_mwproxy" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "backend masters_mwproxy" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    mode http" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    balance roundrobin" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option forwardfor" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option httpchk HEAD / HTTP/1.1\r\nHost:localhost" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    server $(echo ${primary_master} | awk -F. '{print $1}') ${primary_master}:30301 check" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	for i in "${_array[@]}"; do
		echo "    server $(echo $i | awk -F. '{print $1}') $i:30301 check" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	done
	echo "    http-request set-header X-Forwarded-Port %[dst_port]" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    http-request add-header X-Forwarded-Proto https if { ssl_fc }" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "frontend haproxy_kube" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    bind *:6443" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    mode tcp" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option tcplog" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    timeout client  10800s" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    default_backend masters" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "backend masters" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    mode tcp" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option tcplog" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option tcp-check" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    balance roundrobin" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    server $(echo ${primary_master} | awk -F. '{print $1}') ${primary_master}:6443 check" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	for i in "${_array[@]}"; do
		echo "    server $(echo $i | awk -F. '{print $1}') $i:6443 check" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	done
	echo "" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "frontend haproxy_redis" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    bind *:30379" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    mode tcp" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option tcplog" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    timeout client  10800s" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    default_backend masters_redis" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "backend masters_redis" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    mode tcp" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option tcplog" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option tcp-check" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    balance roundrobin" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    server $(echo ${primary_master} | awk -F. '{print $1}') ${primary_master}:30379 check" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	for i in "${_array[@]}"; do
		echo "    server $(echo $i | awk -F. '{print $1}') $i:30379 check" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	done
	echo "" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "frontend haproxy_kibana" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    bind *:32333" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    mode tcp" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option tcplog" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    timeout client  10800s" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    default_backend masters_kibana" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "backend masters_kibana" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    mode tcp" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option tcplog" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option tcp-check" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    balance roundrobin" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    server $(echo ${primary_master} | awk -F. '{print $1}') ${primary_master}:32333 check" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	for i in "${_array[@]}"; do
		echo "    server $(echo $i | awk -F. '{print $1}') $i:32333 check" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	done
	echo "" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "frontend haproxy_elasticsearch" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    bind *:30099" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    mode tcp" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option tcplog" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    timeout client  10800s" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    default_backend masters_elasticsearch" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "backend masters_elasticsearch" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    mode tcp" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option tcplog" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option tcp-check" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    balance roundrobin" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    server $(echo ${primary_master} | awk -F. '{print $1}') ${primary_master}:30099 check" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	for i in "${_array[@]}"; do
		echo "    server $(echo $i | awk -F. '{print $1}') $i:30099 check" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	done
	echo "" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "frontend cnx_ingress_http" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    bind *:32080" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    mode tcp" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option tcplog" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    timeout client  10800s" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    default_backend masters_cnx_ingress_http" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "backend masters_cnx_ingress_http" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    mode tcp" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option tcplog" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option tcp-check" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    balance roundrobin" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    server $(echo ${primary_master} | awk -F. '{print $1}') ${primary_master}:32080 check" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	for i in "${_array[@]}"; do
		echo "    server $(echo $i | awk -F. '{print $1}') $i:32080 check" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	done
	echo "" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "frontend cnx_ingress_https" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    bind *:32443" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    mode tcp" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option tcplog" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    timeout client  10800s" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    default_backend masters_cnx_ingress_https" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "backend masters_cnx_ingress_https" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    mode tcp" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option tcplog" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    option tcp-check" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    balance roundrobin" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	echo "    server $(echo ${primary_master} | awk -F. '{print $1}') ${primary_master}:32443 check" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	for i in "${_array[@]}"; do
		echo "    server $(echo $i | awk -F. '{print $1}') $i:32443 check" | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null
	done
}

function create_primary_config_yaml () {

	homeFolder=$1
	ha_fronting_master=$2
	urls=$3
	podSubnet=$4
	release=$(kubeadm version | grep GitVersion: | awk '{print $5}' | cut -c 14- | sed 's/",//')

	compareVersions ${release} 1.12.99

	if [ ${comparison_result} = 1 -o ${comparison_result} = 0 ]; then

		echo "apiVersion: kubeadm.k8s.io/v1alpha2" | sudo tee /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "kind: MasterConfiguration" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		if [ ${enable_pod_security_policy} = true ]; then
			echo "apiServerExtraArgs:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
			echo "  enable-admission-plugins: PodSecurityPolicy" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		fi
		echo "kubernetesVersion: v${release}" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "apiServerCertSANs:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "- \"${ha_fronting_master}\"" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "api:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "    controlPlaneEndpoint: \"${ha_fronting_master}:6443\"" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "etcd:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "  local:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "    extraArgs:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "      listen-client-urls: \"https://127.0.0.1:2379,https://$(hostname -i):2379\"" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "      advertise-client-urls: \"https://$(hostname -i):2379\"" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "      listen-peer-urls: \"https://$(hostname -i):2380\"" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "      initial-advertise-peer-urls: \"https://$(hostname -i):2380\"" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "      initial-cluster: \"${urls}\"" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "    serverCertSANs:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "      - $(hostname)" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "      - $(hostname -i)" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "    peerCertSANs:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "      - $(hostname)" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "      - $(hostname -i)" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "networking:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "    # This CIDR is a Calico default. Substitute or remove for your CNI provider." | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "    podSubnet: \"${podSubnet}\"" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	else
		echo "apiVersion: kubeadm.k8s.io/v1beta2" | sudo tee /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "kind: ClusterConfiguration" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "kubernetesVersion: v${release}" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "apiServer:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "  certSANs:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "  - \"${ha_fronting_master}\"" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		if [ ${enable_pod_security_policy} = true ]; then
			echo "  extraArgs:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
			echo "    enable-admission-plugins: PodSecurityPolicy" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		fi
		echo "controlPlaneEndpoint: \"${ha_fronting_master}:6443\"" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "networking:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "    # This CIDR is a Calico default. Substitute or remove for your CNI provider." | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "    podSubnet: \"${podSubnet}\"" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	fi
}

function create_secondary_config_yaml () {

	homeFolder=$1
	ha_fronting_master=$2
	urls=$3
	podSubnet=$4
	release=$(kubeadm version | grep GitVersion: | awk '{print $5}' | cut -c 14- | sed 's/",//')

	echo "apiVersion: kubeadm.k8s.io/v1beta2" | sudo tee /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "kind: MasterConfiguration" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	if [ ${enable_pod_security_policy} = true ]; then
		echo "apiServerExtraArgs:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "  enable-admission-plugins: PodSecurityPolicy" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	fi
	echo "kubernetesVersion: v${release}" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "apiServerCertSANs:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "- \"${ha_fronting_master}\"" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "api:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "    controlPlaneEndpoint: \"${ha_fronting_master}:6443\"" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "etcd:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "  local:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "    extraArgs:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "      listen-client-urls: \"https://127.0.0.1:2379,https://$(hostname -i):2379\"" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "      advertise-client-urls: \"https://$(hostname -i):2379\"" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "      listen-peer-urls: \"https://$(hostname -i):2380\"" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "      initial-advertise-peer-urls: \"https://$(hostname -i):2380\"" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "      initial-cluster: \"${urls}\"" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "      initial-cluster-state: existing" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "    serverCertSANs:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "      - $(hostname)" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "      - $(hostname -i)" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "    peerCertSANs:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "      - $(hostname)" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "      - $(hostname -i)" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "networking:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "    # This CIDR is a Calico default. Substitute or remove for your CNI provider." | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	echo "    podSubnet: \"${podSubnet}\"" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
}

function create_config_yaml () {

	homeFolder=$1
	podSubnet=$2
	release=$(kubeadm version | grep GitVersion: | awk '{print $5}' | cut -c 14- | sed 's/",//')

	compareVersions ${release} 1.11.9

	if [ ${comparison_result} = 1 -o ${comparison_result} = 0 ]; then
		echo "apiVersion: kubeadm.k8s.io/v1alpha2" | sudo tee /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "kind: MasterConfiguration" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		if [ ${enable_pod_security_policy} = true ]; then
			echo "apiServerExtraArgs:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
			echo "  enable-admission-plugins: PodSecurityPolicy" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		fi
		echo "kubernetesVersion: v${release}" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "networking:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "    # This CIDR is a Calico default. Substitute or remove for your CNI provider." | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "    podSubnet: \"${podSubnet}\"" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
	else 
		echo "apiVersion: kubeadm.k8s.io/v1beta2" | sudo tee /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "kind: ClusterConfiguration" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		if [ ${enable_pod_security_policy} = true ]; then
			echo "apiServer:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
			echo "  extraArgs:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
			echo "    enable-admission-plugins: PodSecurityPolicy" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		fi
		echo "kubernetesVersion: v${release}" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "networking:" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "    # This CIDR is a Calico default. Substitute or remove for your CNI provider." | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null
		echo "    podSubnet: \"${podSubnet}\"" | sudo tee -a /${homeFolder}/kubeadm-config.yaml > /dev/null

	fi


}


function master_cmds () {

	homeFolder=$1

	mkdir -p ${homeFolder}/.kube
	sudo \cp /etc/kubernetes/admin.conf ${homeFolder}/.kube/config
	sudo chown $(id -u):$(id -g) ${homeFolder}/.kube/config
}

function kubeadm_phase () {

	homeFolder=$1

	sudo kubeadm alpha phase certs all --config /${homeFolder}/kubeadm-config.yaml
	sudo kubeadm alpha phase kubelet config write-to-disk --config /${homeFolder}/kubeadm-config.yaml
	sudo kubeadm alpha phase kubelet write-env-file --config /${homeFolder}/kubeadm-config.yaml
	sudo kubeadm alpha phase kubeconfig kubelet --config /${homeFolder}/kubeadm-config.yaml
	sudo systemctl daemon-reload
	sudo systemctl start kubelet
}

function add_etcd_member () {

	primary_hostname=$1
	primary_ip=$2

	KUBECONFIG=/etc/kubernetes/admin.conf kubectl exec -n kube-system etcd-${primary_hostname} -- etcdctl --ca-file /etc/kubernetes/pki/etcd/ca.crt --cert-file /etc/kubernetes/pki/etcd/peer.crt --key-file /etc/kubernetes/pki/etcd/peer.key --endpoints=https://${primary_ip}:2379 member add $(hostname) https://$(hostname -i):2380
}

function mark_master () {

	homeFolder=$1

	sudo kubeadm alpha phase kubeconfig all --config /${homeFolder}/kubeadm-config.yaml
	sudo kubeadm alpha phase controlplane all --config /${homeFolder}/kubeadm-config.yaml
	sudo kubeadm alpha phase mark-master --config /${homeFolder}/kubeadm-config.yaml
}

function install_helm () {

	helm_version=$1

	wget https://storage.googleapis.com/kubernetes-helm/helm-${helm_version}-linux-amd64.tar.gz
	sudo tar -zxvf helm-${helm_version}-linux-amd64.tar.gz
	sudo rm -rf /usr/local/bin/helm
	sudo mv linux-amd64/helm /usr/local/bin

	# Do the RBAC configuratation for Helm
    kubectl -n kube-system create sa tiller
    kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
    
    /usr/local/bin/helm init --service-account tiller
}

function install_helmv3 () {

	helm_version=$1

	# wget https://storage.googleapis.com/kubernetes-helm/helm-${helm_version}-linux-amd64.tar.gz
	wget https://get.helm.sh/helm-${helm_version}-linux-amd64.tar.gz
	sudo tar -zxvf helm-${helm_version}-linux-amd64.tar.gz
	sudo rm -rf /usr/local/bin/helm
	sudo mv linux-amd64/helm /usr/local/bin
}	

function unmount_containers () {

        set +o errexit
        if [ "`sudo mount | grep /var/lib/kubelet`" != "" ]; then
                sudo mount | grep /var/lib/kubelet | awk '{ print $3 }' | sudo xargs -t -l umount
        fi
        if [ "`sudo mount | grep /var/lib/docker | grep /overlay/`" != "" ]; then
                sudo mount | grep /var/lib/docker | grep /overlay/ | awk '{ print $3 }' | sudo xargs -t -l umount
        fi
        if [ "`sudo mount | grep /var/lib/docker | grep /devicemapper/`" != "" ]; then
                sudo mount | grep /var/lib/docker | grep /devicemapper/ | awk '{ print $3 }' | sudo xargs -t -l umount
        fi
        if [ "`sudo mount | grep /var/lib/docker`" != "" ]; then
                sudo mount | grep /var/lib/docker | awk '{ print $3 }' | sudo xargs -t -l umount
        fi
        if [ "`sudo mount | grep /run/docker`" != "" ]; then
                sudo mount | grep /run/docker | awk '{ print $3 }' | sudo xargs -t -l umount
        fi
        set -o errexit
}

function reset_block_device () {

	docker_storage_block_device=$1

	sudo lvdisplay | grep -q 'docker' && sudo lvremove -f docker || echo "docker logical volume not found.  Nothing to do. Continuing."
	sudo vgdisplay | grep -q 'docker' && sudo vgremove -f docker || echo "docker volume group not found. Nothing to do. Continuing."
	sudo pvdisplay | grep -q ${docker_storage_block_device} && sudo pvremove -f ${docker_storage_block_device} || echo "physical volume ${docker_storage_block_device} not found. Nothing to do. Continuing."

	sudo rm -f /etc/lvm/profile/docker-thinpool.profile
}

function kubeadm_check () {

	echo "Checking if kubeadm is initialised on $(hostname -f)"
	set +o errexit
	if rpm -q kubeadm;  then
		echo "Running kubeadm reset --force on $(hostname -f)"
		sudo kubeadm reset --force
	else
		echo "Kubeadm not initialised on $(hostname -f)"
	fi
	set -o errexit
}

function DNS_check () {

	echo
	echo "Verifying DNS is healthy on $(hostname -f)"

	kubectl create -f https://k8s.io/examples/admin/dns/busybox.yaml

	# Make sure busybox pod is running
	counter=0
	retries=10
	wait=5
	while true; do
		echo
		echo "Checking busybox pod is running.."
		if [[ "$(kubectl get pods busybox | grep 'Running' | awk '{ print $3 }')" = "Running" ]]; then
			echo "Found pod running"
			echo
			break
		fi
		counter=`expr ${counter} + 1`
		if [ ${counter} -ge ${retries} ]; then
			echo
			echo "Giving up. Please investigate why busybox pod is not running"
			kubectl delete -f https://k8s.io/examples/admin/dns/busybox.yaml
			exit 1
		else
			echo "Waiting ${wait}s and then trying again (${counter}/${retries})"
		fi
		sleep ${wait}
	done

	set +o errexit
	kubectl exec -ti busybox -- nslookup kubernetes.default
	if [ $? -ne 0 ]; then
		echo
		echo "Found problem with DNS. Cleaning iptables and retrying.."
		sudo iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
		kubectl exec -ti busybox -- nslookup kubernetes.default
		if [ $? -ne 0 ]; then
			echo
			echo "Still found a problem with DNS. Restarting coredns pods and retrying.."
			kubectl delete pod -n kube-system -l k8s-app=kube-dns
			number_retries=3
			retry_wait_time=5
			counter=1
			while [ ${counter} -le ${number_retries} ]; do
				echo "Checking if coredns is ready (${counter}/${number_retries})"
				kubectl get deployment coredns -n kube-system | awk '$2 == $5 { print $0 }' | grep -q coredns
				if [ $? -ne 0 ]; then
					echo "	coredns is not ready yet, retrying in ${retry_wait_time}s"
					sleep ${retry_wait_time}
					counter=`expr ${counter} + 1`
				else
					echo "coredns is ready"
					break
				fi
			done
			if [ ${counter} -gt ${number_retries} ]; then
				echo "Maximum attempts reached waiting for coredns pods, giving up"
				kubectl delete -f https://k8s.io/examples/admin/dns/busybox.yaml
				exit 1
			fi
			kubectl exec -ti busybox -- nslookup kubernetes.default
			if [ $? -ne 0 ]; then
				echo "Still problems with DNS after cleaning iptables and restarting coredns. Exiting."
				kubectl delete -f https://k8s.io/examples/admin/dns/busybox.yaml
				exit 1
			fi
		fi
	fi
	set -o errexit
	echo
	echo "DNS health check complete"
	kubectl delete -f https://k8s.io/examples/admin/dns/busybox.yaml
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

# nginx validation
if [ "${nginx_reverse_proxy}" != "" -a "${ic_internal}" = "" ]; then
	echo "A value for ic_internal (HTTP server) must be set if you want to deploy and nginx server"
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
if [ "${external_nfs_server}" != "" ]; then
	resolve_ip ${external_nfs_server}
fi
if [ "${external_docker_registry}" != "" ]; then
	resolve_ip ${external_docker_registry}
fi
if [ "${nginx_reverse_proxy}" != "" ]; then
	resolve_ip ${nginx_reverse_proxy}
fi
echo "Hostname validation complete."

# Set the value of ha_fronting_master
if [ "${remaining_master_list}" != "" ]; then
	if [ "${#haproxyArray[@]}" -gt 1 ]; then
		if [ "${haproxy_lb_vip}" = "" ]; then
			echo "A value for haproxy_lb_vip must be entered when deploying more than one load balancer."
			exit 1
		else
			ha_fronting_master=${haproxy_lb_vip}
		fi
	elif [ "${#haproxyArray[@]}" -eq 1 ]; then
		if [ "${haproxy_lb_vip}" != "" ]; then
			echo "A value for haproxy_lb_vip is only needed when deploying more than 1 load balancer."
			exit 1
		else
			ha_fronting_master=${haproxy_lb_list}
		fi
	fi
else
	ha_fronting_master=$(hostname -f)
fi

# Configure Firewall
if [ ${configure_firewall} = true ]; then
	echo
	echo "Configuring firewall ports on $(hostname -f)"
	sudo service firewalld restart

	# Configure masters
	master_ports=(179 6443 2379 2380 10250 10251 10252)
	add_command=""
	for port in ${master_ports[@]}; do
		add_command+="--add-port=$port/tcp "
	done
	sudo firewall-cmd -q --zone=public ${add_command} --permanent
	sudo firewall-cmd --reload

	if [ "${remaining_master_list}" != "" ]; then
		for master in ${masterArray[@]}; do
			echo
			echo "Configuring firewall ports on $master"
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "sudo service firewalld restart"
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "sudo firewall-cmd -q --zone=public ${add_command} --permanent || exit 1"
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "sudo firewall-cmd --reload"
		done
	fi

	# Configure workers
	if [ "${worker_list}" != "" ]; then
		worker_ports=(179 10250 80 443 $(seq 30000 32767))
		add_command=""
		for port in ${worker_ports[@]}; do
			add_command+="--add-port=$port/tcp "
		done
		for worker in ${workerArray[@]}; do
			echo
			echo "Configuring firewall ports on $worker (This may take some time)"
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${worker} "sudo service firewalld restart"
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${worker} "sudo firewall-cmd -q --zone=public ${add_command} --permanent || exit 1"
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${worker} "sudo firewall-cmd --reload"
		done
	fi
	echo
	echo "Firewall configuration complete"
fi

# Remove Docker and Kubernetes
if [ ${remove_prereqs} = true ]; then
	# kubeadm reset
	kubeadm_check
	if [ "${worker_list}" != "" ]; then
		for worker in ${workerArray[@]}; do
			typeset -f kubeadm_check | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${worker} "$(cat); kubeadm_check"
		done
	fi
	if [ "${remaining_master_list}" != "" ]; then
		for master in ${masterArray[@]}; do
			typeset -f kubeadm_check | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "$(cat); kubeadm_check"
		done
	fi

	# Remove kubelet, kubeadm and kubectl
	echo
	echo "Removing kubelet, kubeadm and kubectl on $(hostname -f)"
	${YUM} remove -y kubelet kubeadm* kubectl*
	sudo rm -rf /etc/kubernetes ${homeFolder}/.kube /var/lib/cni/networks
	if [ "${worker_list}" != "" ]; then
		for worker in ${workerArray[@]}; do
			echo
			echo "Removing kubelet, kubeadm and kubectl on $worker"
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${worker} "${YUM} remove -y kubelet kubeadm* kubectl*; sudo rm -rf /etc/kubernetes ${homeFolder}/.kube /var/lib/cni/networks"
		done
	fi
	if [ "${remaining_master_list}" != "" ]; then
		for master in ${masterArray[@]}; do
			echo
			echo "Removing kubelet, kubeadm and kubectl on $master"
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "${YUM} remove -y kubelet kubeadm* kubectl*; sudo rm -rf /etc/kubernetes ${homeFolder}/.kube /var/lib/cni/networks"
		done
	fi

	# Remove docker
	echo
	echo "Removing docker on $(hostname -f)"
	set +o errexit
	sudo docker rm $(sudo docker ps -aq)
	sudo docker rmi -f $(sudo docker images -q)
	sudo service docker stop
	set -o errexit
	${YUM} remove -y docker* docker-ce-cli* container-selinux 2:container-selinux*
	if [ "${docker_storage_type}" == "devicemapper-direct-lvm" -o "${docker_storage_type}" == "devicemapper-loop-lvm" ]; then
		unmount_containers
	fi
	if [ "${docker_storage_type}" == "devicemapper-direct-lvm" ]; then
		echo
		echo "Cleaning up Docker storage block device ${docker_storage_block_device} on $(hostname -f)"
		reset_block_device ${docker_storage_block_device}
	fi
	set +o errexit
	if [ "${docker_storage_type}" == "devicemapper-direct-lvm" -o "${docker_storage_type}" == "devicemapper-loop-lvm" ]; then
		sudo rm -rf /var/lib/docker /var/lib/etcd /etc/docker/daemon.json
	else
		sudo rm -rf /var/lib/docker/* /var/lib/etcd /etc/docker/daemon.json
	fi
	set -o errexit
	if [ "${worker_list}" != "" ]; then
		for worker in ${workerArray[@]}; do
			echo
			echo "Removing docker on $worker"
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${worker} "sudo docker rm $(docker ps -aq); sudo docker rmi -f $(docker images -q); sudo service docker stop; ${YUM} remove -y docker* docker-ce-cli* container-selinux 2:container-selinux*"
			if [ "${docker_storage_type}" == "devicemapper-direct-lvm" -o "${docker_storage_type}" == "devicemapper-loop-lvm" ]; then
				typeset -f unmount_containers | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${worker} "$(cat); unmount_containers"
			fi
			if [ "${docker_storage_type}" == "devicemapper-direct-lvm" ]; then
				echo
				echo "Cleaning up Docker storage block device ${docker_storage_block_device} on $worker"
				typeset -f reset_block_device | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${worker} "$(cat); reset_block_device ${docker_storage_block_device} || exit 1"
			fi
			if [ "${docker_storage_type}" == "devicemapper-direct-lvm" -o "${docker_storage_type}" == "devicemapper-loop-lvm" ]; then
				sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${worker} "sudo rm -rf /var/lib/docker /var/lib/etcd /etc/docker/daemon.json"
			else
				sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${worker} "sudo rm -rf /var/lib/docker/* /var/lib/etcd /etc/docker/daemon.json"
			fi
		done
	fi
	if [ "${remaining_master_list}" != "" ]; then
		for master in ${masterArray[@]}; do
			echo
			echo "Removing docker on $master"
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "sudo docker rm $(docker ps -aq); sudo docker rmi -f $(docker images -q); sudo service docker stop; ${YUM} remove -y docker* docker-ce-cli* container-selinux 2:container-selinux*"
			if [ "${docker_storage_type}" == "devicemapper-direct-lvm" -o "${docker_storage_type}" == "devicemapper-loop-lvm" ]; then
				typeset -f unmount_containers | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "$(cat); unmount_containers"
			fi
			if [ "${docker_storage_type}" == "devicemapper-direct-lvm" ]; then
				echo
				echo "Cleaning up Docker storage block device ${docker_storage_block_device} on $master"
				typeset -f reset_block_device | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "$(cat); reset_block_device ${docker_storage_block_device} || exit 1"
			fi
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "sudo rm -rf /var/lib/docker /var/lib/etcd /etc/docker/daemon.json"
		done
	fi

	# Remove SophosAV
	if [ -e /opt/sophos-av/uninstall.sh ]; then
		sudo /opt/sophos-av/uninstall.sh --automatic --force
		sudo rm -rf /opt/sophos-av
	fi

	# Remove Docker Registry
	sudo rm -rf /docker-registry
	if [ "${remaining_master_list}" != "" ]; then
		for master in ${masterArray[@]}; do
			echo
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "sudo rm -rf /docker-registry"
		done
	fi

	if [ "${worker_list}" != "" ]; then
    		IFS=',' read -r -a workerArray <<< "${worker_list}"
		for worker in ${workerArray[@]}; do
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${worker} "sudo rm -rf /docker-registry"
		done
	fi
fi

# Install Docker
if [ ${install_docker} = true ]; then
	echo
	echo "Installing Docker on $(hostname -f)"
	#docker_install "${YUM}" ${FTP3USER} ${FTP3PASS} ${docker_version} ${docker_storage_type} ${docker_storage_block_device}
	docker_install "${YUM}" ${docker_version} ${docker_storage_type} ${docker_storage_block_device}
	echo
	echo "Validating Docker on $(hostname -f)"
	runDockerHelloWorldTest || exit 1
	set -o errexit
	if [ "${remaining_master_list}" != "" ]; then
		for master in ${masterArray[@]}; do
			echo
			echo "Installing Docker on $master"
			typeset -f docker_install | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "$(cat); docker_install \"${YUM}\" ${docker_version} ${docker_storage_type} ${docker_storage_block_device} || exit 1"
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
			typeset -f docker_install | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${worker} "$(cat); docker_install \"${YUM}\" ${docker_version} ${docker_storage_type} ${docker_storage_block_device} || exit 1"
			echo
			echo "Validating Docker on $worker"
			typeset -f runDockerHelloWorldTest | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${worker} "$(cat); runDockerHelloWorldTest || exit 1"
			set -o errexit
		done
	fi

fi

# Configure Sophos AV
if [ ${enable_sophosav} = true ]; then
        echo
        setup_sophosav
fi

# Install K8s
if [ ${install_k8s} = true ]; then
	# Set calico CIDR
	pod_network_cidr="192.168.0.0/16"
	echo
	echo "Installing Kubernetes on $(hostname -f)"
		#k8s_install "${YUM}" ${k8s_version} ${FTP3USER} ${FTP3PASS} ${k8s_cni_version} || exit 1
		k8s_install "${YUM}" ${k8s_version} ${k8s_cni_version} || exit 1
	if [ "${remaining_master_list}" != "" ]; then
		for master in ${masterArray[@]}; do
			echo
			echo "Installing Kubernetes on $master"
			typeset -f k8s_install | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "$(cat); k8s_install \"${YUM}\" ${k8s_version} ${k8s_cni_version} || exit 1"
		done
	fi
	if [ "${worker_list}" != "" ]; then
		for worker in ${workerArray[@]}; do
			echo
			echo "Installing Kubernetes on $worker"
			typeset -f k8s_install | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${worker} "$(cat); k8s_install \"${YUM}\" ${k8s_version} ${k8s_cni_version} || exit 1"
		done
	fi

	# HA steps
	if [ "${remaining_master_list}" != "" ]; then
		counter=0
		for lb in ${haproxyArray[@]}; do
			counter=`expr ${counter} + 1`
			echo
			echo "Installing HAProxy on $lb"
			typeset -f install_haproxy | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@$lb "$(cat); install_haproxy \"${YUM}\" || exit 1"
			echo
			echo "Configuring HAProxy on $lb"
			primary_master=$(hostname -f)
			typeset -f configure_haproxy | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@$lb "$(cat); configure_haproxy ${primary_master} \"$(echo ${masterArray[@]})\" || exit 1"
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@$lb "sudo systemctl restart haproxy || exit 1"
			if [ "${#haproxyArray[@]}" -gt 1 ]; then
				echo
				echo "Installing keepalived on $lb"
				sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@$lb "${YUM} -y install keepalived"
				echo
				echo "Creating keepalived configuration file on $lb"
				if [ ${counter} -eq 1 ]; then
					typeset -f create_keepalived_conf | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@$lb "$(cat); create_keepalived_conf MASTER 101 ${ha_fronting_master} || exit 1"
				else
					typeset -f create_keepalived_conf | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@$lb "$(cat); create_keepalived_conf SLAVE 100 ${ha_fronting_master} || exit 1"
				fi
				sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@$lb "sudo service keepalived start"
			fi
		done
		echo
		echo "Load balancer stats can be viewed here: http://${ha_fronting_master}:8080/haproxy?stats"
		echo
		echo "Creating kubeadm-config.yaml on $(hostname -f)"
		urls="$(hostname)=https://$(hostname -i):2380"
		create_primary_config_yaml ${homeFolder} ${ha_fronting_master} ${urls} ${pod_network_cidr}
		echo
  		echo "${homeFolder}"
		echo "Running kubeadm init on $(hostname -f)"
		sudo kubeadm init --config=/${homeFolder}/kubeadm-config.yaml | sudo tee init.log
		if grep -q "Unfortunately, an error has occurred" init.log; then
  			echo "Found an issue when trying to initialize. Check init.log"
			exit 1
		fi
		if grep -q "Some fatal errors occurred" init.log; then
  			echo "Some fatal errors occurred when trying to initialize. Check init.log"
			exit 1
		fi
		echo

		echo "Running commands on $(hostname -f) required to start using your cluster"
		master_cmds ${homeFolder}

		if [ ${enable_pod_security_policy} = true ]; then
			echo
			echo "Creating Pod Security Policies on $(hostname -f)"
 			file="privileged-psp-with-rbac.yaml"

			# Download files with icdeploy@hcl.com(Hint: no icci ID at HCL - icci@us.ibm.com) credentials:
			echo "Downloading Pod Security Policy file"
			TOKEN=${GIT_TOKEN}
			OWNER="connections"
			REPO="deploy-services"

			sudo rm -rf $FILE
			PATH_FILE="microservices/hybridcloud/doc/samples/psp/${file}"
			FILE="https://git.cwp.pnp-hcl.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
			sudo curl -H "Authorization: token $TOKEN" \
			-H "Accept: application/vnd.github.v3.raw" \
			-O \
			-L $FILE

			kubectl apply -f privileged-psp-with-rbac.yaml
			echo
		fi

		# Make sure the etcd primary master pod is running before proceeding
		counter=0
		retries=10
		wait=30
		while true; do
			echo
			echo "Checking etcd-$(hostname) pod is running.."
			if [[ "$(kubectl -n kube-system get pod etcd-$(hostname) | grep 'Running' | awk '{ print $3 }')" = "Running" ]]; then
				echo "Check completed"
				echo
				break
			fi
			counter=`expr ${counter} + 1`
			if [ ${counter} -ge ${retries} ]; then
				echo
				echo "Giving up. Please investigate why etcd-$(hostname) pod is not running"
				exit 1
			else
				echo "Waiting ${wait}s and then trying again (${counter}/${retries})"
			fi
			sleep ${wait}
		done
		required_files=( "admin.conf" "pki/ca.crt" "pki/ca.key" "pki/sa.key" "pki/sa.pub" "pki/front-proxy-ca.crt" "pki/front-proxy-ca.key" "pki/etcd/ca.crt" "pki/etcd/ca.key" )
		for master in ${masterArray[@]}; do
			echo
			echo "Copying certs and keys from $(hostname -f) to $master"
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "sudo mkdir -p /etc/kubernetes/pki/etcd"
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "sudo mkdir -p ${homeFolder}/pki; sudo mkdir -p ${homeFolder}/pki/etcd; sudo chmod -R 777 ${homeFolder}/pki"
			for i in "${required_files[@]}"; do
				sshpass -p ${ssh_password} sudo scp -o StrictHostKeyChecking=no /etc/kubernetes/$i ${USER}@${master}:${homeFolder}/$i
				sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "sudo mv ${homeFolder}/$i /etc/kubernetes/$i"
			done
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "sudo rm -rf ${homeFolder}/pki"
		done
		for master in ${masterArray[@]}; do
			echo

			release=$(kubeadm version | grep GitVersion: | awk '{print $5}' | cut -c 14- | sed 's/",//')

			compareVersions ${release} 1.12.99

			if [ ${comparison_result} = 1 -o ${comparison_result} = 0 ]; then
				echo "Creating kubeadm-config.yaml on $master"
				resolve_ip $master
				ip=${resolve_ip_return_result}
				shortname=$(echo $master | awk -F'[_.]' '{print $1}')
				urls="${urls},${shortname}=https://${ip}:2380"
				typeset -f create_secondary_config_yaml | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "$(cat); create_secondary_config_yaml ${homeFolder} ${ha_fronting_master} ${urls} ${pod_network_cidr} || exit 1"
				echo
				echo "Running the kubeadm phase commands on $master"
				typeset -f kubeadm_phase | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "$(cat); kubeadm_phase ${homeFolder} || exit 1"
				echo
				echo "Running commands on $master required to start using your cluster"
				typeset -f master_cmds | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "$(cat); master_cmds ${homeFolder} || exit 1"
				echo
				echo "Running the commands on $master to add it to the etcd cluster"
				primary_hostname=$(hostname)
				primary_ip=$(hostname -i)
				typeset -f add_etcd_member | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "$(cat); add_etcd_member ${primary_hostname} ${primary_ip} || exit 1"
				sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "sudo kubeadm alpha phase etcd local --config /${homeFolder}/kubeadm-config.yaml || exit 1"
				echo
				echo "Deploying the control plane components on $master and marking it as a master"
				typeset -f mark_master | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "$(cat); mark_master ${homeFolder} || exit 1"
			else
				join_cmd=`grep "kubeadm join" init.log`
				sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "sudo ${join_cmd} --experimental-control-plane"
				echo "Running commands on $master required to start using your cluster"
				typeset -f master_cmds | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "$(cat); master_cmds ${homeFolder} || exit 1"
				echo

			fi
		done

	else
		echo
		echo "Running kubeadm init on $(hostname -i)"
		create_config_yaml ${homeFolder} ${pod_network_cidr}
		sudo kubeadm init --config=/${homeFolder}/kubeadm-config.yaml | sudo tee init.log
		if grep -q "Unfortunately, an error has occurred" init.log; then
  			echo "Found an issue when trying to initialize. Check init.log"
			exit 1
		fi
		if grep -q "Some fatal errors occurred" init.log; then
  			echo "Some fatal errors occurred when trying to initialize. Check init.log"
			exit 1
		fi
		master_cmds ${homeFolder}

		if [ ${enable_pod_security_policy} = true ]; then
			echo
			echo "Creating Pod Security Policies on $(hostname -f)"
 			file="privileged-psp-with-rbac.yaml"

			# Download files with icdeploy@hcl.com(Hint: no icci ID at HCL - icci@us.ibm.com) credentials:
			echo "Downloading Pod Security Policy file"
			TOKEN=${GIT_TOKEN}
			OWNER="connections"
			REPO="deploy-services"

			sudo rm -rf $FILE
			PATH_FILE="microservices/hybridcloud/doc/samples/psp/${file}"
			FILE="https://git.cwp.pnp-hcl.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
			sudo curl -H "Authorization: token $TOKEN" \
			-H "Accept: application/vnd.github.v3.raw" \
			-O \
			-L $FILE

			kubectl apply -f privileged-psp-with-rbac.yaml
			echo
		fi


	fi


	# Install calico network add-on
	echo
	echo "Installing calico on $(hostname -f)"
	kubectl apply -f https://docs.projectcalico.org/v${calico_version}/manifests/rbac/rbac-kdd-calico.yaml
	kubectl apply -f https://docs.projectcalico.org/v${calico_version}/getting-started/kubernetes/installation/hosted/kubernetes-datastore/calico-networking/1.7/calico.yaml
	# Install/Upgrade Calico to the latest & greatest
	kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

	release=$(kubeadm version | grep GitVersion: | awk '{print $5}' | cut -c 14- | sed 's/",//')

	compareVersions ${release} 1.12.99

	if [ ${comparison_result} = 1 -o ${comparison_result} = 0 ]; then

		if [ "${remaining_master_list}" != "" ]; then
			for master in ${masterArray[@]}; do
				echo
				echo "Installing calico on $master"
				sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "kubectl apply -f https://docs.projectcalico.org/v${calico_version}/getting-started/kubernetes/installation/hosted/rbac-kdd.yaml; kubectl apply -f https://docs.projectcalico.org/v${calico_version}/getting-started/kubernetes/installation/hosted/kubernetes-datastore/calico-networking/1.7/calico.yaml"
			done
		fi
	fi

	# pods on master(s)
	if [ ${pods_on_master} = true ]; then
		echo
		echo "Allowing pods to run on $(hostname -f)"
    		kubectl taint nodes --all node-role.kubernetes.io/master-
        	if [ "${remaining_master_list}" != "" ]; then
        		for master in ${masterArray[@]}; do
            			echo
        			echo "Allowing pods to run on $master"
        			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "kubectl taint nodes --all node-role.kubernetes.io/master-"
        		done
		fi
	fi

	# configure workers
	if [ "${worker_list}" != "" ]; then
		for worker in ${workerArray[@]}; do
			echo
			echo "Joining node $worker to cluster"
			join_cmd=`grep "kubeadm join" init.log`
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${worker} "sudo ${join_cmd}; mkdir -p ${homeFolder}/.kube"
			sshpass -p ${ssh_password} scp -o StrictHostKeyChecking=no ${homeFolder}/.kube/config ${USER}@${worker}:${homeFolder}/.kube
			sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${worker} "chown \`id -u\`:\`id -g\` ${homeFolder}/.kube/config"
		done
	fi

	# Download files with icdeploy@hcl.com(Hint: no icci ID at HCL - icci@us.ibm.com) credentials:
	echo
	echo "Downloading checkPods.sh"
	TOKEN=${GIT_TOKEN}
	OWNER="connections"
	REPO="deploy-services"
	SCRIPT="checkPods.sh"
	rm -f ${SCRIPT}
	PATH_FILE="microservices/hybridcloud/doc/samples/${SCRIPT}"
	FILE="https://git.cwp.pnp-hcl.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
	curl -H "Authorization: token $TOKEN" \
	-H "Accept: application/vnd.github.v3.raw" \
	-O \
	-L $FILE

	sudo chmod 777 ${SCRIPT}
	echo
	echo "Checking all kube-system pods are running.."
	set +o errexit
	bash ${SCRIPT} --retries=60 --wait_interval=30 --namespace=kube-system
	if [ $? -ne 0 ]; then
		echo "Pod verification failed - please investigate"
		exit 1
	fi
	set -o errexit
	sudo rm -f ${SCRIPT}

	# Taint and label es worker nodes
	if [ "${es_worker_list}" != "" ]; then
		IFS=',' read -r -a esworkerArray <<< "${es_worker_list}"
		for esworker in ${esworkerArray[@]}; do
			esnode=$(echo ${esworker} | awk 'BEGIN {FS="."}{print $1}')
			echo
			echo "Adding label and taint to node: ${esnode}"
			kubectl label nodes "${esnode}" type=infrastructure --overwrite
			kubectl taint nodes "${esnode}" dedicated=infrastructure:NoSchedule --overwrite
		done
	fi
	# Verify DNS is working
	DNS_check
	if [ "${remaining_master_list}" != "" ]; then
		for master in ${masterArray[@]}; do
			typeset -f DNS_check | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@$master "$(cat); DNS_check || exit 1"
		done
	fi

	if [ "${worker_list}" != "" ]; then
		for worker in ${workerArray[@]}; do
			typeset -f DNS_check | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@$worker "$(cat); DNS_check || exit 1"
		done
	fi
fi

# Helm
if [ ${install_helm} = true ]; then
	echo
	echo "Installing Helm ${helm_version} on $(hostname -f)"
	install_helm ${helm_version}
	# install_helmv3 ${helm_version}
	
	sudo rm -f helm-${helm_version}-linux-amd64.tar.gz

	# Wait for helm and tiller services to start
	set +o errexit
	echo
	number_retries=20
	retry_wait_time=30
	counter=1
	tiller_service_name=tiller-deploy
	while [ ${counter} -le ${number_retries} ]; do
		echo
		echo "Checking if tiller is ready (${counter}/${number_retries})"
		PODs=$(kubectl get pods -n kube-system | grep ${tiller_service_name} | grep Running | grep 1\/1 | wc -l)
		if [[ $PODs -eq 1 ]]; then
			echo "tiller is ready"
			break
		else
			echo "tiller is not ready yet, retrying in ${retry_wait_time}s"
			sleep ${retry_wait_time}
			counter=`expr ${counter} + 1`
		fi
	done
	if [ ${counter} -gt ${number_retries} ]; then
		echo "Maximum attempts reached, giving up"
		exit 1
	fi
	set -o errexit

	# Install Helm on remaining masters if HA
	if [ "${remaining_master_list}" != "" ]; then
		for master in ${masterArray[@]}; do
			echo
			echo "Installing Helm ${helm_version} on $master"
			typeset -f install_helm | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "$(cat); install_helm ${helm_version} || exit 1"
			# typeset -f install_helm | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${master} "$(cat); install_helmv3 ${helm_version} || exit 1"
		done
	fi
fi

# Namespace
if [ ${create_namespace} = true ]; then
	echo
	echo "Creating connections namespace"
	kubectl create namespace connections
fi

# Persistent Volumes
if [ ${create_pvs} = true ]; then
	if [ "${external_nfs_server}" = "" ]; then
		echo
		echo "Setting up persistent volumes on $(hostname -f)"
		sudo rm -rf connections-persistent-storage-nfs connections-persistent-storage-nfs-0.1.1.tgz volumes.txt
		setup_pvs ${wipe_data} ${pvconnections_folder_path}
		nfs_server=$(hostname -i)
	else
		echo
		echo "Setting up persistent volumes on ${external_nfs_server}"
		sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${external_nfs_server} "sudo rm -rf connections-persistent-storage-nfs connections-persistent-storage-nfs-0.1.1.tgz volumes.txt"
		typeset -f setup_pvs | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${external_nfs_server} "$(cat); setup_pvs ${wipe_data} ${pvconnections_folder_path} || exit 1"
		nfs_server=${external_nfs_server}
	fi

	# Purge connections-volumes if it already exists
	set +o errexit
	installed=$(helm list -q connections-volumes)
	# for helm v3
	# installed=$(helm list -f connections-volumes -q)
	if [[ ${installed} ]]; then
		echo
		echo "Found connections-volumes already exists. Deleteing it"
		helm delete connections-volumes --purge
	fi
	set -o errexit

	# Create the PVs and PVCs:
	if [ "${external_nfs_server}" != "" ]; then
		LIST="connections-persistent-storage-nfs-0.1.1.tgz"

		# Download files with icdeploy@hcl.com(Hint: no icci ID at HCL - icci@us.ibm.com) credentials:
		echo "Downloading connections-volumes helm chart to $(hostname -f)"
		TOKEN=${GIT_TOKEN}
		OWNER="connections"
		REPO="deploy-services"

		for file in ${LIST}; do
			rm -rf $FILE
			PATH_FILE="microservices/hybridcloud/doc/samples/${file}"
			FILE="https://git.cwp.pnp-hcl.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
			sudo curl -H "Authorization: token $TOKEN" \
			-H "Accept: application/vnd.github.v3.raw" \
			-O \
			-L $FILE
		done
	fi
	echo
	echo "Installing connections-volumes which will creating PVs and PVCs on ${nfs_server}"
	helm install --name=connections-volumes connections-persistent-storage-nfs-0.1.1.tgz --set nfs.server=${nfs_server},persistentVolumePath=${pvconnections_folder_path}
	# helm install connections-volumes connections-persistent-storage-nfs-0.1.1.tgz --set nfs.server=${nfs_server},persistentVolumePath=${pvconnections_folder_path}
fi

# Docker Registry
if [ ${setup_docker_registry} = true ]; then
	# Determine if we are deploying the registry onto the master or onto an external machine for HA

	if [ "${external_docker_registry}" = "" ]; then
		echo
		echo "Setting up docker registry on $(hostname -f)"
		setup_registry
		deleteSecretIfExists myregkey connections
		kubectl create secret docker-registry myregkey -n connections --docker-server=${docker_registry}:5000 --docker-username=admin --docker-password password
	else
		echo
		echo "Setting up docker registry on ${external_docker_registry}"
		echo "not yet implemented.  Exiting"
		exit 1
	fi
fi

# NGINX
if [ "${nginx_reverse_proxy}" != "" ]; then
	echo "Installing Nginx on ${nginx_reverse_proxy}"
	typeset -f install_nginx | sshpass -p ${ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${USER}@${nginx_reverse_proxy} "$(cat); install_nginx \"${YUM}\" ${ic_internal} ${ha_fronting_master} || exit 1"
fi
