#! /bin/bash
# Initial author: on Thu Jun 22 07:25:52 EDT 2017
#
# History:
# --------
# Thu Jun 22 07:25:52 EDT 2017
#	Initial version
#
#

. `dirname $0`/00-all-config.sh

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

script_list="
	A-03-all-validation.sh
	A-04-all-dns-check.sh
	A-04-all-network-check.sh
	A-06-boot-copy.sh
	A-06-boot-timecheck.sh
"

cd ${DEPLOY_CFC_DIR}

# Ensure from this point forward the script is running as root
if [ "`id -u`" != 0 ]; then
	echo
	echo "${DEPLOY_CFC_DIR}/validateDeployment.sh was run as non-root, re-running as root using sudo"
	exec sudo ${DEPLOY_CFC_DIR}/validateDeployment.sh $*
fi

for script in ${script_list}; do
	bash ${script} $* 2>&1 | tee -a ${LOG_FILE}
done

# XYZZY - Refactor A-02 and add validation here
if [ ${HOSTNAME} = ${BOOT} ]; then
	if [ ${skip_ssh_key_validation} = false ]; then
		echo
		validateSSHKeys ${HOST_LIST} 2>&1 | tee -a ${LOG_FILE}
		if [ $? -ne 0 ]; then
			echo "FAILED"
			exit 111
		fi
	else
		echo
		echo "Skipping SSH key validation"
	fi

	echo
	echo "Validating remote execution"
	for host in ${HOST_LIST}; do
		if [ ${host} != ${BOOT} ]; then
			ssh_command ${host} "echo Success" 2>&1 | tee -a ${LOG_FILE}
		fi
	done

	echo
	for host in ${HOST_LIST}; do
		if [ ${host} != ${BOOT} ]; then
			ssh_command ${host} "cd ${DEPLOY_CFC_DIR} && /bin/bash validateDeployment.sh $*" 2>&1 | tee -a ${LOG_FILE}
		fi
	done

	echo
	echo "Deployment validation - OK"
fi

