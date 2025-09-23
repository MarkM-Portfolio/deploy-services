#!/bin/bash

set -o errexit
set -o pipefail

# DOCKERHUB_USER=
# DOCKERHUB_PASS=
#
# ARTIFACTORY_USER=
# ARTIFACTORY_PASS=

# imageTag=
LOG_PATH=logs
ARTIFACTORY_HOST="$2.artifactory.cwp.pnp-hcl.com"
helmRepository="https://artifactory.cwp.pnp-hcl.com/artifactory/$3"
docker_registry_type=artifactory
helmRepoName="$3"

if [ "${DOCKERHUB_USER}" = "" -o "${DOCKERHUB_PASS}" = "" ]; then
	echo "Missing values for DOCKERHUB_USER and/or DOCKERHUB_PASS."
	exit 1
fi

if [ "${ARTIFACTORY_USER}" = "" -o "${ARTIFACTORY_PASS}" = "" ]; then
	echo "Missing values for ARTIFACTORY_USER and/or ARTIFACTORY_PASS."
	exit 1
fi

if [ "$1" = "" ]; then
	echo "ERROR: You must pass a tag for the docker images tagged when using the flags - imageTag"
	exit 1
else
    imageTag=$1
fi

tag=$(echo "$imageTag" | sed 's/-//g')'-'`date +%H%M%S`

#ensure log files exist
create_logs() {
    if [ ! -d "${LOG_PATH}" ] ; then
        if ! mkdir -p "${LOG_PATH}" ; then
            echo "ERROR: unable to create direcotry: '${LOG_PATH}'"
            return 1
        fi
    fi
}

update_helm_charts_txt() {
    local chart_name=$1
    local chart_version_ts=$2
    echo "Updating chart text file: $3"
    # grep for $base_version_str in txt file; if $base_version_str exists; then update the txt file; else append to end of file
    if grep "$chart_name-[0-9].*" "$3" ; then
        # update chart using sed
        sed -i "s/$chart_name-[0-9].*/$chart_version_ts/" "$3" || return 1
    else
        # append to end of file
        echo "$chart_version_ts" >> "$3" || return 1
    fi
}

helm_publish() {
    if [ "$1" = "" -o "$2" = "" -o "$3" = "" ]; then
        echo "ERROR: helm_publish(), One ore more variables are undefined!!!"
        return 1
    fi

    local base_helm_chart=$1
    local tag_ts=$2
    local helm_latest_txt=$3

    tar xvf $base_helm_chart
    if [ $? -ne 0 ]; then
        echo "ERROR: helm_publish(), tar: $base_helm_chart: exiting, helm chart published aborted."
        return 1
    fi
    # Return base chart name (kudos-boards-cp)
    chartname_dir=$(echo $base_helm_chart | sed 's/-\([^-]*\)$//')
    base_kp_cp_chart_name=(`cat ${chartname_dir}/Chart.yaml | grep name: | cut -d' ' -f2`)
    base_kp_cp_chart_version=(`cat ${chartname_dir}/Chart.yaml | grep version: | cut -d' ' -f2`)
    
    sed -i "s|version: .*$|version: ${base_kp_cp_chart_version}-${tag_ts}|" ${chartname_dir}/Chart.yaml  || return 1
    sed -i 's/mongo-rs-members-hosts/mongo5-rs-members-hosts/g' ${chartname_dir}/values.yaml || return 1    
    if [[ ! ${base_helm_chart} =~ activity-migration ]]; then
        sed -i "s|imageTag: .*$|imageTag: $tag|" ${chartname_dir}/charts/huddo-minio/values.yaml || return 1
        sed -i "s|imageTag: .*$|&\n\ \ imagePullSecret: myregkey|" ${chartname_dir}/charts/huddo-minio/values.yaml || return 1
        sed -i "s|imageTag: .*$|imageTag: $tag|" ${chartname_dir}/charts/huddo-app/values.yaml || return 1
        sed -i "s|imagePullSecret: .*$|imagePullSecret: myregkey|" ${chartname_dir}/charts/huddo-app/values.yaml || return 1
    fi
    if [[ ${base_helm_chart} =~ activity-migration ]]; then
        sed -i "s|imageTag: .*$|imageTag: $tag|" ${chartname_dir}/charts/boards-migration/values.yaml || return 1
        sed -i "s|imagePullSecret: .*$|imagePullSecret: myregkey|" ${chartname_dir}/charts/boards-migration/values.yaml || return 1
    fi

    # remove existing chart
    rm -f $base_helm_chart
    helm package $chartname_dir
    if [ $? -ne 0 ]; then
        echo "Fail to package helm chart:  $base_helm_chart"
        return 1
    fi
    base_kp_cp_chart_version=${base_kp_cp_chart_name}-${base_kp_cp_chart_version}
    new_kb_cp_chart_version=${base_kp_cp_chart_version}-${tag_ts}
    new_kp_cp_chart_file="${new_kb_cp_chart_version}.tgz"
    #Remove the chart directory (new chart is already packaged)
    rm -rf $chartname_dir

    if [ $? -eq 0 ]; then
        echo "Uploading $new_kp_cp_chart_file to artifactory"
        if curl --fail --silent --show-error -u "$ARTIFACTORY_USER:$ARTIFACTORY_PASS" -X PUT \
            "${helmRepository}/" \
             -T ${new_kp_cp_chart_file} > ${LOG_PATH}/tmp.log ;
        then
            echo "File $new_kp_cp_chart_file uploaded to artifactory."
        else
            echo "ERROR: failed upload Helm $new_kp_cp_chart_file file to artifactory."
            cat $LOG_PATH/tmp.log
            return 1
        fi
    else
        echo "*** File $new_kp_cp_chart_file doesn't exist!!!"
        return 1
    fi

    #update helm_latest_kudosboards.txt with new version
    update_helm_charts_txt ${base_kp_cp_chart_name} ${new_kb_cp_chart_version} ${helm_latest_txt}
    if [ $? -ne 0 ]; then
        echo "ERROR: helm_publish(), failed to update $helm_latest_txt: $base_helm_chart --> $new_kb_cp_chart_version"
        return 1
    fi
}

images_publish() {
    # login to dockerhub
    echo "login to dockerhub ..."
    docker login -u $DOCKERHUB_USER -p $DOCKERHUB_PASS
    if [ $? -eq 0 ]; then
        echo "SUCCESS: login to dockerhub"
        echo
    else
        echo "login failed!"
        exit 1
    fi
    echo

    declare -a images=( "user" "boards" "core" "licence" "notification" "boards-event" "provider" "webfront" "activity-migration" )

    for t in "${images[@]}"; do
        image_rel='iswkudos/kudos-boards:'$t'-'$imageTag
        # pull the image from dockerhub
        echo "docker pull $image_rel"
        docker pull $image_rel
        #check if pull was successful
        if [ $? -eq 1 ]; then
            echo "Pull Failed!"
            exit 1
        fi
        # tag the image
        docker tag $image_rel ${ARTIFACTORY_HOST}/kudosboards-$t:$tag
        echo "Pull Success"
        echo
    done

    echo "docker pull minio/minio:latest"
    docker pull minio/minio:latest
    if [ $? -eq 1 ]; then
        echo "Pull Failed!"
        exit 1
    fi
    docker tag minio/minio:latest ${ARTIFACTORY_HOST}/kudosboards-minio:$tag
    echo "Pull Success"

    # logout from DockerHub
    echo
    docker logout
    echo "SUCCESS: logout from dockerhub"
    echo

    echo "docker registry : ${ARTIFACTORY_HOST}"
    # login to artifactory
    echo "login to artifactory ..."
    docker login -u $ARTIFACTORY_USER -p $ARTIFACTORY_PASS $ARTIFACTORY_HOST
    if [ $? -eq 0 ]; then
        echo "SUCCESS: login to artifactory"
        echo
    else
        echo "login failed!"
        exit 1
    fi

    for p in "${images[@]}"; do
        echo "docker push ${ARTIFACTORY_HOST}/kudosboards-$p:$tag"
        docker push ${ARTIFACTORY_HOST}/kudosboards-$p:$tag
        if [ $? -eq 1 ]; then
            echo "Push Failed!"
            exit 1
        fi
        echo
    done
    echo "docker push ${ARTIFACTORY_HOST}/kudosboards-minio:$tag"
    docker push ${ARTIFACTORY_HOST}/kudosboards-minio:$tag
    if [ $? -eq 1 ]; then
        echo "Push Failed!"
        exit 1
    fi

    echo
    echo "Done!!! ** use $tag for helm charts and upload to artifactory helm repo "
}

pull_charts() {
    local artifactory_repo="${helmRepository}"
    local latest_tag="${tag}"
    local helm_latest_kudosboards="helm_latest_deployed.txt"
    local artifactory_reponame="${helmRepoName}"

    # download file with latest versions of kudoboards charts
    curl --silent --fail -u $ARTIFACTORY_USER:$ARTIFACTORY_PASS \
        "${artifactory_repo}/$helm_latest_kudosboards" \
        -o $helm_latest_kudosboards
    if [ $? -ne 0 ]; then
        echo "Failed download $helm_latest_kudosboards, helm chart publishing aborted."
        return 1
    fi

    echo "Downloading kudosboards helm charts..."
    charts="huddo-boards-cp-1.1.0.tgz huddo-boards-cp-activity-migration-1.1.0.tgz"
    for chart in $charts ; do
        http_status=`curl --write-out '%{http_code}' --insecure --remote-name https://docs.huddo.com/assets/config/kubernetes/$chart`
        if [ $? -eq 1 -o "${http_status}" != 200 ]; then
            echo "Failed to pull chart from huddoboards public site"
            exit 1
        fi
        gzip -v -t $chart
        if [ $? -ne 0 ]; then
            echo "Corrupt helm chart:  $chart"
            exit 2
        fi
        gunzip < $chart | tar -tf -
        if [ $? -ne 0 ]; then
            echo "Corrupt helm chart:  $chart"
            exit 3
        fi

        if [ ! -f $chart ]; then
            echo "ERROR: pull_charts(), $chart not found!!! helm chart publishing aborted."
            exit 3
        fi
        helm_publish $chart ${latest_tag} ${helm_latest_kudosboards}
        if [ $? -ne 0 ]; then
            echo "ERROR: pull_charts(), failed $chart, helm chart publishing aborted."
            exit 3
        fi
    done

    echo "Uploading ${helm_latest_kudosboards} to artifactory (${artifactory_repo}) ..."
    if curl --fail --silent --show-error -u "$ARTIFACTORY_USER:$ARTIFACTORY_PASS" -X PUT \
        "${artifactory_repo}/" \
            -T ${helm_latest_kudosboards} > ${LOG_PATH}/tmp.log ;
    then
        echo "File ${helm_latest_kudosboards} uploaded to artifactory."
    else
        echo "ERROR: failed upload Helm ${helm_latest_kudosboards} file to artifactory (${artifactory_repo})."
        cat ${LOG_PATH}/tmp.log
        return 1
    fi

    # reindex helm repo on artifactory
    echo "Request to re-index Helm repo (${artifactory_repo})"
    echo "re-index endpoint: (https://artifactory.cwp.pnp-hcl.com/artifactory/api/helm/${artifactory_reponame}/reindex)"
    curl --fail --silent --show-error -u $ARTIFACTORY_USER:$ARTIFACTORY_PASS -X POST \
        "https://artifactory.cwp.pnp-hcl.com/artifactory/api/helm/${artifactory_reponame}/reindex" || return 2
}

create_logs || exit 3

images_publish
if [ $? -ne 0 ]; then
    echo "ERROR: failed to publish huddoboards docker images to artifactory!!!"
    exit 3
fi

pull_charts
if [ $? -ne 0 ]; then
    echo "ERROR: failed to download helm charts/upload helm charts and helm_latest_kudosboards.txt to artifactory!!!"
    exit 3
fi

echo
echo "Clean exit"
exit 0
