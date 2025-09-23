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

# XYZZY:  This script is obsolete once we stop support for ICp 1.2.1

mkdir -p ${CONFIG_DIR}
touch ${CONFIG_DIR}/${HOSTNAME}

# Restore firewall status
if [ ${skip_disable_firewall} = true ]; then
	echo "Firewall configuration was not changed"
else
	# Restore Firewall status
	docker_restart=false
	if [ ! -f ${CONFIG_DIR}/${HOSTNAME} ]; then
		echo "Firewall configuration file not found"
	else
		echo "Reading firewall configuration file: ${CONFIG_DIR}/${HOSTNAME}"
		for firewall in ${FIREWALL_PACKAGES}; do
			if grep -q ${firewall}.enabled=true ${CONFIG_DIR}/${HOSTNAME}; then
				echo "Re-enabling ${firewall}"
				systemctl enable ${firewall}
				docker_restart=true
			fi
			if grep -q ${firewall}.active=true ${CONFIG_DIR}/${HOSTNAME}; then
				echo "Re-activating ${firewall}"
				systemctl start ${firewall}
				docker_restart=true
			fi
		done
	fi
	if [ ${docker_restart} = true ]; then
		echo "Restarting Docker after firewall configuration restored"
		systemctl restart docker
		verifyOperationalServer
	fi
fi

compareVersions ${CFC_VERSION} 1.2.1
if [ ${comparison_result} = 0 ]; then	# CFC_VERSION = 1.2.1
	if [ ${upgrade} = true ]; then
		if ${is_boot}; then		
			# Restart statefulset pods after ICp upgrade - ICp issue #4409 (Fixed in 2.1.0.2)
			statefulset_components="mongodb zookeeper solr redis"
			for component in ${statefulset_components}; do
				set +o errexit
				installed=$(helm list -q ${component})
				if [ $? -ne 0 ]; then
					number_retries=24
					retry_wait_time=5
					counter=1
					while [ ${counter} -le ${number_retries} ]; do # Retry required due to Helm issue: https://github.com/kubernetes/helm/issues/2409
						installed=$(helm list -q ${component})
						if [ $? -ne 0 ]; then
							echo "Helm check for ${component} failed, retrying in ${retry_wait_time}s. Attempt: (${counter}/${number_retries})"
							sleep ${retry_wait_time}
							if [ ${counter} -eq ${number_retries} ]; then
								echo "Max number of retries reached. Please check Helm is healthy"
								exit 1
							fi
							counter=`expr ${counter} + 1`
						else
							break
						fi
					done
				fi
				if [[ ${installed} ]]; then
					if [[ ${component} == "mongodb" ]]; then
						kubectl delete pods mongo-0 mongo-1 mongo-2 -n ${NAMESPACE}
					elif [[ ${component} == "redis" ]]; then
						kubectl delete pods redis-server-0 redis-server-1 redis-server-2 -n ${NAMESPACE}
						kubectl delete pods -n ${NAMESPACE} `kubectl get pods -n ${NAMESPACE} | grep redis-sentinel | awk '{print $1}' | tr '\n' ' '`
					else
						kubectl delete pods ${component}-0 ${component}-1 ${component}-2 -n ${NAMESPACE}
					fi
				fi
				set -o errexit
			done
		fi
		# Update version file upon upgrade for ICp 1.2.1 - ICp issue #1956
		echo ${CFC_VERSION} > /opt/ibm/cfc/version
	fi
fi

