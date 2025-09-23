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
	echo "Skipping IBM Cloud private uninstall"
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

set +o errexit
if [ ! -x /usr/bin/docker ]; then
	echo
	echo "Docker is not installed so IBM Cloud private uninstall won't be invoked."
	echo "This scenario is expected if the uninstall has already completed,"
	echo "the uninstall was invoked on a completely clean system,"
	echo "or an attempt is being made to recover from a failed installation."
	echo
else
	echo
	docker info
	if [ $? -ne 0 ]; then
		echo
		echo "Unable to get Docker info.  Is Docker running?"
		service docker restart
		echo "Waiting for Docker to stabilize"
		sleep 30
		docker info
	fi

	if [ ${HOSTNAME} = ${BOOT} ]; then
		echo
		echo "Invoking IBM Cloud private uninstall"
		echo

		if [ "${cfc_ee_url}" != "" ]; then
			docker images | grep "${icp_image_name}" | grep -q ${cfc_image_version}${cfc_image_name_suffix}
			if [ $? -ne 0 ]; then
				echo "Couldn't find ${icp_image_name}:${cfc_image_version}${cfc_image_name_suffix} in local docker registry, attempting to load from local copy"
				if [ ! -f ${INSTALL_DIR}/cluster/images/ibm-cloud-private-x86_64-${cfc_archive_version}.tar.gz ]; then
					echo "Couldn't find local archive, attempting to download"
					download_ICp_EE
					set +o errexit
				fi
				echo
				echo "Loading Cloud private ${CFC_VERSION} EE into Docker"
				gunzip < ${INSTALL_DIR}/cluster/images/ibm-cloud-private-x86_64-${cfc_archive_version}.tar.gz | tar -xO | docker load
				if [ $? -ne 0 ]; then
					echo "Load from local copy failed.  Uninstall will proceed, but will require a reboot."
					mkdir -p ${CONFIG_DIR}
					echo "uninstall.reboot.required=true" >> ${CONFIG_DIR}/${HOSTNAME}
				fi
			fi
			echo
		else
			echo
			echo "Loading Cloud private ${CFC_VERSION} CE Installer into Docker"
			pullFromDocker ${docker_registry}${docker_stream}/${icp_image_name}:${cfc_image_version}
			if [ $? -ne 0 ]; then
				exit 101
			fi
		fi
		set +o errexit

		docker stop installer
		docker kill installer
		docker rm -f installer
		set -o xtrace
		mkdir -p "${cfc_deployment_directory_cwd}"
		cd "${cfc_deployment_directory_cwd}"
		docker run -e LICENSE=accept ${ansible_temp_location_args} ${cfc_debug1} ${docker_prod_args} --name=installer -v "${cfc_deployment_directory_path}" ${docker_registry}${docker_stream}/${icp_image_name}:${cfc_image_version}${cfc_image_name_suffix} uninstall ${cfc_debug2}
		exit_status=$?
		set +o xtrace
		docker stop installer
		docker kill installer
		docker rm -f installer
		echo
		echo "IBM Cloud private uninstall exit code:  ${exit_status}"
		if [ ${exit_status} -ne 0 -a ${exit_status} -ne 127 ]; then
			echo "Informational purposes only - non-0 exit code can be normal"
		fi
		cd ${WORKING_DIR}
	fi

	echo
	docker info
fi

echo
exit 0

