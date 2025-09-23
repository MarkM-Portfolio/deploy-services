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

MAX_TIME_DEVIATION=55		# seconds

# Time sync check
echo
echo "Checking node times are in sync within ${MAX_TIME_DEVIATION}s"

echo
all_nodes_synced=true
for node in ${HOST_LIST}; do
	if [ ${node} != ${HOSTNAME} ]; then
		printf "Checking ${node} - "
		boot_time=`date +%Y%m%d%H%M%S`
		node_time=`ssh_command ${node} date +%Y%m%d%H%M%S`
		if [ ${boot_time} -ge ${node_time} ]; then
			time_difference=`echo ${boot_time} - ${node_time} | bc`
		else
			time_difference=`echo ${node_time} - ${boot_time} | bc`
		fi
		printf "${time_difference}s - "
		if [ ${time_difference} -le ${MAX_TIME_DEVIATION} ]; then
			echo "OK"
		else
			echo "FAILED (boot: ${boot_time}, node: ${node_time})"
			all_nodes_synced=false
		fi
	fi
done

echo
if [ ${all_nodes_synced} = false ]; then
	echo "Node times not in sync - FAILED"
	exit 1
else
	echo "All nodes within ${MAX_TIME_DEVIATION}s - OK"
fi

