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
for host in ${HOST_LIST}; do
	echo
	echo
	echo "Preparing ${host}"
	if [ ${HOSTNAME} = ${host} ]; then
		echo "Skipping myself..."
		continue
	fi
	echo
	if [ ! -f ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}/id_rsa -a "${uninstall}" != "" ]; then
		echo "
-------------------
The environment for IBM Cloud private is incomplete.
This scenario is expected if the uninstall has already completed,
the uninstall was invoked on a completely clean system,
or an attempt is being made to recover from a failed installation.

The uninstall can still proceed, but if you did not specify the
optional password flag, you may be prompted for the password for
the \"${user}\" user on all of the nodes, sometimes several times.
-------------------
"
	fi

	scp_command ${DEPLOY_CFC_DIR} ${host}:${WORKING_DIR}
	ssh_command ${host} "rm -rf ${DEPLOY_CFC_DIR}"
	scp_command ${DEPLOY_CFC_DIR} ${host}:${WORKING_DIR}
done

