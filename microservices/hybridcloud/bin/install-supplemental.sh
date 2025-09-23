#! /bin/bash
# Initial author: on Sun Feb  5 15:26:49 GMT 2017
#
# History:
# --------
# Sun Feb  5 15:26:49 GMT 2017
#	Initial version

# Duplicate install tasks which are done in CfC deployment, but until we have a
# proven day-to-day CfC upgrade implemented, need this for now.

# To do:
#	1. pull in secrets and stuff from setup.sh which was done before release
#	2. add logration

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

PATH=/usr/bin:/bin:/usr/sbin:/sbin:${PATH}
export PATH
umask 022

if [ "`id -u`" != 0 ]; then
        echo "Must run as root"
        exit 1
fi

ICP_CONFIG_DIR=/opt/ibm/connections
ICP_CONFIG_FILE=config.json
jq=${ICP_CONFIG_DIR}/jq/bin/jq

conn_locn=$(cat $ICP_CONFIG_DIR/$ICP_CONFIG_FILE | $jq -r '.connections_location')
if [ ! -d "${conn_locn}" ]; then
        echo "Cannot determine ICp install directory"
        exit 2
fi
RUNTIME_BINS=${conn_locn}/runtime

PATH=${PATH}:${RUNTIME_BINS}/bin
export PATH

# Support different invocation locations associated with this script at different times
bin_dir="`dirname \"$0\"`"
echo
cd "${bin_dir}" > /dev/null
echo "Changed location to bin:"
echo "	`pwd`"
echo "	(relative path:  ${bin_dir})"

# Logrotate
echo
echo "Deploying logrotation"
mkdir -p ${RUNTIME_BINS}/etc/logrotate.d
rm -f ${RUNTIME_BINS}/etc/logrotate.d/connections-docker-container
rm -f ${RUNTIME_BINS}/bin/logrotate.sh
cp $conn_locn/support/connections-docker-container ${RUNTIME_BINS}/etc/logrotate.d/connections-docker-container
cp $conn_locn/support/logrotate.sh ${RUNTIME_BINS}/bin/logrotate.sh
chmod 644 ${RUNTIME_BINS}/etc/logrotate.d/connections-docker-container
chmod 755 ${RUNTIME_BINS}/etc/logrotate.d
chmod 755 ${RUNTIME_BINS}/bin/logrotate.sh

