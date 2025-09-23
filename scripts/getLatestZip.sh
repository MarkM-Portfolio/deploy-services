#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

ARTIFACTORY_HOST=artifactory.cwp.pnp-hcl.com
ARTIFACTORY_USER=""
ARTIFACTORY_PASS=""
DATE=""


logErr() {
	logIt "ERRO: " "$@"
}

logInfo() {
	logIt "INFO: " "$@"
}

logIt() {
	echo "$@"
}

usage() {
	logIt ""
	logIt "Usage: ./getLatestZip.sh [OPTION]"
	logIt "This script will download the latest deployable IBM Connections Pink artifact"
	logIt ""
	logIt "Options are:"
	logIt "-u  | --user		User to pull from $ARTIFACTORY_HOST. If not specified, user will be prompted."
	logIt "-p  | --pass		Password for above user.  If not specified, user will be prompted."	
	
	
	logIt ""
	logIt "sample usage : ./getLatestZip.sh -u <ARTIFACTORY_USER> -p <ARTIFACTORY_PASS> "
	

	exit 1
} 

downloadZip() {
	

		if [ ${interactive_artifactory_login} = true ]; then
		
			printf "Enter username : "
	        	read ARTIFACTORY_USER		
	
			printf "Enter password : "
	        	read -s ARTIFACTORY_PASS
		
		fi

		curl -SLO -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} https://${ARTIFACTORY_HOST}/artifactory/ibm-connections-cloud-docker/conncloud/docker-base-images/hybridcloud/mastered.sem
		
		latestDate=`cat mastered.sem`

		logInfo "Latest Zip : https://${ARTIFACTORY_HOST}/artifactory/ibm-connections-cloud-docker/conncloud/docker-base-images/hybridcloud/${latestDate}"
		logIt ""
		logIt ""


		logInfo "Downloading Zip : https://${ARTIFACTORY_HOST}/artifactory/ibm-connections-cloud-docker/conncloud/docker-base-images/hybridcloud/${latestDate}"

		set -o errexit		

		curl -SLO -C - -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} https://${ARTIFACTORY_HOST}/artifactory/ibm-connections-cloud-docker/conncloud/docker-base-images/hybridcloud/${latestDate}
	
}


interactive_artifactory_login=true

while [[ $# -gt 0 ]]
do
	key="$1"

	case $key in
		-u|--user)
			ARTIFACTORY_USER="$2"
			shift
			;;
		-p|--pass)
			ARTIFACTORY_PASS="$2"
			shift
			;;				
		*)
			usage
			;;
	esac
	shift
done

if [ "${ARTIFACTORY_USER}" != "" -a "${ARTIFACTORY_PASS}" != "" ]; then
	interactive_artifactory_login=false
fi


downloadZip

echo "Clean exit"
exit 0
