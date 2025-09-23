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

function init_k8s_cluster_context () {
	set +o errexit

	if ${is_master_HA}; then
		master=${master_HA_vip}
	else
		master=${MASTER_LIST}
	fi

	compareVersions ${CFC_VERSION} 2.1.0.1
	set -o errexit
	if [ ${comparison_result} = 1 ]; then
		# CFC_VERSION < 2.1.0.1
		token_raw=`curl -s -k -H "Content-Type: application/json" -X POST -d "{\"uid\": \"${ADMIN_USER}\", \"password\": \"${ADMIN_PASSWD}\"}" https://${master}:8443/acs/api/v1/auth/login?_timestamp=$(date +%s)`
		error_status=$?
		token=`echo ${token_raw} | awk -F\" '{ print $4 }'`

		cluster=cfc
		cluster_context=cfc
		cluster_credentials=user
		namespace_args=""
	else
		token_raw=`curl -s -k -H "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" -X POST -d "grant_type=password&username=${ADMIN_USER}&password=${ADMIN_PASSWD}&scope=openid" https://${master}:8443/idprovider/v1/auth/identitytoken`
		error_status=$?
		token=`echo ${token_raw} | awk -F\" '{ print $22 }'`

		cluster=master.cfc
		cluster_context=master.cfc-context
		cluster_credentials=master.cfc-user
		namespace_args="--namespace=default"
	fi

	if [ ${debug} = true ]; then
		echo
		echo "Raw token:  ${token_raw}"
		echo
	fi

	set +o errexit
	echo ${token} | egrep -q 'Bad Request'\|'Bad Gateway'
	if [ $? -eq 0 -o ${error_status} -ne 0 -o "${token}" = "" ]; then
		echo "Unable to parse token for Kubernetes cluster context (${exit_status})"
		echo
		echo "Raw token:"
		echo "${token_raw}"
		echo
		echo "Parsed token:  ${token}"
		return 3
	fi

	set -o errexit
	set -o xtrace
	kubectl config set-cluster ${cluster} --server=https://${master}:8001 --insecure-skip-tls-verify=true && \
		kubectl config set-context ${cluster_context} --cluster=${cluster} && \
		kubectl config set-credentials ${cluster_credentials} --token=${token} && \
		kubectl config set-context ${cluster_context} --user=${cluster_credentials} ${namespace_args} && \
		kubectl config use-context ${cluster_context}
	error_status=$?
	set +o xtrace
	if [ ${error_status} -ne 0 ]; then
		echo
		echo "Failure initializing Kubernetes cluster context"
		return 1
	fi

	# XYZZY:  set token expiration to longer than 1 hour but not infinite
	echo "Setting non-expiring token so you don't have to do that step every hour"
	token_name=`kubectl describe serviceaccounts default | grep Tokens | awk '{ print $2 }'`
	token_secret=`kubectl describe secret ${token_name} | grep token: | awk '{ print $2 }'`
	kubectl config set-credentials user --token=${token_secret}
}

verifyOperationalServer

if [ ${is_master} = true ]; then
	sleep 15	# final wait delay
fi

# HA diagnostics
if [ \( ${is_master_HA} = true -a ${is_master} = true \) -o \
     \( ${is_proxy_HA} = true -a ${is_proxy} = true \) ]; then
	echo
	ip addr
	echo
	set +o errexit
	arp -a | while read line; do
		for host in ${HOST_LIST} master.cfc; do
			echo ${line} | grep -q ${host}
			if [ $? -eq 0 ]; then
				echo ${line}
			fi
		done
	done
	set -o errexit
fi

echo
if [ ${skip_k8s_cluster_config} = true ]; then
	echo "Skipping Kubernetes cluster context initialization and token timeout"
else
	number_retries=4
	retry_wait_time=30
	counter=1
	while [ ${counter} -le ${number_retries} ]; do
		echo
		echo "Initializing Kubernetes cluster context (${counter}/${number_retries})"
		init_k8s_cluster_context
		exit_status=$?
		set -o errexit
		if [ ${exit_status} -eq 0 ]; then
			break
		else
			if [ ${counter} -eq ${number_retries} ]; then
				break
			else
				echo
				echo "Retrying in ${retry_wait_time}s"
				sleep ${retry_wait_time}
			fi
		fi
		counter=`expr ${counter} + 1`
	done
	if [ ${exit_status} -ne 0 ]; then
		echo
		echo "Failure configuring Kubernetes cluster context (${exit_status})"
		exit 10
	fi
fi

echo
kubectl version

