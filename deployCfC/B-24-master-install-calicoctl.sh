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

compareVersions ${CFC_VERSION} 2.1.0.1
if [ ${comparison_result} = 1 ]; then
	# CFC_VERSION < 2.1.0.1
	exit 0
fi

echo
mkdir -p ${RUNTIME_BINS}/bin ${RUNTIME_BINS}/calicoctl/bin
rm -f ${RUNTIME_BINS}/bin/calicoctl ${RUNTIME_BINS}/calicoctl/bin/calicoctl
cp ${DEPLOY_CFC_DIR}/calicoctl/calicoctl ${RUNTIME_BINS}/bin/calicoctl
echo "Retrieving calicoctl from docker image packaged with IBM Cloud private"

set +o errexit
docker run -v ${RUNTIME_BINS}/calicoctl/bin:/data --entrypoint=cp ibmcom/calico-ctl:${CALICOCTL_VERSION} /calicoctl /data
if [ $? -ne 0 ]; then
	echo "Copy of calicoctl from container failed"
	exit 10
fi
set -o errexit
chmod 755 ${RUNTIME_BINS}/calicoctl/bin/calicoctl

calicoctl version

echo
echo "calicoctl CLI configured"

