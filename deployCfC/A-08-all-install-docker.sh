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

echo
if [ ${skip_docker_deployment} = true ]; then
	echo "Not deploying Docker"
else
	# Follow Docker configuration steps for using external proxy
	if [ "${ext_proxy_url}" != "" ]; then
		FILE=${DOCKER_EXT_PROXY_DIR}/${DOCKER_EXT_PROXY_CONFIG_FILE}
		echo
		if [ -f ${FILE} ]; then
			echo "External proxy setup file for Docker exists: ${FILE}"
			if [ ! -f ${FILE}.${DATE} ]; then
				echo "Creating backup ${FILE}.${DATE}"
				cp -p ${FILE} ${FILE}.${DATE}
			fi
		else
			mkdir -p ${DOCKER_EXT_PROXY_DIR}
		fi
		echo "Configuring external proxy ${ext_proxy_url} for Docker"
		echo "Adding external proxy details to file ${FILE}"
		echo "[Service]" > ${FILE}
		echo "Environment=\"HTTP_PROXY=${ext_proxy_url}/\" \"HTTPS_PROXY=${ext_proxy_url}/\" \"NO_PROXY=localhost,127.0.0.1,master.cfc\"" >> ${FILE}
		echo "Reloading system daemon configuration"
		systemctl daemon-reload
	fi
	echo
	echo "Setting up Docker repo, installing Docker, testing Docker"
	set -o xtrace

	rhel_distributor=`cat ${LOG_FILE}-rhel_distributor.txt`
	if [ "${use_docker_ee}" != "" ]; then
		docker_distribution=ee
		if [ ${rhel_distributor} = RedHatEnterpriseServer ]; then
			rhel_major_version=`cat ${LOG_FILE}-rhel_major_ver.txt`
			echo "${rhel_major_version}" > /etc/yum/vars/dockerosversion
			set +o errexit
			echo ${use_docker_ee} | grep -q '/ee/rhel/sub'
			if [ $? -eq 0 ]; then
				echo "Found Docker Enterprise Edition Trial license for RHEL"
				subscription_suffix=""
			else
				echo ${use_docker_ee} | grep -q '/ee/linux/'
				if [ $? -eq 0 ]; then
					echo "Found Docker Enterprise Edition license for Linux"
					subscription_suffix="/rhel"
				else
					echo "Incompatible subscription:  ${use_docker_ee}"
					echo ${use_docker_ee} | grep -q '/ee/centos/sub'
					if [ $? -eq 0 ]; then
						echo "Found Docker Enterprise Edition Trial license for CentOS instead of RHEL"
					fi
					exit 5
				fi
			fi
			yum-config-manager --enable rhel-${rhel_major_version}-server-extras-rpms
			if [ $? -ne 0 ]; then
				echo "Not necessarily a fatal error unless container-selinux failed to deploy"
			fi
			set -o errexit
		elif [ ${rhel_distributor} = CentOS ]; then
			set +o errexit
			echo ${use_docker_ee} | grep -q '/ee/centos/sub'
			if [ $? -eq 0 ]; then
				echo "Found Docker Enterprise Edition Trial license for CentOS"
				subscription_suffix=""
			else
				echo ${use_docker_ee} | grep -q '/ee/linux/'
				if [ $? -eq 0 ]; then
					echo "Found Docker Enterprise Edition license for Linux"
					subscription_suffix="/centos"
				else
					echo "Incompatible subscription:  ${use_docker_ee}"
					echo ${use_docker_ee} | grep -q '/ee/rhel/sub'
					if [ $? -eq 0 ]; then
						echo "Found Docker Enterprise Edition Trial license for RHEL instead of CentOS"
					fi
					exit 6
				fi
			fi
			set -o errexit
		else
			echo "Unknown OS:  ${rhel_distributor}"
			exit 7
		fi
		mkdir -p /etc/yum/vars
		echo "${use_docker_ee}${subscription_suffix}" > /etc/yum/vars/dockerurl
		yum-config-manager --add-repo ${use_docker_ee}${subscription_suffix}/docker-ee.repo
		yum-config-manager --disable docker*
		if [ "${alt_docker_version}" != "" ]; then
			yum-config-manager --enable docker-ee-stable-${alt_docker_version}
		else
			yum-config-manager --enable docker-ee-stable
		fi
	else
		docker_distribution=ce
		yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
		yum-config-manager --disable docker*
		yum-config-manager --enable docker-ce-stable
	fi
	${YUM} makecache fast
	mkdir -p ${DOCKER}
	set +o errexit
	if [ ${upgrade} = true ]; then
		# XYZZY 6726
		#if [ "${alt_docker_version}" != "" ]; then
		if [ "${alt_docker_version}" = "NEVER_GONNA_HAPPEN" ]; then
			echo "Running in upgrade mode with specified Docker version ${alt_docker_version}, determining compatibility"
			deployed_docker_version=`rpm -qa --queryformat '%{VERSION}\n' 'docker-[ce]e'`
			if [ `echo ${deployed_docker_version} | wc -l` -ne 1 ]; then	# too many results?
				echo "Can't determine deployed Docker version, Docker must be upgraded manually, then re-run Connections upgrade"
				echo "	${deployed_docker_version}"
				exit 99
			fi
			echo "Deployed Docker version:  ${deployed_docker_version}"
			compareVersions ${deployed_docker_version} ${alt_docker_version}
			set +o errexit	# reset in compareVersions
			if [ ${comparison_result} -eq 0 ]; then
				echo "Deployed Docker version ${deployed_docker_version} compatible with specified Docker version ${alt_docker_version}, Docker upgrade can continue"
			elif [ ${comparison_result} -eq 1 ]; then
				echo "Deployed Docker version ${deployed_docker_version} less than specified Docker version ${alt_docker_version}, Docker upgrade can continue"
			else
				echo ${deployed_docker_version} | grep -q "^${alt_docker_version}"
				if [ $? -eq 0 ]; then
					# Another variation of (comparison_result == 0)
					echo "Deployed Docker version ${deployed_docker_version} in the same version family of specified Docker version ${alt_docker_version}, Docker upgrade can continue"
				else
					echo "Deployed Docker version ${deployed_docker_version} greater than specified Docker version ${alt_docker_version}, Docker must be downgraded manually, then re-run Connections upgrade"
					exit 99
				fi
			fi
			${YUM} -y ${YUM_INSTALL_DOCKER_OVERRIDE_FLAGS} update docker-${docker_distribution}-${DOCKER_VERSION}*
			exit_status=$?
		else
			# XYZZY 6726
			#${YUM} -y ${YUM_INSTALL_DOCKER_OVERRIDE_FLAGS} update docker-${docker_distribution}-*
			#exit_status=$?
			exit_status=0
		fi
	else
		${YUM} -y ${YUM_INSTALL_DOCKER_OVERRIDE_FLAGS} install docker-${docker_distribution}-${DOCKER_VERSION}*
		exit_status=$?
	fi
	set -o errexit
	yum-config-manager --disable docker*
	set +o xtrace
	if [ ${exit_status} -ne 0 ]; then
		if [ ${rhel_distributor} = RedHatEnterpriseServer ]; then
			rhel_major_version=`cat ${LOG_FILE}-rhel_major_ver.txt`
			echo "If docker deployment failed due to a missing dependency on"
			echo "the RPM container-selinux, this is usually found in a special RHEL repo called"
			echo "rhel-${rhel_major_version}-server-extras-rpms."
			echo "Enable this repo via yum-config-manager or subscription-manager,"
			echo "depending on how your subscription is managed."
		else
			echo "Failed to deploy Docker"
		fi
		exit ${exit_status}
	fi

	retry=1
	max_retry=3	# If no success after 3 retries, likely never will work
	success=false
	set +o errexit
	set -o xtrace
	while [ ${retry} -le ${max_retry} ]; do
		set -o xtrace
		systemctl start docker
		if [ $? -ne 0 ]; then
			set +o xtrace
			echo
			echo "Retrying Docker start (${retry}/${max_retry})"
			sleep 10
			set -o xtrace
			systemctl stop docker
			set +o xtrace
			sleep 5
		else
			success=true
			break
		fi
		retry=`expr ${retry} + 1`
	done
	set +o xtrace
	set -o errexit
	if [ ${success} = false ]; then
		echo
		systemctl status docker.service --full --lines=200
		echo
		echo "Failure starting Docker"
		exit 66
	fi
	systemctl enable docker.service
	echo
	docker info
fi
echo

runDockerHelloWorldTest || exit 1
set -o errexit

easy_install pip
pip install "docker-py>=${PIP_VERSION}"

echo
docker info

echo "Docker deployment complete"

