#! /bin/bash
#
# History:
# --------
# DATE
#	Initial version

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

PATH=/usr/bin:/bin:/usr/sbin:/sbin:${PATH}
PRG=`basename ${0}`
DATE=`date +%Y%m%d%H%M%S`
TMP_TEMPLATE=/tmp/${PRG}.${DATE}.XXXXXX.$$
umask 022

ICP_CONFIG_DIR=/opt/ibm/connections
ICP_CONFIG_FILE=config.json
jq=${ICP_CONFIG_DIR}/jq/bin/jq

conn_locn=$(cat $ICP_CONFIG_DIR/$ICP_CONFIG_FILE | $jq -r '.connections_location')
if [ ! -d "${conn_locn}" ]; then
        echo "Cannot determine ICp install directory"
        exit 1
fi
RUNTIME_BINS=${conn_locn}/runtime

PATH=${PATH}:${RUNTIME_BINS}/bin
export PATH

logErr() {
	logIt "ERRO: " "$@"
}

logInfo() {
	logIt "INFO: " "$@"
}

logIt() {
	echo "$@"
}


# function description
function some_function() {
	set -o errexit
	set -o pipefail
	set -o nounset

	USAGE_SOME_FUNCTION="usage:  some_function sArg1 ... sArgN"

	set +o nounset
	if [ "$2" = "" ]; then
		logErr "${USAGE_SOME_FUNCTION}"
		exit 101
	fi
	set -o nounset
	func_arg1=$1
	func_arg2=$2

	logInfo "some function result with arguments ${func_arg1}, ${func_arg2}"
}


USAGE="usage:  ${PRG} sArg1 ... sArgN"
set +o nounset
if [ "$2" = "" ]; then
	logErr "${USAGE}"
	exit 1
fi
set -o nounset
arg1=$1
arg2=$2

logInfo "some normal output with arguments ${arg1}, ${arg2}"

set +o errexit
some_function arg1 arg2
exit_status=$?
if [ ${exit_status} -ne 0 ]; then
	logErr "some_function error status ${exit_status}"
	exit 10
fi
set -o errexit

logInfo "some more normal output but only if there haven't been errors"

echo "Clean exit"
exit 0

