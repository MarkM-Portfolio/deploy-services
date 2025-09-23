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

PATH=/usr/bin:/bin:/usr/sbin:/usr/local/bin:/sbin; export PATH

echo
date
logrotate ${OPTIONAL_ARGS} -f /usr/local/etc/logrotate.d/connections-docker-container
date

