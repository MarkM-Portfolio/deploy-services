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

cd ${WORKING_DIR}

# XYZZY:  This script is obsolete once we stop support for ICp 1.2.1

if [ ${skip_kibana_deployment} = true ]; then
	echo "Not deploying Kibana"
else
	if [ ${HOSTNAME} != ${BOOT} ]; then
		echo "Kibana only deployed on first master node"
	else
		uninstallKibana

		pullFromDocker kibana:${KIBANA_VERSION}
		if [ $? -ne 0 ]; then
			exit 101
		fi
		set -o errexit

		if ${is_master_HA}; then
			master_ip=${master_HA_vip}
		else
			resolve_ip ${MASTER_LIST}	# result in resolve_ip_return_result
			master_ip=${resolve_ip_return_result}
			set -o errexit
		fi

		echo "Deploying Kibana"
		set -o xtrace
		nginx_port=`netstat -pan | grep :8743 | awk '{ print $7 }' | egrep -o '^[^/]+'`
		nginx_port=`ps -deaf | grep " $nginx_port " | grep "nginx -g daemon off" | awk '{ print $3 }'`
		nginx_id=`ps -deaf | grep " $nginx_port " | grep "docker-containerd-shim" | awk '{ print $9 }'| cut -c1-8`
		mkdir -p ${KIBANA_DIR}
		docker cp $nginx_id:/etc/cfc/conf ${KIBANA_DIR}
		docker run -d --name kibana -p 5601:5601 -e ELASTICSEARCH_URL="https://${master_ip}:8743" -e ELASTICSEARCH_SSL_CERT="/kibana/server.pem" -e ELASTICSEARCH_SSL_KEY="/kibana/server-key.pem" -e ELASTICSEARCH_SSL_CA="/kibana/ca.pem" -e ELASTICSEARCH_SSL_VERIFY="false" kibana:${KIBANA_VERSION}
		kibana_id=`docker ps | grep kibana | awk '{ print $1 }'`
		docker cp ${KIBANA_DIR}/conf/es/ $kibana_id:/kibana
		docker cp $kibana_id:/opt/kibana/config/kibana.yml ${KIBANA_DIR}
		sed -ri "s!^(\#\s*)?(elasticsearch\.ssl.cert:).*!\2 '/kibana/server.pem'!" ${KIBANA_DIR}/kibana.yml
		sed -ri "s!^(\#\s*)?(elasticsearch\.ssl.key:).*!\2 '/kibana/server-key.pem'!" ${KIBANA_DIR}/kibana.yml
		sed -ri "s!^(\#\s*)?(elasticsearch\.ssl.ca:).*!\2 '/kibana/ca.pem'!" ${KIBANA_DIR}/kibana.yml
		sed -ri "s!^(\#\s*)?(elasticsearch\.ssl.verify:).*!\2 'false'!" ${KIBANA_DIR}/kibana.yml
		docker cp ${KIBANA_DIR}/kibana.yml $kibana_id:/opt/kibana/config
		docker restart $kibana_id

		echo "Kibana dashboard available here: http://${master_ip}:5601"
	fi
fi

