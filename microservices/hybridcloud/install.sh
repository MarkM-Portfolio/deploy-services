#!/bin/bash -
#title           :install.sh
#description     :This script will setup kubernetes environment along with
#                 deployment of all connection applications.
#version         :0.1
#usage		       :bash install.sh
#==============================================================================

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

PATH=/usr/bin:/bin:/usr/sbin:/sbin:${PATH}
export PATH
umask 022

ICP_CONFIG_DIR=/opt/ibm/connections
ICP_CONFIG_FILE=config.json
jq=${ICP_CONFIG_DIR}/jq/bin/jq

conn_locn=$(cat $ICP_CONFIG_DIR/$ICP_CONFIG_FILE | $jq -r '.connections_location')
RUNTIME_BINS=${conn_locn}/runtime

PATH=${PATH}:${RUNTIME_BINS}/bin
export PATH

master_hostname=master.cfc

if [ "`id -u`" != 0 ]; then
	echo "Must run as root"
	exit 1
fi

# Support different invocation locations associated with this script at different times
hybridcloud_dir="`dirname \"$0\"`"
echo
cd "${hybridcloud_dir}" > /dev/null
echo "Changed location to hybridcloud:"
echo "	`pwd`"
echo "	(relative path:  ${hybridcloud_dir})"
echo

cd bin
starter_stack=false

starter_stack_options="orientme customizer elasticsearch"

function usage() {
		echo
		echo "usage:  install.sh [-n|--namespace=<namespace>]"
		for starter_stack_option in ${starter_stack_options}; do
			echo "		   [-ip|--installPack ${starter_stack_option}]"
		done
		echo "		   [-cu|--cfc_user=<cfcusername>]"
		echo "		   [-cp|--cfc_pass=<cfcpassword>]"	
		echo "		   [-h|--help]"
		echo
		echo "All components are deployed by default if Starter Stack option not provided"
		echo
}

CFC_USER=""
CFC_PASS=""
set +o nounset
if [ -z "$CFC_ADMIN_USER" ];then
        CFC_ADMIN_USER=""
fi
if [ -z "$CFC_ADMIN_PASS" ];then
        CFC_ADMIN_PASS=""
fi

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
	-n|--namespace)
		echo "Script performed with -n|--namespace. Services will be deployed in the $2 namespace"
		NAMESPACE="$2"
		if [[ ${NAMESPACE} = "default" || ${NAMESPACE} = "kube-system" ]]; then
			echo "Must set namespace to an existing namespace other than default or kube-system"
			exit 1
		else
			sed -i "s/connections/${NAMESPACE}/" common_values.yaml
		fi
		shift
		shift
		;;
	-ip|--installPack)
		starter_stack=true
		INSTALL_STACK="$2"
		if [ "${INSTALL_STACK}" = customiser ]; then
			INSTALL_STACK=customizer	# UK/IE -> US
		fi

		starter_stack_valid=false
		for starter_stack_option in ${starter_stack_options}; do
			if [ "${INSTALL_STACK}" = ${starter_stack_option} ]; then
				starter_stack_valid=true
				break
			fi
		done
		if [ ${starter_stack_valid} = false ]; then
			echo
			echo "Invalid Starter Stack option"
			usage
			exit 1
		fi
		echo "Script performed with -ip|--installPack. The stack ${INSTALL_STACK} will be deployed."

		shift
		shift
		;;
	-cu|--cfc_user)
		CFC_USER="$2"
		shift
		shift
		;;
	-cp|--cfc_pass)
		CFC_PASS="$2"
		shift
		shift
		;;
	*)
		usage
		exit 0
		;;
esac
done

if [ -z "$NAMESPACE" ]; then
  NAMESPACE='connections'
fi

if [ -z "${CFC_USER}" -a "${CFC_PASS}" ] || [ "${CFC_USER}" -a -z "${CFC_PASS}" ]; then
  echo "ICp username (-cu) and ICp password (-cp) flags must be used together"
  exit 1
fi
set -o nounset

echo
echo "Checking if ${NAMESPACE} namespace exists"
set +o errexit
kubectl get namespace ${NAMESPACE}
if [ $? -ne 0 ]; then
	echo "Unable to find namespace ${NAMESPACE}. Be sure to use the same namespace that was used during deployCfC."
	exit 1
fi
set -o errexit

# Check a node exists with the label infrastructure when elasticsearch is going to be deployed
if [ ${starter_stack} = false ] || [[ "${INSTALL_STACK}" == "elasticsearch" ]]; then
	set +o errexit
	kubectl get nodes --show-labels | grep "type=infrastructure" | grep -w "Ready"
	if [ $? -ne 0 ]; then
		echo
		echo "**WARNING**"                
		echo "Unable to find a node with the label type=infrastructure."
		echo "It is highly recommended to deploy a minimum of 3 nodes with this label for Elasticsearch to be installed on."
		echo "You can use the flag --add_infra_worker with deployCfC.sh to add such a node."
		echo "Refer to the documentation for more info."
		echo "Proceeding with unsupported install in 5 seconds (type CTRL+C to quit).."
		secs=$((5))
		while [ $secs -gt 0 ]; do
			echo -ne "$secs\033[0K\r"
			sleep 1
			: $((secs--))
		done
		echo
	fi
fi
set -o errexit

# Update the icHost required for connections-env installation
ic_host=`kubectl get configmap topology-configuration -n ${NAMESPACE} -o jsonpath='{.data.ic-host}'`
ic_internal=`kubectl get configmap topology-configuration -n ${NAMESPACE} -o jsonpath='{.data.ic-internal}'`
sed -i "s/^  host:.*/  host: ${ic_host}/" common_values.yaml
sed -i "s/^  internal:.*/  internal: ${ic_internal}/" common_values.yaml

if [ "${CFC_USER}" != "" ];then
	cfcuser=${CFC_USER}
elif [ "${CFC_ADMIN_USER}" != "" ];then
	cfcuser=${CFC_ADMIN_USER}
else
	cfcuser="admin"
fi

if [ "${CFC_PASS}" != "" ];then
	cfcpass=${CFC_PASS}
elif [ "${CFC_ADMIN_PASS}" != "" ];then
	cfcpass=${CFC_ADMIN_PASS}
else
	cfcpass="admin"
fi

# Duplicate tasks from CfC install until day-to-day upgrade is implemented
bash ./install-supplemental.sh

# Import images and push to docker registry
bash ./setup.sh -n ${NAMESPACE} -uc $cfcuser -ucp $cfcpass -fs

# Deployment of applications e.g. kubectl create -f templates/webclient/deployment.yml
if [ ${starter_stack} = true ]; then
	bash ./deploy.sh -ip ${INSTALL_STACK}
else
	bash ./deploy.sh
fi

# Produce sanity test URL
set +o errexit

echo
master_ip=""
master_ip_lines=`grep -v '^#' /etc/hosts | grep "[ 	]${master_hostname}[ 	]*" | wc -l`
if [ ${master_ip_lines} -eq 1 ]; then
	echo "Resolving ${master_hostname} using /etc/hosts"
	master_ip=`grep -v '^#' /etc/hosts | grep "[ 	]${master_hostname}[ 	]*" | awk '{ print $1 }'`
fi
if [ "${master_ip}" = "" ]; then
	echo "Resolving ${master_hostname} using host"
	master_ip=`host ${master_hostname} | grep "has address" | head -1 | awk '{ print $NF }'`
fi
if [ "${master_ip}" = "" ]; then
	echo "Resolving ${master_hostname} using ping"
	master_ip=`ping -c 1 ${master_hostname} 2>&1 | grep '^PING ' | grep 'bytes of data.$' | awk '{ print $3 }' | sed -e 's/(//' -e 's/)//'`
fi
if [ "${master_ip}" = "" ]; then
	echo "${master_hostname} is not resolvable"
	echo "Substitute \"${master_hostname}\" with the IP address of the master server or master VIP before pasting into browser"
	master_ip=${master_hostname}
fi

test_status_port=`kubectl get svc -n ${NAMESPACE} sanity -o jsonpath='{.spec.ports[].nodePort}'`
exit_status=$?
if [ ${exit_status} -ne 0 -o "`echo ${test_status_port} | sed -e 's/#/@/g' -e 's/^-//' -e 's/[0-9]/#/g' -e 's/#//g'`" != "" -o "${test_status_port}" = "" ]; then
	echo
	echo "Error determining IBM Connections test status port"
	echo "	Found:  ${test_status_port}"
	echo "	Exit code:  ${exit_status}"
else
	echo
	echo "IBM Connections test status:  http://${master_ip}:${test_status_port}"
fi
set -o errexit

echo
echo "IBM Connections Component Pack deployment complete"
exit 0

