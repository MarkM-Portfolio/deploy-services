#! /bin/bash
# Initial author: on Sun Feb  5 16:59:33 GMT 2017
#
# History:
# --------
# Sun Feb  5 16:59:33 GMT 2017
#	Initial version
#
#

. ./00-all-config.sh

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

function error_cleanup () {
	# ensure SSH keys are setup
	rm -rf ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}
	echo
	echo "Failed to setup SSH keys across all nodes.  Address problem and re-run."
	echo
	echo "$2"
	echo
	exit $1
}

function distributeSSHKey () {
	set +o errexit
	node=$1
	resolve_ip ${node}	# result in resolve_ip_return_result
	if [ $? -ne 0 ]; then
		echo "Unable to resolve ${node}"
		exit 1
	else
		ip=${resolve_ip_return_result}
	fi

	echo "Distributing SSH key to ${node} (${ip})"
	if [ ${skip_ssh_prompts} = true ]; then
		if [ ${user} != root ]; then
			HOME=`eval echo ~${user}` ${setuid_bin} ${user} ${sshpass_bin} -p ${user_passwd} ssh-copy-id ${ssh_args} -i ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}/id_rsa.pub ${ip} || error_cleanup 4 "id_rsa.pub copy failure to node ${user}@${node} (no prompt)"
		else
			sshpass -p ${user_passwd} ssh-copy-id ${ssh_args} -i ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}/id_rsa.pub ${ip} || error_cleanup 4 "id_rsa.pub copy failure to node root@${node} (no prompt)"
		fi
	else
		echo
		echo "**** Enter 'yes' to accept certificate when prompted ****"
		echo "**** Then enter password when prompted ****"
		echo
		if [ ${user} != root ]; then
			HOME=`eval echo ~${user}` ${setuid_bin} ${user} ssh-copy-id -i ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}/id_rsa.pub ${ip} || error_cleanup 5 "id_rsa.pub copy failure to node ${user}@${node}"
		else
			ssh-copy-id -i ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}/id_rsa.pub ${ip} || error_cleanup 5 "id_rsa.pub copy failure to node root@${node}"
		fi
	fi
}


cd ${WORKING_DIR}

echo

# Special case logic on add worker
if [ "${add_worker}" != "" ]; then
	if [ ! -f ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}/id_rsa ]; then
		echo "SSH keys must already exist to add node"
		exit 5
	fi
	setup_host_list="${add_worker}"
else
	setup_host_list="${HOST_LIST}"
fi

# Setup SSH keys
setup_ssh_keys=true
if [ ${skip_ssh_key_generation} = true ]; then
	echo
	echo "Bypassing SSH key generation"
	if [ "${pregenerated_private_key_file}" != "" ]; then
		echo
		echo "Using provided SSH private key: ${pregenerated_private_key_file}"
		if [ ${HOSTNAME} = ${BOOT} ]; then
			rm -rf ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}
			mkdir -p ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}
			cp -p "${pregenerated_private_key_file}" ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}/id_rsa
			echo "Generating public key from provided private key"
			ssh-keygen -f ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}/id_rsa -y > ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}/id_rsa.pub
			echo "Validating SSH keys"
			for ssh_key in ${SSH_KEY_FILES_BOOT}; do
				ssh-keygen -l -f ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}/${ssh_key}
			done
			echo "OK"
		fi
	else
		echo "SSH keys must be already prepared and distributed"
	fi
	setup_ssh_keys=false
else
	if [ ${skip_ssh_prompts} = false ]; then
		if [ -f ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}/id_rsa ]; then
			echo
			echo "SSH keys already setup"
			printf "Setup SSH keys anyway [n]: "
			read answer
			if [ "${answer}" != yes -a "${answer}" != y ]; then
				echo "Not setting up SSH keys"
				setup_ssh_keys=false
			fi
		fi
	fi
fi
if [ ${setup_ssh_keys} = true ]; then
	echo
	echo "Creating SSH keys"

	mkdir -p ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}
	set +o errexit
	if [ ${skip_ssh_prompts} = true ]; then
		echo y | ssh-keygen -b 4096 -t rsa -f ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}/id_rsa -N '' || error_cleanup 2 "ssh-keygen failure (no prompt)"
		echo
	else
		ssh-keygen -b 4096 -t rsa -f ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}/id_rsa -N '' || error_cleanup 3 "ssh-keygen failure"
	fi
	set -o errexit
fi

if [ ${user} != root ]; then
	chown -R ${user} ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}
fi
if [ ${setup_ssh_keys} = true -o "${pregenerated_private_key_file}" != "" ]; then
	chmod 600 ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}/id_rsa
	if [ ${skip_ssh_key_distribution} = false ]; then
		for node in ${setup_host_list}; do
			distributeSSHKey ${node}
		done
	else
		echo "SSH keys must be already prepared and distributed"
	fi
fi

# Validate
if [ ${skip_ssh_key_validation} = false ]; then
	validateSSHKeys ${setup_host_list}
	if [ $? -ne 0 ]; then
		echo "Failed"
		exit 1
	fi
else
	echo
	echo "Skipping SSH key validation"
fi

