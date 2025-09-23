#! /bin/bash
# Initial author: on Sun Feb  5 15:26:49 GMT 2017
#
# History:
# --------
# Sun Feb  5 15:26:49 GMT 2017
#	Initial version
#
#

PATH=/usr/bin:/bin:/usr/sbin:/sbin:${PATH}
export PATH
umask 022

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

PRG=`basename ${0}`
DATE=`date +%Y%m%d%H%M%S`
TMP_TEMPLATE=/tmp/${PRG}.${DATE}.${RANDOM}.XXXXXX.$$
TMP=`mktemp -u ${TMP_TEMPLATE}`

retries_default=60
wait_interval_default=10

function usage () {
	echo "usage:  ${PRG} [--help] [--retries=${retries_default}] [--wait_interval=${wait_interval_default}] [--namespace=<namespace>]"
	echo
	echo "	Defaults for retries (in seconds) and wait interval shown above"
	echo "	If no namespace provided, default is all namespaces"
	echo
}


# return is in is_number
# returns true if whole number, false for other
function isNum () {
	set -o errexit
	set -o pipefail
	set -o nounset

	set +o nounset
	if [ "$1" = "" ]; then
		echo "usage:  isNum nWholeNumber"
		return 100
	fi
	set -o nounset

	if [ "`echo ${1} | sed -e 's/#/@/g' -e 's/^-//' -e 's/[0-9]/#/g' -e 's/#//g'`" = "" ]; then
		is_number=true
	else
		is_number=false
	fi
}


set +o nounset
if [ "$1" = "--help" ]; then
	usage
	exit 1
fi
set -o nounset

retries=${retries_default}
wait_interval=${wait_interval_default}
namespace="--all-namespaces=true"
name_column=2
ready_column=3

set +o errexit
for arg in $*; do
	found_match=false
	echo ${arg} | grep -q '^--retries='
	if [ $? -eq 0 ]; then
		retries=`echo ${arg} | awk -F= '{ print $2 }'`
		found_match=true
	fi
	echo ${arg} | grep -q '^--wait_interval='
	if [ $? -eq 0 ]; then
		wait_interval=`echo ${arg} | awk -F= '{ print $2 }'`
		found_match=true
	fi
	echo ${arg} | grep -q '^--namespace='
	if [ $? -eq 0 ]; then
		namespace=`echo ${arg} | awk -F= '{ print $2 }'`
		namespace="--namespace ${namespace}"
		name_column=1
		ready_column=2
		found_match=true
	fi

	if [ ${found_match} = false ]; then
		usage
		exit 2
	fi

	shift
done

counter=0
while true; do
	echo
	echo
	echo "Checking pods"
	echo

	pods_healthy=true

	kubectl ${namespace} get pods > ${TMP}.1

	# Check obviously unhealthy pods
	grep -v 'Running\|Completed' ${TMP}.1 > ${TMP}.2
	if [ `wc -l < ${TMP}.2` -ne 1 ]; then
		pods_healthy=false
		cat ${TMP}.2
	fi

	# Check pods which might be healthy but unsure
	echo ${pods_healthy} > ${TMP}.3
	grep ' Running ' ${TMP}.1 | while read line; do
		ready_state_started=`echo ${line} | awk "{ print \\$${ready_column} }" | awk -F/ '{ print $1 }'`
		ready_state_total=`echo ${line} | awk "{ print \\$${ready_column} }" | awk -F/ '{ print $2 }'`
		isNum ${ready_state_started}
		if [ ${is_number} = false ]; then
			echo "Failure determining pod state (ready_state_started):  ${line}"
			rm ${TMP}.*
			exit 3
		fi
		isNum ${ready_state_total}
		if [ ${is_number} = false ]; then
			echo "Failure determining pod state (ready_state_total):  ${line}"
			rm ${TMP}.*
			exit 4
		fi

		if [ ${ready_state_started} -ne ${ready_state_total} ]; then
			echo false > ${TMP}.3
			name=`echo ${line} | awk "{ print \\$${name_column} }"`
			grep "${name} " ${TMP}.1
		fi
	done
	pods_healthy=`cat ${TMP}.3`

	rm ${TMP}.*

	if [ ${pods_healthy} = true ]; then
		break
	fi

	echo
	echo "Pods not ready"
	echo
	date
	counter=`expr ${counter} + 1`
	if [ ${counter} -ge ${retries} ]; then
		echo "Giving up..."
		break
	else
		echo "Waiting ${wait_interval}s and then trying again (${counter}/${retries})"
	fi
	sleep ${wait_interval}
done

echo
duration=`echo "scale=3; ${counter} * ${wait_interval} / 60" | bc`
echo "Duration:  ${duration} minutes"

echo
if [ ${pods_healthy} = true ]; then
	exit 0
else
	exit 5
fi

