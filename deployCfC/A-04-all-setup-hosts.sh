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

FILE=/etc/hosts

echo
if [ ! -f ${FILE}.${DATE} ]; then
	echo "Creating backup ${FILE}.${DATE}"
	cp -p ${FILE} ${FILE}.${DATE}
fi
found_me=false
set +o errexit
for host in ${HOST_LIST}; do
	echo ${HOSTNAME} | grep -q "^${host}$"
	if [ $? -eq 0 ]; then
		found_me=true
	fi
	resolve_ip ${host}	# result in resolve_ip_return_result
	if [ $? -ne 0 ]; then
		echo "Unable to resolve ${host}"
		exit 2
	else
		ip=${resolve_ip_return_result}
	fi
	short_host=`echo ${host} | awk -F. '{ print $1 }'`
	hosts_line="${ip}	${host} ${short_host}"
	grep -q "^${ip}[ 	]*${host}" ${FILE}
	if [ $? -eq 1 ]; then
		if [ ${skip_hosts_modification} = false ]; then
			echo "${hosts_line}" >> ${FILE}
		else
			echo "--skip_hosts_modification set but can't find ${host} in ${FILE}"
			exit 9
		fi
	else
		if [ ${skip_hosts_modification} = false ]; then
			sed -i "/^${ip}.*master.cfc$/b; s/^${ip}[ 	].*/${hosts_line}/" ${FILE}
		fi
	fi
done
set -o errexit

# non-colocated boot needs master setup in /etc/hosts
if [ ${is_boot} = true -a ${is_master} = false -a ${is_worker} = false -a ${is_proxy} = false ]; then
	echo "Setting up master.cfc in /etc/hosts for non-colocated boot node"
	if [ ${is_master_HA} = true ]; then
		master_ip=${master_HA_vip}
	else
		resolve_ip ${MASTER_LIST}	# result in resolve_ip_return_result
		if [ $? -ne 0 ]; then
			echo "Unable to resolve ${host}"
			exit 3
		else
			master_ip=${resolve_ip_return_result}
		fi
	fi
	set -o errexit

	if [ "`grep -v '^#' ${FILE} | grep master.cfc | grep -v ${master_ip}`" != "" ]; then
		echo "Found master.cfc in ${FILE} which is not associated with ${master_ip} - unexpected error.  Correct and restart deployment."
		exit 1
	fi

	echo "${master_ip}	master.cfc" >> ${FILE}
fi

echo
echo "Checking changes on ${FILE}"
set +o errexit
diff ${FILE}.${DATE} ${FILE}
set -o errexit

if [ ${found_me} = false ]; then
	echo
	echo "Couldn't find me in list - should not happen"
	exit 1
fi

echo
echo "Hosts setup complete"
exit 0

