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
set -o xtrace

cd ${WORKING_DIR}

echo
if [ "${alt_cfc_docker_registry}" != "" ]; then
	echo "Trusting alternative IBM Cloud private registry ${alt_cfc_docker_registry}"
	wget -O - http://${alt_cfc_docker_registry}/static/trust-me | bash -x
fi

