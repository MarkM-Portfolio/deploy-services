#!/bin/bash

set -o errexit
set -o pipefail

##Uncomment Line below to enable debug
#set -x

DOCKER_REGISTRY=""
STARTER_STACKS=""
STARTER_STACK_USED=false
starter_stack_options="customizer elasticsearch elasticsearch7 teams tailored-exp orientme cs_lite ic360 cnx-mso-plugin kudosboards"

usage() {
        echo -e "This script will load, tag and push the required docker images;\n"
        echo -e "Usage: ./setupImages.sh [OPTION];\n"
        echo -e "Required options:\n"
        echo -e "-dr       | --dockerRegistry      Name of the Docker registry. Required.;\n"
        echo -e "-u        | --user                Docker registry user. Required.\n"
        echo -e "-p        | --password            Docker registry user password. Required.\n"
        echo "Optional options:"
        echo -e "-st       | --starterStacks       Comma seperated list of stacks to load images for. Optional.\n"
        echo -e "Images for all components will be set up by default if Starter Stack option not provided.\n"
        echo -e "sample usage : ./setupImages.sh -dr mydockerregistry:8500 -u user -p password -st orientme,customizer,elasticsearch,elasticsearch7,teams,tailored-exp,cs_lite,ic360,cnx-mso-plugin,kudosboards \n"

        exit 1
}

while [[ $# -gt 0 ]]
do
        key="$1"

        case $key in
                -dr|--dockerRegistry)
                        if [ -z "$2" ]; then
                                echo "ERROR: You must pass a docker registry value when using the flags -dr or --dockerRegistry"
                                usage
                                exit 1
                        fi
                        DOCKER_REGISTRY="$2"
                        shift
                        ;;
                -u|--user)
                        if [ -z "$2" ]; then
                                echo "ERROR: You must pass a username when using the flags -u or --user"
                                usage
                                exit 1
                        fi
                        USER="$2"
                        shift
                        ;;
                -p|--password)
                        if [ -z "$2" ]; then
                                echo "ERROR: You must pass a password when using the flags -p or --password"
                                usage
                                exit 1
                        fi
                        PASSWORD="$2"
                        shift
                        ;;
                -st|--starterStacks)
                        if [ -z "$2" ]; then
                                echo "ERROR: You must pass a comma seperated list of valid starter stack(s) when using the flags -st or --starterStacks"
                                usage
                                exit 1
                        fi
                        STARTER_STACKS="$2"
                        STARTER_STACK_USED=true
                        starter_stack_array=(${STARTER_STACKS//,/ })
                        for stack in "${starter_stack_array[@]}"; do
                                if [[ "${starter_stack_options}" =~ "$stack" ]]; then
                                        starter_stack_valid=true
                                else
                                        starter_stack_valid=false
                                fi
                                if [ ${starter_stack_valid} = false ]; then
                                        echo "ERROR: Invalid Starter Stack option: $stack"
                                        usage
                                        exit 1
                                fi
                        done
                        echo "Script performed with -st|--starterStacks. Only Docker images for the following stacks will be set up: ${STARTER_STACKS}"
                        shift
                        ;;
                *)
                        usage
                        ;;
        esac
        shift
done

if [ "${DOCKER_REGISTRY}" = "" -o "${USER}" = "" -o "${PASSWORD}" = "" ]; then
        echo "ERROR: Missing either Docker registry, user or password definitions."
        echo ""
        usage
        exit 1
fi

if [[ ${DOCKER_REGISTRY} == *"amazonaws.com" ]]; then
        docker login --username ${USER}  -p ${PASSWORD} ${DOCKER_REGISTRY}
        l_status=$?
elif [[ ${DOCKER_REGISTRY} == *"registry.openshift"* ]]; then
        podman login -u ${USER} -p ${PASSWORD} ${DOCKER_REGISTRY}
        l_status=$?
else
        docker login -u ${USER} -p ${PASSWORD} ${DOCKER_REGISTRY}
        l_status=$?
fi

if [ $l_status -ne 0 ]; then
        echo "login to ${DOCKER_REGISTRY} failed!!!"
        exit 127     
fi


if [[ ${DOCKER_REGISTRY} == *"amazonaws.com" ]]; then
        CONTAINER_BINARY="docker"
elif [[ ${DOCKER_REGISTRY} == *"registry.openshift"* ]]; then
        CONTAINER_BINARY="podman"
else
        CONTAINER_BINARY="docker"
fi

tag_and_push () {
        if [ "$1" = "" ]; then
		echo "usage:  setup_image imageTar"
		exit 100
	fi
        img=$(cat ../images/build | grep "$1:")
	echo -e "Tag and Push ${img}"
        ${CONTAINER_BINARY} tag ${SHA} ${DOCKER_REGISTRY}/connections/${img}
        ${CONTAINER_BINARY} push ${DOCKER_REGISTRY}/connections/${img}
}

tag_and_push_all () {

        if [[ " ${image_names[@]} " =~ "${IMG}" ]]; then
		tag_and_push ${IMG}
		if [ "${IMG}" = "appregistry-client" ] || [ "${IMG}" = "appregistry-service" ] || [ "${IMG}" = "mw-proxy" ]; then
                    if [ "${STARTER_STACKS}" = "cs_lite" ]; then
                            img=$(cat ../images/build | grep "${IMG}:" | cut -d"/" -f2)
                            docker tag ${SHA} ${DOCKER_REGISTRY}/connections/"${IMG}":cs_lite
                            docker push ${DOCKER_REGISTRY}/connections/"${IMG}":cs_lite
                    fi
                #else
                #        tag_and_push ${IMG}
                fi
                if [ "${IMG}" = "sanity" ]; then
                        img=$(cat ../images/build | grep "${IMG}:" | cut -d"/" -f2)
                        ${CONTAINER_BINARY} tag ${SHA} ${DOCKER_REGISTRY}/connections/"${IMG}":CP
                        ${CONTAINER_BINARY} push ${DOCKER_REGISTRY}/connections/"${IMG}":CP
                fi
        fi
}

if [[ ${DOCKER_REGISTRY} == *"amazonaws.com" ]]; then
	repos=(
               connections/kudosboards-activity-migration
               connections/analysis-service
               connections/appregistry-client
               connections/appregistry-service
               connections/kudosboards-boards
               connections/bootstrap
               connections/cnx-ingress
               connections/ic360
               connections/connections-outlook-desktop
               connections/community-suggestions
               connections/kudosboards-core
               connections/elasticsearch
               connections/elasticsearch7
               #connections/elasticsearch7-curator
               connections/middleware-haproxy
               connections/indexing-service
               connections/itm-services
               connections/kudosboards-licence
               connections/mail-service
               connections/middleware-graphql
               connections/kudosboards-minio
               connections/middleware-mongodb
               connections/middleware-mongodb-rs-setup
               connections/mw-proxy
               connections/kudosboards-notification
               connections/orient-web-client
               connections/people-datamigration
               connections/people-idmapping
               connections/people-relationship
               connections/people-scoring
               connections/kudosboards-provider
               connections/middleware-redis
               connections/middleware-redis-sentinel
               connections/retrieval-service
               connections/sanity
               connections/sanity-watcher
               connections/middleware-solr-basic
               connections/kudosboards-user
               connections/kudosboards-webfront
               connections/middleware-zookeeper
               connections/teams-share-ui
               connections/teams-share-service
               connections/teams-tab-api
               connections/teams-tab-ui
               connections/te-creation-wizard
               connections/community-template-service
               connections/admin-portal
	       )
	for repo in ${repos[@]} ; do
		aws ecr describe-repositories --repository-names ${repo} --region $(echo ${DOCKER_REGISTRY} | cut -d. -f4) || aws ecr create-repository --repository-name $repo --region $(echo ${DOCKER_REGISTRY} | cut -d. -f4)
	done
fi

image_names=(
        orient-web-client
        middleware-haproxy
        middleware-redis
        middleware-redis-sentinel
        middleware-mongodb
        middleware-mongodb-rs-setup
        middleware-zookeeper
        indexing-service
        middleware-solr-basic
        retrieval-service
        analysis-service
        people-relationship
        people-idmapping
        people-scoring
        people-datamigration
        mail-service
        itm-services
        appregistry-client
        appregistry-service
        middleware-graphql
        mw-proxy
        community-suggestions
        elasticsearch
        elasticsearch7
        sanity
        bootstrap
        sanity-watcher
        #elasticsearch7-curator
        cnx-ingress
        ic360
        connections-outlook-desktop
        teams-tab-ui
        teams-share-service
        teams-share-ui
        teams-tab-api
        te-creation-wizard
        admin-portal
        community-template-service
        kudosboards-user
        kudosboards-boards
        kudosboards-core
        kudosboards-licence
        kudosboards-notification
        kudosboards-provider
        kudosboards-activity-migration
        kudosboards-webfront
        kudosboards-minio
        )

# Choose the docker registry (ECR/OCR/default)
if [[ ${DOCKER_REGISTRY} == *"amazonaws.com" ]]; then
        setup_image() {
            if [ "$1" = "" ]; then
                    echo "usage:  setup_image imageTar"
                    exit 100
            fi
            
            IMG=$(echo $1 | awk '{split($0,img,"."); print img[1]}')
	    echo -e "\nLoading Image $(echo ${IMG}|awk '{print toupper($0)}') to Registry\n"
            SHA=$(docker load -i $1 | tail -1  | cut -c 25,26,27,28,29,30,31,32,33,34,35,36)

            tag_and_push_all ${IMG}
    
        }
elif [[ ${DOCKER_REGISTRY} == *"registry.openshift"* ]]; then
        setup_image() {
            if [ "$1" = "" ]; then
                    echo "usage:  setup_image imageTar"
                    exit 100
            fi
            
            IMG=$(echo $1 | awk '{split($0,img,"."); print img[1]}')
            SHA=$(podman load -i $1 | tail -1 | awk '{ print $3 }' | cut -c 2,3,4,5,6,7,8,9,10,11,12,13)

            tag_and_push_all ${IMG}
 
        }
else
	setup_image() {
            if [ "$1" = "" ]; then
                    echo "usage:  setup_image imageTar"
                    exit 100
            fi
            
            IMG=$(echo $1 | awk '{split($0,img,"."); print img[1]}')
            SHA=$(docker load -i $1 | tail -1  | cut -c 25,26,27,28,29,30,31,32,33,34,35,36)

            tag_and_push_all ${IMG}
            
        }
fi

# Support different invocation locations associated with this script at different times
support_dir="`dirname \"$0\"`"
echo
cd "${support_dir}" > /dev/null
echo "Changed location to:"
echo "  `pwd`"
echo "  (relative path:  ${support_dir})"
echo

cd ../images
# arr=($(ls *.tar|sed ':a;N;$!ba;s/\n/ /g'))

# Set up all images
if [ ${STARTER_STACK_USED} = false ]; then
        arr=(*.tar)
        for f in "${arr[@]}"; do
                setup_image $f
        done
else
        if [ "${STARTER_STACKS}" != "cs_lite" ]; then
                # Always setup bootstrap image
                setup_image bootstrap.tar

                # Always setup sanity image
                setup_image sanity.tar

                # Always setup sanity-watcher image
                setup_image sanity-watcher.tar

                # Always setup cnx-ingress image
                setup_image cnx-ingress.tar
        else
                arr=(appregistry-client.tar appregistry-service.tar mw-proxy.tar)
                for f in "${arr[@]}"; do
                        setup_image $f
                done
        fi

        # Infra
	if [[ ${STARTER_STACKS} =~ "customizer" ]] || [[ ${STARTER_STACKS} =~ "orientme" ]] || [[ ${STARTER_STACKS} =~ "kudosboards" ]] || [[ ${STARTER_STACKS} =~ "ic360" ]] || [[ ${STARTER_STACKS} =~ "teams" ]] || [[ ${STARTER_STACKS} =~ "tailored-exp" ]] || [[ ${STARTER_STACKS} =~ "cnx-mso-plugin" ]]; then
		arr=(middleware-haproxy.tar middleware-mongodb-rs-setup.tar middleware-mongodb.tar middleware-redis-sentinel.tar middleware-redis.tar appregistry-client.tar appregistry-service.tar)
		for f in "${arr[@]}"; do
			setup_image $f
		done
	fi
	
	# Orient Me
	if [[ ${STARTER_STACKS} =~ "orientme" ]]; then
		arr=(analysis-service.tar community-suggestions.tar indexing-service.tar itm-services.tar mail-service.tar middleware-graphql.tar orient-web-client.tar people-datamigration.tar people-idmapping.tar people-relationship.tar people-scoring.tar retrieval-service.tar middleware-zookeeper.tar middleware-solr-basic.tar)
		for f in "${arr[@]}"; do
			setup_image $f
		done
	fi
	
	# Customizer
	if [[ ${STARTER_STACKS} =~ "customizer" ]]; then
		arr=(mw-proxy.tar)
		for f in "${arr[@]}"; do
			setup_image $f
		done
	fi
	
	# elasticsearch
        if [[ ${STARTER_STACKS} =~ "elasticsearch" ]]; then
                IFS=', ' read -r -a arr_of_strs <<< "${STARTER_STACKS}"
                for i in "${arr_of_strs[@]}"; do
                        if [[ $i == "elasticsearch" ]]; then
                                es5="elasticsearch.tar"
                                setup_image $es5
                        fi
                done        
	fi
	
        # elasticsearch7
	if [[ ${STARTER_STACKS} =~ "elasticsearch7" ]]; then
		#arr=(elasticsearch7.tar elasticsearch7-curator.tar)
                arr=(elasticsearch7.tar)
		for f in "${arr[@]}"; do
			setup_image $f
		done
	fi

        # teams
	if [[ ${STARTER_STACKS} =~ "teams" ]]; then
		arr=(teams-share-ui.tar teams-share-service.tar teams-tab-api.tar teams-tab-ui.tar)
		for f in "${arr[@]}"; do
			setup_image $f
		done
	fi

        # tailored-exp
	if [[ ${STARTER_STACKS} =~ "tailored-exp" ]]; then
		arr=(te-creation-wizard.tar community-template-service.tar admin-portal.tar)
		for f in "${arr[@]}"; do
			setup_image $f
		done
	fi

        # ic360
        if [[ ${STARTER_STACKS} =~ "ic360" ]]; then
		arr=(ic360.tar)
		for f in "${arr[@]}"; do
			setup_image $f
		done
	fi

        # connections-outlook-desktop
        if [[ ${STARTER_STACKS} =~ "cnx-mso-plugin" ]]; then
		arr=(connections-outlook-desktop.tar)
		for f in "${arr[@]}"; do
			setup_image $f
		done
	fi

        # kudosboards
	if [[ ${STARTER_STACKS} =~ "kudosboards" ]]; then
		arr=(kudosboards-user.tar kudosboards-boards.tar kudosboards-core.tar kudosboards-licence.tar kudosboards-notification.tar kudosboards-provider.tar kudosboards-activity-migration.tar kudosboards-webfront.tar kudosboards-minio.tar)
		for f in "${arr[@]}"; do
			setup_image $f
		done
	fi
fi

echo -e "\nClean exit\n"
exit 0
