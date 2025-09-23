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

echo "Starting $0 @ `date` on ${HOSTNAME}" | tee -a ${LOG_FILE}

set +o nounset
if [ ${HOSTNAME} != ${BOOT} ]; then
	if [ "${DEPLOYFCF_OK}" != true ]; then
		echo
		echo "Cannot run $0 in standalone mode to reduce chance"
		echo "of accidental loss of data. Run from boot node."
		exit 2
	fi
fi
if [ "${CFC_EXEC}" = "" ]; then
	echo
	echo "CFC_EXEC must be defined"
	exit 3
fi
if [ "${CFC_ARGS}" = "" ]; then
	CFC_ARGS="$*"
fi
if [ "${CFC_EXPORTS}" = "" ]; then
	CFC_EXPORTS=""
fi
set -o nounset

set +o errexit
echo ${CFC_EXEC} | grep -q /
if [ $? -eq 1 ]; then
	if [ -f "${DEPLOY_CFC_DIR}/${CFC_EXEC}" ]; then
		echo "Assuming ${CFC_EXEC} should be ${DEPLOY_CFC_DIR}/${CFC_EXEC}"
		CFC_EXEC=${DEPLOY_CFC_DIR}/${CFC_EXEC}
	fi
fi
set -o errexit

echo "Remote node exeution starting $0 @ `date` on ${HOSTNAME}" | tee -a ${LOG_FILE}

# Invoke on all non-boot nodes (which would not include nodes co-located with boot)
if [ ${HOSTNAME} = ${BOOT} ]; then
	node_list=""
	for node in ${HOST_LIST}; do
		if [ ${node} != ${HOSTNAME} ]; then
			node_list="${node_list} ${node}"
		fi
	done

	set +o errexit
	for node in ${node_list}; do
		ssh_command ${node} "cd ${DEPLOY_CFC_DIR} && export SEMAPHORE_PREFIX=${DATE} && export DEPLOYFCF_OK=true && export CFC_EXEC=\"${CFC_EXEC}\" && export CFC_ARGS=\"${CFC_ARGS}\" && export CFC_EXPORTS=\"${CFC_EXPORTS}\" && /bin/bash $0 $*" 2>&1 | tee -a ${LOG_FILE}
		if [ $? -ne 0 ]; then
			echo "Error detected, continuing"
			failed=true
		fi
	done
	set -o errexit
fi

echo "Continuing $0 @ `date` on ${HOSTNAME}" | tee -a ${LOG_FILE}
cd ${DEPLOY_CFC_DIR}
echo
${CFC_EXPORTS}
${CFC_EXEC} ${CFC_ARGS} 2>&1 | tee -a ${LOG_FILE}
echo

echo "Ending $0 @ `date` on ${HOSTNAME}" | tee -a ${LOG_FILE}

exit 0

