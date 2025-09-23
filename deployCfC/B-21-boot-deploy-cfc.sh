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

touch ${LOG_FILE}-${DATE}-cfc-install-output.log
chmod 600 ${LOG_FILE}-${DATE}-cfc-install-output.log

set +o errexit
(
	set -o xtrace
	mkdir -p "${cfc_deployment_directory_cwd}"
	cd "${cfc_deployment_directory_cwd}"
	if [ ${upgrade} = true ]; then
		docker run ${manual_docker_command} -e LICENSE=accept ${ansible_temp_location_args} ${cfc_debug1} ${docker_prod_args} -v "${cfc_deployment_directory_path}" ${docker_registry}${docker_stream}/${icp_image_name}:${cfc_image_version}${cfc_image_name_suffix} upgrade ${cfc_debug2}
	else
		docker run ${manual_docker_command} -e LICENSE=accept ${ansible_temp_location_args} ${cfc_debug1} ${docker_prod_args} -v "${cfc_deployment_directory_path}" ${docker_registry}${docker_stream}/${icp_image_name}:${cfc_image_version}${cfc_image_name_suffix} install ${cfc_debug2}
	fi
	echo $? > ${LOG_FILE}-cfc-install-exit.log
	set +o xtrace
	cd ${WORKING_DIR}
) 2>&1 | tee ${LOG_FILE}-${DATE}-cfc-install-output.log
exit_status=`cat ${LOG_FILE}-cfc-install-exit.log`

# Docker isn't always returning non-0 on failure
echo "Exit status:  ${exit_status}"
echo
set +o pipefail

# error checks - unreachable and failed
cfc_error_status1=`grep 'unreachable=' ${LOG_FILE}-${DATE}-cfc-install-output.log | grep -v 'unreachable=0' | wc -l`
cfc_error_status2=`grep 'failed=' ${LOG_FILE}-${DATE}-cfc-install-output.log | grep -v 'failed=0' | wc -l`
cfc_fail_status=`grep -i 'fatal:' ${LOG_FILE}-${DATE}-cfc-install-output.log | wc -l`

# success checks
cfc_success_status1=`grep 'unreachable=' ${LOG_FILE}-${DATE}-cfc-install-output.log | grep 'unreachable=0' | wc -l`
cfc_success_status2=`grep 'failed=' ${LOG_FILE}-${DATE}-cfc-install-output.log | grep 'failed=0' | wc -l`

# totals to determine whether test tally agrees
cfc_status1_total=`expr ${cfc_error_status1} + ${cfc_success_status1}`
cfc_status2_total=`expr ${cfc_error_status2} + ${cfc_success_status2}`
cfc_status3_total=`grep "ok=" ${LOG_FILE}-${DATE}-cfc-install-output.log | wc -l`

if [ \( ${cfc_error_status1} -ne 0 -o ${cfc_error_status2} -ne 0 \) -o \
     \( ${cfc_success_status1} -ne ${cfc_success_status2} \) -o \
     \( ${cfc_success_status1} -eq 0 -o ${cfc_success_status2} -eq 0 \) -o \
     \( ${cfc_status1_total} -ne ${cfc_status2_total} \) -o \
     \( ${cfc_status1_total} -ne ${cfc_status3_total} \) -o \
     \( ${cfc_fail_status} -ne 0 \) -o \
     \( ${exit_status} -ne 0 \) ]; then
	echo "IBM Cloud private install failed (${cfc_error_status1}/${cfc_success_status1}, ${cfc_error_status2}/${cfc_success_status2}, ${cfc_status1_total}:${cfc_status2_total}:${cfc_status3_total}, ${cfc_fail_status}, ${exit_status})"
	exit 5
else
	echo "Secondary validations for IBM Cloud private install passed (${cfc_error_status1}/${cfc_success_status1}, ${cfc_error_status2}/${cfc_success_status2}, ${cfc_status1_total}:${cfc_status2_total}:${cfc_status3_total}, ${cfc_fail_status}, ${exit_status})"
fi
set -o errexit

# Remove cfc containers after install - issue #4983
docker ps -a | grep ibmcom/${icp_image_name}:${cfc_image_version} | cut -d ' ' -f 1 | xargs sudo docker rm || echo "OK if this fails"

# Rename old installation directory after upgrade
if [ ${upgrade} = true ]; then
	if [ ${day_to_day} = false ]; then
		mv ${CURRENT_DEPLOYED_DIR}/cluster ${CURRENT_DEPLOYED_DIR}/cluster.pre-upgrade.${DATE}
	fi
fi

set -o errexit
set -o pipefail

