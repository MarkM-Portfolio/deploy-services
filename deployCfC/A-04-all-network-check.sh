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
TMP=`mktemp ${TMP_TEMPLATE}`

echo
echo "Checking network connectivity across all nodes"

for node in ${HOST_LIST}; do
	if [ ${HOSTNAME} = ${node} ]; then
		echo "Skipping self"
	else
		printf "Checking connectivity with ${node} - "
		check_port ${node} 22 false 3 5 5 > ${TMP} 2>&1
		grep -q '^SSH-' ${TMP}
		if [ $? -ne 0 ]; then
			echo "FAILED"
			echo
			echo "Connectivity check logs:"
			grep -v '^	OK' ${TMP}
			echo
			echo "Fix network connectivity and restart"
			exit 1
		else
			echo "OK"
			grep -v '^	OK' ${TMP} >> ${LOG_FILE}
		fi
		set -o errexit
	fi
done

echo
echo "Network connectivity checks complete"
exit 0

