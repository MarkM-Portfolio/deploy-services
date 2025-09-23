#!/bin/bash

USAGE="
USAGE: 
If installing from a server that requires user login to download the chart:
installNewService.sh -s SERVICE_NAME -l CHART_LOCATION -b BUILD -n NAMESPACE -u ARTIFACTORY_USERNAME -p ARTIFACTORY_PASSWORD

EXAMPLE: 
installNewService.sh -s governor-lite -l https://artifactory.cwp.pnp-hcl.com/artifactory/connections-docker/charts/ -b governor-lite-0.1.0-20180306-050313.tgz -n connections -u username@ibm.com -p password

If installing from a server that does not require user login:
installNewService.sh -s SERVICE_NAME -l CHART_LOCATION -d PINK_DEPLOY_LOCATION -b BUILD -n NAMESPACE

EXAMPLE:
installNewService.sh -s governor-lite -l https://artifactory.cwp.pnp-hcl.com/artifactory/connections-docker/charts/ -b governor-lite-0.1.0-20180306-050313.tgz -n kube-system

If you wish to use a custom values yaml or have not installed using the deployPink automation you can specify the path with the -c flag

installNewService.sh -s governor-lite -l https://artifactory.cwp.pnp-hcl.com/artifactory/connections-docker/charts/ -c /opt/deployPink/deployPink/microservices/hybridcloud/bin/common_values.yaml -b governor-lite-0.1.0-20180306-050313.tgz -n kube-system

If you wish to upgrade a chart you can use the -up flag

EXAMPLE:
installNewService.sh -s governor-lite -l https://artifactory.cwp.pnp-hcl.com/artifactory/connections-docker/charts/ -b governor-lite-0.1.0-20180306-050313.tgz -n kube-system -up
"

service=""
location=""
build=""
namespace=""
user=""
password=""
valuesYaml="/opt/deployPink/deployPink/microservices/hybridcloud/bin/common_values.yaml"
upgrade=false
helmCommandType="installed"

while [[ $# -gt 0 ]]
do
	key="$1"

	case $key in
		-u|--user)
			user="$2"
			shift
			;;
		-p|--pass)
			password="$2"
			shift
			;;
		-s|--service)
			service="$2"
			shift
			;;
		-l|--location)
			location="$2"
			shift
			;;
		-c|--customValues)
			valuesYaml="$2"
			shift
			;;
		-b|--build)
			build="$2"
			shift
			;;
		-n|--namespace)
			namespace="$2"
			shift
			;;
		-up|--upgrade)
			upgrade=true
			;;
		*)
			echo "${USAGE}"
			;;
	esac

	shift
done

if [[ "${location}" == "" ]] || [[ "${namespace}" == "" ]] || [[ "${build}" == "" ]] || [[ "${service}" == "" ]]; then
	echo "To deploy a service you must specify a namespace, chart location, chart name and service name minimum!"
	echo "${USAGE}"
	exit 1
fi

if [[ ! "${location}" =~ "http" ]]; then
        echo "http or https must be specified in chart location"
        echo "${USAGE}"
        exit 1
fi

if [[ "${valuesYaml}" =~ "yaml" ]]; then
	helmCommand="timeout 10m helm install ${build} --name=${service} --values=${valuesYaml} --set namespace=${namespace},env.enabled=true,image.repository=connections-docker.artifactory.cwp.pnp-hcl.com"
else
	echo "When entering a custom values file it must be a .yaml file"
	echo "${USAGE}"
	exit 1
fi

if helm list | grep -q ${service} ; then
	if [ ${upgrade} = true ]; then
		echo "Helm chart already installed, upgrade will be attempted"
		helmCommand="timeout 10m helm upgrade ${service} ${build} --values=${valuesYaml} --set namespace=${namespace},env.enabled=true,image.repository=connections-docker.artifactory.cwp.pnp-hcl.com"
		helmCommandType="upgraded"
	else
		echo "Service by that name already installed. If you wish to delete it please run:"
		echo "helm delete ${service} --purge"
		echo "Or if you will to upgrade the chart please use the -up flag"
		echo "${USAGE}"
		exit 1
	fi
else
	echo "No service by that name is already installed. Continue"
fi

if [[ ! "${user}" == "" ]] && [[ ! "${password}" == "" ]]; then
	wget ${location}${build} --user=${user} --password=${password}
	if [ $? -eq 0 ]; then
		echo "Download of chart successful"
	else
		echo "Download of chart unsuccessful! Please check your username and password, and check the build name entered matches the chart in the desired location"
		echo "${USAGE}"
		exit 1
	fi
else
	wget ${location}${build}
	if [ $? -eq 0 ]; then
		echo "Download of chart successful"
	else
		echo "Download of chart unsuccessful! Maybe you need to login to the server to download the chart, and check the build name entered matches the chart in the desired location"
		echo "${USAGE}"
		exit 1
	fi
fi

$helmCommand
if [ ! $? -eq 0 ]; then
	echo "Process failed on ${service}"
	echo "Please check your chart, service and location details"
	echo "${USAGE}"
	exit 1
fi

if helm get manifest $service | grep -q "namespace"; then
	echo "Helm chart ${service} ${helmCommandType}"
else
	echo "Helm chart ${service} is missing a namespace. Please Fix!"
	helm delete ${service} --purge
	exit 1
fi
