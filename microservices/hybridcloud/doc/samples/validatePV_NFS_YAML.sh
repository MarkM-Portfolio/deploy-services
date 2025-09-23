#! /bin/bash
# Initial author: on Sun Feb  5 15:26:49 GMT 2017
#
# History:
# --------
# Sun Feb  5 15:26:49 GMT 2017
#	Initial version
#
#

PATH=/usr/bin:/bin:/usr/sbin:/sbin:${PATH}
export PATH
umask 022

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

fullPVs_NFS_DEFAULT=fullPVs_NFS.yml

force=false
fullPVs_NFS=""
set +o nounset
for arg in $*; do
	if [ "${arg}" = --debug ]; then
		set -o xtrace
	elif [ "${arg}" = --force ]; then
		force=true
	else
		fullPVs_NFS="${arg}"
	fi
	shift
done
set -o nounset

if [ "${fullPVs_NFS}" = "" ]; then
	echo "usage:  `basename $0` fullPVs_NFS.yml [--debug] [--force]"
	exit 1
fi

echo
if [ ! -f "${fullPVs_NFS}" ]; then
	echo "Can't find ${fullPVs_NFS} for source of NFS mounts"
	if [ "${fullPVs_NFS}" != "${fullPVs_NFS_DEFAULT}" ]; then
		echo "Usually will be named ${fullPVs_NFS_DEFAULT}"
		echo "Refer to documentation on setting up the persistent volumes"
	fi
	exit 2
else
	echo "Found ${fullPVs_NFS} for source of NFS mounts"
fi

echo
echo "Validation script must be run on every node in the topology"
echo "This instance is running on `hostname -f`"
if [ "${force}" = false ]; then
	echo "Proceed?"
	echo
	printf "Enter \"yes\" to confim:  "
	read answer
	if [ "${answer}" != yes ]; then
		echo
		echo "NFS mount and write permissions test aborted"
		echo
		exit 0
	fi
fi

grep path: ${fullPVs_NFS} | while read line; do
	if [ `echo "${line}" | wc -w` -ne 2 ]; then
		echo "Malformed path in yml:  ${line}"
		exit 66
	fi
done

number_path_lines=`grep path: ${fullPVs_NFS} | wc -l`
number_unique_path_lines=`grep path: ${fullPVs_NFS} | awk -F: '{ print $2 }' | sort -u | wc -l`
if [ ${number_path_lines} -ne ${number_unique_path_lines} ]; then
	echo "Number of paths not unique.  Found ${number_path_lines} but only ${number_unique_path_lines} are unique - should be the same."
	exit 88
fi

mount_list=""
for path in `grep path: ${fullPVs_NFS} | awk -F: '{ print $2 }'`; do
	server=`grep -A1 "${path}" ${fullPVs_NFS} | tail -1`
	if [ `echo "${server}" | wc -w` -ne 2 ]; then
		echo "Malformed server in yml:  ${server}"
		exit 99
	fi
	set +o errexit
	echo ${server} | grep -q 'server:'
	if [ $? -ne 0 ]; then
		echo "Couldn't find server mapping pair to path ${path}"
		exit 77
	fi
	set -o errexit
	server=`echo ${server} | awk -F: '{ print $2 }'`
	mount_list="${mount_list} ${server}:${path}"
done

#my_ip=`hostname -i | awk '{ print $1 }'`
MOUNT_OPTS="rw,hard,nfsvers=4,tcp,timeo=200"	# ,clientaddr=${my_ip}"

set +o errexit
for mount in ${mount_list}; do
	echo
	echo "Testing NFS mount and write permissions for ${mount}"
	temp_mount=`mktemp -d /mnt.${RANDOM}.XXXXXX.$$` && \
	mount -o ${MOUNT_OPTS} ${mount} ${temp_mount} && \
	date > ${temp_mount}/success.txt && \
	rm -f ${temp_mount}/success.txt
	exit_status=$?

	# issue 7684
	# not all PVs are writeable by non-root after Pink containers run as they
	# change the owner and permission
	# /opt/deployCfC/setuid/bin/setuid nobody touch ${temp_mount}/success.txt
	# /opt/deployCfC/setuid/bin/setuid nobody rm -f ${temp_mount}/success.txt

	counter=1
	retries=3
	while [ ${counter} -le ${retries} ]; do
		if [ -d ${temp_mount} ]; then
			sync
			umount ${temp_mount}
			rmdir ${temp_mount}
			if [ $? -eq 0 ]; then
				break
			fi
		else
			break
		fi
		counter=`expr ${counter} + 1`
	done
	if [ ${counter} -gt ${retries} ]; then
		echo "	Failed to unmount persistent storage ${temp_mount}"
		echo "	This shouldn't happen.  Cleanup manually."
	fi

	if [ ${exit_status} -ne 0 ]; then
		echo
		echo "Failure testing NFS mount and write permissions for ${mount}"
		exit 78
	else
		echo "OK"
	fi
done
set -o errexit

echo
echo "NFS mount and write permissions tests passed on node `hostname -f`"
echo "Complete tests by running on every node in topology"
echo
exit 0

