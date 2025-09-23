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

# Configure helm client and proxy
if ${is_master_HA}; then
	master_ip=${master_HA_vip}
else
	resolve_ip ${MASTER_LIST}	# result in resolve_ip_return_result
	master_ip=${resolve_ip_return_result}
	set -o errexit
fi
if ${is_proxy_HA}; then
	proxy_ip=${proxy_HA_vip}
else
	resolve_ip ${PROXY_LIST}	# result in resolve_ip_return_result
	proxy_ip=${resolve_ip_return_result}
	set -o errexit
fi

# Configure external proxy if using one
echo
if [ "${ext_proxy_url}" != "" ]; then
	echo "Configuring external proxy ${ext_proxy_url}"
	export http_proxy=${ext_proxy_url}
	export https_proxy=${ext_proxy_url}
	export ftp_proxy=${ext_proxy_url}
	export no_proxy=localhost,127.0.0.1,master.cfc
	for host in ${HOST_LIST[@]}; do
		no_proxy=$no_proxy,$host
	done
	if ${is_master_HA}; then
		no_proxy=${no_proxy},${master_ip}
	fi
	if ${is_proxy_HA}; then
		no_proxy=${no_proxy},${proxy_ip}
	fi
fi

# Determine tiller service name
compareVersions ${CFC_VERSION} 2.1.0.1
if [ ${comparison_result} = 1 ]; then	# CFC_VERSION < 2.1.0.1
	tiller_service_name=tiller
	tiller_json_key=nodePort
	setup_helm_nodePort=true
else
	tiller_service_name=tiller-deploy
	tiller_json_key=DOES_NOT_EXIST_ANYMORE
	setup_helm_nodePort=false
fi


# Wait for helm and tiller services to start
set +o errexit

echo
number_retries=20
retry_wait_time=30
counter=1
while [ ${counter} -le ${number_retries} ]; do
	echo "Checking if tiller is ready (${counter}/${number_retries})"
	set -o xtrace
	kubectl get deployment ${tiller_service_name} -n kube-system | awk '$2 == $5 { print $0 }' | grep -q ${tiller_service_name}
	exit_status=$?
	set +o xtrace
	if [ ${exit_status} -ne 0 ]; then
		echo "	tiller is not ready yet, retrying in ${retry_wait_time}s"
		sleep ${retry_wait_time}
		counter=`expr ${counter} + 1`
	else
		echo "tiller is ready"
		break
	fi
done

if [ ${counter} -gt ${number_retries} ]; then
	echo "Maximum attempts reached, giving up"
	exit 1
fi

set -o errexit


echo
mkdir -p /var/lib/helm ${RUNTIME_BINS}/bin ${RUNTIME_BINS}/helm/bin
rm -f ${RUNTIME_BINS}/bin/helm ${RUNTIME_BINS}/helm/bin/helm
if [ ${independent_helm_install} = true ]; then
	echo "Downloading helm ${HELM_VERSION}"
	TMP=`mktemp ${TMP_TEMPLATE}`		# ensure unique
	curl -f https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get > ${TMP}
	bash ${TMP} --version ${HELM_VERSION}
	rm ${TMP}
else
	echo "Retrieving helm from docker image packaged with IBM Cloud private"
	pullFromDocker ${docker_registry}${docker_stream}/helm:${HELM_VERSION}
	if [ $? -ne 0 ]; then
		exit 101
	fi
	set -o errexit

	helm_container=`docker create --name ${TMP_TEMPLATE_SUFFIX} ${docker_stream}/helm:${HELM_VERSION}`
	set +o errexit
	set -o xtrace
	docker cp ${helm_container}:/helm ${RUNTIME_BINS}/bin/helm
	if [ $? -ne 0 ]; then
		echo "Can't find location of helm in container"
		exit 10
	fi
	docker rm -v ${helm_container}		# if creating container from image
	set -o errexit
	set +o xtrace
fi

mv ${RUNTIME_BINS}/bin/helm ${RUNTIME_BINS}/helm/bin/helm
cp ${DEPLOY_CFC_DIR}/helm/helm ${RUNTIME_BINS}/bin/helm
chmod 755 ${RUNTIME_BINS}/bin/helm ${RUNTIME_BINS}/helm/bin/helm
if [ ${setup_helm_nodePort} = true ]; then
	HELM_PORT=$(kubectl get svc ${tiller_service_name} -n kube-system -o jsonpath="{.spec.ports[?(@.name==\"grpc\")].${tiller_json_key}}")
	HELM_HOST=${master_ip}:${HELM_PORT}
	echo "Using ${HELM_HOST}"
	sed -i -e "s/.*DEFAULT_HELM_HOST=.*/DEFAULT_HELM_HOST=${HELM_HOST}/" ${RUNTIME_BINS}/bin/helm
else
	sed -i -e "s/.*DEFAULT_HELM_HOST=.*/DEFAULT_HELM_HOST=not_used/" ${RUNTIME_BINS}/bin/helm
fi

conn_locn=$(cat $ICP_CONFIG_DIR/$ICP_CONFIG_FILE | $jq_bin -r '.connections_location')
if [ ! -d "${conn_locn}" ]; then
	echo "Cannot determine ICp install directory"
	exit 3
fi
# Only create a symlink if it's a default installation as non-default deployment may indicate that changes to the system should be localized
if [ "${conn_locn}" == "/opt/deployCfC" ]; then
	
	set +o errexit
	# Create a softlink to the utility in the default paths 
	ln -sf ${RUNTIME_BINS}/helm/bin/helm /usr/local/bin/helm
	if [ $? -ne 0 ]; then
		echo
		echo 
		echo "******* WARNING *******"
		echo "Failed to create symbolic link to new helm binary"
		echo "Please check your system to see if helm commands will run from the command line and update your path to the helm binary if necessary"
		echo
		echo
	fi
	set -o errexit
fi

helm init --client-only
helm version

echo
echo "helm client configured"

