 
#! /bin/bash
# Initial author: on Sun Feb  5 15:26:49 GMT 2017
#
# History:
# --------
# Sun Feb  5 15:26:49 GMT 2017
#	Initial version
#
#

. ./00-all-config.sh

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

cd ${WORKING_DIR}

compareVersions ${CFC_VERSION} 2.1.0.1
if [ ${comparison_result} = 2 -o ${comparison_result} = 0 ]; then
	# CFC_VERSION >= 2.1.0.1
	set +o errexit
	kubectl delete role psp:privileged -n ${NAMESPACE}
	kubectl delete rolebinding default:psp:privileged -n ${NAMESPACE}
	set -o errexit

	kubectl create role psp:privileged --verb=use --resource=podsecuritypolicy --resource-name=privileged -n ${NAMESPACE}
	kubectl create rolebinding default:psp:privileged --role=psp:privileged --serviceaccount=${NAMESPACE}:default -n ${NAMESPACE}

	echo
	echo "Roles and Role Binding configured for privileged Pod Security Policy"
fi
