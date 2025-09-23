#! /bin/bash
# Initial author: on Sun Feb  5 15:26:49 GMT 2017
#
# History:
# --------
# Sun Feb  5 15:26:49 GMT 2017
#	Initial version
#
#

. `dirname $0`/00-all-config.sh

set +o errexit
set +o pipefail
set -o nounset
#set -o xtrace

cd ${WORKING_DIR}

if [ ! -f ${LOG_FILE} ]; then
	echo "Log was empty so no bread crumbs"
	echo "Empty" >> ${LOG_FILE}
fi

TMP=`mktemp ${TMP_TEMPLATE}.zip || exit 1`	# ensure unique
rm -f ${TMP}

echo
echo "Gathering system info.  This can take a few minutes..."
(
	echo
	docker info
	echo
	echo '===='
	echo
	docker ps
	echo
	echo '===='
	echo
	docker stats --all --no-stream
	echo
	echo '===='
	echo
	kubectl get pods
	echo
	echo '===='
	echo
	kubectl cluster-info
	echo
	echo '===='
	echo
	uptime
	echo
	echo '===='
	echo
	ifconfig
	echo
	echo '===='
	echo
	ip addr
	echo
	echo '===='
	echo
	arp -a | while read line; do
		for host in ${HOST_LIST} master.cfc; do
			echo ${line} | grep -q ${host}
			if [ $? -eq 0 ]; then
				echo ${line}
			fi
		done
	done
	echo
	echo '===='
	echo
	for interface in `ifconfig | grep '^eth' | awk '{ print $1 }'`; do
		ethtool ${interface}
		echo
		ethtool -S ${interface}
		echo
		ethtool -k ${interface}
		echo
	done
	echo '===='
	echo
	netstat -s
	echo
	echo '===='
	echo
	systemctl status iptables.service
	echo '===='
	echo
	iptables --list
	echo
	echo '===='
	echo
	netstat -rn
	echo
	echo '===='
	echo
	netstat -anp
	echo
	echo '===='
	echo
	lsof -Pn
	echo
	echo '===='
	echo
	iostat -k
	echo '===='
	echo
	df -k
	echo
	echo '===='
	echo
	mount
	echo
	echo '===='
	echo
	vmstat
	echo '===='
	echo
	vmstat -f
	echo
	echo '===='
	echo
	vmstat -s
	echo
	echo '===='
	ipcs
	echo '===='
	echo
	sysctl -a
	echo
	echo '===='
	echo
	echo "SELinux:"
	getenforce
	echo
	echo '===='
	echo
	ps auxww
	echo
	echo '===='
	echo
	ulimit -a
	echo
	echo '===='
	echo
	set
	echo
	echo '===='
	echo
	uname -a
	echo
	echo '===='
	echo
	dmesg
	echo
	echo '===='
	echo
	rpm -q -a --queryformat '%{NAME}-%{VERSION}-%{RELEASE} %{ARCH}\n'
	echo
	echo '===='
	echo
	rpm -q -a --last
	echo
	echo '===='
	echo
	cat /etc/sysconfig/iptables-config
	echo
	echo '===='
	echo
	if [ -f /etc/sysconfig/system-config-firewall ]; then
		cat /etc/sysconfig/system-config-firewall
	else
		echo "No /etc/sysconfig/system-config-firewall"
	fi
	echo
) > /tmp/ServerDetails.txt 2>&1

echo "Creating ZIP of data for support"

zip -q -9 -r ${TMP} /tmp/ServerDetails.txt ${PACKAGE_LIST} deployCfC/manifest.md5 ${INSTALL_DIR}/cluster ${LOG_FILE}* /etc/fstab /etc/hosts /etc/redhat-release /etc/resolv.conf /etc/yum.repos.d /var/log/boot.log /var/log/calico /var/log/containers/*.log /var/log/containers/*.log.1 /var/log/containers/docker/*.log /var/log/containers/docker/*.log.1 /var/log/dmesg* /var/log/messages* /var/log/yum.log

echo "Provide ${TMP} to support"

