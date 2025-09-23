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

# Configure external proxy if using one
echo
if [ "${ext_proxy_url}" != "" ]; then
	echo "Configuring external proxy ${ext_proxy_url}"
	export http_proxy=${ext_proxy_url}
	export https_proxy=${ext_proxy_url}
	export ftp_proxy=${ext_proxy_url}
	export no_proxy=localhost,127.0.0.1
	for host in ${HOST_LIST[@]}; do
		export no_proxy=$no_proxy,$host
	done
fi

TMP=`mktemp ${TMP_TEMPLATE}`
curl -f -L https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl > ${TMP}
if [ ! -s ${TMP} ]; then
	echo "kubectl failed to download (1)"
	exit 1
fi
set +o errexit
file ${TMP} | grep -q 'ELF 64-bit LSB executable'
if [ $? -ne 0 ]; then
	echo "kubectl failed to download (2)"
	exit 2
fi
set -o errexit

mkdir -p ${RUNTIME_BINS}/bin ${RUNTIME_BINS}/kubectl/bin
rm -f ${RUNTIME_BINS}/bin/kubectl ${RUNTIME_BINS}/kubectl/bin/kubectl
cp ${DEPLOY_CFC_DIR}/kubectl/kubectl ${RUNTIME_BINS}/bin/kubectl
mv ${TMP} ${RUNTIME_BINS}/kubectl/bin/kubectl
chmod 755 ${RUNTIME_BINS}/bin/kubectl ${RUNTIME_BINS}/kubectl/bin/kubectl

conn_locn=$(cat $ICP_CONFIG_DIR/$ICP_CONFIG_FILE | $jq_bin -r '.connections_location')
if [ ! -d "${conn_locn}" ]; then
	echo "Cannot determine ICp install directory"
	exit 3
fi

# Only create a symlink if it's a default installation as non-default deployment may indicate that changes to the system should be localized
if [ "${conn_locn}" == "/opt/deployCfC" ]; then
	set +o errexit
	# Create a softlink to the utility in the default paths 
	ln -sf ${RUNTIME_BINS}/kubectl/bin/kubectl /usr/local/bin/kubectl
	if [ $? -ne 0 ]; then
		echo
		echo
		echo "******* WARNING ******"
		echo
		echo "Failed to create symbolic link to new kubectl binary"
		echo "Please check your system to see if kubectl commands will run from the command line and update your path to the kubectl binary if necessary"
		echo
		echo
	fi 
	set -o errexit
fi

set +o xtrace

echo
echo "kubectl deployed"


