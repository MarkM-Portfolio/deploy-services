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

# Check for version mismatch
echo
echo "Validating versions before proceeding with uninstall"
echo "This IBM Cloud private deployment automation is ${CFC_VERSION}"
deployed_cfc_version=""
version_matches=true
if [ -f /opt/ibm/cfc/version ]; then
	deployed_cfc_version=`cat /opt/ibm/cfc/version`
	if [ "${deployed_cfc_version}" != "" ]; then
		echo "Found deployed IBM Cloud private version ${deployed_cfc_version}"
	else
		echo "Can't determine deployed IBM Cloud private version"
		if [ ${force_uninstall} = false ]; then
			echo "To ignore this failure, use the --force_uninstall argument"
			echo
			exit 10
		fi
	fi
fi

#running_cfc_version=""
#if [ -x /usr/bin/docker ]; then
#	set +o pipefail
#	running_cfc_version=`docker ps | grep ibmcom/cfc-image-manager | head -1 | awk '{ print $2 }' | awk -F: '{ print $2 }'`
#	set -o pipefail
#	if [ "${running_cfc_version}" != "" ]; then
#		echo "Found running IBM Cloud private version ${running_cfc_version}"
#	else
#		echo "Can't determine running IBM Cloud private version"
#		if [ ${force_uninstall} = false ]; then
#			echo "To ignore this failure, use the --force_uninstall argument"
#			echo
#			exit 11
#		fi
#	fi
#fi
#if [ "${deployed_cfc_version}" = "" -a "${running_cfc_version}" = "" ]; then
#	echo "No deployment detected"
#else
#	if [ "${deployed_cfc_version}" != "${running_cfc_version}" ]; then
#		echo "WARNING:  Deployed IBM Cloud private version ${deployed_cfc_version} does not match running IBM Cloud private version ${running_cfc_version} - usually happens on a failed install or incomplete uninstall"
#		version_matches=false
#		if [ ${force_uninstall} = false ]; then
#			echo "To ignore this mismatch, use the --force_uninstall argument"
#			echo
#			exit 12
#		fi
#	fi
#fi
if [ ${CFC_VERSION} != "${deployed_cfc_version}" -a "${deployed_cfc_version}" != "" ]; then
	version_matches=false
	if [ ${force_uninstall} = false ]; then
		echo "Uninstall must be invoked using IBM Cloud private deployment automation version ${deployed_cfc_version} (deployed version)"
		echo "To ignore this mismatch, use the --force_uninstall argument"
		echo "which will force the uninstall using ${CFC_VERSION} regardless"
		echo "or alternatively, use the option --alt_cfc_version=${deployed_cfc_version}"
		echo "for example:"
		set +o errexit
		echo $* | grep -q -e --alt_cfc_version=
		if [ $? -eq 0 ]; then
			args=`echo $* | sed "s/--alt_cfc_version=[0-9].[0-9].[0-9]/--alt_cfc_version=${deployed_cfc_version}/"`
		else
			args="$* --alt_cfc_version=${deployed_cfc_version}"
		fi
		set -o errexit
		echo "	bash ${DEPLOY_CFC_DIR}/deployCfC.sh ${args}"
		echo
		exit 13
	fi
fi
#if [ ${CFC_VERSION} != "${running_cfc_version}" -a "${running_cfc_version}" != "" ]; then
#	version_matches=false
#	if [ ${force_uninstall} = false ]; then
#		echo "Uninstall must be invoked using IBM Cloud private deployment automation version ${running_cfc_version} (running version)"
#		echo "To ignore this mismatch, use the --force_uninstall argument"
#		echo "which will force the uninstall using ${CFC_VERSION} regardless"
#		echo "or alternatively, use the option --alt_cfc_version=${running_cfc_version}"
#		echo "for example:"
#		echo "	$0 $* --alt_cfc_version=${running_cfc_version}"
#		echo
#		exit 14
#	fi
#fi

if [ ${version_matches} = true ]; then
	echo "No version mismatches - OK"
else
	echo "Versions don't match, but proceeding anyway - FAILED"
fi

