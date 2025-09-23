#! /bin/bash
# Initial author: on Sun Feb  5 15:26:49 GMT 2017
#
# History:
# --------
# Sun Feb  5 15:26:49 GMT 2017
#	Initial version

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

update_dir="`dirname \"$0\"`"
cd "${update_dir}" > /dev/null

# Deploy fixes from this script only
CNX_DEPLOYED_FROM_TOP_LEVEL=true; export CNX_DEPLOYED_FROM_TOP_LEVEL

# Uncomment after issue 2201 resolved
#if [ ! -f /opt/deployCfC/00-all-config.sh ]; then
#	echo "Can't find IBM Connections deployment of Conductor for Containers"
#	exit 1
#fi
#. /opt/deployCfC/00-all-config.sh

set +o nounset
# Default admin credentials
if [ "${ADMIN_USER}" = "" ]; then
	ADMIN_USER=admin
else
	echo "Overriding ADMIN_USER=${ADMIN_USER}"
fi
if [ "${ADMIN_PASSWD}" = "" ]; then
	ADMIN_PASSWD=admin
else
	echo "Overriding ADMIN_PASSWD=${ADMIN_PASSWD}"
fi
set -o nounset
export ADMIN_USER ADMIN_PASSWD
LOG_FILE=/var/log/cfc.log
PRG=`basename ${0}`
# End of special steps for issue 2201


USAGE="
usage:  ${PRG}
	[--help]
	sFix1 sFix2 ... sFixN

Example:
	bash deployFixes.sh orient-web-client redis
"

(

echo
set +o nounset
if [ "$1" = --help ]; then
	echo "${USAGE}"
	exit 0
elif [ "$1" != "" ]; then
	fix_list="$*"
	echo "Using provided list for deployment:  ${fix_list}"
else
	fix_list=`ls -1 */deploySubUpdate.sh | sed 's@/deploySubUpdate.sh@@'`
	echo "Using generated list for deployment:  ${fix_list}"
fi
set -o nounset

for fix in ${fix_list}; do
	echo
	echo
	echo "Checking ${fix}"
	if [ ! -d ${fix} -o ! -f ${fix}/deploySubUpdate.sh ]; then
		echo "Can't find deployment script for ${fix}"
		exit 2
	fi

	echo
	echo "Deploying ${fix}"
	pushd ${fix} > /dev/null
	bash deploySubUpdate.sh $*
	popd > /dev/null

	# Add k8s calls to wait for fix deployment confirmation before proceeding?
done

) 2>&1 | tee -a ${LOG_FILE}

