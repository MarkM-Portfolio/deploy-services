#!/bin/bash

set -o errexit
set -o pipefail
#set -o nounset
#set -o xtrace


PRODUCT=cc	# default value for Connections Cloud

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
	logIt "Usage: ./uploadChart.sh [OPTION]"
	logIt "This script will push a Helm Chart to Governor."
	logIt "	The Helm chart must exist."
	logIt "	The Helm chart must have a.tgz extension."
	logIt "	The Helm chart name and Chart Name must be unique."

	logIt ""
	logIt "Options are:"
	logIt "-u   	| --user			Credentials required for SSO Access to https://requests.governor.infrastructure.conncloudk8s.com.  Must have [Governor-Product-cc]
[Governor-Product-cc-Requests] access to SSO-BU01-SB System.  Request Access to https://usam.svl.ibm.com:9443/AM/index.jsp"
	logIt "-p   	| --pass			Password for above user.  If not specified, user will be prompted."
	logIt "-pa	| --path			Image name e.g. middleware/redis.  Required."
	logIt "-po   	| --product			Product. Default is cc.  Optional"
	logIt ""

	logIt "Sample Usage : ./uploadChart.sh -pa /root/chart/mychart.tgz"

	
	
}

uploadChart() {

	set -o errexit
       
	if [ ${interactive_login} = true ]; then
		logInfo "Credentials required for SSO Access to https://requests.governor.infrastructure.conncloudk8s.com"
		echo -n "Login: "
		read SSO_USER
		echo -n "Password: "
		read -s SSO_PASS
		echo
	fi

	# Check if chart exists and has the .tgz extension
	if [ -f ${PATHTOCHART} ]; then
	   echo "File $PATHTOCHART exists. OK."
	   if [ ${PATHTOCHART: -4} != ".tgz" ]; then
		logErr "File Extension is not .tgz.  EXITING."
		exit 1
	   fi
	   
	else
	   logErr "File $PATHTOCHART does not exist. EXITING."	
	   exit 1
	fi

	CREDSBASE64=$(echo ${SSO_USER}:${SSO_PASS} | tr -d '\n' | base64 -w 0)
	PRODUCT=$PRODUCT
	
	response=$(curl -H "Authorization: Basic ${CREDSBASE64}" -F "file=@${PATHTOCHART}" -F "product=${PRODUCT}" -X PUT "https://requests.governor.infrastructure.conncloudk8s.com/chart" | python -c "import sys, json; print json.load(sys.stdin)['msg']")
	logIt "%{http_code}"
	
	if [ "%{http_code}" != 200 ]; then
		logErr "Upload Failed.  Exiting.  Reason : $response"
		exit 1
	fi

}


interactive_login=true

while [[ $# -gt 0 ]]
do
	key="$1"

	case $key in
		-u|--user)
			SSO_USER="$2"
			shift
			;;
		-p|--pass)
			SSO_PASS="$2"
			shift
			;;
		-pa|--path)
			PATHTOCHART="$2"
			shift
			;;
                -po|--product)
			PRODUCT="$2"
			shift
			;;               
                	
		*)
			usage
			;;
	esac
	shift
done


if [ "${PATHTOCHART}" = "" ]; then
	logErr "Missing Data"
	logErr "PATHTOCHART = ${PATHTOCHART}"

	usage

	exit 5
fi

if [ "${SSO_USER}" != "" -a "${SSO_PASS}" != "" ]; then
	interactive_login=false
fi

uploadChart






