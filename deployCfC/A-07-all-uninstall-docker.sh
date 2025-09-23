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

echo
if [ ${upgrade} = true -o "${uninstall}" = "" ]; then
	echo "Skipping Docker uninstall"
	exit 0
fi

# Configure external proxy if using one
echo
if [ "${ext_proxy_url}" != "" ]; then
	echo "Configuring external proxy ${ext_proxy_url}"
	export http_proxy=${ext_proxy_url}
	export https_proxy=${ext_proxy_url}
	export ftp_proxy=${ext_proxy_url}
	export no_proxy=localhost,127.0.0.1
	for host in ${HOST_LIST[@]}; do
		export no_proxy=$no_proxy,$host
	done
fi

# Uninstall steps may not work and should not be considered a failure
set +o errexit

if [ -x /usr/bin/docker ]; then
	echo
	docker ps
fi
echo
service docker stop

echo
echo "Removing Docker RPMs"
${YUM} -y remove ${YUM_UNINSTALL_DOCKER_OVERRIDE_FLAGS} docker* container-selinux
if [ $? -ne 0 ]; then
	echo "Failure removing Docker"
fi

if [ ${skip_docker_deployment} = true ]; then
	echo "Not removing any Docker repos"
else
	docker_distribution=ce
	if [ "${use_docker_ee}" != "" ]; then
		docker_distribution=ee
		if [ -f ${LOG_FILE}-rhel_distributor.txt ]; then
			rhel_distributor=`cat ${LOG_FILE}-rhel_distributor.txt`
			if [ ${rhel_distributor} = RedHatEnterpriseServer ]; then
				if [ -f ${LOG_FILE}-rhel_major_ver.txt ]; then
					rhel_major_version=`cat ${LOG_FILE}-rhel_major_ver.txt`
					yum-config-manager --disable rhel-${rhel_major_version}-server-extras-rpms
				else
					echo "${LOG_FILE}-rhel_major_ver.txt was not found."
				fi
				echo "Deleting the file /etc/yum/vars/dockerosversion"
				rm -f /etc/yum/vars/dockerosversion
			fi
		else
			echo "${LOG_FILE}-rhel_distributor.txt was not found."
		fi
		echo "Deleting the file /etc/yum/vars/dockerurl"
		rm -f /etc/yum/vars/dockerurl
	fi
	echo "Deleting the Docker repo file: /etc/yum.repos.d/docker-${docker_distribution}.repo"
	rm -f /etc/yum.repos.d/docker-${docker_distribution}.repo
	yum makecache fast
	if [ "${docker_storage_block_device}" != "" ]; then
		echo
		reboot_required=false
		echo "Cleaning up Docker storage block device ${docker_storage_block_device}"
		lvremove -f docker
		vgremove -f docker
		pvremove -f ${docker_storage_block_device}
		if [ $? -ne 0 ]; then
			reboot_required=true
		fi
		rm -f /etc/lvm/profile/docker-thinpool.profile
		rm -f ${DOCKER_CONFIG_DIR}/${DOCKER_CONFIG_FILE}
		if [ ${reboot_required} = true ]; then
			echo "*** WARNING:  reboot required on ${HOSTNAME} to complete uninstall"
			mkdir -p ${CONFIG_DIR}
			echo "uninstall.reboot.required=true" >> ${CONFIG_DIR}/${HOSTNAME}
		fi
	fi
fi

exit 0


