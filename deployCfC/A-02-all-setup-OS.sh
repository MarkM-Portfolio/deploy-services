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

# Wipe the config file if exists
rm -f ${CONFIG_DIR}/${HOSTNAME}

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

# Hook to configure RHEL repos if necessary
if [ -f /root/rhel-config.sh ]; then
	set +o errexit
	bash /root/rhel-config.sh
	if [ $? -ne 0 ]; then
		echo "Failed to configure RHEL repos"
		exit 11
	fi
	set -o errexit
fi

# RHEL packages
echo
if [ ${skip_rpm_installation} = true ]; then
	echo "Skipping RPM installation and verifying prereqs are installed"
	set +o errexit
	prereqs_ok=true
	for rpm in ${REQUIRED_RPMS}; do
		printf "Checking ${rpm} - "
		rpm -q ${rpm} > /dev/null
		if [ $? -ne 0 ]; then
			echo "not installed"
			prereqs_ok=false
		else
			echo "OK"
		fi
	done
	if [ ${prereqs_ok} = false ]; then
		echo
		echo "One or more RPM prereqs are not installed.  See above output."
		echo
		echo "Complete list of RPM prereqs:  ${REQUIRED_RPMS}"
		exit 10
	fi
	set -o errexit
else
	set +o errexit
	echo
	echo "Checking for dependent RHEL yum packages"
	${YUM} install -y ${REQUIRED_RPMS}
	if [ $? -ne 0 ]; then
		echo "Failure installing RHEL packages"
		exit 10
	fi
	set -o errexit
fi

# Copy jq to deployment directory for each host
deployjq
if [ $? -ne 0 ]; then
	echo "Failed to copy jq binary to ${ICP_CONFIG_DIR}/jq/bin/jq" 
	exit 10
else
	echo "jq copied to deployment directory"	
fi


# issue 1950
echo
compatible_release=false
distributor=`lsb_release -i | awk '{ print $3 }'`
echo "Detected distributor:  ${distributor}"
if [ "${distributor}" = RedHatEnterpriseServer ]; then
	echo "Detected Red Hat Enterprise Server"
	rhel_release=`lsb_release -r | awk '{ print $2 }'`
	rhel_major_ver=`echo ${rhel_release} | awk -F. '{ print $1 }'`
	rhel_minor_ver=`echo ${rhel_release} | awk -F. '{ print $2 }'`
	if [ "${rhel_minor_ver}" = "" ]; then
		rhel_minor_ver=0
	fi
	echo "Required versions list:  RHEL 7.4 and later"
	echo "Detected RHEL ${rhel_major_ver}.${rhel_minor_ver}"
	if [ ${rhel_major_ver} -eq 7 ]; then
		if [ ${rhel_minor_ver} -ge 4 ]; then	# -a ${rhel_minor_ver} -le X
			compatible_release=true
		fi
	fi
	echo ${rhel_major_ver} > ${LOG_FILE}-rhel_major_ver.txt
	echo ${rhel_minor_ver} > ${LOG_FILE}-rhel_minor_ver.txt
	echo ${distributor} > ${LOG_FILE}-rhel_distributor.txt
elif [ "${distributor}" = CentOS ]; then
	echo "Detected CentOS"
	rhel_release=`lsb_release -r | awk '{ print $2 }'`
	rhel_major_ver=`echo ${rhel_release} | awk -F. '{ print $1 }'`
	rhel_minor_ver=`echo ${rhel_release} | awk -F. '{ print $2 }'`
	if [ "${rhel_minor_ver}" = "" ]; then
		rhel_minor_ver=0
	fi
	echo "Required versions list:  CentOS 7.4 and later"
	echo "Detected CentOS ${rhel_major_ver}.${rhel_minor_ver}"
	if [ ${rhel_major_ver} -eq 7 ]; then
		if [ ${rhel_minor_ver} -ge 4 ]; then	# -a ${rhel_minor_ver} -le X
			compatible_release=true
		fi
	fi
	echo ${rhel_major_ver} > ${LOG_FILE}-rhel_major_ver.txt
	echo ${rhel_minor_ver} > ${LOG_FILE}-rhel_minor_ver.txt
	echo ${distributor} > ${LOG_FILE}-rhel_distributor.txt
elif [ "${distributor}" = Ubuntu ]; then
	echo "Detected Ubuntu"
	#ubuntu_release=`lsb_release -d`
	#echo "Required versions list:  Ubuntu 16.04 LTS"
	#echo "Detected ${ubuntu_release}"
	#if [ "${ubuntu_release}" = "Ubuntu 16.04 LTS" ]; then
		#compatible_release=true
		compatible_release=false
	#fi
fi

if [ ${compatible_release} = false ]; then
	echo "Incompatible OS release"
	if [ ${ignore_os_requirements} = true ]; then
		echo "Ignoring incompatible OS release warning"
	else
		echo "Use --ignore_os_requirements flag to proceed anyway, but the results are not supported"
		exit 1
	fi
else
	echo "Compatible OS version"
fi


# Open ports in firewall
# Assumes public is the correct zone
echo
if [ ${configure_firewall} = false ]; then
	echo "Not configuring firewall"
else
	set +o errexit
	set -o xtrace
	for port in ${FIREWALL_PORT_LIST}; do
		firewall-cmd --zone=public --add-port=${port}/tcp --permanent
	done
	set +o xtrace
	set -o errexit
fi


# Manage firewalls during deployment
set +o errexit
echo
if [ ${skip_disable_firewall} = true ]; then
	echo "Skipping firewall enablement management"
else
	# Disable firewall for install, and then restore it again after if CFC_VERSION < 2.1.0.1
	compareVersions ${CFC_VERSION} 2.1.0.1
	set +o errexit		# reset in compareVersions
	if [ ${comparison_result} = 1 ]; then
		# CFC_VERSION < 2.1.0.1
		mkdir -p ${CONFIG_DIR}
		for firewall in ${FIREWALL_PACKAGES}; do
			echo
			echo "Checking ${firewall} status"
			echo
			systemctl status ${firewall}
			echo "Running firewall test for ${firewall}"
			if [ "`systemctl status ${firewall} | grep Active: | awk '{print $2}'`" == "active" ]; then
				echo "${firewall}.active=true" >> ${CONFIG_DIR}/${HOSTNAME}
				echo "Added the status of ${firewall} to ${CONFIG_DIR}/${HOSTNAME}"
				echo "Found ${firewall} is active. Stopping it now."
				systemctl stop ${firewall}
			elif [ "`systemctl status ${firewall} | grep Active: | awk '{print $2}'`" == "inactive" ]; then
				echo "${firewall}.active=false" >> ${CONFIG_DIR}/${HOSTNAME}
				echo "Added the status of ${firewall} to ${CONFIG_DIR}/${HOSTNAME}"
				echo "Found ${firewall} is inactive."
			else
				echo "Unkown status for ${firewall}"
			fi
			if [ "`systemctl status ${firewall} | grep Loaded: | awk '{print $4}'`" == "enabled;" ]; then
				echo "${firewall}.enabled=true" >> ${CONFIG_DIR}/${HOSTNAME}
				echo "Added the status of ${firewall} to ${CONFIG_DIR}/${HOSTNAME}"
				echo "Found ${firewall} is enabled. Disabling it now."
				systemctl disable ${firewall}
			elif [ "`systemctl status ${firewall} | grep Loaded: | awk '{print $4}'`" == "disabled;" ]; then
				echo "${firewall}.enabled=false" >> ${CONFIG_DIR}/${HOSTNAME}
				echo "Added the status of ${firewall} to ${CONFIG_DIR}/${HOSTNAME}"
				echo "Found ${firewall} is disabled."
			else
				echo "Unkown status for ${firewall}"
			fi
			echo
			echo "Exit status:  $? (non-0 OK, just informational)"
		done
	else
		echo "Not managing firewall enablement"
	fi
fi
set -o errexit


# SELinux
echo
if [ ${skip_disable_selinux} = true ]; then
	echo "Skipping SELinux configuration"
else
	echo "Checking SELinux configuration status"
	if [ `getenforce` = Enforcing ]; then
		echo "SELinux runtime is enforced, setting SELinux runtime to permissive"
		setenforce 0
	else
		echo "SELinux runtime is not enabled, no changes needed"
	fi

	FILE=/etc/selinux/config
	echo
	if [ ! -f ${FILE}.${DATE} ]; then
		echo "Creating backup ${FILE}.${DATE}"
		cp -p ${FILE} ${FILE}.${DATE}
	fi
	set +o errexit
	grep -q '^SELINUX[ 	]*=' ${FILE}
	if [ $? -eq 1 ]; then
		echo "Setting SELinux to permissive persistently"
		echo "SELINUX=permissive" >> ${FILE}
	else
		grep -q '^SELINUX[ 	]*=enforcing' ${FILE}
		if [ $? -eq 0 ]; then
			echo "Changing SELinux from enforcing to permissive persistently"
			sed -i 's/^SELINUX[ 	]*=.*/SELINUX=permissive/' ${FILE}
			if [ $? -ne 0 ]; then
				echo "Failed configuring SELinux to permissive in ${FILE}"
				exit 6
			fi
		else
			echo "SELinux already configured permissive or disabled persistently, no changes needed"
		fi
	fi

	echo
	echo "Checking changes on ${FILE}"
	diff ${FILE}.${DATE} ${FILE}
fi
set -o errexit


# ntp
set +o errexit
echo
if [ ${skip_ntp_check} = true ]; then
	echo "Skipping NTP configuration"
else
	echo
	echo "Stopping ntpd - ignore if already stopped"
	echo
	systemctl stop ntpd
	sleep 1
	for ntp_service in ntpdate ntpd; do
		echo
		echo "Starting and enabling ${ntp_service}"
		systemctl start ${ntp_service} && systemctl enable ${ntp_service}
		if [ $? -ne 0 ]; then
			echo "Failure starting and enabling ${ntp_service}"
			echo "boot, master, worker, and proxy nodes must all be in sync via ntp."
				exit 9
		fi
		sleep 1
	done
fi
set -o errexit


# sysctl OS tuning
echo
if [ ${skip_os_tuning} = true ]; then
	echo "Skipping OS tuning"
else
	FILE=/etc/sysctl.conf
	echo
	if [ ! -f ${FILE}.${DATE} ]; then
		echo "Creating backup ${FILE}.${DATE}"
		cp -p ${FILE} ${FILE}.${DATE}
	fi

	echo
	echo "Current vm.max_map_count setting:"
	sysctl vm.max_map_count
	sed -i '/^vm.max_map_count[ 	]*=/d' ${FILE}
	echo "vm.max_map_count=${VM_MAX_MAP_COUNT}" >> ${FILE}

	echo
	echo "Current net.ipv4.ip_forward setting:"
	sysctl net.ipv4.ip_forward
	sed -i '/^net.ipv4.ip_forward[ 	]*=/d' ${FILE}
	echo "net.ipv4.ip_forward=1" >> ${FILE}

	echo
	echo "Checking changes on ${FILE}"
	set +o errexit
	diff ${FILE}.${DATE} ${FILE}
	set -o errexit

	echo
	echo "Configuring from ${FILE}"
	sysctl -w -p ${FILE}
fi

# Transparent huge pages
# Once we have dedicated workers, only do this for Redis and Mongo workers
set -o errexit
echo
if [ ${is_worker} = true -a ${skip_os_tuning} = false ]; then
	echo
	echo "Configuring transparent huge pages tunining on worker"
	rm -f /etc/init.d/disable-transparent-hugepages
	cp -av deployCfC/support/disable-transparent-hugepages /etc/init.d/
	chmod 755 /etc/init.d/disable-transparent-hugepages
	service disable-transparent-hugepages start
	chkconfig --add disable-transparent-hugepages
else
	echo "Skipping transparent huge pages tuning on worker"
fi


# Log Rotate
echo
if [ ${skip_logrotation_configuration} = true ]; then
	echo "Skipping log rotation configuration"
else
	echo
	echo "Installing log rotation"
	if [ -e /etc/logrotate.d/connections-docker-container ]; then
		rm -f /etc/logrotate.d/connections-docker-container
	fi
	#cp ${DEPLOY_CFC_DIR}/support/connections-docker-container /etc/logrotate.d/connections-docker-container
	#chmod 644 /etc/logrotate.d/connections-docker-container

	mkdir -p ${RUNTIME_BINS}/etc/logrotate.d
	rm -f ${RUNTIME_BINS}/etc/logrotate.d/connections-docker-container
	cp ${DEPLOY_CFC_DIR}/support/connections-docker-container ${RUNTIME_BINS}/etc/logrotate.d/connections-docker-container
	chmod 644 ${RUNTIME_BINS}/etc/logrotate.d/connections-docker-container
	chmod 755 ${RUNTIME_BINS}/etc/logrotate.d

	echo "Performing crontab maintenance"
	tmp_file=`mktemp || exit 102`
	pushd ${DEPLOY_CFC_DIR}/support > /dev/null
	for script in logrotate.sh; do
		mkdir -p ${RUNTIME_BINS}/bin
		rm -f ${RUNTIME_BINS}/bin/${script}
		cp ${script} ${RUNTIME_BINS}/bin/${script}
		set +o errexit
		crontab -l > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			echo "Detected existing crontab:"
			crontab -l
			crontab -l | egrep -v ${RUNTIME_BINS}/bin/${script} >> ${tmp_file}
		fi
		set -o errexit
		cron_entry="7 * * * * ${RUNTIME_BINS}/bin/${script} >> ${LOG_FILE}-logrotate.log 2>&1"
		echo "${cron_entry}" >> ${tmp_file}
		echo "Installing crontab:"
		cat ${tmp_file}
		set +o errexit
		crontab ${tmp_file}
		if [ $? -ne 0 ]; then
			echo "Unable to install crontab"
			exit 104
		fi
		set -o errexit
		rm -f ${tmp_file}
	done
	popd > /dev/null
fi

