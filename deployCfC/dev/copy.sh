#! /bin/bash
# Initial author: on Sun Feb  5 15:26:49 GMT 2017
#
# History:
# --------
# Sun Feb  5 15:26:49 GMT 2017
#	Initial version
#
#

# bash 3.2 on Mac OS X 10.12 no longer compatible
#. ./00-all-config.sh
. `dirname "$0"`/dev.sh

set -o errexit
echo
bash `dirname "$0"`/package.sh $*
echo

for host in ${BOOT}; do
	echo
	echo
	echo "Preparing ${host}"
	echo
	scp /tmp/deployCfC.zip root@${host}:/tmp
	ssh root@${host} "rm -rf ${DEPLOY_CFC_DIR} && unzip -d ${WORKING_DIR} /tmp/deployCfC.zip && chmod -R 755 ${DEPLOY_CFC_DIR} && rm /tmp/deployCfC.zip"
done

