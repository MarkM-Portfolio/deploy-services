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

function deleteSecretIfExists {
	set +o errexit
	set -o pipefail
	set +o nounset

	if [ "$1" = "" ]; then
		echo "usage:  deleteSecretIfExists sSecretName"
		exit 107
	fi
	secret_name="$1"
	set -o nounset

	if [[ "$(kubectl get secrets -o jsonpath={.items[*].metadata.name} -n ${NAMESPACE})" =~ .*${secret_name}.* ]]; then
		echo
		echo "Deleting ${secret_name} so that we can replace with new."
		kubectl delete secret ${secret_name} -n="${NAMESPACE}"
		echo
	fi

}

# function resets errexit to ignore so calling script must either reset if desired
function createKrb5K8Secret {
	set +o errexit
	set -o pipefail
	set +o nounset

	krb5_keytab_file_path="$1"
	krb5_conf_file_path="$2"
	set_default_krb5=""
	set_secret=""
	set -o nounset

	echo "Kerberos authentication setup is only required for Mail and Calendar integration in SPNEGO environments."
	echo "If you do not require Kerberos you can skip this step by pressing Enter key."
	while [[ -z "${krb5_keytab_file_path}" || -z "${krb5_conf_file_path}" ]]; do
		printf "Enter Krb5_keytab_file_path: "
		read krb5_keytab_file_path

		if [ ${#krb5_keytab_file_path} -eq 0 ]; then
			echo "Skipping this step and using default Krb5 Secret."
			set_default_krb5="true"
			break
		fi

		if ! [ -e "$krb5_keytab_file_path" ]; then
			echo
			echo "Krb5 Keytab file ${krb5_keytab_file_path} does not exist."
			echo "Please start over or Press Enter to skip creating krb5 step..."
			echo
			continue
		fi

		echo
		printf "Enter Krb5_conf_file_path: "
		read krb5_conf_file_path

		if [ ${#krb5_conf_file_path} -eq 0 ]; then
			echo
			echo "Skipping this step and using default Krb5 Secret."
			set_default_krb5="true"
			break
		fi

		if ! [ -e "$krb5_conf_file_path" ]; then
			echo
			echo "Krb5 Keytab Conf file ${krb5_conf_file_path} does not exist."
			echo "Please start over or Press Enter to skip creating krb5 step..."
			echo
			# reset variables as steps are about to run through again.
			krb5_keytab_file_path=""
			krb5_conf_file_path=""
			continue
		fi
	done

	set -o errexit
	cd ${DEPLOY_CFC_DIR}
	if [ "${set_default_krb5}" == "true" ]; then
		kubectl create secret generic krb5keytab --from-file=./secrets/krb5keytab.yml -n="${NAMESPACE}"
	else
		kubectl create secret generic krb5keytab --from-file=${krb5_keytab_file_path} --from-file=${krb5_conf_file_path} -n="${NAMESPACE}"
	fi
	cd ${WORKING_DIR}
}

# function creates CA key/cert files for Solr in order to HTTPs and Client authentication. Plus get them available at k8s cluster by the secret: solr-cert-secret
function createSolrSecret {
	set -o errexit
	set -o pipefail
	set -o nounset

	solrFolder=${WORKING_DIR}/solr-secrets
	secretName=solr-certs-secret
	rm -rf ${solrFolder}
	mkdir -p ${solrFolder}
	cd ${solrFolder}

	#Create the private key
	openssl genrsa -out solrCA.key -aes256 -passout pass:${set_solr_secret} 2048

	#Create the Certificate Authority (CA)
	openssl req -x509 -new -extensions v3_ca -key solrCA.key -days 730 -out solrCA.crt -passin pass:${set_solr_secret} -subj "/emailAddress=ca@solr/CN=solr/OU=Connections/O=IBM/L=Armonk/ST=NY/C=US"

	#Verify key/certs
	echo
	echo
	echo " ==========Dump Solr CA key and certificate=========="
	openssl rsa -in solrCA.key -check -passin pass:${set_solr_secret}
	openssl x509 -in solrCA.crt -text -noout
	echo " ==========       Done with Dump           =========="

	#Generate the pem files
	cat solrCA.key solrCA.crt > ca-keyAndCert.pem

	#Create the secret solr-secret.yaml
	solr_secret_cmd="kubectl create secret generic ${secretName} -n=${NAMESPACE} --from-file=ca-keyAndCert.pem --from-literal=store_password=${set_solr_secret}"
	eval $solr_secret_cmd

	#Export solr-secret in order to have a safely backup
	kubectl get secret ${secretName} -o yaml -n="${NAMESPACE}" > solr-secret.yaml
	cd ${WORKING_DIR}
}

# Function to create Root CA for ElasticSearch cluster
function createESRootCA {
	set -o errexit
	set -o pipefail
	set -o nounset
	# Create Root CA for ElasticSearch cluster
	mkdir -p ca/root-ca/private ca/root-ca/db crl certs
	chmod 700 ca/root-ca/private

	cp /dev/null ca/root-ca/db/root-ca.db
	cp /dev/null ca/root-ca/db/root-ca.db.attr
	echo 01 > ca/root-ca/db/root-ca.crt.srl
	echo 01 > ca/root-ca/db/root-ca.crl.srl

	openssl req -new \
		-config ${DEPLOY_CFC_DIR}/elasticsearch/caconfig/root-ca.conf \
		-out ca/root-ca.csr \
		-keyout ca/root-ca/private/root-ca.key \
		-batch \
		-passout pass:$set_elasticsearch_ca_password

	openssl ca -selfsign \
		-config ${DEPLOY_CFC_DIR}/elasticsearch/caconfig/root-ca.conf \
		-in ca/root-ca.csr \
		-out ca/root-ca.crt \
		-extensions root_ca_ext \
		-batch \
		-passin pass:$set_elasticsearch_ca_password

	echo Root CA generated

	# Create Signing CA for ElasticSearch cluster
	mkdir -p ca/signing-ca/private ca/signing-ca/db crl certs
	chmod 700 ca/signing-ca/private

	cp /dev/null ca/signing-ca/db/signing-ca.db
	cp /dev/null ca/signing-ca/db/signing-ca.db.attr
	echo 01 > ca/signing-ca/db/signing-ca.crt.srl
	echo 01 > ca/signing-ca/db/signing-ca.crl.srl

	openssl req -new \
		-config ${DEPLOY_CFC_DIR}/elasticsearch/caconfig/signing-ca.conf \
		-out ca/signing-ca.csr \
		-keyout ca/signing-ca/private/signing-ca.key \
		-batch \
		-passout pass:$set_elasticsearch_ca_password

	openssl ca \
		-config ${DEPLOY_CFC_DIR}/elasticsearch/caconfig/root-ca.conf \
		-in ca/signing-ca.csr \
		-out ca/signing-ca.crt \
		-extensions signing_ca_ext \
		-batch \
		-passin pass:$set_elasticsearch_ca_password

	echo Signing CA generated

	#Covert crt files to PEM format
	openssl x509 -in ca/root-ca.crt -out ca/root-ca.pem -outform PEM
	openssl x509 -in ca/signing-ca.crt -out ca/signing-ca.pem -outform PEM
	cat ca/signing-ca.pem ca/root-ca.pem > ca/chain-ca.pem
}

# Function to create Server Certificate for each of ElasticSearch Node
function createESNodeCert {
	set -o errexit
	set -o pipefail
	set -o nounset

	NODE_NAME=elasticsearch-$1
	SERVER_NAME=/CN=${NODE_NAME}/OU=CES/O=HCL/C=US
	openssl genrsa -out $NODE_NAME.key.tmp 2048
	openssl pkcs8 -topk8 -inform pem -in $NODE_NAME.key.tmp -outform pem -out $NODE_NAME.key -passout "pass:$set_elasticsearch_key_password"

	openssl req -new -key $NODE_NAME.key -out $NODE_NAME.csr -passin "pass:$set_elasticsearch_key_password" \
		-subj "$SERVER_NAME" \
		-reqexts v3_req \
		-config ${DEPLOY_CFC_DIR}/elasticsearch/caconfig/node-ssl.conf

	openssl ca \
		-in "$NODE_NAME.csr" \
		-notext \
		-out "$NODE_NAME-signed.pem" \
		-config "${DEPLOY_CFC_DIR}/elasticsearch/caconfig/signing-ca.conf" \
		-extensions v3_req \
		-batch \
		-passin "pass:$set_elasticsearch_ca_password" \
		-days 730 \
		-extensions server_ext

	#we do not add the root certificate to the chain
	cat "$NODE_NAME-signed.pem" ca/signing-ca.pem > $NODE_NAME.crt.pem
	openssl pkcs12 -export -in "$NODE_NAME.crt.pem" -inkey "$NODE_NAME.key" -out "$NODE_NAME.p12" -passin "pass:$set_elasticsearch_key_password" -passout "pass:$set_elasticsearch_key_password"
}

# Function to create Clinet Certificate for client of ElasticSearch Cluster
function createESClientCert {
	set -o errexit
	set -o pipefail
	set -o nounset

	CLIENT_NAME=elasticsearch-$1
	SERVER_NAME=/CN=${CLIENT_NAME}/OU=CES/O=HCL/C=US
	openssl genrsa -out $CLIENT_NAME.key.tmp 2048
	openssl pkcs8 -topk8 -inform pem -in $CLIENT_NAME.key.tmp -outform pem -out $CLIENT_NAME.key -passout "pass:$set_elasticsearch_key_password"

	#Curl7.29 only works with des encrytped key, so we also need the des ecnrytped version of private key
	openssl rsa -des3 -in $CLIENT_NAME.key.tmp -out $CLIENT_NAME.des3.key -passout "pass:$set_elasticsearch_key_password"

	openssl req -new -key $CLIENT_NAME.key -out $CLIENT_NAME.csr -passin "pass:$set_elasticsearch_key_password" \
		-subj "$SERVER_NAME" \
		-reqexts v3_req \
		-config ${DEPLOY_CFC_DIR}/elasticsearch/caconfig/client-ssl.conf

	openssl ca \
		-in "$CLIENT_NAME.csr" \
		-notext \
		-out "$CLIENT_NAME-signed.pem" \
		-config ${DEPLOY_CFC_DIR}/elasticsearch/caconfig/signing-ca.conf \
		-extensions v3_req \
		-batch \
		-passin "pass:$set_elasticsearch_ca_password" \
		-days 730 \
		-extensions server_ext

	#we do not add the root certificate to the chain
	cat "$CLIENT_NAME-signed.pem" ca/signing-ca.pem > $CLIENT_NAME.crt.pem
	openssl pkcs12 -export -in "$CLIENT_NAME.crt.pem" -inkey "$CLIENT_NAME.key" -out "$CLIENT_NAME.p12" -passin "pass:$set_elasticsearch_key_password" -passout "pass:$set_elasticsearch_key_password"
}

# function to clean all the certificates and CAs
function cleanESCerts {
	set -o errexit
	rm -rf ca/
	rm -rf certs/
	rm -rf crl/
	rm -f ./*tmp*
	rm -f *.txt
	rm -f ./elasticsearch*
}

# function to read all the password needed by creating solr secrets
function readSolrPasswords {
	set -o errexit
	set -o pipefail
	set -o nounset

	if [ -z "${set_solr_secret}" ]; then
		readPassword "Solr secret"
		set_solr_secret=${set_secret}
	fi
}

# function to read all the password needed by creating elasticsearch secrets
function readESPasswords {
	set -o errexit
	set -o pipefail
	set -o nounset

	if [ -z "${set_elasticsearch_ca_password}" ]; then
		readPassword "ElasticSearch CA password"
		set_elasticsearch_ca_password=${set_secret}
	fi

	if [ -z "${set_elasticsearch_key_password}" ]; then
		readPassword "ElasticSearch password to protect the server private key"
		set_elasticsearch_key_password=${set_secret}
	fi
}

# funtion to write elaticsearch secrets to k8s secret 'elasticsearch-secret'
function writeESSecrets {
	set -o errexit
	set -o pipefail
	set -o nounset

	elasticsearch_cert_files=(
		"elasticsearch-ca-password.txt"
		"elasticsearch-key-password.txt"
		"elasticsearch-transport.key"
		"elasticsearch-http.key"
		"elasticsearch-transport.crt.pem"
		"elasticsearch-http.crt.pem"
		"elasticsearch-admin.key"
		"elasticsearch-admin.crt.pem"
		"elasticsearch-metrics.key"
		"elasticsearch-metrics.crt.pem"
		"elasticsearch-healthcheck.key"
		"elasticsearch-healthcheck.des3.key"
		"elasticsearch-healthcheck.crt.pem"
		"ca/chain-ca.pem"
		"elasticsearch-orientme.key"
		"elasticsearch-orientme.crt.pem"
		"elasticsearch-orientme.p12"
	)

	elasticsearch_secret_cmd="kubectl create secret generic elasticsearch-secret -n="${NAMESPACE}""
	for elasticsearch_cert_file in "${elasticsearch_cert_files[@]}"
	do
		elasticsearch_secret_cmd="$elasticsearch_secret_cmd --from-file=$elasticsearch_cert_file"
	done

	eval $elasticsearch_secret_cmd

	#remove password and private key in plain text
	rm -f elasticsearch-ca-password.txt
	rm -f elasticsearch-key-password.txt
	rm -f *.key.tmp
}

cd ${WORKING_DIR}


if [ ${is_master_HA} = true ]; then
	echo
	echo "Checking master node high availability deployment requirements"

	set +o nounset
	if [ "${SEMAPHORE_PREFIX}" = "" ]; then
		echo "SEMAPHORE_PREFIX not set"
		echo "Suggestion:  export SEMAPHORE_PREFIX=${DATE}"
		exit 50
	fi
	set -o nounset

	SEMAPHORE=${SEMAPHORE_PREFIX}.1
	setSemaphore ${SEMAPHORE}		# return in semaphore_init
	if [ ${semaphore_init} = true ]; then	# first master node
		echo "First master node in high availability check"
		set +o errexit
		for semaphore_target in ${semaphore_targets}; do
			if [ ! -d ${semaphore_target} ]; then
				echo "Master node high availability prerequisite shared volume ${semaphore_target} does not exist"
				exit 55
			fi

			date > ${semaphore_target}/${SEMAPHORE}.${HOSTNAME}.$$
			if [ $? -ne 0 ]; then
				echo "Failure creating semaphore ${semaphore_target}/${SEMAPHORE}.${HOSTNAME}.$$"
				exit 21
			fi
			set -o errexit
			echo ${HOSTNAME} >> ${semaphore_target}/${SEMAPHORE}.${HOSTNAME}.$$
			set +o errexit
			ln ${semaphore_target}/${SEMAPHORE}.${HOSTNAME}.$$ ${semaphore_target}/${SEMAPHORE}
			exit_status=$?
			set -o errexit
			rm ${semaphore_target}/${SEMAPHORE}.${HOSTNAME}.$$
			if [ ${exit_status} -eq 0 ]; then
				echo "First master node created semaphore ${semaphore_target}/${SEMAPHORE}"
			else
				echo "${semaphore_target}/${SEMAPHORE} alredy exists even though ${HOSTNAME} is the first master node (or can't write to ${semaphore_target}"
				echo
				echo "${semaphore_target}/${SEMAPHORE}:"
				cat ${semaphore_target}/${SEMAPHORE}
				exit 18
			fi
		done
		set -o errexit
	elif [ ${semaphore_init} = false ]; then	# subsequent master node
		echo "Subsequent master node in high availability check"
		found_all_masters=true
		for semaphore_target in ${semaphore_targets}; do
			if [ -e ${semaphore_target}/${SEMAPHORE} ]; then
				echo "Validated master node high availability prerequisite on shared volume ${semaphore_target} for this master node"

				echo >> ${semaphore_target}/${SEMAPHORE}
				date >> ${semaphore_target}/${SEMAPHORE}
				echo ${HOSTNAME} >> ${semaphore_target}/${SEMAPHORE}

				set +o errexit
				for master in ${MASTER_LIST}; do
					grep -q ${master} ${semaphore_target}/${SEMAPHORE}
					if [ $? -eq 1 ]; then
						found_all_masters=false
					fi
				done
				set -o errexit
				if [ ${found_all_masters} = true ]; then
					echo
					echo "All master nodes validated for ${semaphore_target}"
					echo
					cat ${semaphore_target}/${SEMAPHORE}
					echo
					rm ${semaphore_target}/${SEMAPHORE}
				fi
			else
				echo
				echo "Could not validate shared volume ${semaphore_target}"
				echo
				echo "Master node high availability has a prerequisite on shared volume(s) ${semaphore_targets} across all master nodes"
				echo "Please review documentation and prepare shared volume(s) ${semaphore_targets}"
				echo "Note: effort underway to move this check earlier in the deployment to save time"
				# XYZZY:  move HA shared volume check earlier
				exit 19
			fi
		done

		set -o errexit
		if [ ${found_all_masters} = true ]; then
			echo "Cleaning up semaphore ${SEMAPHORE}"
			deleteSemaphore ${SEMAPHORE}
		fi

		echo
		echo "Subsequent steps only run on first master node"
		exit 0
	else
		echo "Unknown state"
		exit 20
	fi
fi

# The following steps run once per deployment
# For a master HA deployment, only the first master performs these steps
set +o errexit
if [ ${regenerate_passwords} = false -a ${upgrade} = true ]; then
	echo "Skipping delete of current service secrets.."
else
	echo
	deleteSecretIfExists redis-secret
	deleteSecretIfExists s2ssecret
	deleteSecretIfExists elasticsearch-secret
	deleteSecretIfExists solr-certs-secret
fi
deleteSecretIfExists krb5keytab
deleteSecretIfExists ic-admin-secret
echo "=== Ignore if not found"
kubectl delete configmap ${HOSTNAME} -n ${NAMESPACE}
kubectl delete configmap ${BOOT} -n ${NAMESPACE}
kubectl delete configmap topology-configuration -n ${NAMESPACE}
echo "=== End of ignore section"
set -o errexit

echo
if [ "${set_namespace}" != "" ]; then
	echo "Name of namespace: ${NAMESPACE}"
else
	echo "Using default namespace name: ${NAMESPACE}"
fi

echo
if [ "`kubectl get namespaces | grep ${NAMESPACE} | awk '{print $1}'`" == "${NAMESPACE}" ]; then
	echo "Found ${NAMESPACE} namespace already exists. Using this."
else
	kubectl create namespace ${NAMESPACE}
fi

echo
while [ "${set_ic_host}" = "" ]; do
	echo
	printf "Connections FQHN: "
	read set_ic_host
	set +o errexit
	validate_ic_host "Entered input" ${set_ic_host}
	if [ $? -ne 0 ]; then
		set_ic_host=""
	fi
	set -o errexit
done
echo
while [ "${set_ic_admin_user}" = "" ]; do
	echo
	printf "Connections Admin user: "
	read set_ic_admin_user
done
echo
if [ "${set_ic_admin_password}" = "" ]; then
	readPassword "Connections Admin password"	# result in set_secret
	set_ic_admin_password=${set_secret}
	set -o errexit
fi
echo
if [ "${internal_ic}" = "" ]; then
	internal_ic=${set_ic_host}
fi
echo
kubectl create configmap topology-configuration --from-literal=ic-host="${set_ic_host}" --from-literal=ic-internal="${internal_ic}" -n="${NAMESPACE}"
kubectl create secret generic ic-admin-secret --from-literal=uid="${set_ic_admin_user}" --from-literal=password="${set_ic_admin_password}" -n="${NAMESPACE}"

echo
if [ ${regenerate_passwords} = false -a ${upgrade} = true ]; then
	echo "Skipping regeneration of service secrets.."
else
	# Prepare Solr secret
	echo
	if [ "${set_solr_secret}" = "" ]; then
		readSolrPasswords
	fi
	echo
	createSolrSecret

	echo
	if [ "${set_elasticsearch_ca_password}" = "" ] && [ "${set_elasticsearch_key_password}" = "" ]; then
		readESPasswords
	fi

	mkdir -p ${ELASTICSEARCH_DIR}
	chmod 700 ${ELASTICSEARCH_DIR}
	cd ${ELASTICSEARCH_DIR}
	cleanESCerts
	echo ${set_elasticsearch_ca_password} > elasticsearch-ca-password.txt
	echo ${set_elasticsearch_key_password} > elasticsearch-key-password.txt
	createESRootCA
	createESNodeCert 'http' && createESNodeCert 'transport'
	createESClientCert 'admin' && createESClientCert 'metrics' && createESClientCert 'healthcheck'  && createESClientCert 'orientme'
	writeESSecrets
	cd ${WORKING_DIR}

	echo
	if [ "${set_redis_secret}" = "" ]; then
		readPassword "Redis secret"			# result in set_secret
		set_redis_secret=${set_secret}
		set -o errexit
	fi
	echo
	kubectl create secret generic redis-secret "--from-literal=secret=${set_redis_secret}" -n="${NAMESPACE}"

	echo
	if [ "${set_search_secret}" = "" ]; then
		readPassword "Search secret"			# result in set_secret
		set_search_secret=${set_secret}
		set -o errexit
	fi
	echo
	kubectl create secret generic s2ssecret "--from-literal=s2s_auth_token=${set_search_secret}" -n="${NAMESPACE}"
fi

if [ ${regenerate_passwords} = true -a ${upgrade} = true ]; then
	mkdir -p ${CONFIG_DIR}
	echo "regenerate_passwords=true" >> ${CONFIG_DIR}/${HOSTNAME}
fi

echo
if [ "${set_krb5_secret}" = "" ]; then
	createKrb5K8Secret "" ""
	set -o errexit
else
	set -o errexit
	cd ${DEPLOY_CFC_DIR}
	echo
	kubectl create secret generic krb5keytab --from-file="${set_krb5_secret}" -n="${NAMESPACE}"
	cd ${WORKING_DIR}
fi

	echo

# Workaround for ICP Issue #4014
if [ ${is_master_HA} = true ]; then
	masterCount=`echo "${MASTER_LIST}" | wc -w`
	kubectl scale deployment -n kube-system kube-dns --replicas=${masterCount}
fi

echo
workerArray=(${WORKER_LIST//,/ }) # Will include infra_workers too if infra_worker_list was used
if [ "${INFRA_WORKER_LIST}" != "" ]; then
	infra_workerArray=(${INFRA_WORKER_LIST//,/ }) # Array of infra workers only
	for i in "${infra_workerArray[@]}"; do
		workerArray=(${workerArray[@]//*$i*}) # Array of generic workers only
	done
fi
for worker in "${workerArray[@]}"; do
	resolve_ip ${worker}	# result in resolve_ip_return_result
	ip=${resolve_ip_return_result}
	echo "Labeling ${worker} with type=generic"
	set -o errexit
	kubectl label nodes "${ip}" type=generic --overwrite
done
if [ "${INFRA_WORKER_LIST}" != "" ]; then
	for infra_worker in "${infra_workerArray[@]}"; do
		resolve_ip ${infra_worker}	# result in resolve_ip_return_result
		ip=${resolve_ip_return_result}
		echo "Labeling ${infra_worker} with type=infrastructure"
		set -o errexit
		kubectl drain "${ip}" --force --delete-local-data --ignore-daemonsets
		kubectl label nodes "${ip}" type=infrastructure --overwrite
		kubectl taint nodes "${ip}" dedicated=infrastructure:NoSchedule --overwrite
		kubectl uncordon "${ip}"
	done
fi

echo
echo "Clean exit"
echo

