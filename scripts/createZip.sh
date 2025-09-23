#!/bin/bash

set -o errexit
set -o pipefail
#set -o nounset
#set -o xtrace

ARTIFACTORY_HOST=connections-docker.artifactory.cwp.pnp-hcl.com

sidecarTag=""

logErr() {
	logIt "ERROR: " "$@"
}

logInfo() {
	logIt "INFO: " "$@"
}

logIt() {
	echo "$@"
}

usage() {
	logIt ""
	logIt "Usage: ./createZip.sh [OPTION]"
	logIt ""
	logIt "Options are:"
	logIt "-u | --user	User to pull/push from/to ${ARTIFACTORY_HOST_AND_PORT}"
	logIt "-p | --pass	Password for above user"
	logIt "--push		Push zip to ${ARTIFACTORY_HOST_AND_PORT}"
	logIt "			Note:  Push should only be done from Jenkins job"
	logIt "--nozip		Don't create ZIP (saves time for local builds)"
	logIt "--dev		Build a dev zip for upload to dev area.  Not based off master."
	logIt "--pub            Build a potential zip for upload to staging area to be tested before publish"
	logIt "--csl            Build the customizerLite zip"
	logIt ""
	logIt "eg.:"
	logIt "./createZip.sh"
	logIt "./createZip.sh --nozip"
	logIt "./createZip.sh -u ARTIFACTORY_USER -p ARTIFACTORY_PASS"
	logIt "./createZip.sh -u ARTIFACTORY_USER -p ARTIFACTORY_PASS --push"
	logIt "./createZip.sh -u ARTIFACTORY_USER -p ARTIFACTORY_PASS --push --csl"
	logIt ""
	logIt "Note that --push and --nozip are mutually exclusive.  Must create ZIP to push."
	logIt ""
	exit 1
}

getChart() {

	build=$1
	if [ ! -f microservices_connections/hybridcloud/helmbuilds/${build}.tgz ]; then
		cd microservices_connections/hybridcloud/helmbuilds
		# get chart from artifactory
		http_status=`curl --write-out '%{http_code}' --insecure --remote-name https://${ARTIFACTORY_HOST}/artifactory/v-connections-helm/${build}.tgz`
		if [ $? -eq 1 -o "${http_status}" != 200 ]; then
	            echo "Failed to pull chart from Artifactory"
        	    exit 1
		fi
		gzip -v -t ${build}.tgz
		if [ $? -ne 0 ]; then
			echo "Corrupt helm chart:  ${build}.tgz"
			exit 2
		fi
		gunzip < ${build}.tgz | tar -tf -
		if [ $? -ne 0 ]; then
			echo "Corrupt helm chart:  ${build}.tgz"
			exit 3
		fi

		cd -;
	fi
}

PullCharts() {

    declare -a arr=("bootstrap" "connections-env" "elasticsearch" "elasticsearch7" "sanity" "sanity-watcher" "mw-proxy" "cnx-ingress" "k8s-psp" "ic360" "kudos-boards-cp" "connections-outlook-desktop" "kudos-boards-cp-activity-migration" "component-pack-pvc-efs" )
	for t in "${arr[@]}"; do
		build=`grep ^$t-[[:digit:]].[[:digit:]].[[:digit:]]* microservices_connections/hybridcloud/helmbuilds/latest_helmbuilds.txt`
		# Remove trailing spaces
		build="$(echo -e "${build}" | sed -e 's/[[:space:]]*$//')"
		getChart ${build}
	done
}


makeChartofChart() {

	declare arr=("${!2}")
	name=$1
	rm -rf $name
	helm create $name
	rm -rf $name/templates
	touch "$name/requirements.yaml"
	echo "dependencies:" > $name/requirements.yaml

	for component  in "${arr[@]}"; do

		if [ $component  == "redis" ]; then
			build=`grep -v "redis-sentinel" microservices_connections/hybridcloud/helmbuilds/latest_helmbuilds.txt | grep $component`
		else
			build=`grep $component microservices_connections/hybridcloud/helmbuilds/latest_helmbuilds.txt`
		fi

		# Remove trailing spaces
		build="$(echo -e "${build}" | sed -e 's/[[:space:]]*$//')"

		# pattern is a variable, use : instead of /
		# returns [[:digit:]].[[:digit:]].[[:digit:]]-<tag>
		version=$(echo -e $build | sed -e "s:$component-::")

		echo "  - name: ${component}" >> $name/requirements.yaml
		echo "    repository: '@connections'" >> $name/requirements.yaml
		echo "    version: ${version}" >> $name/requirements.yaml
	done

	cd $name
	helmdepup
}

addHelmRepo() {

	# if connections repo already exists, the repo will be overwritten with the new repo

	# Artifactory only supports resolution of Helm charts from virtual Helm chart repositories.
	helm repo add connections https://${ARTIFACTORY_HOST}/artifactory/v-connections-helm

}

helmdepup() {

	helm dep up

}

helmPackage() {

	# Support different invocation locations associated with this script at different times
	repo_top_dir="`dirname \"$0\"`/.."
	echo
	cd "${repo_top_dir}" > /dev/null
	echo "Changed location to repo top level dir:"
	echo "	`pwd`"
	echo "	(relative path:  ${repo_top_dir})"

	pwd

	name=$1

	chartDate=`date +%Y%m%d-%H%M%S`
	chartVersion=$2-${chartDate}
	sed -i "s|^version: .*$|version: ${chartVersion}|" $name/Chart.yaml

	helm package $name

	cp -av $name-${chartVersion}.tgz microservices_connections/hybridcloud/helmbuilds

}

makeValuesYaml() {

	declare arr=("${!2}")

	name=$1

	rm -rf values.yaml

	touch "values.yaml"

  	echo "global:" >> values.yaml
	echo "  image:" >> values.yaml
   	echo "    repository: null" >> values.yaml
	echo "  onPrem: null" >> values.yaml
	echo " " >> values.yaml

	for component  in "${arr[@]}"
	do

		tar xvf charts/$component-[[:digit:]]*.tgz $component/values.yaml

		echo "$component :" >> values.yaml


		while IFS='' read -r line || [[ -n "$line" ]]; do
			echo "  $line" >> values.yaml

		done < "$component/values.yaml"

		if [ ${component} == mongodb ]; then
			# Get the mongo sidecar tag
			sidecarTag=`grep sidecarTag $component/values.yaml | awk '{print $2}'`
			echo $sidecarTag
		fi


		rm -rf $component

	done
}

pullImageTag() {

	imageTag="$1"
	imageName="$2"

	echo "docker pull ${ARTIFACTORY_HOST}/${imageName}:${imageTag}"
	docker pull ${ARTIFACTORY_HOST}/${imageName}:${imageTag}
	#check if pull was successful
	if [ $? -eq 1 ]; then
		echo "Pull Failed!"
		exit 1
	fi

	echo "Working on ${imageName} image"

	rm -f microservices_connections/hybridcloud/id.txt

	docker inspect --format=\"{{.ID}}\" ${ARTIFACTORY_HOST}/${imageName}:${imageTag} | sed 's/"//g' | cut -d':' -f2 > microservices_connections/hybridcloud/id.txt
	docker save `cat microservices_connections/hybridcloud/id.txt` -o microservices_connections/hybridcloud/images/${imageName}.tar

	rm -f microservices_connections/hybridcloud/id.txt

	GREP_TAG=$(cat microservices_connections/hybridcloud/support/setupImages.sh | grep ${imageName} | grep tag)
	GREP_PUSH=$(cat microservices_connections/hybridcloud/support/setupImages.sh | grep ${imageName} | grep push)

	# Adding tag version to the docker tag command
	sed -i "/${GREP_TAG////\\/}$/s/$/:${imageTag}/" microservices_connections/hybridcloud/support/setupImages.sh
	# Adding tag version to the docker push command
	sed -i "/${GREP_PUSH////\\/}$/s/$/:${imageTag}/" microservices_connections/hybridcloud/support/setupImages.sh

	echo "${imageName}:${imageTag}" >> microservices_connections/hybridcloud/images/build

}



buildZip() {
	set -o errexit
	if [ ${interactive_artifactory_login} = true ]; then
		logInfo "Authentication required for $ARTIFACTORY_HOST"
		echo -n "Login: "
		read ARTIFACTORY_USER
		echo -n "Password: "
		read -s ARTIFACTORY_PASS
		echo
	fi
	docker login -u ${ARTIFACTORY_USER} -p ${ARTIFACTORY_PASS} ${ARTIFACTORY_HOST}
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

	echo

	rm -rf microservices_connections

	mkdir -p microservices_connections/hybridcloud/images
	mkdir -p microservices_connections/hybridcloud/helmbuilds
	mkdir -p microservices_connections/hybridcloud/support
	mkdir -p microservices_connections/hybridcloud/license
	mkdir -p microservices_connections/hybridcloud/support/redis
	mkdir -p microservices_connections/hybridcloud/support/psp
	mkdir -p microservices_connections/hybridcloud/support/customizer
	mkdir -p microservices_connections/hybridcloud/support/kudos-boards
	mkdir -p microservices_connections/hybridcloud/support/gatekeeper
	mkdir -p microservices_connections/hybridcloud/support/ms-teams

	cp -av microservices/hybridcloud/doc/samples/connections-persistent-storage-nfs-0.1.1.tgz microservices_connections/hybridcloud/helmbuilds
	cp -av microservices/hybridcloud/doc/samples/esbackuprestore-0.1.0.tgz microservices_connections/hybridcloud/helmbuilds
	cp -av microservices/hybridcloud/doc/samples/nfsSetup.sh microservices_connections/hybridcloud/support
	cp -av microservices/hybridcloud/doc/samples/setupImages.sh microservices_connections/hybridcloud/support
	chmod +x microservices_connections/hybridcloud/support/setupImages.sh
	cp -av microservices/hybridcloud/bin/config_blue_metrics.py microservices_connections/hybridcloud/support
	cp -av scripts/configureRedis.sh microservices_connections/hybridcloud/support/redis
	cp -av microservices/hybridcloud/doc/samples/updateRedisJSON.sh microservices_connections/hybridcloud/support/redis
	cp -av microservices/hybridcloud/doc/samples/masterRedis.json microservices_connections/hybridcloud/support/redis
	cp -av microservices/hybridcloud/doc/samples/pwRedis.json microservices_connections/hybridcloud/support/redis
	cp -av microservices/hybridcloud/doc/samples/dashboard-admin.yaml microservices_connections/hybridcloud/support
	cp -av microservices/hybridcloud/doc/samples/psp/privileged-psp-with-rbac.yaml microservices_connections/hybridcloud/support/psp
	cp -av microservices/hybridcloud/doc/samples/kudos-boards/boards-cp.yaml microservices_connections/hybridcloud/support/kudos-boards

	cp -avr microservices/hybridcloud/doc/samples/gatekeeper/* microservices_connections/hybridcloud/support/gatekeeper
	cp -avr microservices/hybridcloud/doc/samples/ms-teams/* microservices_connections/hybridcloud/support/ms-teams

	cp -av microservices/hybridcloud/license/v7.0/*.txt microservices_connections/hybridcloud/license
	wget -P microservices_connections/hybridcloud/support/customizer https://raw.githubusercontent.com/ibmcnxdev/customizer-utils/master/container.css
	wget -P microservices_connections/hybridcloud/support/customizer https://raw.githubusercontent.com/ibmcnxdev/customizer-utils/master/containerUtils.js
	wget -P microservices_connections/hybridcloud/support/customizer https://raw.githubusercontent.com/ibmcnxdev/customizer-utils/master/utils.js

	rm -rf microservices_connections/hybridcloud/support/volumes.txt
	content=(`cat microservices/hybridcloud/doc/samples/connections-persistent-storage-nfs/templates/fullPVs_NFS.yaml | grep path: | cut -d'/' -f3-`)
	touch microservices_connections/hybridcloud/support/volumes.txt
	for t in "${content[@]}"
	do
		echo "/pv-connections/$t" >> microservices_connections/hybridcloud/support/volumes.txt
	done
	chmod +x microservices_connections/hybridcloud/support/volumes.txt

	# Get the latest good helm chart builds. sed command is removing the http
	# helm repo moved to artifactory
	wget -qO- https://${ARTIFACTORY_HOST}/artifactory/v-connections-helm/helm_latest_deployed.txt | sed -e 's/<[^>]*>//g' | sort -u > microservices_connections/hybridcloud/helmbuilds/latest_helmbuilds.txt
	if [ ! -s microservices_connections/hybridcloud/helmbuilds/latest_helmbuilds.txt ]; then
		echo "Fatal error retrieving latest helm builds"
		exit 99
	fi

	# Pull HELM Charts from artifactory for inclusion in zip
	PullCharts

	touch microservices_connections/hybridcloud/images/build

	addHelmRepo

	# make infra helm chart
	declare -a infra=("haproxy" "redis" "redis-sentinel" "mongodb" "appregistry-client" "appregistry-service" "middleware-jsonapi")
	echo "array:"  ${infra[@]}
	makeChartofChart "infrastructure" infra[@]
	makeValuesYaml "infrastructure" infra[@]
	component_infra=${infra[0]}
	build_infra=`grep $component_infra ../microservices_connections/hybridcloud/helmbuilds/latest_helmbuilds.txt`
	version_infra=$(echo -e $build_infra | sed -e "s:$component_infra-::")
	chart_version_infra=`echo $version_infra | grep ^[[:digit:]].[[:digit:]].[[:digit:]] |  cut -d'-' -f1`
	helmPackage "infrastructure" $chart_version_infra

	# make orientme helm chart
	declare -a orientme=("itm-services" "orient-web-client" "orient-analysis-service" "orient-indexing-service" "middleware-graphql" "orient-retrieval-service" "people-scoring" "people-datamigration" "people-relationship" "mail-service" "people-idmapping" "community-suggestions")
	echo "array:"  ${orientme[@]}
	makeChartofChart "orientme" orientme[@]
	makeValuesYaml "orientme" orientme[@]
	component_ome=${orientme[0]}
	build_ome=`grep $component_ome ../microservices_connections/hybridcloud/helmbuilds/latest_helmbuilds.txt`
	version_ome=$(echo -e $build_ome | sed -e "s:$component_ome-::")
	chart_version_ome=`echo $version_ome | grep ^[[:digit:]].[[:digit:]].[[:digit:]] |  cut -d'-' -f1`
	helmPackage "orientme" $chart_version_ome

	# make teams helm chart
	declare -a teams=("teams-share-ui" "teams-share-service" "teams-tab-api" "teams-tab-ui")
	echo "array:"  ${teams[@]}
	makeChartofChart "teams" teams[@]
	makeValuesYaml "teams" teams[@]
	component_teams=${teams[0]}
	build_teams=`grep $component_teams ../microservices_connections/hybridcloud/helmbuilds/latest_helmbuilds.txt`
	version_teams=$(echo -e $build_teams | sed -e "s:$component_teams-::")
	chart_version_teams=`echo $version_teams | grep ^[[:digit:]].[[:digit:]].[[:digit:]] |  cut -d'-' -f1`
	helmPackage "teams" $chart_version_teams

	# make tailored-exp helm chart
	declare -a tailored_exp=("te-creation-wizard" "community-template-service" "admin-portal")
	echo "array:"  ${tailored_exp[@]}
	makeChartofChart "tailored-exp" tailored_exp[@]
	makeValuesYaml "tailored-exp" tailored_exp[@]
	component_te=${tailored_exp[0]}
	build_te=`grep $component_te ../microservices_connections/hybridcloud/helmbuilds/latest_helmbuilds.txt`
	version_te=$(echo -e $build_te | sed -e "s:$component_te-::")
	chart_version_te=`echo $version_te | grep ^[[:digit:]].[[:digit:]].[[:digit:]] |  cut -d'-' -f1`
	helmPackage "tailored-exp" $chart_version_te

	# make elasticstack7 helm chart
	declare -a elasticstack7=("filebeat-7" "logstash-7" "kibana-7" "elasticsearch7-curator")
	echo "array:"  ${elasticstack7[@]}
	makeChartofChart "elasticstack7" elasticstack7[@]
	makeValuesYaml "elasticstack7" elasticstack7[@]
	component_elk=${elasticstack7[0]}
	build_elk=`grep $component_elk ../microservices_connections/hybridcloud/helmbuilds/latest_helmbuilds.txt`
	version_elk=$(echo -e $build_elk | sed -e "s:$component_elk-::")
	chart_version_elk=`echo $version_elk | grep ^[[:digit:]]* |  cut -d'-' -f1`
	helmPackage "elasticstack7" $chart_version_elk

	# Pull latest for the images
	helmbuilds=( `cat "microservices_connections/hybridcloud/helmbuilds/latest_helmbuilds.txt" ` )
	# Add mongo sidecar to the helm builds array
	# mongo sidecar is packaged as part of the mongo helm ch
	helmbuilds+=('mongodb-rs-setup-'${sidecarTag})

	# Add kudos-boards to the helmbuilds array
	kbcp="kudos-boards-cp"
	build=`grep ^$kbcp-[[:digit:]].[[:digit:]].[[:digit:]]* microservices_connections/hybridcloud/helmbuilds/latest_helmbuilds.txt`
	if [ -n "${build}" ]; then
		# Remove trailing spaces
		build="$(echo -e "${build}" | sed -e 's/[[:space:]]*$//')"
		# Return {version}-{tag}
		taggedVer="$(echo -e "${build}" | sed -e 's/[a-zA-Z-]*-//')"

		helmbuilds+=('user-'$taggedVer)
		helmbuilds+=('boards-'$taggedVer)
		helmbuilds+=('core-'$taggedVer)
		helmbuilds+=('licence-'$taggedVer)
		helmbuilds+=('notification-'$taggedVer)
		helmbuilds+=('provider-'$taggedVer)
		helmbuilds+=('webfront-'$taggedVer)
		helmbuilds+=('minio-'$taggedVer)
		helmbuilds+=('boards-event-'$taggedVer)
	fi

	kbcp_act_migration="kudos-boards-cp-activity-migration"
	build=`grep ^$kbcp_act_migration-[[:digit:]].[[:digit:]].[[:digit:]]* microservices_connections/hybridcloud/helmbuilds/latest_helmbuilds.txt`
	if [ -n "${build}" ]; then
		# Remove trailing spaces
		build="$(echo -e "${build}" | sed -e 's/[[:space:]]*$//')"
		# Return {version}-{tag}
		taggedVer="$(echo -e "${build}" | sed -e 's/[a-zA-Z-]*-//')"

		helmbuilds+=('activity-migration-'$taggedVer)
	fi

	for t in "${helmbuilds[@]}";do
		# Remove helm versioning e.g. 0.1.0
		if [[ ! ${t} =~ mongodb-rs-setup ]];then
			tag=$(echo "$t" | sed 's/-[0-9].[0-9].[0-9]//')
			# Remove orient from orient-indexing, orient-analysis and orient-retrieval
			if [[ ${t} =~ orient-indexing|orient-analysis|orient-retrieval ]];then
				tag=$(echo "$tag" | sed 's/orient-//')
			fi
		else
			tag=${t}
		fi

		# Replace - with : before tag. Required format for docker pull
		if [[ ${t} =~ mongodb-rs-setup ]];then
			# replace last occurrence of - with : (mongodb-rs-setup-latest to mongodb-rs-setup:latest)
			tag_update=$(echo "$tag" | sed 's/-\([^-]*\)$/:\1/')
		else
			tag_update=$(echo "$tag" | sed 's/-\([0-9]\)/:\1/')
		fi

		if [[ ${t} =~ haproxy|mongo|redis ]];then
			# append middleware- for haproxy, mongodb, redis
			i="middleware-$tag_update"
		elif [[ ${t} =~ middleware-jsonapi ]];then
			i="$tag_update"
		elif [[ ${t} =~ itm-services ]];then
			i="$tag_update"
		elif [[ ${t} =~ cnx-ingress|elasticsearch7-curator|bootstrap|indexing|analysis|retrieval|mail-service|appregistry|graphql|mw-proxy|suggestions|elasticsearch|elasticsearch7|sanity|sanity-watcher|orient-web|ic360 ]] && [[ ! ${t} =~ mw-elasticsearch ]];then
			# at root/top level
			i="$tag_update"
		elif [[ ${t} =~ scoring|datamigration|relationship|idmapping ]];then
			i="$tag_update"
		elif [[ ${t} =~ teams-share-ui|teams-share-service|teams-tab-api|teams-tab-ui ]];then
			i="$tag_update"
		elif [[ ${t} =~ te-creation-wizard|community-template-service|admin-portal ]];then
			i="$tag_update"
		elif [[ ${t} =~ connections-outlook-desktop ]]; then
			i="$tag_update"
		elif [[ ${t} =~ user|boards|core|licence|notification|provider|activity-migration|webfront|minio|boards-event ]] && [[ ! ${t} =~ livegrid-core ]] && [[ ! ${t} =~ kudos-boards-cp ]];then
			# append kudosboards- for ISW images
			i="kudosboards-$tag_update"
		else
			continue # skip any unsupported charts
		fi

		echo "docker pull ${ARTIFACTORY_HOST}/$i"
		docker pull ${ARTIFACTORY_HOST}/$i
		# check if pull was successful
		if [ $? -eq 1 ]; then
			echo "Pull Failed!"
			exit 1
		fi

		#remove quotes if have
		i="${i//\'}"

		IMG=$(echo $i | awk '{split($0,img,":"); print img[1]}')
		if [[ $i = *"/"* ]]; then
			IMG=$(echo $IMG | awk '{split($0,img,"/"); print img[2]}')
		fi

		echo "Working on $i"

		docker inspect --format=\"{{.ID}}\" ${ARTIFACTORY_HOST}/$i | sed 's/"//g' | cut -d':' -f2 > microservices_connections/hybridcloud/id.txt
		docker save `cat microservices_connections/hybridcloud/id.txt` -o microservices_connections/hybridcloud/images/${IMG}.tar

		echo ${i} >> microservices_connections/hybridcloud/images/build
	done #end for: helmbuilds

	if [ ${customizerLiteZip} = true ]; then
		cp microservices_connections/hybridcloud/images/appregistry-client.tar customizerLite/images
		cp microservices_connections/hybridcloud/images/appregistry-service.tar customizerLite/images
		cp microservices_connections/hybridcloud/images/mw-proxy.tar customizerLite/images
		cp microservices_connections/hybridcloud/support/customizer/container.css customizerLite/customizations
		cp microservices_connections/hybridcloud/support/customizer/containerUtils.js customizerLite/customizations
		cp microservices_connections/hybridcloud/support/customizer/utils.js customizerLite/customizations
		grep 'appregistry-client\|appregistry-service\|mw-proxy' microservices_connections/hybridcloud/images/build > customizerLite/images/build
		cp microservices_connections/hybridcloud/support/setupImages.sh customizerLite/scripts
		rm -f customizerLite/customizations/.gitignore customizerLite/data/settings/.gitignore customizerLite/images/.gitignore
	fi

	rm -f microservices_connections/hybridcloud/id.txt
	cat microservices_connections/hybridcloud/images/build
	rm -f microservices_connections/hybridcloud/*.txt
	rm -f microservices_connections/hybridcloud/helmbuilds/latest_helmbuilds.txt

	DATE=`date +%Y%m%d-%H%M%S`
	FILETOUPLOAD="hybridcloud_$DATE.zip"
	SHA1FILE="$FILETOUPLOAD.sha1"
	SHA256FILE="$FILETOUPLOAD.sha256"

	if [ ${create_zip} = true ]; then
		if [ ${push_to_artifactory} = true ]; then
			zip_args=-4	# save space - 8% reduction, 42% more time
		else
			zip_args=-1	# save time
		fi
		zip ${zip_args} -r $FILETOUPLOAD microservices_connections/hybridcloud
		sha1sum $FILETOUPLOAD > $SHA1FILE
		sha256sum $FILETOUPLOAD > $SHA256FILE
		if [ ${customizerLiteZip} = true ]; then
			CSFILETOUPLOAD="customizerLite_$DATE.zip"
			zip ${zip_args} -r $CSFILETOUPLOAD customizerLite
			sha1sum $CSFILETOUPLOAD > $CSFILETOUPLOAD.sha1
			sha256sum $CSFILETOUPLOAD > $CSFILETOUPLOAD.sha256
		fi

	else
		echo "Not creating ZIP"
	fi

	if [ ${push_to_artifactory} = true ]; then

		# create a mastered.sem to indicate that the upload has completed
		echo $FILETOUPLOAD > mastered.sem
		echo "Pushing build into ${ARTIFACTORY_HOST}"

		curl -f -v -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} -k -X PUT https://${ARTIFACTORY_HOST}/artifactory/ibm-connections-cloud-docker/conncloud/docker-base-images/${push_folder}/ --upload-file $FILETOUPLOAD
		if [ $? -ne 0 ]; then
			echo "Upload failed"
			exit 1
		fi

		curl -f -v -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} -k -X PUT https://${ARTIFACTORY_HOST}/artifactory/api/storage/ibm-connections-cloud-docker/conncloud/docker-base-images/${push_folder}/${FILETOUPLOAD}?properties=NODE_NAME=${NODE_NAME}%7CBuiltInContainer=True%7CBUILD_AGENT=${buildNodeExpression}%7CBUILD_TIMESTAMP=${BUILD_TIMESTAMP}%7CBUILD_URL=${BUILD_URL}%7CUploadedBy=${ArtifactoryUser}%7CGIT_COMMIT=${GIT_COMMIT}%7CHOSTNAME=${HOSTNAME}
		if [ $? -ne 0 ]; then
			echo "Property upload failed"
			exit 1
		fi

		curl -f -v -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} -k -X PUT https://${ARTIFACTORY_HOST}/artifactory/ibm-connections-cloud-docker/conncloud/docker-base-images/${push_folder}/ --upload-file mastered.sem
		if [ $? -ne 0 ]; then
			echo "Upload failed"
			exit 1
		fi

		curl -f -v -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} -k -X PUT https://${ARTIFACTORY_HOST}/artifactory/ibm-connections-cloud-docker/conncloud/docker-base-images/${push_folder}/ --upload-file $SHA1FILE
		if [ $? -ne 0 ]; then
			echo "Upload failed"
			exit 1
		fi

		curl -f -v -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} -k -X PUT https://${ARTIFACTORY_HOST}/artifactory/ibm-connections-cloud-docker/conncloud/docker-base-images/${push_folder}/ --upload-file $SHA256FILE
		if [ $? -ne 0 ]; then
			echo "Upload failed"
			exit 1
		fi

		echo $DATE > build_timestamp.txt
		cat build_timestamp.txt

		if [ ${customizerLiteZip} = true ]; then
			# create a mastered.sem to indicate that the upload has completed
			echo $CSFILETOUPLOAD > cs_mastered.sem
			echo "Pushing customizerLite build into ${ARTIFACTORY_HOST}"

			curl -f -v -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} -k -X PUT https://${ARTIFACTORY_HOST}/artifactory/ibm-connections-cloud-docker/conncloud/docker-base-images/${cs_push_folder}/ --upload-file $CSFILETOUPLOAD
			if [ $? -ne 0 ]; then
				echo "Upload failed"
				exit 1
			fi

			curl -f -v -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} -k -X PUT https://${ARTIFACTORY_HOST}/artifactory/api/storage/ibm-connections-cloud-docker/conncloud/docker-base-images/${cs_push_folder}/${CSFILETOUPLOAD}?properties=NODE_NAME=${NODE_NAME}%7CBuiltInContainer=True%7CBUILD_AGENT=${buildNodeExpression}%7CBUILD_TIMESTAMP=${BUILD_TIMESTAMP}%7CBUILD_URL=${BUILD_URL}%7CUploadedBy=${ArtifactoryUser}%7CGIT_COMMIT=${GIT_COMMIT}%7CHOSTNAME=${HOSTNAME}
			if [ $? -ne 0 ]; then
				echo "Property Upload failed"
				exit 1
			fi

			curl -f -v -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} -k -X PUT https://${ARTIFACTORY_HOST}/artifactory/ibm-connections-cloud-docker/conncloud/docker-base-images/${cs_push_folder}/ --upload-file cs_mastered.sem
			if [ $? -ne 0 ]; then
				echo "Upload failed"
				exit 1
			fi

			curl -f -v -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} -k -X PUT https://${ARTIFACTORY_HOST}/artifactory/ibm-connections-cloud-docker/conncloud/docker-base-images/${cs_push_folder}/ --upload-file $CSFILETOUPLOAD.sha1
			if [ $? -ne 0 ]; then
				echo "Upload failed"
				exit 1
			fi

			curl -f -v -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASS} -k -X PUT https://${ARTIFACTORY_HOST}/artifactory/ibm-connections-cloud-docker/conncloud/docker-base-images/${cs_push_folder}/ --upload-file $CSFILETOUPLOAD.sha256
			if [ $? -ne 0 ]; then
				echo "Upload failed"
				exit 1
			fi
		fi
	else
		echo "Not pushing build into ${ARTIFACTORY_HOST}"

		echo "Moving the build $FILETOUPLOAD to local build-store - /opt/deployCP-np/"

		sudo mv $FILETOUPLOAD /opt/deployCP-np/
		sudo mv $SHA1FILE /opt/deployCP-np/
		sudo mv $SHA256FILE /opt/deployCP-np/

		sudo mv $CSFILETOUPLOAD /opt/deployCP-np/
		sudo mv $CSFILETOUPLOAD.sha1 /opt/deployCP-np/
		sudo mv $CSFILETOUPLOAD.sha256 /opt/deployCP-np/

		# create a symlink
		cd /opt/deployCP-np/
		my_link="component_pack_latest.zip"
		if [ -L ${my_link} ] ; then
			if [ -e ${my_link} ] ; then
				#un-link and link the new build
				sudo unlink ${my_link}
				sudo ln -s $FILETOUPLOAD component_pack_latest.zip
			fi
		else
			# symlink didn't exist
			sudo ln -s $FILETOUPLOAD component_pack_latest.zip
		fi
	fi
}


push_to_artifactory=false
interactive_artifactory_login=true
create_zip=true
push_folder=hybridcloud
cs_push_folder=customizerLite
pullfromintegration=true
bypasstagcheck=false
customizerLiteZip=false

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
		--push)
			echo "Pushing to artifactory"
			push_to_artifactory=true
			;;
		--nozip)
			echo "Not creating ZIP"
			create_zip=false
			;;
		--dev)
			push_folder=hybridcloud_test
			cs_push_folder=customizerLite_test
			;;
		--pub)
			push_folder=pre_publish
			echo "folder will be $push_folder"
			echo "ARTIFACTORY_HOST = $ARTIFACTORY_HOST"
			sleep 10
                        ;;
		--cyl)
			pullfromintegration=false
			;;
		--byp)
			bypasstagcheck=true
			;;
		--csl)
			customizerLiteZip=true
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

buildZip

echo "Clean exit"
exit 0
