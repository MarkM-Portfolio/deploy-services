#!/bin/bash

# Script designed to work with the following Jenkins job: https://ics-connect-jenkins.swg-devops.com/view/Private%20Cloud/job/Component%20Pack/job/DeployPink-Helm%20(MASTER)/

set -o errexit
#set -o xtrace

# Uncomment and complete the values below in order to run this script manually
# GIT_USER=
# GIT_TOKEN=
# ARTIFACTORY_USER=
# ARTIFACTORY_PASSWORD=
# production_zip=""		# blank for latest zips or put version release. e.g. "6.0.0.6"
# filename_zip=""		# blank for latest
# dev_build=			# Yes or No
# uninstall_or_upgrade=		# uninstall or upgrade
# docker_registry_type=		# artifactory, icp or private
# ic_admin_username=
# ic_admin_password=
# install_K8_dashbaord=		# Yes or No
# connections_env=		# Yes or No
# ic_host=			# front door FQDN
# ic_internal=			# IHS FQDN
# orientme=			# Yes or No
# customizer=			# Yes or No
# elasticsearch=		# Yes or No
# elasticsearch7=		# Yes or No
# es_node_affinity=		# required or preferred
# sanity=			# Yes or No
# elasticstack=			# Yes or No
# curator_schedule=		# cron format e.g. Every 1 hour="0 */1 * * *"
# skip_configure_redis=		# Yes or No
# ha_fronting_master=
# enforceSSL=			# Yes or No
# non_root=			# Yes or No
# enable_sophosav= 		# true or false

if [ "${GIT_USER}" = "" -o "${GIT_TOKEN}" = "" ]; then
	echo "Missing values for GIT_USER and/or GIT_TOKEN."
	exit 1
fi

if [ "${ARTIFACTORY_USER}" = "" -o "${ARTIFACTORY_PASSWORD}" = "" ]; then
	echo "Missing values for ARTIFACTORY_USER and/or ARTIFACTORY_PASSWORD."
	exit 1
fi

working_dir=/opt
helm_dir=${working_dir}/deployPink/microservices_connections/hybridcloud/helmbuilds
support_dir=${working_dir}/deployPink/microservices_connections/hybridcloud/support
sudo rm -rf ${working_dir}/deployPink
sudo rm -rf ${working_dir}/mastered.sem
cd ${working_dir}

if [ "${non_root}" = "" ]; then
        non_root=No
fi

if [ "${ha_fronting_master}" = "" ]; then
	master_ip=`hostname -i`
else
	master_ip=${ha_fronting_master}
fi

if [ "${ic_admin_username}" = "" -o "${ic_admin_password}" = "" -o "${ic_host}" = "" -o "${ic_internal}" = "" ]; then
	echo "ic_admin_username, ic_admin_password, ic_host and ic_internal are all required arguments"
	exit 1
fi

if [ "${ARTIFACTORY_USER}" = "" -o "${ARTIFACTORY_PASSWORD}" = "" ]; then
	echo "Missing values for ARTIFACTORY_USER and/or ARTIFACTORY_PASSWORD."
	exit 1
fi

if [ "${production_zip}" != "" ]; then
	artifactoryLocation="https://connections-docker.artifactory.cwp.pnp-hcl.com/artifactory/ibm-connections-docker-release/Component-Pack/v${production_zip}/"
	set +o errexit
	curl -sSf -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASSWORD} ${artifactoryLocation} > /dev/null
	if [ $? -ne 0 ]; then
		echo "Unable to find URL: ${artifactoryLocation}"
		exit 1
	fi
	set -o errexit
else
	if [ "${dev_build}" = "No" ]; then
		artifactoryLocation="https://connections-docker.artifactory.cwp.pnp-hcl.com/artifactory/ibm-connections-cloud-docker/conncloud/docker-base-images/hybridcloud/"
	else
		artifactoryLocation="https://connections-docker.artifactory.cwp.pnp-hcl.com/artifactory/ibm-connections-cloud-docker/conncloud/docker-base-images/hybridcloud_test/"
	fi
fi

if [ "${production_zip}" != "" ]; then
		zip=$(curl -s -u ${ARTIFACTORY_USER}:${ARTIFACTORY_PASSWORD} ${artifactoryLocation} --list-only | sed -n 's%.*href="\([^.]*\.zip\)".*%\n\1%; ta; b; :a; s%.*\n%%; p')
else
	if [ "${filename_zip}" != "" ]; then
		zip=${filename_zip}
	else
		sudo wget -q --user=${ARTIFACTORY_USER} --password=${ARTIFACTORY_PASSWORD} ${artifactoryLocation}/mastered.sem
		zip=`cat mastered.sem`
	fi
fi
sudo rm -rf ${working_dir}/${zip}*

if [ "${docker_registry_type}" = "artifactory" ]; then
	docker_registry="connections-docker.artifactory.cwp.pnp-hcl.com"
elif  [ "${docker_registry_type}" = "icp" ]; then
	docker_registry="master.cfc:8500"
	docker_registry_username="admin"
	docker_registry_password="admin"
elif  [ "${docker_registry_type}" = "private" ]; then
	docker_registry="$(sudo hostname -f):5000"
	docker_registry_username="admin"
	docker_registry_password="password"
else
	echo "docker registry type not recognised.  Exiting."
	exit 1
fi

echo "docker registry : ${docker_registry}"

if [ -z "${enable_sophosav}" ]; then
        enable_sophosav=true
fi

# Configure Sophos AV
if [ ${enable_sophosav} = true ]; then
        echo
	sudo /opt/sophos-av/bin/savdstatus | grep "Sophos Anti-Virus is active and on-access scanning is running"
	if [ $? -ne 0 ]; then
        	echo "Sophos Anti-Virus is either inactive or on-access scanning is not running. Exiting."
        	exit 1
	fi

	sudo /opt/sophos-av/bin/savupdate

	sudo /opt/sophos-av/bin/savdstatus --version
fi

echo "Downloading ${zip}.."
sudo wget -q --user=${ARTIFACTORY_USER} --password=${ARTIFACTORY_PASSWORD} ${artifactoryLocation}/${zip}
sudo unzip ${zip} -d deployPink
sudo rm -rf ${working_dir}/mastered.sem*
sudo rm -rf ${working_dir}/${zip}

# Load docker images if using 6005 ICp env/private docker registry
if [ "${docker_registry}" != "connections-docker.artifactory.cwp.pnp-hcl.com" ]; then
	sudo bash ${working_dir}/deployPink/microservices_connections/hybridcloud/support/setupImages.sh -dr ${docker_registry} -u ${docker_registry_username} -p ${docker_registry_password}
	docker_registry=${docker_registry}/connections
fi

# If uninstall is chosen, uninstall charts first
if [ "${uninstall_or_upgrade}" = "uninstall" ]; then
	release_list=( "orientme" "elasticsearch" "elasticsearch7" "mw-proxy" "infrastructure" "connections-env" "bootstrap" "sanity" "sanity-watcher" "elasticstack" "k8s-psp" "cnx-ingress" )
	for release in "${release_list[@]}"; do
		set +o errexit
		rel_deployed=`helm list $release$ --deployed -q`
		if [ "${rel_deployed}" = "${release}" ]; then
			set -o errexit
			echo "Found $release is already installed. Uninstalling.."
			helm delete $release --purge
			if [ "${release}" = "elasticsearch" ]; then
				set +o errexit
				kubectl delete pod --grace-period=0 --force --selector=component=elasticsearch,role=data -n connections
				kubectl delete statefulset es-data --grace-period=0 --force -n connections
				kubectl delete pod -l=component=elasticsearch --grace-period=0 --force -n connections
				set -o errexit
			elif [ "${release}" = "elasticsearch7" ]; then	
				set +o errexit
				kubectl delete pod --grace-period=0 --force --selector=component=elasticsearch7,role=data -n connections
				kubectl delete statefulset es-data-7 --grace-period=0 --force -n connections
				kubectl delete pod -l=component=elasticsearch7 --grace-period=0 --force -n connections
				set -o errexit
			elif [ "${release}" = "infrastructure" ]; then
				set +o errexit
				# kubectl delete pod --grace-period=0 --force --selector=app=redis-sentinel -n connections
				kubectl delete pod --grace-period=0 --force --selector=app=redis-server -n connections
				kubectl delete pod --grace-period=0 --force --selector=app=mongo -n connections
				kubectl delete statefulset mongo --grace-period=0 --force -n connections
                		set -o errexit
			elif [ "${release}" = "orientme" ]; then
				set +o errexit
				kubectl delete pod --grace-period=0 --force --selector=app=solr -n connections
				kubectl delete statefulset solr --grace-period=0 --force -n connections
				set -o errexit
			elif [ "${release}" = "elasticstack" ]; then
				# Clean old jobs
				for j in $(kubectl get jobs -o custom-columns=:.metadata.name -n connections | grep elasticsearch-curator); do
					kubectl delete jobs $j -n connections
				done
				set +o errexit
				kubectl delete pod --grace-period=0 --force --selector=component=logstash,role=data -n connections
				kubectl delete statefulset logstash --grace-period=0 --force -n connections
				kubectl delete daemonsets filebeat -n connections
				kubectl delete pod -l=k8s-app=filebeat --grace-period=0 --force -n connections
				kubectl delete pod -l=component=kibana --grace-period=0 --force -n connections
				kubectl delete pod -l=name=logstash --grace-period=0 --force -n connections
				set -o errexit
			fi
		fi
		set -o errexit
	done

	# Make sure all terminating pods are finished terminating before proceeding
	counter=0
	retries=10
	wait=30
	while true; do
		echo
		echo "Checking for any Terminating pods.."
		if [[ "$(kubectl get pods -n connections | grep Terminating )" = "" ]]; then
			echo "Check completed"
			echo
			break
		fi
		echo
		echo "Found some terminating pods"
		set +o errexit # Need to allow exit code 1 here incase pods have been terminated by the time the command runs
		kubectl get pods -n connections | grep Terminating
		set -o errexit
		counter=`expr ${counter} + 1`
		if [ ${counter} -ge ${retries} ]; then
			echo
			echo "Giving up. Please investigate why it is taking so long to terminate pod(s)"
			exit 1
		else
			echo "Waiting ${wait}s and then trying again (${counter}/${retries})"
		fi
		sleep ${wait}
	done
elif [ "${uninstall_or_upgrade}" = "upgrade" ]; then
	set +o errexit
	helm list | grep bootstrap -q
	if [ $? -eq 0 ]; then
		echo "Purging bootstrap"
		helm delete bootstrap --purge
	fi
	set -o errexit
fi

# K8 Dashbaord
if [ "${install_K8_dashbaord}" = "Yes" ]; then
	# Remove if already installed
	echo
	echo "Removing any previous dashboard configuration.."
	set +o errexit
	kubectl delete -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/rbac/heapster-rbac.yaml
	kubectl delete -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/influxdb.yaml
	kubectl delete -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/heapster.yaml
	kubectl delete -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/grafana.yaml
	kubectl delete -f ${support_dir}/dashboard-admin.yaml
	kubectl delete clusterrolebinding cluster-system-anonymous
	kubectl delete -f https://raw.githubusercontent.com/kubernetes/dashboard/master/aio/deploy/recommended/kubernetes-dashboard.yaml
	kubectl delete secret kubernetes-dashboard-key-holder -n kube-system
	set -o errexit

	# Install dashboard
	echo
	echo "Installing dashboard.."
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/master/aio/deploy/recommended/kubernetes-dashboard.yaml
	kubectl create -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/grafana.yaml
	kubectl create -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/heapster.yaml
	kubectl create -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/influxdb.yaml
	kubectl create -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/rbac/heapster-rbac.yaml
	# Allow anonymous access to dashboard (for internal testing only)
	kubectl create clusterrolebinding cluster-system-anonymous --clusterrole=cluster-admin --user=system:anonymous
	# Create a Service Account with name admin-user
	kubectl apply -f ${support_dir}/dashboard-admin.yaml
	echo
	echo "Dashboard now available here: https://${master_ip}:6443/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/"
fi

if ! [ "${production_zip}" = "6.0.0.6" -o "${production_zip}" = "6.0.0.5iFix1" ]; then
	# Pod Security Policy
	k8s_psp_chart=`ls ${helm_dir} | grep k8s-psp`

	set +o errexit
	k8s_psp="k8s-psp"
	helm list | grep ${k8s_psp} -q
	if [ $? -eq 0 ]; then
		set -o errexit
		echo "Found ${k8s_psp} is already installed.."
		if [ "${uninstall_or_upgrade}" = "upgrade" ]; then
	    		echo "Upgrading.."
			helm upgrade ${k8s_psp} ${helm_dir}/${k8s_psp_chart}
		fi
	else
		set -o errexit
		helm install --name=${k8s_psp} ${helm_dir}/${k8s_psp_chart}
	fi

	# NGINX Ingress Controller and Ingress rules
	domain_name=`hostname -d`
	cnx_ingress_chart=`ls ${helm_dir} | grep cnx-ingress`
	cnx_set="ingress.hosts.domain=${domain_name},global.onPrem=true,global.image.repository=${docker_registry}"
	set +o errexit
	cnx_ingress="cnx-ingress"
	helm list | grep ${cnx_ingress} -q
	if [ $? -eq 0 ]; then
		set -o errexit
		echo "Found ${cnx_ingress} is already installed.."
		if [ "${uninstall_or_upgrade}" = "upgrade" ]; then
		        echo "Upgrading.."
		        helm upgrade ${cnx_ingress} ${helm_dir}/${cnx_ingress_chart} --set ${cnx_set}
		fi
	else
		set -o errexit
		helm install --name=${cnx_ingress} ${helm_dir}/${cnx_ingress_chart} --set ${cnx_set}
	fi
fi

# bootstrap
if [ "${docker_registry_type}" != "icp" ]; then
	if [ "${skip_configure_redis}" = "Yes" ]; then
		configure_redis="env.skip_configure_redis=true"
	else
		configure_redis="env.skip_configure_redis=false"
	fi
	bootstrap_chart=`ls ${helm_dir} | grep bootstrap`
	helm install --name=bootstrap ${helm_dir}/${bootstrap_chart} --set env.set_ic_admin_user=${ic_admin_username},env.set_ic_admin_password=${ic_admin_password},env.set_ic_internal=${ic_internal},env.set_master_ip=${master_ip},env.set_elasticsearch_ca_password=password,env.set_elasticsearch_key_password=password,env.set_redis_secret=password,env.set_search_secret=password,env.set_solr_secret=password,${configure_redis},image.repository=${docker_registry}
	sleep 5

	# Make sure bootstrap completed before proceeding
	counter=0
	retries=10
	wait=20
	while true; do
		echo "Checking bootstrap completed OK.."
		# if [[ "$(kubectl get pods -n connections -a | grep bootstrap | grep Completed | awk '{ print $3 }')" = "Completed" ]]; then
		if [[ "$(kubectl get pods -n connections | grep bootstrap | grep Completed | awk '{ print $3 }')" = "Completed" ]]; then
			echo "Bootstrap completed"
			break
		fi
		kubectl get pods -n connections | grep bootstrap
		echo
		echo "Pod not completed"
		echo
		counter=`expr ${counter} + 1`
		if [ ${counter} -ge ${retries} ]; then
			echo "Giving up. Please check the logs of the bootstrap image"
			exit 1
		else
			echo "Waiting ${wait}s and then trying again (${counter}/${retries})"
		fi
		sleep ${wait}
	done
fi

# connections-env
con_env_chart=`ls ${helm_dir} | grep connections-env`

if [ "${enforceSSL}" = "Yes" ]; then
	extra_args=",ic.interserviceOpengraphPort=443,ic.interserviceConnectionsPort=443,ic.interserviceScheme=https"
else
	extra_args=""
fi

con_env_set="onPrem=true,createSecret=false,ic.host=${ic_host},ic.internal=${ic_internal}${extra_args},environmentName=CP"

set +o errexit
helm list | grep connections-env -q
if [ $? -eq 0 ]; then
	set -o errexit
	echo "Found connections-env is already installed.."
	if [ "${uninstall_or_upgrade}" = "upgrade" ]; then
	    	echo "Upgrading.."
		helm upgrade connections-env ${helm_dir}/${con_env_chart} --set ${con_env_set}
	fi
else
	set -o errexit
	helm install --name=connections-env ${helm_dir}/${con_env_chart} --set ${con_env_set}
fi

# elasticsearch
if [ "${elasticsearch}" = "Yes" ]; then
	t="elasticsearch"
	nodeAffinity=""
	if [ "${es_node_affinity}" = "required" ]; then
		nodeAffinity=",nodeAffinityRequired=true"
	fi
	es_chart=`ls ${helm_dir} | grep ^$t-[[:digit:]].[[:digit:]].[[:digit:]]*`
	es_set="image.repository=${docker_registry}${nodeAffinity}"
	if [ "${non_root}" = "Yes" ]; then
		es_set+=",common.runInitChmodDataAsUser=1000"
	fi
	set +o errexit
	es_deployed=`helm list $t$ --deployed -q`
	if [ "${es_deployed}" = "elasticsearch" ]; then
		set -o errexit
		echo "Found elasticsearch is already installed.."
		if [ "${uninstall_or_upgrade}" = "upgrade" ]; then
			echo "Upgrading.."
			helm upgrade elasticsearch ${helm_dir}/${es_chart} --set ${es_set}
		fi
	else
		set -o errexit
		helm install --name=elasticsearch ${helm_dir}/${es_chart} --set ${es_set}
	fi
fi

# elasticsearch7
if [ "${elasticsearch7}" = "Yes" ]; then
	t="elasticsearch7"
	nodeAffinity=""
	if [ "${es_node_affinity}" = "required" ]; then
		nodeAffinity=",nodeAffinityRequired=true"
	fi
	es7_chart=`ls ${helm_dir} | grep ^$t-[[:digit:]].[[:digit:]].[[:digit:]]*`
	es7_set="image.repository=${docker_registry}${nodeAffinity}"
	if [ "${non_root}" = "Yes" ]; then
		es7_set+=",common.runInitChmodDataAsUser=1000"
	fi
	set +o errexit
	es7_deployed=`helm list $t$ --deployed -q`
	if [ "${es7_deployed}" = "elasticsearch7" ]; then
		set -o errexit
		echo "Found elasticsearch7 is already installed.."
		if [ "${uninstall_or_upgrade}" = "upgrade" ]; then
			echo "Upgrading.."
			helm upgrade elasticsearch7 ${helm_dir}/${es7_chart} --set ${es7_set}
		fi
	else
		set -o errexit
		helm install --name=elasticsearch7 ${helm_dir}/${es7_chart} --set ${es7_set}
	fi
fi

# infrastructure
if [ "${customizer}" = "Yes" -o "${orientme}" = "Yes" ]; then
	infra_chart=`ls ${helm_dir} | grep infrastructure`
	infra_set="mongodb.createSecret=false,mongodb.image.pullPolicy=Always,global.onPrem=true,global.image.repository=${docker_registry},appregistry-service.deploymentType=hybrid_cloud"
	if [ "${non_root}" = "Yes" ]; then
		infra_set+=",mongodb.securityContext.runInitChmodDataAsUser=1001"
	fi
	set +o errexit
	helm list | grep infrastructure -q
	if [ $? -eq 0 ]; then
		set -o errexit
		echo "Found infrastructure is already installed.."
		if [ "${uninstall_or_upgrade}" = "upgrade" ]; then
			echo "Upgrading.."
			helm upgrade infrastructure ${helm_dir}/${infra_chart} --set ${infra_set}
		fi
	else
		set -o errexit
		helm install --name=infrastructure ${helm_dir}/${infra_chart} --set ${infra_set}
	fi
fi

# customizer
if [ "${customizer}" = "Yes" ]; then
	mwproxy_chart=`ls ${helm_dir} | grep "mw-proxy"`
	mwproxy_set="image.repository=${docker_registry},deploymentType=hybrid_cloud"
	set +o errexit
	helm list | grep "mw-proxy" -q
	if [ $? -eq 0 ]; then
		set -o errexit
		echo "Found mw-proxy is already installed.."
		if [ "${uninstall_or_upgrade}" = "upgrade" ]; then
			echo "Upgrading.."
			helm upgrade mw-proxy ${helm_dir}/${mwproxy_chart} --set ${mwproxy_set}
		fi
	else
		set -o errexit
		helm install --name=mw-proxy ${helm_dir}/${mwproxy_chart} --set ${mwproxy_set}
	fi
fi

# orient me
if [ "${orientme}" = "Yes" ]; then
	wait=30
	om_chart=`ls ${helm_dir} | grep orientme`
	om_set="global.onPrem=true,global.image.repository=${docker_registry},orient-web-client.service.nodePort=30001,itm-services.service.nodePort=31100,mail-service.service.nodePort=32721,community-suggestions.service.nodePort=32200,deploymentType=hybrid_cloud,orient-indexing-service.indexing.solr=false,orient-indexing-service.indexing.elasticsearch=true"
	if [ "${non_root}" = "Yes" ]; then
		om_set+=",zookeeper.securityContext.runInitChmodDataAsUser=1000,solr-basic.securityContext.runInitChmodDataAsUser=8983"
	fi
	set +o errexit
	helm list | grep orientme -q
	if [ $? -eq 0 ]; then
		set -o errexit
		echo "Found orientme is already installed.."
		if [ "${uninstall_or_upgrade}" = "upgrade" ]; then
			echo "Upgrading.."
			helm upgrade orientme ${helm_dir}/${om_chart} --set ${om_set}
			if [ $? -eq 0 ]; then
				# set retrieveal-service to use elasticsearch
				sleep ${wait}
				om_set+=",orient-retrieval-service.retrieval.elasticsearch=true"
				helm upgrade orientme ${helm_dir}/${om_chart} --set ${om_set}
			fi
		fi
	else
		set -o errexit
		helm install --name=orientme ${helm_dir}/${om_chart} --set ${om_set}
		if [ $? -eq 0 ]; then
			# set retrieveal-service to use elasticsearch
			sleep ${wait}
			om_set+=",orient-retrieval-service.retrieval.elasticsearch=true"
			helm upgrade orientme ${helm_dir}/${om_chart} --set ${om_set}
		fi
	fi
fi

# sanity
if [ "${sanity}" = "Yes" ]; then
	# sanity
	sanity_chart=`ls ${helm_dir} | grep sanity | grep -v watcher`
	sanity_set="image.repository=${docker_registry},logLevel=info"
	set +o errexit
	helm list | grep sanity | grep -v watcher -q
	if [ $? -eq 0 ]; then
		set -o errexit
		echo "Found sanity is already installed.."
		if [ "${uninstall_or_upgrade}" = "upgrade" ]; then
			echo "Upgrading.."
			helm upgrade sanity ${helm_dir}/${sanity_chart} --set ${sanity_set}
		fi
	else
		set -o errexit
		helm install --name=sanity ${helm_dir}/${sanity_chart} --set ${sanity_set}
	fi
	# sanity-watcher
	sanity_watcher_chart=`ls ${helm_dir} | grep sanity-watcher`
	sanity_watcher_set="image.repository=${docker_registry}"
	set +o errexit
	helm list | grep sanity-watcher
	if [ $? -eq 0 ]; then
		set -o errexit
		echo "Found sanity-watcher is already installed.."
		if [ "${uninstall_or_upgrade}" = "upgrade" ]; then
			echo "Upgrading.."
			helm upgrade sanity-watcher ${helm_dir}/${sanity_watcher_chart} --set ${sanity_watcher_set}
		fi
	else
		set -o errexit
		helm install --name=sanity-watcher ${helm_dir}/${sanity_watcher_chart} --set ${sanity_watcher_set}
	fi
fi

# elasticstack
if [ "${elasticstack}" = "Yes" ]; then
	elasticstack_chart=`ls ${helm_dir} | grep elasticstack`
	if [ "${curator_schedule}" = "" ]; then
		# Set to run every day
		curator_schedule="1 0 * * *"
	fi
	elasticstack_set="global.onPrem=true,global.image.repository=${docker_registry},elasticsearch-curator.logging.elasticsearch.cronjobSchedule="
	set +o errexit
	helm list | grep elasticstack -q
	if [ $? -eq 0 ]; then
		set -o errexit
		echo "Found elasticstack is already installed.."
		if [ "${uninstall_or_upgrade}" = "upgrade" ]; then
			echo "Upgrading.."
			helm upgrade elasticstack ${helm_dir}/${elasticstack_chart} --set ${elasticstack_set}"${curator_schedule}"
		fi
	else
		set -o errexit
		helm install --name=elasticstack ${helm_dir}/${elasticstack_chart} --set ${elasticstack_set}"${curator_schedule}"
	fi
fi

echo
echo "Helm list:"
helm list
echo

# Download files with icdeploy@hcl.com (Hint: no icci ID at HCL - icci@us.ibm.com) credentials:
echo "Downloading checkPods.sh"
OWNER="connections"
REPO="deploy-services"
SCRIPT="checkPods.sh"
sudo rm -f ${SCRIPT}
PATH_FILE="microservices/hybridcloud/doc/samples/${SCRIPT}"
FILE="https://git.cwp.pnp-hcl.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
sudo curl -H "Authorization: token $GIT_TOKEN" \
-H "Accept: application/vnd.github.v3.raw" \
-O \
-L $FILE

sudo chmod 777 ${SCRIPT}
set +o errexit
bash ${SCRIPT} --retries=80 --wait_interval=30 --namespace=connections
if [ $? -ne 0 ]; then
	echo "Pod verification failed - please investigate"
	exit 1
fi
set -o errexit
