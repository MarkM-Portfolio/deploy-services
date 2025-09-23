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

if [ -x /sbin/md5 ]; then		# Mac OS X
	MD5="/sbin/md5 -r"
elif [ -x /usr/bin/md5sum ]; then	# Linux
	MD5="/usr/bin/md5sum"
else
	echo "Don't know where to find md5sum"
	exit 1
fi
# need sort to key off of column 2, not the md5 hash column
SORT_ARGS="-k 2"

rm -f /tmp/deployCfC.zip
pushd ..
PACKAGE_LIST=$(echo ${PACKAGE_LIST} | cut -d "\`" -f 2)

echo
echo "Testing scripts"
set +o errexit
for script in ${PACKAGE_LIST}; do
	echo ${script} | grep -q '\.sh$'
	if [ $? -eq 0 ]; then
		bash -n ${script}
		if [ $? -ne 0 ]; then
			echo "Problem with script:  ${script}"
			exit 1
		fi
	fi
done
echo OK
set -o errexit

set +o nounset
if [ "${EXTRA_PACKAGE_LIST}" = "" ]; then
	EXTRA_PACKAGE_LIST=""
fi
set -o nounset

${MD5} ${PACKAGE_LIST} | sort -f ${SORT_ARGS} | sed -e 's/  / /g' -e 's/ /  /g' > deployCfC/manifest.md5
zip -1 -r /tmp/deployCfC.zip deployCfC/manifest.md5 ${PACKAGE_LIST} ${EXTRA_PACKAGE_LIST}
popd

