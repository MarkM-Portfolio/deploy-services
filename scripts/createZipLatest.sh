#!/bin/bash

set -o errexit
set -o pipefail
#set -o nounset
#set -o xtrace

ARTIFACTORY_HOST=artifactory.cwp.pnp-hcl.com
ARTIFACTORY_HOST_AND_PORT=${ARTIFACTORY_HOST}:6562

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
	logIt "Usage: ./createZipLatest.sh [OPTION]"
	logIt "This script will configure and setup K8 on CFC"
	logIt ""
	logIt "Options are:"
	logIt "-u | --user	User to pull/push from/to ${ARTIFACTORY_HOST_AND_PORT}"
	logIt "-p | --pass	Password for above user"
	logIt "--service_list	Comma delimited list of services to build into update"
	logIt "--push		Push zip to ${ARTIFACTORY_HOST_AND_PORT}"
	logIt "			Note:  Push should only be done from Jenkins job"
	logIt "--nozip		Don't create ZIP (saves time for local builds)"
	logIt "--dev		Build a dev zip for upload to dev area.  Not based off master."
	logIt "--cyl		Don't pull yaml from icekubes"
	logIt "--fix_pack	Fix Pack Number e.g. 02.  If not specified, default is 01"
	logIt ""
	logIt "eg.:"
	logIt "./createZipLatest.sh"
	logIt "./createZipLatest.sh --nozip"
	logIt "./createZipLatest.sh -u ARTIFACTORY_USER -p ARTIFACTORY_PASS"
	logIt "./createZipLatest.sh -u ARTIFACTORY_USER -p ARTIFACTORY_PASS --push"
	logIt ""
	logIt "Note that --push and --nozip are mutually exclusive.  Must create ZIP to push."
	logIt ""
	exit 1
}

whichfile() {

	serviceToBuild=$1
	kind=$2

	nameToSearch=""
						
	if [[ ${serviceToBuild} = "analysis-service" ]]; then
		nameToSearch="analysisservice"
	elif [[ ${serviceToBuild} = "indexing-service" ]]; then
		nameToSearch="indexingservice"
	elif [[ ${serviceToBuild} = "itm-services" ]]; then
		nameToSearch="itm-services"
	elif [[ ${serviceToBuild} = "mail-service" ]]; then
		nameToSearch="mail-service"
	elif [[ ${serviceToBuild} = "orient-web-client" ]]; then
		nameToSearch="orient-webclient"
	elif [[ ${serviceToBuild} = "people-relationship" ]]; then
		nameToSearch="people-relation"
	elif [[ ${serviceToBuild} = "people-scoring" ]]; then
		nameToSearch="people-scoring"
	elif [[ ${serviceToBuild} = "people-datamigration" ]]; then
		nameToSearch="people-migrate"
	elif [[ ${serviceToBuild} = "retrieval-service" ]]; then
		nameToSearch="retrievalservice"
	fi
	
	if [[ -z $nameToSearch ]]; then
		logIt "No search term found when checking the service to build.  Service not included in list."
		exit 1
	fi

	FILE=""
	FILE=`grep -Pzl --exclude-dir=* '(?s)name: '${nameToSearch}'.*\n.*kind: '${kind}'|(?s)kind: '${kind}'.*\n.*name: '${nameToSearch}'' PINK*`
	echo "Found in $FILE"
}


buildMicroservice() {

	set -o errexit

	serviceToBuild=$1	
	echo "Working on $serviceToBuild"

	props_file="image.properties"

	# deployment.yaml or deployment.yml
	deployYmlFilename="deploy.yaml"

	# create the structure
	mkdir -p microservices/hybridcloud/${update_dir_name}/${serviceToBuild}

	cp -av scripts/deploySubUpdate.sh microservices/hybridcloud/${update_dir_name}/${serviceToBuild}

	# define any parent services
	if [ ${serviceToBuild} != 'mongodb-rs-setup' ]; then
		parentservice="mongodb"
	fi
	

	if [ ${pullfromintegration} = true ]; then

		
		if [ ${serviceToBuild} != 'mongodb-rs-setup' ]; then
			


		if [ ${serviceToBuild} = 'solr' ]; then

			# solr deployment.yml
			TOKEN="0fc2408c6107bc7048e1f476f104c957972dd6af"
			OWNER="connections"
			REPO="solr-basic"		

			# solr service.yml		
			PATH_FILE="deployment/kubernetes/service.yml"
			FILE="https://github.ibm.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
				curl -H "Authorization: token $TOKEN" \
				-H "Accept: application/vnd.github.v3.raw" \
				-O \
				-L $FILE
			
			cat service.yml > microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}

			echo '---' >> microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}			

			PATH_FILE="deployment/kubernetes/deployment.yml"
			FILE="https://github.ibm.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
			curl -H "Authorization: token $TOKEN" \
				-H "Accept: application/vnd.github.v3.raw" \
				-O \
				-L $FILE

			cat deployment.yml >> microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}
			

		elif [ ${serviceToBuild} = 'zookeeper' ]; then
	
			
			TOKEN="0fc2408c6107bc7048e1f476f104c957972dd6af"
			OWNER="connections"
			REPO="deploy-services"

			# zookeeper service.yml		
			PATH_FILE="microservices/hybridcloud/templates/zookeeper/service.yml"
			FILE="https://github.ibm.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
				curl -H "Authorization: token $TOKEN" \
				-H "Accept: application/vnd.github.v3.raw" \
				-O \
				-L $FILE

			cat service.yml > microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}

			echo '---' >> microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}

			PATH_FILE="microservices/hybridcloud/templates/zookeeper/deployment.yml"
			FILE="https://github.ibm.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
				curl -H "Authorization: token $TOKEN" \
				-H "Accept: application/vnd.github.v3.raw" \
				-O \
				-L $FILE
			
			cat deployment.yml >> microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}

			

		elif [ ${serviceToBuild} = 'mongodb' ]; then

			cp -av scripts/upgrade/mongodb/upgrade.sh microservices/hybridcloud/${update_dir_name}/${serviceToBuild}
			chmod +x microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/upgrade.sh

			deployYmlFilename="deploy_fromscript.yaml"
	
			# mongo statefulset.yml
			TOKEN="0fc2408c6107bc7048e1f476f104c957972dd6af"
			OWNER="connections"
			REPO="mongodb"

			# mongo service.yml		
			PATH_FILE="deployment/kubernetes/service.yml"
			FILE="https://github.ibm.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
				curl -H "Authorization: token $TOKEN" \
				-H "Accept: application/vnd.github.v3.raw" \
				-O \
				-L $FILE

			cat service.yml > microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}

			echo '---' >> microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}

			PATH_FILE="deployment/kubernetes/statefulset.yml"
			FILE="https://github.ibm.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
				curl -H "Authorization: token $TOKEN" \
				-H "Accept: application/vnd.github.v3.raw" \
				-O \
				-L $FILE
			
			cat statefulset.yml >> microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}	

			

		elif [ ${serviceToBuild} = 'haproxy' ]; then

			# haproxy deployment.yml
			TOKEN="0fc2408c6107bc7048e1f476f104c957972dd6af"
			OWNER="connections"
			REPO="middleware"

			# haproxy service.yaml		
			PATH_FILE="haproxy/service.yml"
			FILE="https://github.ibm.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
				curl -H "Authorization: token $TOKEN" \
				-H "Accept: application/vnd.github.v3.raw" \
				-O \
				-L $FILE

			cat service.yml > microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}

			echo '---' >> microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}

			PATH_FILE="haproxy/deployment.yaml"
			FILE="https://github.ibm.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
				curl -H "Authorization: token $TOKEN" \
				-H "Accept: application/vnd.github.v3.raw" \
				-O \
				-L $FILE
			
			cat deployment.yaml >> microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}

			sed -i -- "s|'master.cfc:8500/default/haproxy'|master.cfc:8500/default/haproxy|g" microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}

		elif [ ${serviceToBuild} = 'redis' ]; then

			cp -av scripts/upgrade/redis/upgrade.sh microservices/hybridcloud/${update_dir_name}/${serviceToBuild}
			chmod +x microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/upgrade.sh

			deployYmlFilename="deploy_fromscript.yaml"
	
			# redis statefulset.yml
			TOKEN="0fc2408c6107bc7048e1f476f104c957972dd6af"
			OWNER="connections"
			REPO="redis"

			# redis service.yml		
			PATH_FILE="deployment/kubernetes/ha/service.yml"
			FILE="https://github.ibm.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
				curl -H "Authorization: token $TOKEN" \
				-H "Accept: application/vnd.github.v3.raw" \
				-O \
				-L $FILE

			cat service.yml > microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}

			echo '---' >> microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}

			PATH_FILE="deployment/kubernetes/ha/statefulset.yml"
			FILE="https://github.ibm.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
				curl -H "Authorization: token $TOKEN" \
				-H "Accept: application/vnd.github.v3.raw" \
				-O \
				-L $FILE
			
			cat statefulset.yml >> microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}


			echo '---' >> microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}			
			
			# redis sentinel deployment.yml
			TOKEN="0fc2408c6107bc7048e1f476f104c957972dd6af"
			OWNER="connections"
			REPO="redis"

			PATH_FILE="deployment/kubernetes/ha/deployment.yml"
			FILE="https://github.ibm.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
				curl -H "Authorization: token $TOKEN" \
				-H "Accept: application/vnd.github.v3.raw" \
				-O \
				-L $FILE
			
			cat deployment.yml >> microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}		

		else
			
			touch microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}

			# Service
			if [ ${serviceToBuild} != 'people-datamigration' ]; then

				whichfile ${serviceToBuild} "Service"
	
				echo $FILE
		
				sed -i -- '/---/ d' $FILE

				cat $FILE >> microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}

				echo '---' >> microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}
			fi

			
			# Deployment
			whichfile ${serviceToBuild} "Deployment"
	
			echo $FILE
		
			sed -i -- '/---/ d' $FILE

			cat $FILE >> microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}	

		fi
		fi
		

	fi
	
	
	if [ ${serviceToBuild} = 'solr' ]; then

		i="middleware/solr/solr_tag"

		MW_TAG=$(curl -k -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} https://${ARTIFACTORY_HOST_AND_PORT}/artifactory/connections-docker/$i)
		if [ $? -ne 0 ]; then
			logErr "Likely problem pulling TAG info file"
			exit 2
		fi
		i=$(echo $i | awk '{split($0,arr,"/"); print arr[1]"/"arr[2]}'):$MW_TAG
		echo $MW_TAG

	elif [ ${serviceToBuild} = 'zookeeper' ]; then

		i="base/zookeeper/zookeeper_tag"

		MW_TAG=$(curl -k -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} https://${ARTIFACTORY_HOST_AND_PORT}/artifactory/connections-docker/$i)
		if [ $? -ne 0 ]; then
			logErr "Likely problem pulling TAG info file"
			exit 2
		fi
		i=$(echo $i | awk '{split($0,arr,"/"); print arr[1]"/"arr[2]}'):$MW_TAG
		echo $MW_TAG

	elif [ ${serviceToBuild} = 'mongodb' ]; then
		
		i="middleware/mongodb/mongodb_tag"

		MW_TAG=$(curl -k -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} https://${ARTIFACTORY_HOST_AND_PORT}/artifactory/connections-docker/$i)
		if [ $? -ne 0 ]; then
			logErr "Likely problem pulling TAG info file"
			exit 2
		fi
		i=$(echo $i | awk '{split($0,arr,"/"); print arr[1]"/"arr[2]}'):$MW_TAG
		echo $MW_TAG

	elif [ ${serviceToBuild} = 'mongodb-rs-setup' ]; then
		
		i="middleware/mongodb-rs-setup/mongodb-rs-setup_tag"

		MW_TAG=$(curl -k -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} https://${ARTIFACTORY_HOST_AND_PORT}/artifactory/connections-docker/$i)
		if [ $? -ne 0 ]; then
			logErr "Likely problem pulling TAG info file"
			exit 2
		fi
		i=$(echo $i | awk '{split($0,arr,"/"); print arr[1]"/"arr[2]}'):$MW_TAG
		echo $MW_TAG

	elif [ ${serviceToBuild} = 'haproxy' ]; then
		
		i="middleware/haproxy/haproxy_tag"

		MW_TAG=$(curl -k -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} https://${ARTIFACTORY_HOST_AND_PORT}/artifactory/connections-docker/$i)
		if [ $? -ne 0 ]; then
			logErr "Likely problem pulling TAG info file"
			exit 2
		fi
		i=$(echo $i | awk '{split($0,arr,"/"); print arr[1]"/"arr[2]}'):$MW_TAG
		echo $MW_TAG

	elif [ ${serviceToBuild} = 'redis' ]; then
		
		i="middleware/redis/redis_tag"

		MW_TAG=$(curl -k -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} https://${ARTIFACTORY_HOST_AND_PORT}/artifactory/connections-docker/$i)
		if [ $? -ne 0 ]; then
			logErr "Likely problem pulling TAG info file"
			exit 2
		fi
		i=$(echo $i | awk '{split($0,arr,"/"); print arr[1]"/"arr[2]}'):$MW_TAG
		echo $MW_TAG

	
	else
		i=$(cat microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename} | grep artifactory.cwp.pnp-hcl.com | awk '{split($0,img,"6562/"); print img[2]}')
		echo $i
	fi


	#Remove single quotation marks
	i="${i//\'}"

	tag=$(echo $i | cut -d':' -f2)	
	echo "tag is $tag"

	if [ -z "$tag" ]; then
		echo "ERROR: No Tag for $i. Exiting"
		exit 5
	fi


	IMG=$(echo $i | awk '{split($0,img,":"); print img[1]}')
	echo $IMG


	echo "Working on $i"
	# or do whatever with individual element of the array
	
	# TODO : Pull based of a meaningful tag e.g. docker pull ${ARTIFACTORY_HOST_AND_PORT}/orientme/orient-web-client:good_build, not a tag from icekubes pipeline

	docker pull ${ARTIFACTORY_HOST_AND_PORT}/$i
	docker inspect --format=\"{{.ID}}\" ${ARTIFACTORY_HOST_AND_PORT}/$i | sed 's/"//g' | cut -d':' -f2 > microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${serviceToBuild}_id.txt
	docker save `cat microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${serviceToBuild}_id.txt` -o microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${serviceToBuild}.tar
	#docker save `cat microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${serviceToBuild}_id.txt` -o microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${serviceToBuild}.tar && xz microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${serviceToBuild}.tar
	
	image_id=`cat microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${serviceToBuild}_id.txt`	

	IMG_SUFFIX=$(echo $IMG | awk '{split($0,img,"/"); print img[2]}')
	echo $IMG_SUFFIX

	if [ ${serviceToBuild} = 'solr' -o ${serviceToBuild} = 'zookeeper' -o ${serviceToBuild} = 'mongodb' -o ${serviceToBuild} = 'mongodb-rs-setup' -o ${serviceToBuild} = 'haproxy' -o ${serviceToBuild} = 'redis' ]; then
				

		if [ ${serviceToBuild} = 'mongodb-rs-setup' ]; then

			deployYmlFilename="deploy_fromscript.yaml"

			GREP_INFR_PATTERN=$(grep -r "image:" microservices/hybridcloud/${update_dir_name}/${parentservice}/${deployYmlFilename} | grep $IMG_SUFFIX$ | grep -m 1 -v "yml:#" | awk '{split($0,arr,"image: "); print arr[2]}')
						
			# Adding tag version to the infra (middlewares) images
			sed -i "/${GREP_INFR_PATTERN////\\/}$/s/$/:${tag}/" microservices/hybridcloud/${update_dir_name}/${parentservice}/${deployYmlFilename}
		else		
			
			GREP_INFR_PATTERN=$(grep -r "image:" microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename} | grep $IMG_SUFFIX$ | grep -m 1 -v "yml:#" | awk '{split($0,arr,"image: "); print arr[2]}')

			# Adding tag version to the infra (middlewares) images
			sed -i "/${GREP_INFR_PATTERN////\\/}$/s/$/:${tag}/" microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}
		fi

	fi

	# making the build.properties file
	echo "image_name=${serviceToBuild}" > microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${props_file}
	echo "image_tag=${tag}" >> microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${props_file}
	echo "image_image_id=${image_id}" >> microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${props_file}
	
	rm -rf microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${serviceToBuild}_id.txt

	if [ ${serviceToBuild} != 'mongodb-rs-setup' ]; then

		# Sync YAMLs to CFC
		sed -i -- "s|${ARTIFACTORY_HOST_AND_PORT}|master.cfc:8500/default|g" microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}
		sed -i -- "s|${ARTIFACTORY_HOST_AND_PORT}|master.cfc:8500/default|g" microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}
		sed -i -- 's|myregkey-cloud|myregkey|g' microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}
		sed -i -- '/namespace:/ d' microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}
		sed -i -- "s|middleware/||g" microservices/hybridcloud/${update_dir_name}/${serviceToBuild}/${deployYmlFilename}	

	fi

	logIt "Completed ${serviceToBuild}"
	logIt ""





}


containsElement () {
  local e
  for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
  return 1
}

buildZip() {
	set -o errexit
	if [ ${interactive_artifactory_login} = true ]; then
		logInfo "Authentication required for $ARTIFACTORY_HOST_AND_PORT"
		echo -n "Login: "
		read ARTIFACTORY_USER
		echo -n "Password: "
		read -s ARTIFACTORY_PASS
		echo
	fi
	docker login -u ${ARTIFACTORY_USER} -p ${ARTIFACTORY_PASS} ${ARTIFACTORY_HOST_AND_PORT}
	if [ $? -ne 0 ]; then
		# no log message, due docker login already provide one. Just exit it.
		exit 2
	fi

	# Support different invocation locations associated with this script at different times
	repo_top_dir="`dirname \"$0\"`/.."
	echo
	cd "${repo_top_dir}" > /dev/null
	echo "Changed location to repo top level dir:"
	echo "	`pwd`"
	echo "	(relative path:  ${repo_top_dir})"
	
	rm -rf microservices/hybridcloud/${update_dir_name}
	rm -rf microservices/hybridcloud/${update_dir_name}-*
	mkdir -p microservices/hybridcloud/${update_dir_name}
	cp -av scripts/deployUpdates.sh microservices/hybridcloud/${update_dir_name}

	cp -av scripts/fixpack_01.sh microservices/hybridcloud/${update_dir_name}
	
	cp -av scripts/update-configmaps.sh microservices/hybridcloud/${update_dir_name}

	cp -av scripts/configureRedis.sh microservices/hybridcloud/${update_dir_name}

	chmod +x microservices/hybridcloud/${update_dir_name}/*.sh

	curl -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} https://${ARTIFACTORY_HOST}/artifactory/connections-docker/builds/latest/connections.yaml > connections.yaml
		
	# Split them based on delimiter ---		
		
	csplit --prefix=PINK connections.yaml /---/  {*}

	echo "To deploy, run:  bash fixpack_01.sh" > microservices/hybridcloud/${update_dir_name}/README.txt
	
	IFS=',' read -r -a SERVICESTOBUILD <<< "$SERVICE_LIST"	
	
	found=0
	for i in "${SERVICESTOBUILD[@]}"
	do	

		if [ $i = 'mongodb-rs-setup' ]; then

			
			for i in "${SERVICESTOBUILD[@]}"
			do
				if [[ $i == "mongodb" ]]; then
            				
					logIt "Found mongodb when mongodb-rs-setup is included."
					found=1
            				break				
        			fi
			done
			

			if [[ $found = 0 ]]; then
	
				logErr "Service List Error : mongodb-rs-setup listed but no mongodb listed. "
				logErr "The service mongodb-rs-setup is dependant on mongodb and if mongodb-rs-setup is required, mongodb must also be listed and listed prior to mongo-rs-setup"

				exit 5
			fi
	
		fi

		
	done

		
	for i in "${SERVICESTOBUILD[@]}"
	do	
		echo "Building ${i}"
		buildMicroservice ${i}
	done

	

	rm -f microservices/hybridcloud/*.txt
	rm -rf microservices/hybridcloud/templates
	rm -rf microservices/hybridcloud/images
	rm -rf microservices/hybridcloud/bin
	rm -rf microservices/hybridcloud/install.sh
	rm -rf microservices/hybridcloud/environment
	rm -rf microservices/hybridcloud/doc

	DATE=`date +%Y%m%d-%H%M%S`
	FILETOUPLOAD="hybridcloud_fixpack${FIXPACK_NUMBER}_$DATE.zip"
	SHA1FILE="$FILETOUPLOAD.sha1"


	if [ ${create_zip} = true ]; then
		if [ ${push_to_artifactory} = true ]; then
			zip_args=-4	# save space - 8% reduction, 42% more time
		else
			zip_args=-1	# save time
		fi
		pushd microservices/hybridcloud > /dev/null
		mv ${update_dir_name} ${update_dir_name}-${DATE}
		zip ${zip_args} -r ../../$FILETOUPLOAD ${update_dir_name}-${DATE}
		popd > /dev/null

		sha1sum $FILETOUPLOAD > $SHA1FILE

	else
		echo "Not creating ZIP"
	fi

	if [ ${push_to_artifactory} = true ]; then

		# create a mastered.sem to indicate that the upload has completed
		echo $FILETOUPLOAD > mastered.sem

		echo "Pushing build into ${ARTIFACTORY_HOST}"

		curl -v -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} -k -X PUT https://${ARTIFACTORY_HOST}/artifactory/ibm-connections-cloud-docker/conncloud/docker-base-images/${push_folder}/ --upload-file $FILETOUPLOAD

		curl -v -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} -k -X PUT https://${ARTIFACTORY_HOST}/artifactory/ibm-connections-cloud-docker/conncloud/docker-base-images/${push_folder}/ --upload-file mastered.sem

		curl -v -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} -k -X PUT https://${ARTIFACTORY_HOST}/artifactory/ibm-connections-cloud-docker/conncloud/docker-base-images/${push_folder}/ --upload-file $SHA1FILE


	else
		echo "Not pushing build into ${ARTIFACTORY_HOST}"
	fi
}


push_to_artifactory=false
interactive_artifactory_login=true
create_zip=true
push_folder=hybridcloud_60Fix
pullfromintegration=true
update_dir_name="update"
FIXPACK_NUMBER="01"
FILE=""

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
		--service_list)
			SERVICE_LIST="$2"
			shift
			;;
		--fix_pack)
			FIXPACK_NUMBER="$2"
			shift
			;;
		--push)
			echo "Pushing to artifactory"
			push_to_artifactory=true
			;;
		--nozip)
			echo "Not creating ZIP"
			create_zip=false
			;;
		--dev)
			push_folder=hybridcloud_60Fix_test
			;;
		--cyl)
			pullfromintegration=false
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
if [ ${create_zip} = false -a ${push_to_artifactory} = true ]; then
	echo "Must create ZIP if pushing to artifactory"
	exit 3
fi
if [ "${SERVICE_LIST}" = "" ]; then
	echo "No services to build"
	exit 4
fi




buildZip

echo "Clean exit"
exit 0
