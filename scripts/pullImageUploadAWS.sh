#!/bin/bash

set -o errexit
set -o pipefail
#set -o nounset
#set -o xtrace

ARTIFACTORY_HOST=artifactory.cwp.pnp-hcl.com
ARTIFACTORY_HOST_AND_PORT=${ARTIFACTORY_HOST}:6562
BUILDTAG=""
IMAGENAME=""

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
	logIt "Usage: ./pullImageUploadAWS.sh [OPTION]"
	logIt "This script will pull a docker image from Artifactory and Upload it to AWS."
	logIt ""
	logIt "Options are:"
	logIt "-u   	| --user			User to pull from $ARTIFACTORY_HOST. If not specified, user will be prompted."
	logIt "-p   	| --pass			Password for above user.  If not specified, user will be prompted."
	logIt "-bld   	| --build			Build Tag to Pull from Artifactory.  Required."
	logIt "-im	| --image			Image name e.g. middleware/redis.  Required."
	logIt "-sP	| --skipPush			If specified, will skip the push to AWS.  Optional."
	logIt "-de	| --debug			If specified, will provide additional debug info.  Optional."
        logIt ""
	logIt "Sample Usage : ./pullImageUploadAWS.sh -bld 3.2.10-20170831.165817 -im middleware/redis"



	
	
}

pullAndUploadToAWS() {

	set -o errexit
       
	if [ ${interactive_login} = true ]; then
		logInfo "Authentication required for $ARTIFACTORY_HOST_AND_PORT"
		echo -n "Login: "
		read ARTIFACTORY_USER
		echo -n "Password: "
		read -s ARTIFACTORY_PASS
		echo
	fi

	docker login -u ${ARTIFACTORY_USER} -p ${ARTIFACTORY_PASS} ${ARTIFACTORY_HOST_AND_PORT}

	docker pull ${ARTIFACTORY_HOST_AND_PORT}/${IMAGENAME}:${BUILDTAG}

	cmd="--artifactoryImageName=${ARTIFACTORY_HOST_AND_PORT}/${IMAGENAME} --artifactoryImageTag=${BUILDTAG} --awsImageName=${IMAGENAME}"
	
	echo ${cmd}

	if [ ${skipPush} = true ]; then	
		cmd="$cmd --skipPush"
	fi
	

 	if [ ${debug} = "true" ]; then
		cmd="$cmd --debug"		
	fi

	echo ${cmd}

	./uploadImageToAWS.sh ${cmd}

}


interactive_login=true
skipPush=false
debug=false

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
                -bld|--build)
			BUILDTAG="$2"
			shift
			;;
                -im|--image)
			IMAGENAME="$2"
			shift
			;;
                -sP|--skipPush)
			skipPush=true
			;;
                -de|--debug)
			debug=true
			;;		
		*)
			usage
			;;
	esac
	shift
done


if [ "${BUILDTAG}" = "" -o "${IMAGENAME}" = "" ]; then
	logErr "Missing Data"

	logErr "BUILDTAG = ${BUILDTAG}"
	logErr "IMAGENAME = ${IMAGENAME}"

	usage

	exit 5
fi

if [ "${ARTIFACTORY_USER}" != "" -a "${ARTIFACTORY_PASS}" != "" ]; then
	interactive_login=false
fi

pullAndUploadToAWS




