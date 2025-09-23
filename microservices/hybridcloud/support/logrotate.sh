#! /bin/bash
# Initial author: on Sun Feb  5 15:26:49 GMT 2017
#
# History:
# --------
# Sun Feb  5 15:26:49 GMT 2017
#	Initial version
#
#

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

#OPTIONAL_ARGS=-v
OPTIONAL_ARGS=""

PATH=/usr/bin:/bin:/usr/sbin:/sbin:${PATH}
export PATH

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

echo
date
logrotate ${OPTIONAL_ARGS} -f ${conn_locn}/etc/logrotate.d/connections-docker-container
date

