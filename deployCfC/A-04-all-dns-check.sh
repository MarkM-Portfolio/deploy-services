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

MAX_DNS_LATENCY=10000	# miliseconds

echo
echo "Checking DNS latency"
device_list=`nmcli -t connection show --active | awk -F: '{ print $NF }'`
set +o errexit
dns_server_list=`
	for device in ${device_list}; do
		nmcli -t device show ${device} | grep IP4.DNS | awk -F: '{ print $2 }'
	done | sort -u`
set -o errexit

for dns_server in ${dns_server_list}; do
	start_time=`python -c 'import time; print int(round(time.time() * 1000))'`
	set +o errexit
	dig @${dns_server} -t A raw.githubusercontent.com > /dev/null
	if [ $? -ne 0 ]; then
		echo "Error resolving with DNS server ${dns_server}"
	fi
	set -o errexit
	end_time=`python -c 'import time; print int(round(time.time() * 1000))'`
	dns_latency=`expr ${end_time} - ${start_time}`
	if [ ${dns_latency} -le ${MAX_DNS_LATENCY} ]; then
		echo "DNS latency with server ${dns_server} is ${dns_latency}ms (maximum: ${MAX_DNS_LATENCY}ms) - OK"
	else
		echo "DNS latency with server ${dns_server} is ${dns_latency}ms (maximum: ${MAX_DNS_LATENCY}ms) - FAILED"
	fi
done

echo
echo "DNS latency checks complete"
exit 0

