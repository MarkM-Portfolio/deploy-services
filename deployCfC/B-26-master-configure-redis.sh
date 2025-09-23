#!/bin/bash
#
# This script will configure IBM Connections for communicating Redis traffic to OrientMe
# The args passed are:
# CFC_HOSTNAME CFC Server Hostname/IPAddress
# REDIS_PORT
# ICHOST_FQHN FQHN of Connections OnPrem server.  Include http / https
# REDIS_SECRET

. ./00-all-config.sh

set -o errexit
set -o nounset

mkdir -p ${CONFIG_DIR}
touch ${CONFIG_DIR}/${HOSTNAME}

if grep -q ic_server_behind_proxy=true ${CONFIG_DIR}/${HOSTNAME}; then
	skip_configure_redis=true
fi

if [ ${skip_configure_redis} = true ]; then
	echo "Not configuring Redis"
else
	CFC_HOSTNAME=""
	REDIS_PORT=""
	ICHOST_FQHN=""
	REDIS_SECRET=""

	logErr() {
		logIt "ERRO: " "$@"
	}

	logInfo() {
		logIt "INFO: " "$@"
	}

	logIt() {
		echo "$@"
	}

	configureRedis() {
		CFC_HOSTNAME="$1"
		REDIS_PORT="$2"
		ICHOST_FQHN="$3"
		REDIS_SECRET="$4"

		echo "Setting c2.export.redis.host"

		confighost_response=`curl --insecure -w '%{http_code}' -v -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "settingName=c2.export.redis.host&settingValue=${CFC_HOSTNAME}" "https://${ICHOST_FQHN}/homepage/orgadmin/adminapi.jsp"`

		if [ ${confighost_response} -ne 200 ]; then
			confighost_response=`curl --insecure -w '%{http_code}' -v -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "settingName=c2.export.redis.host&settingValue=${CFC_HOSTNAME}" "http://${ICHOST_FQHN}/homepage/orgadmin/adminapi.jsp"`
			if [ ${confighost_response} -ne 200 ]; then
				logErr "redis host config failed. Exiting. Reason : ${confighost_response}. Please check your connections server is up and healthy. Exiting"
				exit 1
			fi
		fi

		echo "Setting c2.export.redis.port"

		configport_response=`curl --insecure -w '%{http_code}' -v -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "settingName=c2.export.redis.port&settingValue=${REDIS_PORT}" "https://${ICHOST_FQHN}/homepage/orgadmin/adminapi.jsp"`

		if [ ${configport_response} -ne 200 ]; then
			configport_response=`curl --insecure -w '%{http_code}' -v -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "settingName=c2.export.redis.port&settingValue=${REDIS_PORT}" "http://${ICHOST_FQHN}/homepage/orgadmin/adminapi.jsp"`
			if [ ${configport_response} -ne 200 ]; then
				logErr "redis port config failed. Reason : ${configport_response}. Please check your connections server is up and healthy. Exiting"
				exit 2
			fi
		fi

		echo "Setting c2.export.redis.pass"

		configpass_response=`curl --insecure -w '%{http_code}' -v -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "settingName=c2.export.redis.pass&settingValue=${REDIS_SECRET}" "https://${ICHOST_FQHN}/homepage/orgadmin/adminapi.jsp"`

		if [ ${configpass_response} -ne 200 ]; then
			configpass_response=`curl --insecure -w '%{http_code}' -v -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "settingName=c2.export.redis.pass&settingValue=${REDIS_SECRET}" "http://${ICHOST_FQHN}/homepage/orgadmin/adminapi.jsp"`
			if [ ${configport_response} -ne 200 ]; then
				logErr "redis password configuration failed. Reason : ${configpass_response}. Please check your connections server is up and healthy. Exiting"
				exit 3
			fi
		fi
	}

	if ${is_master_HA}; then
		master_ip=${master_HA_vip}
	else
		resolve_ip ${MASTER_LIST}	# result in resolve_ip_return_result
		master_ip=${resolve_ip_return_result}
		set -o errexit
	fi

	# Set the ic_host, port and password details
	ic_host=`kubectl get configmap topology-configuration -o jsonpath='{.data.ic-host}' -n $NAMESPACE`
	port=30379
	secret=`kubectl get secret redis-secret -o jsonpath='{.data.secret}' -n $NAMESPACE | base64 --decode`

	configureRedis "$master_ip" "$port" "${ic_host}" "$secret"
	if [ $? -ne 0 ]; then
		echo "Unable to configure redis."
		exit 1
	fi
fi

