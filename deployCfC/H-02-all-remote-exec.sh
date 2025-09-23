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
set +o nounset
#set -o xtrace

PATH=/usr/bin:/bin:/usr/sbin:${RUNTIME_BINS}/bin:/sbin; export PATH
umask 022

if [ "$1" = "" ]; then
	echo "Incorrect configuration (1)"
	exit 1
fi
if [ ! -f "$1" ]; then
	echo "Incorrect configuration (2):  $1"
	exit 2
fi

/bin/bash "$1"

if [ "$2" != --debug ]; then
	rm -f "$1"
fi

