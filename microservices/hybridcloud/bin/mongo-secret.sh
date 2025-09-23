#!/bin/bash -
#title           :mongo-secret.sh
#description     :This script will delete and create the mongo secret.
#version         :0.2
#usage                 :bash mongo.sh
#==============================================================================
#!/bin/bash

#set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

PATH=/usr/bin:/bin:/usr/sbin:/usr/local/bin:/sbin:${PATH}
export PATH
umask 022

if [ "`id -u`" != 0 ]; then
	echo "Must run as root"
	exit 1
fi

deleteSecretIfExists() {
	set +o errexit
	set -o pipefail
	set +o nounset

	if [ "$1" = "" ]; then
		echo "usage:  deleteSecretIfExists sSecretName"
		exit 107
	fi
	secret_name="$1"
	set -o nounset

	if [[ "$(kubectl get secrets -o jsonpath={.items[*].metadata.name} -n ${namespace})" =~ .*${secret_name}.* ]]; then
		echo
		echo "Deleting ${secret_name} so that we can replace with new."
		kubectl delete secret ${secret_name} -n="${namespace}"
		echo
	fi

}

# TODO: The session below will generate the certs for existent applications client
## that still not migrated to the mechanism created at #8469. This will ensure the 
## backward compatibility
createAppsX509CertsYetNotComplianceWith8469() {
	APPS_NAME=( \
	"admin" \
	"app-catalog" \
	"app-registry" \
	"itm" \
	"people-service" \
	"mongodb-tester" \
	"sanity" \
	"livegrid-core" \
	"middleware-api-gateway" \
	"security-auth-services" \
	"security-ams" \
	"activitystreams" \
	"content-base" \
	"content-share" \
	"content-storage" \
	"content-conversion-proxy" \
	)

	for APP_NAME in "${APPS_NAME[@]}"
	do
		#Create the application clients' users (OU must be different)
		openssl req -new -nodes -newkey rsa:2048 -keyout user_${APP_NAME}.key -out user_${APP_NAME}.csr \
		-subj "/emailAddress=${APP_NAME}@mongodb/CN=${APP_NAME}/OU=Connections-Middleware-Clients/O=IBM/L=Dublin/ST=Ireland/C=IE"

		#Sign the CSRs with the CA and generate the public certificate of them (CRTs)
		openssl x509 -CA ${PK_CA_PATH}/internal-ca-chain.cert.pem -CAkey ${PK_CA_PATH}/intermediate.key.pem -CAcreateserial -req -days 730 -in user_${APP_NAME}.csr -out user_${APP_NAME}.crt

		#Generate the pem files
		cat user_${APP_NAME}.key user_${APP_NAME}.crt > user_${APP_NAME}.pem
		rm -f user_${APP_NAME}.key user_${APP_NAME}.crt user_${APP_NAME}.csr
	done
}

createMongoSecret() {
	set -o errexit
	set -o pipefail
	set -o nounset
	local WORKING_DIR=/opt

	rm -rf ${WORKING_DIR}/mongo-secret/x509
	mkdir -p ${WORKING_DIR}/mongo-secret/x509
	mkdir -p ${WORKING_DIR}/mongo-secret/yamlContent

	# Get support path here
	cp -av support/ca ${WORKING_DIR}/mongo-secret/x509
	# variable used by ca/openssl.cfg and ca/intermediate/openssl.cfg
    export OPENSSL_DIR=${WORKING_DIR}/mongo-secret/x509/ca

	# Create the directory structure.
	pushd $OPENSSL_DIR
	mkdir -p certs crl newcerts private
	chmod 700 private
	touch index.txt
	echo 1000 > serial

	# Create the root key
	KEY_PASS=$(uuidgen)
	openssl genrsa -aes256 -passout pass:${KEY_PASS} -out private/ca.key.pem.enc 4096
	openssl rsa -in private/ca.key.pem.enc -out private/ca.key.pem -passin pass:${KEY_PASS}
	rm -f private/ca.key.pem.enc
	chmod 400 private/ca.key.pem

	# Use the root key (ca.key.pem) to create a root certificate (ca.cert.pem)
	TWENTY_YEARS=7300
	openssl req -config openssl.cnf \
	-key private/ca.key.pem \
	-new -x509 -days ${TWENTY_YEARS} -sha256 -extensions v3_ca \
	-out certs/ca.cert.pem \
	-subj "/emailAddress=ca@mongodb/CN=mongodb-ca/OU=Connections/O=IBM/L=Dublin/ST=Ireland/C=IE"
	chmod 444 certs/ca.cert.pem

	# Create the intermediate pair
	pushd $OPENSSL_DIR/intermediate
	mkdir -p certs crl csr newcerts private
	chmod 700 private
	touch index.txt
	echo 1000 > serial
	echo 1000 > $OPENSSL_DIR/intermediate/crlnumber

	# Create the intermediate key
	popd
	openssl genrsa -aes256 -passout pass:${KEY_PASS} -out intermediate/private/intermediate.key.pem.enc 4096
	openssl rsa -in intermediate/private/intermediate.key.pem.enc -out intermediate/private/intermediate.key.pem -passin pass:${KEY_PASS}
	rm -f intermediate/private/intermediate.key.pem.enc
	chmod 400 intermediate/private/intermediate.key.pem

	# Create the intermediate certificate
	openssl req -config intermediate/openssl.cnf -new -sha256 \
	-key intermediate/private/intermediate.key.pem \
	-out intermediate/csr/intermediate.csr.pem \
	-subj "/emailAddress=ca-intermediate@mongodb/CN=mongodb-ca-intermediate/OU=Connections/O=IBM/L=Dublin/ST=Ireland/C=IE"
	chmod 444 certs/ca.cert.pem

	## To create an intermediate certificate, use the root CA
	TEN_YEARS=3650
	openssl ca -batch -config openssl.cnf -extensions v3_intermediate_ca \
	-days ${TEN_YEARS} -notext -md sha256 \
	-in intermediate/csr/intermediate.csr.pem \
	-out intermediate/certs/intermediate.cert.pem
	chmod 444 intermediate/certs/intermediate.cert.pem

	## Verify the intermediate certificate against the root certificate
	openssl verify -CAfile certs/ca.cert.pem intermediate/certs/intermediate.cert.pem | grep OK

	# Create the certificate chain file
	cat intermediate/certs/intermediate.cert.pem \
	certs/ca.cert.pem > intermediate/certs/internal-ca-chain.cert.pem
	chmod 444 intermediate/certs/internal-ca-chain.cert.pem

	# Create the mongo-secret.yaml
	rm -rf ${WORKING_DIR}/mongo-secret/yamlContent
	mkdir -p ${WORKING_DIR}/mongo-secret/yamlContent
	PK_CA_PATH=${WORKING_DIR}/mongo-secret/yamlContent
	pushd ${PK_CA_PATH}
	cp -av $OPENSSL_DIR/intermediate/certs/internal-ca-chain.cert.pem .
	cp -av $OPENSSL_DIR/intermediate/private/intermediate.key.pem .

	# TODO: The session below will generate the certs for existent applications client
	## that still not migrated to the mechanism created at #8469. This will ensure the 
	## backward compatibility
	createAppsX509CertsYetNotComplianceWith8469

	#Create the secret mongo-secret.yaml
	echo
	echo

	# x509 is activated on mongo by default in our helm install, so setting the value to true
	echo -n "true" > mongo-x509-auth-enabled

	PEM_FILES=(*.pem)
	PEM_FILES+=(mongo-x509-auth-enabled)

	# keep backward compatibility with runbook
	cp -av internal-ca-chain.cert.pem mongo-CA-cert.crt
	PEM_FILES+=(mongo-CA-cert.crt)

	# Mongo Daemons and Sidecar uses Env Variables instead of logical volumes: 
	cat intermediate.key.pem | base64 | tr -d '\n' > b64_intermediate.key.pem
	echo >> b64_intermediate.key.pem
	PEM_FILES+=(b64_intermediate.key.pem)

	cat internal-ca-chain.cert.pem | base64 | tr -d '\n' > b64_internal-ca-chain.cert.pem
	echo >> b64_internal-ca-chain.cert.pem
	PEM_FILES+=(b64_internal-ca-chain.cert.pem)

	mongo_secret_cmd="kubectl create secret generic mongo-secret -n ${namespace}"
	
	for mongo_cert_file in "${PEM_FILES[@]}"
	do
		mongo_secret_cmd="$mongo_secret_cmd --from-file=$mongo_cert_file"
	done

	eval $mongo_secret_cmd

	popd
	popd
}

namespace=`grep namespace bin/common_values.yaml | awk '{print $2}'`

deleteSecretIfExists mongo-secret
createMongoSecret
