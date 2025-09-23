#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

if [ "`id -u`" != 0 ]; then
	echo "Must run as root"
	exit 1
fi


(
	echo "Running with arguments:  $*"
	echo
) 2>&1 | tee -a /var/log/cfc.log-deployPink.log

ARTIFACTORY_HOST=artifactory.cwp.pnp-hcl.com
ARTIFACTORY_USER=""
ARTIFACTORY_PASS=""
BOOT_FQHN=""
MASTER_FQHN=""
WORKER_FQHN=""
INFRA_WORKER_FQHN=""
PROXY_FQHN=""
ICHOST_FQHN=""
ICADMIN_USER=""
ICADMIN_PASS=""
ROOT_PASSWORD=""
FILENAME=""
HYBRIDCLOUD_FOLDER=""
ICROOT_PASS=""
ICHTTPSERVER_PATH=/opt/IBM/HTTPServer/
MASTER_FRONT_END=""
PROXY_FRONT_END=""
hybridFlagCount=0
pwd=""
useLocal=false
SET_BLOCK_DEVICE=false
BLOCK_DEVICE=""
skip_check_pods=false
check_pod_retries=60
check_pod_wait=15
stack=""
starterStack=false
onlyStack=false
old_installation_directory=""

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
	logIt "Usage: ./deployPink.sh [OPTION]"
	logIt "This script will download deployable IBM Connections Pink artifact, deploy CfC, configure storage and install IBM Connections Pink on CfC"
	logIt ""
	logIt "Options are:"
	logIt "-u   | --user			User to pull from $ARTIFACTORY_HOST. If not specified, user will be prompted."
	logIt "-p   | --pass			Password for above user.  If not specified, user will be prompted."
	logIt "-b   | --boot			FQHN of Boot Server.  Required."
	logIt "-m   | --master			FQHN of Master Server.  Required."
	logIt "-w   | --worker			Comma sepaared list of Worker Machines - FQHN.  Required."
	logIt "-iw  | --infra_worker		Comma sepaared list of Infra Worker Machines - FQHN.  Optional additional argument if deploying dedicated infrastructure for Elasticsearch."
	logIt "-pr  | --proxy			FQHN of Proxy Server. Required."
	logIt "-ic  | --ic_host		FQHN of Connections OnPrem server.  Required."
	logIt "-icA | --ic_admin		IC Admin Username.  Required."
	logIt "-icP | --ic_pass		IC Admin Password.  Required."
	logIt "-icR | --ic_rootpass		IC Root Password.  Required."
	logIt "-pw  | --root_password		Root Password of Nodes - for skip SSH Prompts.  One of root or non-root arguments required."
	logIt "-nru | --non_root_user		Non-root user of Nodes - for skip SSH Prompts.  One of root or non-root arguments required."
	logIt "-nrpw| --non_root_password	Non-root user password of Nodes - for skip SSH Prompts.  One of root or non-root arguments required."

	logIt ""
	logIt "HA options:"
	logIt "-cmip  | --CfCmasterVIP		IP address for CfC master cluster.  Optional (unless doing HA)."
	logIt "-cmif  | --CfCmasterIFace	Primary interface on master nodes (usually eth0).  Optional (unless doing HA)."
	logIt "-cpip  | --CfCproxyVIP		IP address for CfC proxy cluster.  Optional (unless doing HA)."
	logIt "-cpif  | --CfCproxyIFace	Primary interface on proxy nodes (usually eth0).  Optional (unless doing HA)."
	logIt "-hamr  | --HaMountReg		The HA Mount Registry of the system including the server FQHN. optional. HA only. Example: -hamr <storage_server.hostname.com>:/CFC_IMAGE_REPO "
	logIt "-hama  | --HaMountAud		The HA Mount Audit of the system including the server FQHN. optional. HA only. Example: -hama <storage_server.hostname.com>:/CFC_AUDIT"
	logIt "-bd    | --BlockDev		Use this flag is the system is  being used for HA. set to ignore if not using Block Device and specify the block device if you are using a block device. Example: -bd ignore" 

	logIt ""
	logIt "Other options:"
	logIt "-fi  | --filename		Filename of zip e.g. hybridcloud_20170324-083845.zip.  Optional.  If not specified, will use latest zip"
	logIt "-sH  | --setHybrid		The hybridcloud folder from artifactory e.g. hybridcloud_602.  Optional. Only to be used when testing specialist builds like hybridcloud_602. Cannot be used with dev or pub."
	logIt "-fs  | --useFileSystem		Use local filesystem without zip.  Infers no zip download and a local build exists.  Optional"
	logIt "-lo  | --local			Use local zip instead of downloading. Infers zip already downloaded or built locally.  Optional"
	logIt "-de  | --dev			Use a zip from the hybridcloud_test and not the publish location"
	logIt "-pub | --PrePublish		Use a zip from the staging location. Used for testing zips before publish"
	logIt "-sC  | --skipCfC		Skip CfC deployment.  Infers already installed.  Optional"
	logIt "-uC  | --useExistingCfC		Deploy with CfC already in /opt/deployCfC.  Optional"
	logIt "-fo  | --forcePSR		Force re-creation of persistent storage (used when uninstalling and installing with same VMs)"
	logIt "-un  | --uninstall		Uninstall Pink."
	logIt "-up  | --upgrade			Upgrade ICp."
	logIt "-cl  | --clean_level		key=value pair for uninstall clean level, valid arguments:  clean, cleaner, cleanest (default is clean)"
	logIt "-icH | --ic_httpserverpath	IBM Connections Server HTTP Server Path."
	logIt "-sB  | --skipBlue		Skip IBM Connections Blue configuration steps."
	logIt "-cl  | --clean			Clean OrientMe Applications before Installing."
	logIt "-uZ  | --useZip			Flag for using published version of deployPink."
	logIt "-ss  | --startStack		The starter stack to install"
	logIt "-os  | --onlyStack		Only install a starter stack and skip everything else. Must be used with -sp"
	logIt "-sCP | --skipCheckPods		Don't finish up with checkPods.sh"
	logIt "-cPR | --checkPodRetries	If finishing up with checkPods.sh, the number of retries (if not using the default ${check_pod_retries})"
	logIt "-cPW | --checkPodWait		If finishing up with checkPods.sh, the wait time in seconds between retries (if not using the default ${check_pod_wait})"
	logIt "-nrK | --newRelicKey		The new relic license key. Support for SVT"
	logIt "-nrL | --newRelicLab		The new relic label. Support for SVT"
	logIt "-was | --wasPath			The WebSphere directory path. Only needed for skip_Blue=no. Example: /opt/IBM/WebSphere"
	logIt "-ci  | --connections_install     Location where ICp will be deployed from."
	logIT "-oid | --old_installation_directory	Location where ICp is currently installed if upgrading or uninstalling and using new location"

	logIt ""
	logIt "sample usage (published build - non-interactive login) : ./deployPink.sh -u <ARTIFACTORY_USER> -p <ARTIFACTORY_PASS> -b mybootnode.mydomain.com -m mymasternode.mydomain.com -w myworkernode1.mydomain.com,myworkernode2.mydomain.com,myworkernode3.mydomain.com -pr myproxynode.mydomain.com -ic myconnserver.mydomain.com -icA adminusername -icP adminpassw0rd -icR ibmconnectionsServerRootPW -icH /opt/IBM/HTTPServer/ -pw mypassw0rd"
	logIt ""

	logIt "sample usage (published build - interactive login) : ./deployPink.sh -b mybootnode.mydomain.com -m mymasternode.mydomain.com -w myworkernode1.mydomain.com,myworkernode2.mydomain.com,myworkernode3.mydomain.com -pr myproxynode.mydomain.com -ic myconnserver.mydomain.com -icA adminusername -icP adminpassw0rd -icR ibmconnectionsServerRootPW -icH /opt/IBM/HTTPServer/ -pw mypassw0rd"
	logIt ""

	logIt "sample usage (local build) : ./deployPink.sh -b mybootnode.mydomain.com -m mymasternode.mydomain.com -w myworkernode1.mydomain.com,myworkernode2.mydomain.com,myworkernode3.mydomain.com -pr myproxynode.mydomain.com -ic myconnserver.mydomain.com -pw mypassw0rd -icA adminusername -icP adminpassw0rd -icR ibmconnectionsServerRootPW -icH /opt/IBM/HTTPServer/ -lo -fi hybridcloud_20170324-083845.zip"


	logIt ""
	logIt "sample usage (reapply OrientMe Applications over deployed CFC) : ./deployPink.sh -b mybootnode.mydomain.com -m mymasternode.mydomain.com -w myworkernode1.mydomain.com,myworkernode2.mydomain.com,myworkernode3.mydomain.com -pr myproxynode.mydomain.com -ic myconnserver.mydomain.com -pw mypassw0rd -icA adminusername -icP adminpassw0rd -icR ibmconnectionsServerRootPW -cl -sC -fo"

	logIt ""
	logIt "sample usage (published build - HA mode - interactive login) : ./deployPink.sh -b mybootnode.mydomain.com -m mymasternode1.mydomain.com,mymasternode1.mydomain.com,mymasternode3.mydomain.com -w myworkernode1.mydomain.com,myworkernode2.mydomain.com,myworkernode3.mydomain.com -pr myproxynode1.mydomain.com,myproxynode2.mydomain.com,myproxynode3.mydomain.com -ic myconnserver.mydomain.com -icA adminusername -icP adminpassw0rd -icR ibmconnectionsServerRootPW -icH /opt/IBM/HTTPServer/ -pw mypassw0rd -icA adminusername -icP adminpassw0rd -icR ibmconnectionsServerRootPW -cmip 1.1.1.1 -cmif eth0 -cpip 3.3.3.3 -cpif eth0"



	exit 1
}

collectLogs() {
	if [ $? != 0 ]; then
		echo "Error in deployment process found. Running log collection."
		if [ -f $conn_locn/deployCfC/collectLogs.sh ]; then
			bash $conn_locn/deployCfC/collectLogs.sh
		else
			echo "Trap could not find collectLogs script."
		fi
		exit 14
  	else
		echo "DeployPink.sh completed. Check system to ensure the deployment was successful"
  	fi
}
trap collectLogs EXIT

downloadZip() {

	if [ ${use_local_zip} = false ]; then

		if [ ${interactive_artifactory_login} = true ]; then

			printf "Enter username : "
			read ARTIFACTORY_USER

			printf "Enter password : "
			read -s ARTIFACTORY_PASS

		fi

		if [ "${FILENAME}" = "" ]; then

			curl -SLO -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} https://${ARTIFACTORY_HOST}/artifactory/ibm-connections-cloud-docker/conncloud/docker-base-images/$HYBRIDCLOUD_FOLDER/mastered.sem

			FILENAME=`cat mastered.sem`

			logInfo "Latest Zip : https://${ARTIFACTORY_HOST}/artifactory/ibm-connections-cloud-docker/conncloud/docker-base-images/$HYBRIDCLOUD_FOLDER/${FILENAME}"
			logIt ""
			logIt ""
		fi


		logInfo "Downloading Zip : https://${ARTIFACTORY_HOST}/artifactory/ibm-connections-cloud-docker/conncloud/docker-base-images/$HYBRIDCLOUD_FOLDER/${FILENAME}"

		set -o errexit

		curl -SLO -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} https://${ARTIFACTORY_HOST}/artifactory/ibm-connections-cloud-docker/conncloud/docker-base-images/$HYBRIDCLOUD_FOLDER/${FILENAME}
	else

		logInfo "Using local zip - ${FILENAME}.  Not downloading from Artifactory."

		if [ ! -f ${FILENAME} ]; then
			logErr "${FILENAME} not found!  Exiting."

			exit 1
		fi


	fi
}

unzipPink() {
	set +o nounset
	if [ $# -lt 1 ]; then
		logErr "usage:  unzipPink bUseFilesystem [sNonRootUser]"
		exit 13
	fi
	use_filesystem=$1
	non_root_user="$2"
	set -o nounset

	if [ ${use_filesystem} = false ]; then
		logInfo "Unzipping Archive."

		set -o errexit

		logInfo unzipping

		rm -rf microservices

		unzip ${FILENAME}
		rm -f ${FILENAME}

		if [ "${non_root_user}" != "" ]; then
			echo "Changing ownership to ${non_root_user}"
			chown -R ${non_root_user} microservices
		fi
	else
		logInfo "Not unzipping download archive, using direct from filesystem"
		if [ ! -f microservices/hybridcloud/install.sh -o ! -f microservices/hybridcloud/images/orientme/orient-web-client.tar ]; then
			logErr "Unable to find valid build on filesystem"
			exit 14
		fi
	fi
}


configureNewRelic() {
	if [ $# -ne 2 ]; then
		logErr "usage:  configureNewRelic bConfigureNewRelic"
		exit 13
	fi
	nrKey=$1
	nrLabel=$2

	if [ ! -f microservices/hybridcloud/bin/common_values.yaml ]; then
		logErr "Unable to find common_values.yaml"
		exit 14
	fi

	echo "ENABLING NEWRELIC"
	echo "newRelic:" >> microservices/hybridcloud/bin/common_values.yaml
	echo "  licenceKey: '${nrKey}'" >> microservices/hybridcloud/bin/common_values.yaml
	echo "  enabled: true" >> microservices/hybridcloud/bin/common_values.yaml
	echo "  labels: '${nrLabel}'" >> microservices/hybridcloud/bin/common_values.yaml
	cat microservices/hybridcloud/bin/common_values.yaml
}

copyCfCinstall() {
	if [ $# -ne 1 ]; then
		logErr "usage:  copyCfCinstall bUseExistingCfC"
		exit 14
	fi
	use_existing_CfC=$1

	set -o errexit
	if [ ${use_existing_CfC} = true ]; then
		logInfo "Skipping copy of deployCfC - existing version assumed"
		if [ ! -f $conn_locn/deployCfC/deployCfC.sh ]; then
			logErr "Unable to find $conn_locn/deployCfC/deployCfC.sh"
			exit 16
		fi
	else
		DATE=`date "+%F-%T"`
		# Back up the old installation directory
		if [ -d ${old_installation_directory}/deployCfC ]; then
			echo "Backing up ${old_installation_directory}/deployCfC to ${old_installation_directory}/deployCfC_${DATE}"
			mv -f ${old_installation_directory}/deployCfC/ ${old_installation_directory}/deployCfC_${DATE}
		fi
		rm -rf ${old_installation_directory}/deployCfC
		rm -rf $conn_locn/deployCfC
		# For non-default deployments, need to create the directory so deployCfC becomes the dest dir
		if [ ! -d $conn_locn ]; then
			mkdir -p $conn_locn
		fi
		# Copy the deployCfC directory from the extracted zip to the $conn_locn
		cp -avr microservices/hybridcloud/deployCfC $conn_locn
		# Move runtime folder from backed up old installation directory if it exists
		if [ -d ${old_installation_directory}/deployCfC_${DATE}/runtime ]; then
			echo "Restoring runtime folder from ${old_installation_directory}/deployCfC_${DATE}/runtime"
			mv -f ${old_installation_directory}/deployCfC_${DATE}/runtime $conn_locn/deployCfC
		fi
		# Move config folder from backed up old installation directory if it exists
		if [ -d ${old_installation_directory}/deployCfC_${DATE}/config ]; then
			echo "Restoring config folder from ${old_installation_directory}/deployCfC_${DATE}/config"
			mv -f ${old_installation_directory}/deployCfC_${DATE}/config $conn_locn/deployCfC
		fi
		# Delete the backed up old installation directory
		echo "Removing ${old_installation_directory}/deployCfC_${DATE}"
		rm -rf ${old_installation_directory}/deployCfC_${DATE}

		chmod -R 755 $conn_locn/deployCfC
	fi
}

deployCfC() {
	if [ $# -ne 1 ]; then
		logErr "usage:  deployCfC bSkipCfC"
		exit 11
	fi
	skip_CfC=$1

	if [ ${skip_CfC} = true ]; then
		logInfo "Skipping deployCfC - existing deployment assumed"
		if [ ! -d /var/lib/docker/containers ]; then
			logErr "Couldn't find evidence of an existing CfC deployment"
			exit 15
		fi
	else
		logInfo ""
		logInfo "Deploying CfC"
		
		if [ ${upgrade} = true ]; then
			cfc_arguments="--boot=$BOOT_FQHN --master_list=$MASTER_FQHN --worker_list=$WORKER_FQHN --proxy_list=$PROXY_FQHN --set_ic_host=$ICHOST_FQHN --set_krb5_secret=$conn_locn/deployCfC/secrets/krb5keytab.yml --set_ic_admin_user=$ICADMIN_USER --set_ic_admin_password=$ICADMIN_PASS --skip_ssh_prompts ${user_args} ${password_args} ${EXTRA_ARGS} ${CFC_MASTER_ARGS} ${CFC_PROXY_ARGS}"
		else
			cfc_arguments="--boot=$BOOT_FQHN --master_list=$MASTER_FQHN --worker_list=$WORKER_FQHN --proxy_list=$PROXY_FQHN --set_redis_secret=redissecret --set_search_secret=searchsecret --set_solr_secret=solrsecret --set_elasticsearch_ca_password=escapassword --set_elasticsearch_key_password=eskeypassword --set_ic_host=$ICHOST_FQHN --set_krb5_secret=$conn_locn/deployCfC/secrets/krb5keytab.yml --set_ic_admin_user=$ICADMIN_USER --set_ic_admin_password=$ICADMIN_PASS --skip_ssh_prompts ${user_args} ${password_args} ${EXTRA_ARGS} ${CFC_MASTER_ARGS} ${CFC_PROXY_ARGS}"
		fi
		echo "Running deployCfC.sh deployment with arguments:  ${cfc_arguments}"
		$conn_locn/deployCfC/deployCfC.sh ${cfc_arguments}
	fi
}

prepareSupportingScripts() {
	if [ $# -ne 1 ]; then
		logErr "usage:  prepareSupportingScripts bUseLocal"
		exit 11
	fi
	useLocal=$1

	script_list="
		scripts/mongodb-solr-zk-samples-nfs-volumes-creation.sh
		scripts/configurationDriver.sh
		scripts/configure-ha-storage.sh
		microservices/hybridcloud/doc/samples/checkPods.sh
	"

	if [ "${useLocal}" = true ]; then
		logInfo "Using local volume creation scripts"
		for script in ${script_list}; do
			basename_script=`basename ${script}`
			if [ ! -f ${basename_script} ]; then
				if [ -f ${script} ]; then
					cp -p ${script} .
				else
					echo "Can't find local script:  ${basename_script}"
					exit 11
				fi
			fi
		done
	elif [ "${useLocal}" = false ]; then
		# pull from github
		logInfo "Downloading volume creation scripts"
		TOKEN="0fc2408c6107bc7048e1f476f104c957972dd6af"
		OWNER="connections"
		REPO="deploy-services"

		for script in ${script_list}; do
			PATH_FILE=${script}
			FILE="https://github.ibm.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
			curl -H "Authorization: token $TOKEN" \
				-H "Accept: application/vnd.github.v3.raw" \
				-O \
				-L $FILE
			chmod +x `basename ${script}`
		done
	else
		echo "Unknown argument to prepareSupportingScripts():  ${useLocal}"
		exit 11
	fi

	for script in ${script_list}; do
		basename_script=`basename ${script}`
		if [ ! -f ${basename_script} ]; then
			echo "Couldn't find script:  ${basename_script}"
			exit 11
		fi
	done
}

setBlockDeviceFlag() {
	if [ $# -ne 1 ]; then
		logErr "usage: setBlockDeviceFlag requires ignore or block device location passed in"
		exit 12
	fi
	BLOCK_DEVICE=$1
	if [[ "${BLOCK_DEVICE}" == "IGNORE" ]] || [[ "${BLOCK_DEVICE}" == "ignore" ]]; then
		EXTRA_ARGS="${EXTRA_ARGS} --docker_storage_block_device=ignore"
	elif [[ "${BLOCK_DEVICE}" != "" ]]; then
		EXTRA_ARGS="${EXTRA_ARGS} --docker_storage_block_device=${BLOCK_DEVICE}" 
	else
		echo "When using the -bd or --BlockDev flag, you must specify set it to ignore or the block device location"
	fi
}

createVolumes() {
	if [ $# -lt 1 ] && [  $# -gt 2 ]; then
		logErr "usage:  createVolumes bRecreatePersistentVolumes bUseZip"
		exit 12
	fi
	force_persistent_storage_rebuild=$1
	useZip=$2

	logInfo "Creating Persistent Volumes"
	argumentList=""
	if [ "${HA_MOUNT_REGISTRY}" != "" ]; then
		argumentList=$argumentList" -hA"
	fi
	if [ ${useZip} = true ]; then
		argumentList=$argumentList" -uZ"
	fi
	if [ ${force_persistent_storage_rebuild} = true ]; then
		argumentList=$argumentList" -f"
		logIt ""
		logIt "Forcing persistent storage rebuild"
		logIt ""
	fi
	bash mongodb-solr-zk-samples-nfs-volumes-creation.sh ${argumentList}
}

configureIBMConnections() {
	if [ -f configurationDriver.sh ]; then
                bash configurationDriver.sh microservices/hybridcloud/ $ICHOST_FQHN $ICROOT_PASS $ICHTTPSERVER_PATH ${MASTER_FRONT_END} $ICADMIN_USER $ICADMIN_PASS $WASPATH
	else
		echo "configurationDriver.sh not found"
		exit 1
	fi
}

configureHAStorageNFS() {
	if [[ "${HA_MOUNT_AUDIT}" != "" ]]; then
		bash configure-ha-storage.sh $conn_locn $NFS_FQHN $ROOT_PASSWORD $HA_MOUNT_REGISTRY $HA_MOUNT_AUDIT
	else
		bash configure-ha-storage.sh $conn_locn $NFS_FQHN $ROOT_PASSWORD $HA_MOUNT_REGISTRY
	fi
}

cleanPink() {

	set +e

	logInfo "Cleaning Pink from CfC"

	pushd $pwd/microservices/hybridcloud/bin > /dev/null

	bash clean.sh

	popd > /dev/null

	set -o errexit

}

installPink() {
	pushd $pwd/microservices/hybridcloud > /dev/null

	if [ ${starterStack} = false ]; then
		logInfo "Deploying Pink to CfC"

		bash install.sh
	elif [[ "${stack}" != "" ]]; then 
		logInfo "Deploying Pink ${stack} starter stack to CfC"
		
		bash install.sh -ip ${stack}
	else
		logInfo "Starter stack flag set but no stack has been entered"
		usage
	fi

	popd > /dev/null
}

uninstallPink() {

	logInfo "Uninstalling Pink"

	if [ -e "$conn_locn/deployCfC/deployCfC.sh" ]; then
		if [ "${uninstall_version}" = "" ]; then
			modified_extra_args="${EXTRA_ARGS}"
		else
			set +o errexit
			if [ "${EXTRA_ARGS}" = "" ]; then
				modified_extra_args="--alt_cfc_version=${uninstall_version}"
			else
				modified_extra_args=`echo ${EXTRA_ARGS} | sed -e "s/--alt_cfc_version=[0-9].[0-9].[0-9]/--alt_cfc_version=${uninstall_version}/" -e "s/--alt_cfc_version=[0-9].[0-9].[0-9].[0-9]/--alt_cfc_version=${uninstall_version}/"`
				if [ "${EXTRA_ARGS}" != "${modified_extra_args}" ]; then
					logInfo "Uninstall version override:  ${modified_extra_args}"
				else
					logErr "Failed to override uninstall version to ${uninstall_version}.  Is --alt_cfc_version set to ${uninstall_version} redundantly?  If so, --uninstall=${uninstall_version} does not need to be passed to deployPink.sh too.  Just pass --alt_cfc_version=${uninstall_version} to deployCfC.sh."
					exit 99
				fi
			fi
			set -o errexit
		fi
		echo "yes" | $conn_locn/deployCfC/deployCfC.sh --boot=$BOOT_FQHN --master_list=$MASTER_FQHN --worker_list=$WORKER_FQHN --proxy_list=$PROXY_FQHN --uninstall=${uninstall_clean_level} --skip_ssh_prompts ${user_args} ${password_args} ${modified_extra_args} ${CFC_MASTER_ARGS} ${CFC_PROXY_ARGS}
	else
		logErr "Unable to uninstall - CfC deployment scripts are missing"
		exit 13
	fi

}

set +o nounset
if [ "${EXTRA_DEPLOYCFC_ARGS}" != "" ]; then
	EXTRA_ARGS=${EXTRA_DEPLOYCFC_ARGS}
else
	EXTRA_ARGS=""
fi
set -o nounset


CFC_MASTER_ARGS=""
interactive_artifactory_login=true
use_local_zip=false
skip_Blue=false
skip_CfC=false
use_existing_CfC=false
force_persistent_storage_rebuild=false
skip_persistent_storage=false
use_filesystem=false
dev=false
pub=false
sethybrid=false
uninstallpink=false
upgrade=false
uninstall_version=""
uninstall_clean_level=clean
cleanpink=false
MASTER_VIP=""
PROXY_VIP=""
MASTER_IFACE=""
PROXY_IFACE=""
ROOT_PASSWORD=""
NON_ROOT_USER=""
NON_ROOT_PASSWORD=""
HA_MOUNT_REGISTRY=""
HA_MOUNT_AUDIT=""
NFS_FQHN=""
configureHANFS=false
nrKey=""
nrLabel=""
nrConfig=false
WASPATH=""
conn_locn=/opt

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
		-b|--boot)
			BOOT_FQHN="$2"
			shift
			;;
		-m|--master)
			MASTER_FQHN="$2"
			shift
			;;
		-w|--worker)
			WORKER_FQHN="$2"
			shift
			;;
		-iw|--infra_worker)
			INFRA_WORKER_FQHN="$2"
			shift
			;;
		-pr|--proxy)
			PROXY_FQHN="$2"
			shift
			;;
		-ic|--ic_host)
			ICHOST_FQHN="$2"
			shift
			;;
		-icA|--ic_admin)
			ICADMIN_USER="$2"
			shift
			;;
		-icP|--ic_pass)
			ICADMIN_PASS="$2"
			shift
			;;
		-cmip|--CfCmasterVIP)
			MASTER_VIP="$2"
			shift
			;;
		-cmif|--CfCmasterIFace)
			MASTER_IFACE="$2"
			shift
			;;
		-cpip|--CfCproxyVIP)
			PROXY_VIP="$2"
			shift
			;;
		-cpif|--CfCproxyIFace)
			PROXY_IFACE="$2"
			shift
			;;
		-icR|--ic_rootpass)
			ICROOT_PASS="$2"
			shift
			;;
		-icH|--ic_httpserverpath)
			ICHTTPSERVER_PATH="$2"
			shift
			;;
		-pw|--root_password)
			ROOT_PASSWORD="$2"
			shift
			;;
		-nru|--non_root_user)
			NON_ROOT_USER="$2"
			shift
			;;
		-nrpw|--non_root_password)
			NON_ROOT_PASSWORD="$2"
			shift
			;;
		-sB|--skipBlue)
			skip_Blue=true
			;;
		-sC|--skipCfC)
			skip_CfC=true
			;;
		-uC|--useExistingCfC)
			use_existing_CfC=true
			echo "use_existing_CfC"
			;;
		-lo|--local)
			use_local_zip=true
			;;
		-fs|--useFileSystem)
			use_filesystem=true
			;;
		-fi|--filename)
			FILENAME="$2"
			shift
			;;
		-sH|--setHybrid)
			HYBRIDCLOUD_FOLDER="$2"
			shift
			sethybrid=true
			let hybridFlagCount+=1
			;;
		-fo|--forcePSR)
			force_persistent_storage_rebuild=true
			;;
		-spv|--skipPV)
			skip_persistent_storage=true
			;;
		-de|--dev)
			dev=true
			let hybridFlagCount+=1
			;;
		-hamr|--HaMountReg)
			HA_MOUNT_REGISTRY="$2"
			shift
			;;
		-hama|--HaMountAud)
			HA_MOUNT_AUDIT="$2"
			shift
			;;
		-chanfs|--configureHANFS)
			configureHANFS=true
			;;
		-pub|--PrePublish)
			pub=true
			let hybridFlagCount+=1
			;;
		-bd|--BlockDev)
			BLOCK_DEVICE="$2"
			SET_BLOCK_DEVICE=true
			shift
			;;
		-un*|--uninstall*)
			uninstallpink=true
			set +o errexit
			echo ${key} | grep -q =
			if [ $? -eq 0 ]; then
				uninstall_version=`echo ${key} | awk -F= '{ print $2 }'`
				echo "CfC uninstall override version:  ${uninstall_version}"
			fi
			set -o errexit
			;;
		-up|--upgrade)
			upgrade=true
			;;
		-cl=*|--clean_level=*)
			uninstall_clean_level=`echo ${key} | awk -F= '{ print $2 }'`
			;;
		-uZ|--useZip)
			useLocal=true
			;;
		-cl|--clean)
			cleanpink=true
			;;
		-sCP|--skipCheckPods)
			skip_check_pods=true
			;;
		-cPW|--checkPodWait)
			check_pod_wait="$2"
			shift
			;;
		-cPR|--checkPodRetries)
			check_pod_retries="$2"
			shift
			;;
		-ss|--startStack)
			stack="$2"
			shift
			starterStack=true
			;;
		-os|--onlyStack)
			onlyStack=true
			;;
		-nrK|--newRelicKey)
                        nrKey="$2"
                        shift
                        ;;
		-nrL|--newRelicLab)
                        nrLabel="$2"
                        shift
                        ;;
		-was|--wasPath)
			WASPATH="$2"
			shift
			;;
		-ci|--connections_install)
			conn_locn=$2
			shift
			;;
		-oid|--old_installation_directory)
			old_installation_directory=$2
			shift
			;;	
		*)
			usage
			;;
	esac

	shift
done

if [ "${NON_ROOT_USER}" != "" -a "${NON_ROOT_PASSWORD}" = "" ]; then
	echo "--non_root_user requires --non_root_password"
	exit 1
fi
if [ "${ROOT_PASSWORD}" != "" -a "${NON_ROOT_PASSWORD}" != "" ]; then
	echo "--root_password and --non_root_user/--non_root_password are mutually exclusive"
	exit 1
fi
if [ "${ROOT_PASSWORD}" = "" -a "${NON_ROOT_PASSWORD}" = "" ]; then
	echo "One of --root_password or --non_root_user/--non_root_password must be used"
	exit 1
fi
if [ "${uninstall_version}" = 1.1.0 -a "${NON_ROOT_PASSWORD}" != "" ]; then
	echo "1.1.0 does not support --non_root_user/--non_root_password"
	exit 1
fi
if [ "${uninstall_clean_level}" != clean -a "${uninstall_clean_level}" != cleaner -a "${uninstall_clean_level}" != cleanest ]; then
	echo "Valid --clean arguments are clean, cleaner, cleanest"
	exit 1
fi
if [ "${ROOT_PASSWORD}" != "" ]; then
	user_args=""
	password_args="--root_login_passwd=${ROOT_PASSWORD}"
else
	user_args="--non_root_user=${NON_ROOT_USER}"
	password_args="--non_root_passwd=${NON_ROOT_PASSWORD}"
fi
if [[ "${WASPATH}" == "" ]] && [ ${skip_Blue} = false ]; then
	echo "When trying to configure blue you must supply the WebSphere directory with the -was or --wasPath argument"
	exit 1
fi
if [[ "${nrKey}" != "" ]] && [[ "${nrLabel}" != "" ]]; then
	nrConfig=true
fi
if [[ "${nrKey}" == "" ]] && [[ "${nrLabel}" != "" ]]; then
		echo "When trying to configure new relic you need both to use both -nrK and -nrL flags"
		usage
elif [[ "${nrLabel}" == "" ]] && [[ "${nrKey}" != "" ]]; then
		echo "When trying to configure new relic you need both to use both -nrK and -nrL flags"
		usage
fi

if [ "${INFRA_WORKER_FQHN}" != "" ]; then
	EXTRA_ARGS="${EXTRA_ARGS} --infra_worker_list=${INFRA_WORKER_FQHN}"
fi

if [ "${HA_MOUNT_REGISTRY}" != "" ]; then
	EXTRA_ARGS="${EXTRA_ARGS} --master_HA_mount_registry=${HA_MOUNT_REGISTRY}"
	if [ "${HA_MOUNT_AUDIT}" != "" ]; then
		EXTRA_ARGS="${EXTRA_ARGS} --master_HA_mount_audit=${HA_MOUNT_AUDIT}"
	else
		echo "When deploying a CfC HA system you must have a mount for HA_MOUNT_AUDIT and for HA_MOUNT_REGISTRY" 
		usage
	fi
	if [[ "${HA_MOUNT_REGISTRY}" =~ .*":".* ]] && [[ "${HA_MOUNT_AUDIT}" =~ .*":".* ]]; then
		NFS_FQHN=`echo ${HA_MOUNT_REGISTRY} | cut -d: -f1`
	else
		echo "When using a mount for HA_MOUNT_AUDIT and for HA_MOUNT_REGISTRY, you must specify a hostname or ip address for the server to store the directory to. Example HA_MOUNT_REGISTRY.hostname.com:/CFC_IMAGE_REPO"
		usage
	fi
fi

if [ ${upgrade} = true ]; then
	EXTRA_ARGS="${EXTRA_ARGS} --upgrade"
fi

if [ "${old_installation_directory}" != "" ]; then
	if [ ! -d ${old_installation_directory}/deployCfC ]; then
		echo "Unable to find ${old_installation_directory}/deployCfC. Please check this is the correct old installation directory."
		exit 1
	fi
else
	old_installation_directory=${conn_locn}
	if [ ${upgrade} = true ] && [ ! -d ${old_installation_directory}/deployCfC ]; then
		echo "Unable to find the directory ${old_installation_directory}/deployCfC"
		echo "If you are upgrading using a different install directory to the one that was used during the initial install, please use the flag -oid or --old_installation_directory to pass in the original install location"
		exit 1
	fi
fi

if [ ${upgrade} = false ] && [ ${skip_persistent_storage} = true ]; then
	echo "You can only skip persistent volume creation if you are upgrading"
	exit 1
fi

if [ ${starterStack} = false ] && [ ${onlyStack} = true ]; then
	echo "When using -os or --onlyStack, you must use -ss or --startStack"
	usage
fi

if [[ "${stack}" = "" ]] && [ ${onlyStack} = true ]; then
	echo "When using -os or --onlyStack, you must must specify a starter stack using -ss or --startStack"
	usage
fi

if [[ $hybridFlagCount -gt 1 ]]; then
	echo "de, pub and setHybrid flags can not be used together"
	exit 1
fi

if [ "${MASTER_VIP}" = "" ]; then
	MASTER_FRONT_END="${MASTER_FQHN}"
else
	MASTER_FRONT_END="${MASTER_VIP}"
	if [[ "${BLOCK_DEVICE}" == "" ]] || [ ${SET_BLOCK_DEVICE} = false ]; then
		echo "When deploying a HA system you must use the block device flag"
		usage
	fi
fi

if [[ "${BLOCK_DEVICE}" != "" ]] && [ ${SET_BLOCK_DEVICE} = true ]; then
	setBlockDeviceFlag ${BLOCK_DEVICE}
fi

if [ "${PROXY_VIP}" = "" ]; then
	PROXY_FRONT_END="${PROXY_FQHN}"
else
	PROXY_FRONT_END="${PROXY_VIP}"
fi
if [ "${MASTER_VIP}" != "" -a "${MASTER_IFACE}" != "" ]; then
	CFC_MASTER_ARGS="--master_HA_vip=${MASTER_VIP} --master_HA_iface=${MASTER_IFACE}"
else
	logInfo "Not deploying with master HA"
	CFC_MASTER_ARGS=""
fi
if [ "${PROXY_VIP}" != "" -a "${PROXY_IFACE}" != "" ]; then
	CFC_PROXY_ARGS="--proxy_HA_vip=${PROXY_VIP} --proxy_HA_iface=${PROXY_IFACE}"
else
	logInfo "Not deploying with proxy HA"
	CFC_PROXY_ARGS=""
fi

if [ ${skip_CfC} = true -a ${uninstallpink} = true ]; then
	logErr "Can't use --skipCfC with --uninstall"
	exit 10
fi

if [ "${ARTIFACTORY_USER}" != "" -a "${ARTIFACTORY_PASS}" != "" ]; then
	interactive_artifactory_login=false
fi


if [ "${BOOT_FQHN}" = "" -o "${MASTER_FQHN}" = "" -o "${WORKER_FQHN}" = "" -o "${PROXY_FQHN}" = "" -o "${ICHOST_FQHN}" = "" -o "${ICADMIN_USER}" = "" -o "${ICADMIN_PASS}" = "" -o "${ICROOT_PASS}" = "" ]; then
	logErr "Missing boot, master_list, worker_list, proxy_list, ichost or password definitions"

	logErr "BOOT = ${BOOT_FQHN}"
	logErr "MASTER_LIST = ${MASTER_FQHN}"
	logErr "WORKER_LIST = ${WORKER_FQHN}"
	logErr "PROXY_LIST = ${PROXY_FQHN}"
	logErr "ICHOST = ${ICHOST_FQHN}"
	logErr "ICADMIN_USER = ${ICADMIN_USER}"
	logErr "ICADMIN_PASS = ${ICADMIN_PASS}"
	logErr "ICROOT_PASS = ${ICROOT_PASS}"


	logErr ""

	usage

	exit 5
fi

if [ "${dev}" = true ]; then
	HYBRIDCLOUD_FOLDER="hybridcloud_test"
elif [ "${pub}" = true ]; then
	HYBRIDCLOUD_FOLDER="pre_publish"
elif [ "${sethybrid}" = true ]; then
	echo "HYBRIDCLOUD_FOLDER=$HYBRIDCLOUD_FOLDER"
	if [ "$HYBRIDCLOUD_FOLDER" == "" ]; then
		echo "To use -sH a folder name must be entered"
		usage
	fi
	if [ "$FILENAME" == "" ]; then
		echo "When using -sH -fi must also be used and set to the desired zip file name"
		usage
	fi
else
	HYBRIDCLOUD_FOLDER="hybridcloud"
fi

echo "hybridFlagCount = $hybridFlagCount"
if [[ $hybridFlagCount -gt 1 ]]; then
	echo "de, pub and setHybrid flags can not be used together. Only one can be used at a time"
	usage
fi

(
	script_location="`dirname \"$0\"`/.."
	echo
	cd "${script_location}" > /dev/null
	echo "Changed location to script directory location:"
	echo "	`pwd`"
	echo "	(relative path:  ${script_location})"
	pwd=$(pwd)

	if [ ${onlyStack} = false ]; then
		if [ ${use_filesystem} = false ]; then
			downloadZip
		fi

		unzipPink ${use_filesystem} ${NON_ROOT_USER}

		if [ ${nrConfig} = true ]; then
			configureNewRelic ${nrKey} ${nrLabel}
		fi

		copyCfCinstall ${use_existing_CfC}

		if [ ${uninstallpink} = true ]; then
			uninstallPink
		fi

		prepareSupportingScripts ${useLocal}

		if [ ${configureHANFS} = true ]; then
			configureHAStorageNFS
		fi

		deployCfC ${skip_CfC}

		if [ ${skip_persistent_storage} = true ]; then
			echo "Skipping persistent volume creation"
		else
			echo "Create Volumes"
			echo "force_persistent_storage_rebuild = $force_persistent_storage_rebuild"

			createVolumes ${force_persistent_storage_rebuild} ${useLocal}
		fi

		if [ ${cleanpink} = true ]; then
			cleanPink
		fi
 
	fi

	installPink

	if [ ${skip_Blue} != true ]; then
		pwd
		configureIBMConnections
	fi

	if [ ${skip_check_pods} = false ]; then
		bash checkPods.sh --retries=${check_pod_retries} --wait_interval=${check_pod_wait}
	fi

	exit 0
) 2>&1 | tee -a /var/log/cfc.log-deployPink.log


