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
DISK_SPACE_MIN=2097152	# Kb
TMP=`mktemp -d ${TMP_TEMPLATE}`

# Preserve the ICp hosts file before the docker pull overwrites it when day to day upgrade
if [ ${upgrade} = true -a ${day_to_day} = true ]; then
	mkdir -p ${CONFIG_DIR}		
	rm -f ${CONFIG_DIR}/hosts
	cp ${CURRENT_DEPLOYED_DIR}/cluster/hosts ${CONFIG_DIR}
fi

mkdir -p ${INSTALL_DIR}/cluster

# Prepare EE image(s)
if [ "${cfc_ee_url}" != "" ]; then
	download_ICp_EE

	echo
	echo "Loading Cloud private ${CFC_VERSION} EE into Docker"
	gunzip < ${INSTALL_DIR}/cluster/images/ibm-cloud-private-x86_64-${cfc_archive_version}.tar.gz | tar -xO | docker load
else
	echo
	echo "Loading Cloud private ${CFC_VERSION} CE Installer into Docker"
	pullFromDocker ${docker_registry}${docker_stream}/${icp_image_name}:${cfc_image_version}
	if [ $? -ne 0 ]; then
		exit 101
	fi
fi
set -o errexit

# Extract installer
echo
cd ${INSTALL_DIR}
compareVersions ${CFC_VERSION} 2.1.0.1
if [ ${comparison_result} = 1 -a "${cfc_ee_url}" != "" ]; then
	# For EE versions prior to 2.1.0.1
	echo "Extracting ibm-cloud-private-installer-${cfc_archive_version}.tar.gz to temporary location ${TMP}"
	if [ ${input_type} == "url" ]; then
		tar -zxvf ${TMP}/ibm-cloud-private-installer-${cfc_archive_version}.tar.gz -C ${TMP}
	elif [ ${input_type} == "local" ]; then
		tar -zxvf ${cfc_ee_url}/ibm-cloud-private-installer-${cfc_archive_version}.tar.gz -C ${TMP}
	else
		echo "Unexpected failure with ibm-cloud-private location"
		exit 3
	fi
	cp -pr ${TMP}/ibm-cloud-private-${cfc_archive_version}/* cluster
else
	# For all CE versions as well as EE starting with 2.1.0.1
	echo "Extracting Cloud Private config from ${icp_image_name}"
	docker run -e LICENSE=accept -v "$(pwd)":/data ${docker_registry}${docker_stream}/${icp_image_name}:${cfc_image_version}${cfc_image_name_suffix} cp -r cluster /data
fi

if [ "${custom_config}" != "" ]; then
	if [ -e ${INSTALL_DIR}/cluster/config.yaml ]; then
		mv ${INSTALL_DIR}/cluster/config.yaml ${INSTALL_DIR}/cluster/config.yaml.${DATE}
	fi
	cp ${custom_config} ${INSTALL_DIR}/cluster/config.yaml
	set +o errexit
	diff ${INSTALL_DIR}/cluster/config.yaml.${DATE} ${INSTALL_DIR}/cluster/config.yaml
	set -o errexit
fi

if [ -e ${INSTALL_DIR}/cluster/ssh_key ]; then
	echo
	echo "Saving ssh_key"
	mv ${INSTALL_DIR}/cluster/ssh_key ${TMP}/ssh_key.${DATE}
fi

if [ ${upgrade} = true ]; then
	echo
	echo "Saving configuration files for upgrade support"
	if [ ${day_to_day} = false ]; then
		upgrade_files=("config.yaml" "ssh_key")
		for i in "${upgrade_files[@]}"
		do
			rm -f ${INSTALL_DIR}/cluster/$i
			cp ${CURRENT_DEPLOYED_DIR}/cluster/$i ${INSTALL_DIR}/cluster
		done
	else
		mv ${TMP}/ssh_key.${DATE} ${INSTALL_DIR}/cluster/ssh_key
	fi
fi
rm -rf ${TMP}

