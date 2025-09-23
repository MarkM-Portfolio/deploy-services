
#!/bin/bash

set -o errexit
set -o pipefail
#set -o nounset
#set -o xtrace


ICEKUBES_HOST=icekubes.swg.usma.ibm.com
HELM_CHARTNAME=""

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
	logIt "Usage: ./downloadHelmChart.sh [OPTION]"
	logIt "This script will download a HELM Chart from http://icekubes.swg.usma.ibm.com/helm/charts and unzip it."
	logIt ""
	logIt "Options are:"
	logIt "-u   | --user			User to pull from $ARTIFACTORY_HOST. If not specified, user will be prompted."
	logIt "-p   | --pass			Password for above user.  If not specified, user will be prompted."
	logIt "-ch   | --boot			Name of Helm Chart.  Required."
	
}

downloadHelmChart() {

	set -o errexit
	if [ ${interactive_login} = true ]; then
		logInfo "Authentication required for $ARTIFACTORY_HOST_AND_PORT"
		echo -n "Login: "
		read ARTIFACTORY_USER
		echo -n "Password: "
		read -s ARTIFACTORY_PASS
		echo
	fi

if [ $HELM_CHARTNAME = "" ]; then
     logErr "${HELM_CHARTNAME} is empty!  Exiting."
fi

curl -SLOk -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} http://icekubes.swg.usma.ibm.com/helm/charts/$HELM_CHARTNAME

tar xvf $HELM_CHARTNAME

}

interactive_login=true

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
                -ch|--helm_chart)
			HELM_CHARTNAME="$2"
			shift
			;;		
		*)
			usage
			;;
	esac
	shift
done


if [ "${HELM_CHARTNAME}" = "" ]; then
	logErr "Missing helm chartname"

	logErr ""

	usage

	exit 5
fi

if [ "${ARTIFACTORY_USER}" != "" -a "${ARTIFACTORY_PASS}" != "" ]; then
	interactive_login=false
fi

downloadHelmChart


