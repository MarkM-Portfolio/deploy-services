# steps because bash 3.2 on Mac OS X 10.12 no longer compatible

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

if [ ! -f 00-all-config.sh ]; then
	echo "Dependency on 00-all-config.sh missing - must be in same directory"
	exit 1
fi
WORKING_DIR=/opt	# Hardcoded - won't mesh with flexible deployment location
DEPLOY_CFC_DIR=`grep '^DEPLOY_CFC_DIR=' 00-all-config.sh | awk -F= '{ print $2 }'`
if [ "${DEPLOY_CFC_DIR}" = "" ]; then
	echo "Parsing problem for DEPLOY_CFC_DIR"
	exit 2
fi
PACKAGE_LIST=`grep -m 1 '^PACKAGE_LIST=' 00-all-config.sh | awk -F = '{ print $2 }'`
pushd ..
PACKAGE_LIST=`eval echo ${PACKAGE_LIST}`
popd
if [ "${PACKAGE_LIST}" = "" ]; then
	echo "Parsing problem for PACKAGE_LIST"
	exit 3
fi

# because DEPLOY_CFC_DIR has an embedded macro
DEPLOY_CFC_DIR=`eval echo ${DEPLOY_CFC_DIR}`

set +o errexit
for arg in $*; do
	echo ${arg} | grep -q -e --boot=
	if [ $? -eq 0 ]; then
		BOOT=`echo ${arg} | awk -F= '{ print $2 }'`
	fi
done
set -o errexit
set +o nounset
if [ "${BOOT}" = "" -a `basename $0` != package.sh ]; then
	echo "BOOT undefined"
	exit 2
fi
set -o nounset

