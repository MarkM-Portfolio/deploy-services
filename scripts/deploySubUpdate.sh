#! /bin/bash
# Initial author: on Sun Feb  5 15:26:49 GMT 2017
#
# History:
# --------
# Sun Feb  5 15:26:49 GMT 2017
#	Initial version

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

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
	logIt "This script will deploy an update to a IBM Connections Pink Kubernetes Microservice"
	logIt ""
	logIt "For performing the deployment, there are 3 modes of operation"
	logIt "NB : All Modes log into CFC, Load the new Image, Tag the Image and Push the new Image to CFC"
	logIt ""

	logIt "Mode 1 : Excecute an upgrade script : Where a rolling update cannot be performed.  e.g. when updating a statefulset."
	logIt "Mode 2 : Perform a rolling update."
	logIt "Mode 3 : No Deploy : Where a microservice has an image but is deployed via another microservice.  e.g. mongodb-rs-setup"
	
	logIt ""
	logIt "Deployment : The deployer will attempt Mode 1 first.  If requirements of Mode 1 are not met, it will then attempt Mode 2, if requirements of Mode 2 are not met, it will attempt Mode 3."
	logIt ""

	logIt "Mode 1 :  Excecute an upgrade script"
	logIt "Requirements : "
	logIt "- upgrade.sh script exists in the microservice folder.  This script will represent a bash script to perform the update."
	logIt "- no deploy.yml exists in the microservice folder."
	logIt ""
	logIt "Mode 2 :  Perform a rolling Update:  Log in to CFC, Load Image, Tag Image, Push Image, Apply the new Image. "
	logIt "Requirements : "
	logIt "- deploy.yaml script exists in the microservice folder which represents the updated K8s configuration to apply."
	logIt ""

	logIt "Mode 3 :  No Deploy :   Log in to CFC, Load Image, Tag Image, Push Image, No Deploy."
	logIt "Requirements : "
	logIt "- no upgrade.sh script exists in the microservice folder."
	logIt "- no deploy.yml exists in the microservice folder."


	
}

while [[ $# -gt 0 ]]
do
	key="$1"

	case $key in		
                -h|--help)			
			usage
			;;
		*)
			
	esac
	shift
done



set +o nounset
if [ "${CNX_DEPLOYED_FROM_TOP_LEVEL}" != true ]; then
	echo
	echo "Deploy fixes from deployUpdates.sh only"
	exit 1
fi
set -o nounset


if [ -f upgrade.sh -a -f deploy.yaml ]; then
	echo
	echo "upgrade.sh and deploy.yaml both exist in the folder. If using a bash script to upgrade, must not use a deploy.yaml to store configuration data."
	exit 1
fi


# Uncomment after issue 2201 resolved
#if [ ! -f /opt/deployCfC/00-all-config.sh ]; then
#	echo
#	echo "Can't find IBM Connections deployment of Conductor for Containers"
#	exit 2
#fi
#. /opt/deployCfC/00-all-config.sh


this_fix_dir=`pwd | awk -F/ '{ print $NF }'`
if [ ! -f image.properties ]; then
	echo
	echo "Can't find image.properties for ${this_fix_dir}"
	exit 3
fi
. ./image.properties

set +o nounset
if [	"${image_name}" = "" -o \
	"${image_tag}" = "" -o \
	"${image_image_id}" = "" ]; then
	echo
	echo "Can't find a required image property"
	exit 4
fi
if [ ${this_fix_dir} != ${image_name} ]; then
	echo
	echo "WARNING:  usually the directory name for the fix ${this_fix_dir} matches"
	echo "the fix name ${image_name}.  The fix may be mispackaged."
fi
image_name_full=${image_name}.tar
if [ ! -f ${image_name_full} ]; then
	echo
	echo "Can't find image:  ${image_name_full}"
	exit 5
fi
#if [ ! -f deploy.yaml ]; then
#	echo
#	echo "Can't find deploy.yaml"
#	exit 6
#fi

if [ ${image_name} = orient-web-client ]; then
	subdir="orientme/"
elif [ ${image_name} = people-relationship ]; then
	subdir="people/"
elif [ ${image_name} = people-scoring ]; then
	subdir="people/"
elif [ ${image_name} = people-datamigration ]; then
	subdir="people/"
elif [ ${image_name} = itm-services ]; then
	subdir="itm/"
else
	subdir=""
fi

if [ -f pre-push-steps.sh ]; then
	echo
	echo "Executing pre-image push steps"
	bash pre-push-steps.sh $*
fi

echo
echo "Logging into local registry"
docker login -u ${ADMIN_USER} -p ${ADMIN_PASSWD} -e admin@us.ibm.com master.cfc:8500

echo
echo "Loading image"
docker load -i ${image_name_full}

echo
echo "Tagging image"
docker tag ${image_image_id} master.cfc:8500/default/${subdir}${image_name}:${image_tag}

echo
echo "Pushing image"
docker push master.cfc:8500/default/${subdir}${image_name}

if [ -f pre-deploy-steps.sh ]; then
	echo
	echo "Executing pre-deploy steps"
	bash pre-deploy-steps.sh $*
fi

if [ -f upgrade.sh ]; then

	chmod +x upgrade.sh
	bash upgrade.sh

elif [ -f deploy.yaml ]; then

	echo "Deploying image"
	kubectl apply -f deploy.yaml
else
	echo "Nothing to Deploy"
fi


if [ -f post-deploy-steps.sh ]; then
	echo
	echo "Executing post-deploy steps"
	bash post-deploy-steps.sh $*
fi



