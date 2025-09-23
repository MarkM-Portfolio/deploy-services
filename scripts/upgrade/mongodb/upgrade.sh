#!/bin/bash

set -o pipefail

logErr() {
	logIt "ERRO: " "$@"
}

logInfo() {
	logIt "INFO: " "$@"
}

logIt() {
	echo "$@"
}

# return is in set_secret
# function resets errexit to ignore so calling script must either reset if desired
function readPassword() {
	set +o errexit
	set -o pipefail
	set +o nounset

	if [ "$1" = "" ]; then
		echo "usage:  readPassword sDescriptor"
		exit 107
	fi
	set -o nounset
	descriptor="$1"
	set_secret=""

	echo
	while [ "${set_secret}" = "" ]; do
		echo
		printf "${descriptor}: "
		read -s set_secret		# -s not working #2770
		printf "\n${descriptor} (confirmation):  "
		read -s set_secret_confirm	# -s not working #2770
		if [ "${set_secret}" != "${set_secret_confirm}" ]; then
			echo
			echo "=== Input does not match, try again"
			set_secret=""
			continue
		fi
	done
}

function deleteSecretIfExists {
	set +o errexit
	set -o pipefail
	set +o nounset

	if [ "$1" = "" ]; then
		echo "usage:  secret name"
		exit 107
	fi
	secret_name="$1"
	set -o nounset

	if [[ "$(kubectl get secrets -o jsonpath={.items[*].metadata.name})" =~ .*${secret_name}.* ]]; then
		echo
		echo "Deleting ${secret_name} so that we can replace with new."
		kubectl delete secret ${secret_name}
		echo
	fi

}

# function creates the TLS/SSL files in order to support x509 certificates on MongoDB RS. Plus get them available at k8s cluster by the secret: mongo-secret
function createMongoSecret {
	set +o errexit
	set -o pipefail
	set +o nounset

	ICP_CONFIG_DIR=/opt/ibm/connections
	ICP_CONFIG_FILE=config.json
	jq=${ICP_CONFIG_DIR}/jq/bin/jq

	WORKING_DIR=$(cat $ICP_CONFIG_DIR/$ICP_CONFIG_FILE | $jq -r '.connections_location')
	if [ ! -d "${conn_locn}" ]; then
		echo "Cannot determine ICp install directory"
		exit 108
	fi

	mkdir -p ${WORKING_DIR}/mongo-secret/x509
	cd ${WORKING_DIR}/mongo-secret/x509

	#Create the private key password file:
	echo ${set_mongo_secret} > pemKeyPass.txt

	#Create the private key
	openssl genrsa -out mongoPrivate.key -aes256 -passout pass:${set_mongo_secret}

	#Create the Certificate Authority (CA)
	openssl req -x509 -new -extensions v3_ca -key mongoPrivate.key -days 730 -out mongo-CA-cert.crt -passin pass:${set_mongo_secret} \
	-subj "/emailAddress=ca@mongodb/CN=mongodb/OU=Connections/O=IBM/L=Dublin/ST=Ireland/C=IE"

	#Create the mongoD's Certificates, (Common Name must be different)
	openssl req -new -nodes -newkey rsa:2048 -keyout mongo-0.key -out mongo-0.csr \
	-subj "/emailAddress=mongo-0.mongo@mongodb/CN=mongo-0.mongo.default.svc.cluster.local/OU=Connections/O=IBM/L=Dublin/ST=Ireland/C=IE"

	openssl req -new -nodes -newkey rsa:2048 -keyout mongo-1.key -out mongo-1.csr \
	-subj "/emailAddress=mongo-1.mongo@mongodb/CN=mongo-1.mongo.default.svc.cluster.local/OU=Connections/O=IBM/L=Dublin/ST=Ireland/C=IE"

	openssl req -new -nodes -newkey rsa:2048 -keyout mongo-2.key -out mongo-2.csr \
	-subj "/emailAddress=mongo-2.mongo@mongodb/CN=mongo-2.mongo.default.svc.cluster.local/OU=Connections/O=IBM/L=Dublin/ST=Ireland/C=IE"

	#Create the Admin and application clients' users (OU must be different)
	openssl req -new -nodes -newkey rsa:2048 -keyout user_admin.key -out user_admin.csr \
	-subj "/emailAddress=admin@mongodb/CN=admin/OU=Connections-Middleware-Clients/O=IBM/L=Dublin/ST=Ireland/C=IE"

	openssl req -new -nodes -newkey rsa:2048 -keyout user_itm.key -out user_itm.csr \
	-subj "/emailAddress=itm@mongodb/CN=itm/OU=Connections-Middleware-Clients/O=IBM/L=Dublin/ST=Ireland/C=IE"

	openssl req -new -nodes -newkey rsa:2048 -keyout user_people-service.key -out user_people-service.csr \
	-subj "/emailAddress=people-service@mongodb/CN=people-service/OU=Connections-Middleware-Clients/O=IBM/L=Dublin/ST=Ireland/C=IE"

	openssl req -new -nodes -newkey rsa:2048 -keyout user_app-catalog.key -out user_app-catalog.csr \
	-subj "/emailAddress=app-catalog@mongodb/CN=app-catalog/OU=Connections-Middleware-Clients/O=IBM/L=Dublin/ST=Ireland/C=IE"

	openssl req -new -nodes -newkey rsa:2048 -keyout user_app-registry.key -out user_app-registry.csr \
	-subj "/emailAddress=app-registry@mongodb/CN=app-registry/OU=Connections-Middleware-Clients/O=IBM/L=Dublin/ST=Ireland/C=IE"

	openssl req -new -nodes -newkey rsa:2048 -keyout user_mongodb-tester.key -out user_mongodb-tester.csr \
	-subj "/emailAddress=mongodb-tester@mongodb/CN=mongodb-tester/OU=Connections-Middleware-Clients/O=IBM/L=Dublin/ST=Ireland/C=IE"

	openssl req -new -nodes -newkey rsa:2048 -keyout user_sanity.key -out user_sanity.csr \
	-subj "/emailAddress=sanity@mongodb/CN=sanity/OU=Connections-Middleware-Clients/O=IBM/L=Dublin/ST=Ireland/C=IE"

	openssl req -new -nodes -newkey rsa:2048 -keyout user_livegrid-core.key -out user_livegrid-core.csr \
	-subj "/emailAddress=livegrid-core@mongodb/CN=livegrid-core/OU=Connections-Middleware-Clients/O=IBM/L=Dublin/ST=Ireland/C=IE"

	openssl req -new -nodes -newkey rsa:2048 -keyout user_middleware-api-gateway.key -out user_middleware-api-gateway.csr \
	-subj "/emailAddress=middleware-api-gateway@mongodb/CN=middleware-api-gateway/OU=Connections-Middleware-Clients/O=IBM/L=Dublin/ST=Ireland/C=IE"

	openssl req -new -nodes -newkey rsa:2048 -keyout user_security-auth-services.key -out user_security-auth-services.csr \
	-subj "/emailAddress=security-auth-services@mongodb/CN=security-auth-services/OU=Connections-Middleware-Clients/O=IBM/L=Dublin/ST=Ireland/C=IE"

	openssl req -new -nodes -newkey rsa:2048 -keyout user_security-ams.key -out user_security-ams.csr \
	-subj "/emailAddress=security-ams@mongodb/CN=security-ams/OU=Connections-Middleware-Clients/O=IBM/L=Dublin/ST=Ireland/C=IE"

	#Sign the CSRs with the CA and generate the public certificate of them (CRTs)
	openssl x509 -CA mongo-CA-cert.crt -CAkey mongoPrivate.key -CAcreateserial -req -days 730 -in mongo-0.csr -out mongo-0.crt -passin pass:${set_mongo_secret}
	openssl x509 -CA mongo-CA-cert.crt -CAkey mongoPrivate.key -CAcreateserial -req -days 730 -in mongo-1.csr -out mongo-1.crt -passin pass:${set_mongo_secret}
	openssl x509 -CA mongo-CA-cert.crt -CAkey mongoPrivate.key -CAcreateserial -req -days 730 -in mongo-2.csr -out mongo-2.crt -passin pass:${set_mongo_secret}
	openssl x509 -CA mongo-CA-cert.crt -CAkey mongoPrivate.key -CAcreateserial -req -days 730 -in user_admin.csr -out user_admin.crt -passin pass:${set_mongo_secret}
	openssl x509 -CA mongo-CA-cert.crt -CAkey mongoPrivate.key -CAcreateserial -req -days 730 -in user_itm.csr -out user_itm.crt -passin pass:${set_mongo_secret}
	openssl x509 -CA mongo-CA-cert.crt -CAkey mongoPrivate.key -CAcreateserial -req -days 730 -in user_people-service.csr -out user_people-service.crt -passin pass:${set_mongo_secret}
	openssl x509 -CA mongo-CA-cert.crt -CAkey mongoPrivate.key -CAcreateserial -req -days 730 -in user_app-catalog.csr -out user_app-catalog.crt -passin pass:${set_mongo_secret}
	openssl x509 -CA mongo-CA-cert.crt -CAkey mongoPrivate.key -CAcreateserial -req -days 730 -in user_app-registry.csr -out user_app-registry.crt -passin pass:${set_mongo_secret}
	openssl x509 -CA mongo-CA-cert.crt -CAkey mongoPrivate.key -CAcreateserial -req -days 730 -in user_mongodb-tester.csr -out user_mongodb-tester.crt -passin pass:${set_mongo_secret}
	openssl x509 -CA mongo-CA-cert.crt -CAkey mongoPrivate.key -CAcreateserial -req -days 730 -in user_sanity.csr -out user_sanity.crt -passin pass:${set_mongo_secret}
	openssl x509 -CA mongo-CA-cert.crt -CAkey mongoPrivate.key -CAcreateserial -req -days 730 -in user_livegrid-core.csr -out user_livegrid-core.crt -passin pass:${set_mongo_secret}
	openssl x509 -CA mongo-CA-cert.crt -CAkey mongoPrivate.key -CAcreateserial -req -days 730 -in user_middleware-api-gateway.csr -out user_middleware-api-gateway.crt -passin pass:${set_mongo_secret}
	openssl x509 -CA mongo-CA-cert.crt -CAkey mongoPrivate.key -CAcreateserial -req -days 730 -in user_security-auth-services.csr -out user_security-auth-services.crt -passin pass:${set_mongo_secret}
	openssl x509 -CA mongo-CA-cert.crt -CAkey mongoPrivate.key -CAcreateserial -req -days 730 -in user_security-ams.csr -out user_security-ams.crt -passin pass:${set_mongo_secret}

	#Generate the pem files
	cat mongo-0.key mongo-0.crt > mongo-0.pem
	cat mongo-1.key mongo-1.crt > mongo-1.pem
	cat mongo-2.key mongo-2.crt > mongo-2.pem
	cat user_admin.key user_admin.crt > user_admin.pem
	cat user_itm.key user_itm.crt > user_itm.pem
	cat user_people-service.key user_people-service.crt > user_people-service.pem
	cat user_app-catalog.key user_app-catalog.crt > user_app-catalog.pem
	cat user_app-registry.key user_app-registry.crt > user_app-registry.pem
	cat user_mongodb-tester.key user_mongodb-tester.crt > user_mongodb-tester.pem
	cat user_sanity.key user_sanity.crt > user_sanity.pem
	cat user_livegrid-core.key user_livegrid-core.crt > user_livegrid-core.pem
	cat user_middleware-api-gateway.key user_middleware-api-gateway.crt > user_middleware-api-gateway.pem
	cat user_security-auth-services.key user_security-auth-services.crt > user_security-auth-services.pem
	cat user_security-ams.key user_security-ams.crt > user_security-ams.pem

	#Create the secret mongo-secret.yaml
	kubectl create secret generic mongo-secret \
	--from-file=pemKeyPass.txt \
	--from-file=./mongo-CA-cert.crt \
	--from-file=mongo-0.pem \
	--from-file=mongo-1.pem \
	--from-file=mongo-2.pem \
	--from-file=user_admin.pem \
	--from-file=user_app-catalog.pem \
	--from-file=user_itm.pem \
	--from-file=user_people-service.pem \
	--from-file=user_app-registry.pem \
	--from-file=user_mongodb-tester.pem \
	--from-file=user_sanity.pem \
	--from-file=user_livegrid-core.pem \
	--from-file=user_middleware-api-gateway.pem \
	--from-file=user_security-auth-services.pem \
	--from-file=user_security-ams.pem 
	#Export mongo-secret in order to have a safely backup
	kubectl get secret mongo-secret -o yaml > mongo-secret.yaml
	cd ${WORKING_DIR}
}

upgrade() {

	#Delete Stateful Sets

	currentDir=`pwd`
	echo $pwd

	set_secret=""

	STATEFULSET=$(kubectl get statefulset | grep mongo)

	if [[ ! -z $STATEFULSET ]]; then

		kubectl delete statefulset mongo --cascade=false
	fi

	#Delete Mongo service
	SERVICE=$(kubectl get service | grep mongo)
	if [[ ! -z $SERVICE ]]; then
		kubectl delete service mongo
	fi


	#Delete Pods
	array=(mongo-0 mongo-1 mongo-2)
	for item in ${array[*]}
	do
		POD=$(kubectl get pods | grep $item)
		if [[ ! -z $POD ]]; then
			kubectl delete pod $item
		fi
	done

	# In OM 1.0 GA, we prompted the user for a password for a literal mongo secret.  We assume that the password is still there.
	# We use that password for creating the x509 certificates.
	# If the secret doesn't exist, we prompt the user for a new password.
	# Once upgraded, to run the upgrade script a second time, the user must delete the mongo secret to force a re-prompt of the password and recreation of the secret

	if [[ "$(kubectl get secrets -o jsonpath={.items[*].metadata.name})" =~ .*mongo-secret.* ]]; then

		mongo_secret=$(kubectl get secret mongo-secret --template='{{.data.secret}}')
		if [[ $mongo_secret = "<no value>" ]]; then

			logIt "ERROR : Mongo Secret is set but has no value. Exiting.  Delete the mongo secret via 'kubectl delete secret mongo-secret' and rerun.  You will be prompted for a password. "
			exit 1
		else

			set_mongo_secret=$(echo "${mongo_secret}" | base64 --decode)

		fi
	else

		readPassword "Mongo secret"			# result in set_secret
		set_mongo_secret=${set_secret}
		set -o errexit
	fi

	deleteSecretIfExists mongo-secret

	createMongoSecret

	#Create the new Stateful Sets

	cd $currentDir
	kubectl create -f deploy_fromscript.yaml
}



upgrade

echo "Clean exit"
exit 0
