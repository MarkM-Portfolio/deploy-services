#! /bin/bash
# Initial author: on Sun Feb  5 15:26:49 GMT 2017
#
# History:
# --------
# Sun Feb  5 15:26:49 GMT 2017
#	Initial version
#
# $Header: /home/jabbott/archive/src/scripts/RCS/rhel-config_ibm-yum.sh,v 1.2 2017/11/02 12:53:24 jabbott Exp $

set -o errexit
set -o pipefail
set -o nounset
set +o xtrace

echo

set +o nounset
if [ "$1" = -f ]; then
	rm -f /root/.rhel-config.done
fi
set +o nounset
if [ -f /root/.rhel-config.done ]; then
	echo "Already registered"
	echo
	exit 0
fi

# Optionally hard code here so you aren't prompted
#FTP3USER=
#FTP3PASS=

set +o nounset
if [ "${FTP3USER}" = "" ]; then
	printf "FTP3USER: "
	read FTP3USER
fi
if [ "${FTP3PASS}" = "" ]; then
	printf "FTP3PASS: "
	read -s FTP3PASS
fi
set -o nounset
export FTP3USER FTP3PASS

echo
echo
cd /root
rm -f ibm-yum.sh os-config.sh
#wget http://pokgsa.ibm.com/~jgabbott/public/Pink/rhel/ibm-yum.sh
wget --user=${FTP3USER} --password=${FTP3PASS} ftp://ftp3.linux.ibm.com/redhat/ibm-yum.sh
chmod 755 ibm-yum.sh
echo export YUM=/root/ibm-yum.sh > os-config.sh
echo export FTP3USER=${FTP3USER} >> os-config.sh
echo export FTP3PASS=${FTP3PASS}  >> os-config.sh
if [ -f /etc/sysconfig/rhn/up2date ]; then
	if (grep -q rhn.linux.ibm.com /etc/sysconfig/rhn/up2date); then
		echo Fixing RHN
		mv /etc/sysconfig/rhn/up2date /etc/sysconfig/rhn/up2date.IBM_RHN_SHUTDOWN
	fi
fi

echo
echo "Completed successfully"
echo
exit 0

