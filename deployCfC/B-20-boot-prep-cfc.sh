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

function generateHosts() {
	set +o nounset
	if [ "$3" = "" ]; then
		echo "usage:  generateHosts sHostsFileLocation sType sHost1 ... [sHostN]"
		exit 1
	fi
	set -o nounset
	hosts_file=$1
	type=$2
	shift
	shift

	echo "[${type}]" >> ${hosts_file}
	for node in $*; do
		resolve_ip ${node}	# result in resolve_ip_return_result
		if [ $? -ne 0 ]; then
			echo "Unable to resolve ${node}"
			exit 2
		else
			ip=${resolve_ip_return_result}
		fi
		set -o errexit
		echo ${ip} >> ${hosts_file}
	done
	echo >> ${hosts_file}
}

cd ${WORKING_DIR}

# Cleanup potentially bad cert (issue #6399)
echo
echo "Removing master cert"
rm -f /etc/docker/certs.d/master.cfc:8500/ca.crt

# Generate topology
if [ -f ${INSTALL_DIR}/cluster/hosts ]; then
	echo "Creating backup of ${INSTALL_DIR}/cluster/hosts"
	mv ${INSTALL_DIR}/cluster/hosts ${INSTALL_DIR}/cluster/hosts.${DATE}
fi

echo "Generating new topology"
generateHosts ${INSTALL_DIR}/cluster/hosts master ${MASTER_LIST}
generateHosts ${INSTALL_DIR}/cluster/hosts worker ${WORKER_LIST}
generateHosts ${INSTALL_DIR}/cluster/hosts proxy ${PROXY_LIST}
compareVersions ${CFC_VERSION} 2.1.0.1
if [ ${comparison_result} = 2 -o ${comparison_result} = 0 ]; then
	# CFC_VERSION >= 2.1.0.1
	generateHosts ${INSTALL_DIR}/cluster/hosts management ${MASTER_LIST}
fi

echo
cat ${INSTALL_DIR}/cluster/hosts

if [ ${upgrade} = true ]; then
	topology_defnition_checklist=""
	if [ "${CURRENT_DEPLOYED_DIR}" != "${INSTALL_DIR}" ]; then
		topology_defnition_checklist="${INSTALL_DIR}/cluster/hosts"
	fi
	if [ -f ${INSTALL_DIR}/cluster/hosts.${DATE} -a ${day_to_day} = true ]; then
		topology_defnition_checklist="${topology_defnition_checklist} ${CONFIG_DIR}/hosts"
	fi
	set +o errexit
	for topology_defnition in ${topology_defnition_checklist}; do
		diff <(sort ${CURRENT_DEPLOYED_DIR}/cluster/hosts) <(sort ${topology_defnition}) &> /dev/null
		if [ $? -ne 0 ]; then
			# XYZZY:  for 2.1.0.1, management node is added so
			# take that into account when implementing upgrades
			echo "The upgrade detected a topology change as compared to the existing deplyment."
			echo "Topology changes must take place either before or after the upgrade."
			echo "For the upgrade to complete, please ensure that the hostnames used match the ones in your existing deployment."
			echo
			echo "Topology definitions for existing deployment:"
			echo
			cat ${topology_defnition}
			echo
			echo "Topology definitions for upgrade deployment:"
			echo
			cat ${INSTALL_DIR}/cluster/hosts
			echo
			exit 200
		fi
	done
	set -o errexit
	echo "No topology changes detected - proceeding with upgrade"
	if [ ${day_to_day} = true ]; then
		rm -f ${CONFIG_DIR}/hosts
	fi
fi

echo
FILE=${INSTALL_DIR}/cluster/config.yaml
echo
if [ ! -f ${FILE}.${DATE} ]; then
	echo "Creating backup ${FILE}.${DATE}"
	cp -p ${FILE} ${FILE}.${DATE}
fi

set +o errexit
grep -q '^calico_ipip_enabled:[ 	]*true' ${FILE}
if [ $? -eq 0 ]; then
	echo "calico ipip already enabled"
else
	grep -q '^calico_ipip_enabled:' ${FILE}
	if [ $? -eq 1 ]; then
		echo "Enabling calico ipip"
		echo "calico_ipip_enabled: true" >> ${FILE}
	else
		grep -q '^calico_ipip_enabled:[ 	]*false' ${FILE}
		if [ $? -eq 0 ]; then
			echo "Changing calico ip to enabled"
			sed -i 's/^calico_ipip_enabled:.*/calico_ipip_enabled: true/' ${FILE}
			if [ $? -ne 0 ]; then
				echo "Failed enabling calico ipip"
				exit 7
			fi
		fi
	fi
fi

echo
echo "Checking changes on ${FILE}"
diff ${FILE}.${DATE} ${FILE}

set -o errexit
if ${is_master_HA}; then
	echo
	FILE=${INSTALL_DIR}/cluster/config.yaml
	echo
	if [ ! -f ${FILE}.${DATE} ]; then
		echo "Creating backup ${FILE}.${DATE}"
		cp -p ${FILE} ${FILE}.${DATE}
	fi

	set +o errexit
	grep -q "^vip_iface:[ 	]*${master_HA_iface}" ${FILE}
	if [ $? -eq 0 ]; then
		echo "master node high availability interface already set"
	else
		grep -q '^vip_iface:' ${FILE}
		if [ $? -eq 1 ]; then
			echo "Setting master node high availability interface to ${master_HA_iface}"
			echo "vip_iface: ${master_HA_iface}" >> ${FILE}
		else
			echo "Changing master node high availability interface to ${master_HA_iface}"
			sed -i "s/^vip_iface:.*/vip_iface: ${master_HA_iface}/" ${FILE}
			if [ $? -ne 0 ]; then
				echo "Failed changing master node high availability interface to ${master_HA_iface} in ${FILE}"
				exit 8
			fi
		fi
	fi

	grep -q "^cluster_vip:[ 	]*${master_HA_vip}" ${FILE}
	if [ $? -eq 0 ]; then
		echo "master node high availability VIP already set"
	else
		grep -q '^cluster_vip:' ${FILE}
		if [ $? -eq 1 ]; then
			echo "Setting master node high availability VIP to ${master_HA_vip}"
			echo "cluster_vip: ${master_HA_vip}" >> ${FILE}
		else
			echo "Changing master node high availability VIP to ${master_HA_vip}"
			sed -i "s/^cluster_vip:.*/cluster_vip: ${master_HA_vip}/" ${FILE}
			if [ $? -ne 0 ]; then
				echo "Failed changing master node high availability VIP to ${master_HA_vip} in ${FILE}"
				exit 9
			fi
		fi
	fi

	echo
	echo "Checking changes on ${FILE}"
	diff ${FILE}.${DATE} ${FILE}
fi

set -o errexit
if ${is_proxy_HA}; then
	echo
	FILE=${INSTALL_DIR}/cluster/config.yaml
	echo
	if [ ! -f ${FILE}.${DATE} ]; then
		echo "Creating backup ${FILE}.${DATE}"
		cp -p ${FILE} ${FILE}.${DATE}
	fi

	set +o errexit
	grep -q "^proxy_vip_iface:[ 	]*${proxy_HA_iface}" ${FILE}
	if [ $? -eq 0 ]; then
		echo "proxy HA interface already set"
	else
		grep -q '^proxy_vip_iface:' ${FILE}
		if [ $? -eq 1 ]; then
			echo "Setting proxy HA interface to ${proxy_HA_iface}"
			echo "proxy_vip_iface: ${proxy_HA_iface}" >> ${FILE}
		else
			echo "Changing proxy HA interface to ${proxy_HA_iface}"
			sed -i "s/^proxy_vip_iface:.*/proxy_vip_iface: ${proxy_HA_iface}/" ${FILE}
			if [ $? -ne 0 ]; then
				echo "Failed changing proxy HA interface to ${proxy_HA_iface} in ${FILE}"
				exit 10
			fi
		fi
	fi

	grep -q "^proxy_vip:[ 	]*${proxy_HA_vip}" ${FILE}
	if [ $? -eq 0 ]; then
		echo "proxy HA VIP already set"
	else
		grep -q '^proxy_vip:' ${FILE}
		if [ $? -eq 1 ]; then
			echo "Setting proxy HA VIP to ${proxy_HA_vip}"
			echo "proxy_vip: ${proxy_HA_vip}" >> ${FILE}
		else
			echo "Changing proxy HA VIP to ${proxy_HA_vip}"
			sed -i "s/^proxy_vip:.*/proxy_vip: ${proxy_HA_vip}/" ${FILE}
			if [ $? -ne 0 ]; then
				echo "Failed changing proxy HA VIP to ${proxy_HA_vip} in ${FILE}"
				exit 11
			fi
		fi
	fi

	echo
	echo "Checking changes on ${FILE}"
	diff ${FILE}.${DATE} ${FILE}
fi

set -o errexit
if [ "${non_root_user}" != "" ]; then
	echo
	FILE=${INSTALL_DIR}/cluster/config.yaml
	echo
	if [ ! -f ${FILE}.${DATE} ]; then
		echo "Creating backup ${FILE}.${DATE}"
		cp -p ${FILE} ${FILE}.${DATE}
	fi

	set +o errexit
	grep -q "^ansible_user:[ 	]*${non_root_user}" ${FILE}
	if [ $? -eq 0 ]; then
		echo "non-root user already set"
	else
		grep -q '^ansible_user:' ${FILE}
		if [ $? -eq 1 ]; then
			echo "Setting non-root user to ${non_root_user}"
			echo "ansible_user: ${non_root_user}" >> ${FILE}
		else
			echo "Changing non-root user to ${non_root_user}"
			sed -i "s/^ansible_user:.*/ansible_user: ${non_root_user}/" ${FILE}
			if [ $? -ne 0 ]; then
				echo "Failed configuring non-root user to ${non_root_user} in ${FILE}"
				exit 12
			fi
		fi
	fi

	grep -q "^ansible_become:[ 	]*true" ${FILE}
	if [ $? -eq 0 ]; then
		echo "non-root sudo already set"
	else
		grep -q '^ansible_become:' ${FILE}
		if [ $? -eq 1 ]; then
			echo "Setting non-root sudo to true"
			echo "ansible_become: true" >> ${FILE}
		else
			echo "Changing non-root sudo to true"
			sed -i "s/^ansible_become:.*/ansible_become: true/" ${FILE}
			if [ $? -ne 0 ]; then
				echo "Failed configuring non-root sudo to true in ${FILE}"
				exit 13
			fi
		fi
	fi

	grep -q "^ansible_become_password:[ 	]*${non_root_passwd}" ${FILE}
	if [ $? -eq 0 ]; then
		echo "non-root sudo password already set"
	else
		grep -q '^ansible_become_password:' ${FILE}
		if [ $? -eq 1 ]; then
			echo "Setting non-root sudo password"
			echo "ansible_become_password: ${non_root_passwd}" >> ${FILE}
		else
			echo "Changing non-root sudo password"
			sed -i "s/^ansible_become_password:.*/ansible_become_password: ${non_root_passwd}/" ${FILE}
			if [ $? -ne 0 ]; then
				echo "Failed configuring non-root sudo password in ${FILE}"
				exit 14
			fi
		fi
	fi	

	echo
	echo "Checking changes on ${FILE}"
	diff ${FILE}.${DATE} ${FILE} | sed 's/ansible_become_password: .*/ansible_become_password: ***/'
fi

set -o errexit
compareVersions ${CFC_VERSION} 2.1.0.1
if [ ${comparison_result} = 1 ]; then
	# CFC_VERSION < 2.1.0.1

	FILE=${INSTALL_DIR}/cluster/config.yaml
	echo
	if [ ! -f ${FILE}.${DATE} ]; then
		echo "Creating backup ${FILE}.${DATE}"
		cp -p ${FILE} ${FILE}.${DATE}
	fi

	set +o errexit

	# CE Workaround for ICp issue #4304
	if [ "${cfc_ee_url}" = "" ]; then
		echo "Using indices-cleaner:0.2a"
		sed -i -e 's@ibmcom/indices-cleaner:0.2.*@ibmcom/indices-cleaner:0.2a"@g' ${FILE}
		sed -i -e '/indices-cleaner:0.2a/s/# //g' ${FILE}
	fi

	# XYZZY:  Below code was only applicable for CfC 1.1.0 -> ICp 1.2.x upgrade. Needs to be updated when we support ICp 1.2.1 -> 2.1.0.1 upgrade.
#	if [ ${upgrade} = true ]; then
#		echo "Reconfigure config.yaml for upgrade"
#		# Remove the line that contains the mesos_enabled parameter
#		sed -ri 's/mesos_enabled/# mesos_enabled/g' ${INSTALL_DIR}/cluster/config.yaml
#		# Remove the line that contains the network_type parameter
#		sed -ri 's/network_type/# network_type/g' ${INSTALL_DIR}/cluster/config.yaml
#		# Remove all docker images from the file
#		sed -i -e '/_image/s/^\([^#]\)/#/' ${INSTALL_DIR}/cluster/config.yaml
#	else
#		echo "Not in upgrade mode so no changes needed in config.yaml"
#	fi

	echo
	echo "Checking changes on ${FILE}"
	diff ${FILE}.${DATE} ${FILE} | sed 's/ansible_become_password: .*/ansible_become_password: ***/'
else
	# CFC_VERSION >= 2.1.0.1

	FILE=${INSTALL_DIR}/cluster/config.yaml
	echo
	if [ ! -f ${FILE}.${DATE} ]; then
		echo "Creating backup ${FILE}.${DATE}"
		cp -p ${FILE} ${FILE}.${DATE}
	fi

	set +o errexit
	grep -q "^cluster_CA_domain:[ 	]*master.cfc" ${FILE}
	if [ $? -eq 0 ]; then
		echo "cluster name already set to master.cfc"
	else
		grep -q '^cluster_CA_domain:' ${FILE}
		if [ $? -eq 1 ]; then
			echo "Setting cluster name to master.cfc"
			echo "cluster_CA_domain: master.cfc" >> ${FILE}
		else
			echo "Changing cluster name to master.cfc"
			sed -i "s/^cluster_CA_domain:.*/cluster_CA_domain: master.cfc/" ${FILE}
			if [ $? -ne 0 ]; then
				echo "Failed changing cluster name to master.cfc"
				exit 9
			fi
		fi
	fi

	grep -q "^kibana_install:[ 	]*true" ${FILE}
	if [ $? -eq 0 ]; then
		echo "kibana_install already set to true"
	else
		grep -q '^kibana_install:' ${FILE}
		if [ $? -eq 1 ]; then
			echo "Setting kibana_install to true"
			echo "kibana_install: true" >> ${FILE}
		else
			echo "Changing kibana_install to true"
			sed -i "s/^kibana_install:.*/kibana_install: true/" ${FILE}
			if [ $? -ne 0 ]; then
				echo "Failed changing kibana_install to true"
				exit 9
			fi
		fi
	fi

	grep -q "^firewall_enabled:[ 	]*true" ${FILE}
	if [ $? -eq 0 ]; then
		echo "firewall_enabled already set to true"
	else
		grep -q '^firewall_enabled:' ${FILE}
		if [ $? -eq 1 ]; then
			echo "Setting firewall_enabled to true"
			echo "firewall_enabled: true" >> ${FILE}
		else
			echo "Changing firewall_enabled to true"
			sed -i "s/^firewall_enabled:.*/firewall_enabled: true/" ${FILE}
			if [ $? -ne 0 ]; then
				echo "Failed changing firewall_enabled to true"
				exit 9
			fi
		fi
	fi

	if [ ${enable_management_node} = true ]; then
		echo "Enabling management node for metering and monitoring"
		sed -i "s/^disabled_management_services:/# disabled_management_services:/" ${FILE}
	else
		grep -q "^disabled_management_services:[ 	]*\[\"metering\", \"monitoring\", \"va\"\]" ${FILE}
		if [ $? -eq 0 ]; then
			echo "disabled_management_services already set to [\"metering\", \"monitoring\", \"va\"]"
		else
			grep -q '^disabled_management_services:' ${FILE}
			if [ $? -eq 1 ]; then
				echo "Setting disabled_management_services to [\"metering\", \"monitoring\", \"va\"]"
				echo "disabled_management_services: [\"metering\", \"monitoring\", \"va\"]" >> ${FILE}
			else
				echo "Changing disabled_management_services to [\"metering\", \"monitoring\", \"va\"]"
				sed -i "s/^disabled_management_services:.*/disabled_management_services: \[\"metering\", \"monitoring\", \"va\"\]/" ${FILE}
				if [ $? -ne 0 ]; then
					echo "Failed changing disabled_management_services to [\"metering\", \"monitoring\", \"va\"]"
					exit 9
				fi
			fi
		fi
	fi

	echo
	echo "Checking changes on ${FILE}"
	diff ${FILE}.${DATE} ${FILE} | sed 's/ansible_become_password: .*/ansible_become_password: ***/'
fi

set -o errexit
compareVersions ${CFC_VERSION} 2.1.0.1
if [ ${comparison_result} = 2 -o ${comparison_result} = 0 ]; then
	# CFC_VERSION >= 2.1.0.1
	FILE=${INSTALL_DIR}/cluster/config.yaml
	echo
	if [ ! -f ${FILE}.${DATE} ]; then
		echo "Creating backup ${FILE}.${DATE}"
		cp -p ${FILE} ${FILE}.${DATE}
	fi

	if [ "${temporary_file_location}" = "" ]; then
		echo "Disabling temporary file location"
		sed -i "s/^offline_pkg_copy_path:/# offline_pkg_copy_path:/" ${FILE}
	else
		echo "Configuring deployment for temporary file location:  ${temporary_file_location}"
		set +o errexit
		grep -q "^offline_pkg_copy_path:[ 	]*${temporary_file_location}" ${FILE}
		if [ $? -eq 0 ]; then
			echo "Temporary file location already set to ${temporary_file_location}"
		else
			grep -q '^offline_pkg_copy_path:' ${FILE}
			if [ $? -eq 1 ]; then
				echo "Setting temporary file location to ${temporary_file_location}"
				echo "offline_pkg_copy_path: ${temporary_file_location}" >> ${FILE}
			else
				echo "Changing temporary file location ${temporary_file_location}"
				sed -i "s/^offline_pkg_copy_path:.*/offline_pkg_copy_path: ${temporary_file_location}/" ${FILE}
				if [ $? -ne 0 ]; then
					echo "Failed changing temporary file location to ${temporary_file_location}"
					exit 9
				fi
			fi
		fi
	fi

	set +o errexit
	echo
	echo "Checking changes on ${FILE}"
	diff ${FILE}.${DATE} ${FILE} | sed 's/ansible_become_password: .*/ansible_become_password: ***/'
fi

set -o errexit
if [ -f ${INSTALL_DIR}/cluster/ssh_key ]; then
	echo
	echo "Creating backup of ${INSTALL_DIR}/cluster/ssh_key"
	mv ${INSTALL_DIR}/cluster/ssh_key ${INSTALL_DIR}/cluster/ssh_key.${DATE}
fi
cp ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}/id_rsa ${INSTALL_DIR}/cluster/ssh_key
chmod 400 ${INSTALL_DIR}/cluster/ssh_key

mkdir -p ${CONFIG_DIR}
echo "icp.install.directory=${INSTALL_DIR}" >> ${CONFIG_DIR}/${HOSTNAME}

