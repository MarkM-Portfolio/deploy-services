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


# More extensive checks later through lsb-release, but may not have that installed
# yet, and we need to know the target environment is compatible with the automation
echo
if [ -f /etc/redhat-release ]; then
	echo "RedHat detected"
else
	echo "Only RedHat and CentOS supported"
	exit 7
fi

# Check supported upgrade path
echo
if [ ${upgrade} = true ]; then
	compareVersions ${CFC_VERSION} ${deployed_cfc_version}
	set +o nounset		# reset in compareVersions
	if [ ${comparison_result} = 1 ]; then
		echo "${deployed_cfc_version} -> ${CFC_VERSION} is not a supported upgrade path"
		exit 10
	fi
fi

# hostname requirements
echo
printf "Checking ${HOSTNAME} is a Fully Qualified Domain Name (FQDN)"
set +o errexit
echo ${HOSTNAME} | grep -q '\.'
if [ $? -eq 1 ]; then
	echo
	echo "Hostname must be a Fully Qualified Domain Name"
	echo "Reconfigure system, reboot, and ensure 'hostname -f' shows a FQDN"
	echo "Current hostname:  ${HOSTNAME}"
	exit 4
else
	echo " - OK"
fi
echo
printf "Checking ${HOSTNAME} is all lower case"
echo ${HOSTNAME} | grep -q '[A-Z]'
if [ $? -eq 0 ]; then
	echo
	echo "Hostname must be all lower case"
	echo "Current hostname:  ${HOSTNAME}"
	exit 5
else
	echo " - OK"
fi
set -o errexit

# Configure external proxy if using one and then validating it
if [ "${ext_proxy_url}" != "" ]; then
        echo
        echo "Configuring external proxy ${ext_proxy_url}"
        export http_proxy=${ext_proxy_url}
        export https_proxy=${ext_proxy_url}
        export ftp_proxy=${ext_proxy_url}
        export no_proxy=localhost,127.0.0.1
        for host in ${HOST_LIST[@]}; do
                export no_proxy=$no_proxy,$host
        done
        set +o errexit
        curl -s -f https://storage.googleapis.com/kubernetes-release/release/stable.txt | grep -q '^v'
        if [ $? -ne 0 ]; then
                echo "Problem accessing the internet. Please check your proxy server: ${ext_proxy_url}"
                exit 101
        else
                echo "Validation of external proxy complete"
        fi
        set -o errexit
fi

echo
printf "Checking for cloud-init"
if [ -f /etc/cloud/cloud.cfg -a ${skip_cloud_init_check} = false ]; then
	echo
	echo "cloud-init not supported.  If configuration changes have been made manually"
	echo "to /etc/cloud/cloud.cfg to avoid conflicts with IBM Connections, use the bypass"
	echo "flag --skip_cloud_init_check to skip this check."
	exit 11
else
	echo " - OK"
fi

if ${is_boot}; then
	if [ ${upgrade} = true ]; then
		# Temporarily add /usr/local/bin to the PATH, as that is where kubectl is located in 6005
		PATH=/usr/local/bin:$PATH; export PATH
		if ! [ "`kubectl get namespaces | grep ${NAMESPACE} | awk '{print $1}'`" == "${NAMESPACE}" ]; then
			echo "Unable to find a namespace called ${NAMESPACE}. When upgrading, make sure to use the same namespace that was used during initial install."
			echo "List of namespaces:"
			kubectl get namespaces
			exit 200
		fi
		if [ "${deployed_cfc_version}" = "1.2.1" ]; then
			image=cfc-installer
		else
			image=${icp_image_name}
		fi	
		if [ "${cfc_ee_url}" = "" ]; then
			if echo `docker images | grep ibmcom/${image} | awk '{ print $2 }'` | grep -q ee; then
				echo "Unsupported upgrade path found: IBM Cloud private EE -> IBM Cloud private CE"
				echo "Please use the --cfc_ee_url flag to upgrade IBM Cloud private EE"
				exit 10
			fi
		else
			if echo `docker images | grep ibmcom/${image} | awk '{ print $2 }'` | grep -v -q ee; then
				echo "Unsupported upgrade path found: IBM Cloud private CE -> IBM Cloud private EE"
				echo "Please remove the --cfc_ee_url flag to upgrade IBM Cloud private CE"
				exit 10
			fi
		fi
	fi

	# Check ${cfc_ee_url} has the required files
	if [ "${cfc_ee_url}" != "" ]; then
		# List of required fies
		compareVersions ${CFC_VERSION} 2.1.0.1
		if [ ${comparison_result} = 1 ]; then
			# CFC_VERSION < 2.1.0.1
			required_files=( "ibm-cloud-private-installer-${cfc_archive_version}.tar.gz" "ibm-cloud-private-x86_64-${cfc_archive_version}.tar.gz" )
		else
			required_files=( "ibm-cloud-private-x86_64-${cfc_archive_version}.tar.gz" )
		fi

		echo
		# Check if ${cfc_ee_url} is a URL
		if echo "${cfc_ee_url}" | egrep -q 'http.*://|ftp://'; then
			echo "Detected that the cfc_ee_url flag ${cfc_ee_url} is a URL"
			input_type=url

			# Check the necessary files exist in ${cfc_ee_url}
			echo
			echo "Checking required files exist at URL"
			for i in "${required_files[@]}"; do
				if echo `curl -s ${cfc_ee_url}/` | grep -q $i; then
					echo "Found valid file $i at ${cfc_ee_url}"
				else
					echo "$i was not found at ${cfc_ee_url}"
					exit 2
				fi
			done

		else	# Assuming ${cfc_ee_url} is a local directory and not a URL
			echo "Detected that the cfc_ee_url flag ${cfc_ee_url} is a local directory"
			input_type=local
			# Check the necessary files exist in ${cfc_ee_url}
			echo
			for i in "${required_files[@]}"; do
				if [ -f ${cfc_ee_url}/$i ]; then
					echo "Found valid file $i at ${cfc_ee_url}"
				else
					echo "$i was not found at ${cfc_ee_url}"
					exit 2
				fi
			done
		fi	
	fi
fi
