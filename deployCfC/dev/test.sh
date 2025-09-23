#! /bin/bash
# Initial author: on Sun Feb  5 15:26:49 GMT 2017
#
# History:
# --------
# Sun Feb  5 15:26:49 GMT 2017
#	Initial version
#
#

. `dirname "$0"`/../00-all-config.sh

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

runDockerHelloWorldTest
exit 0

modifyJSON /tmp/test.json redirect_uris '["https://master.cfc:8443/auth/liberty/callback", "https://9.98.176.126:8443/auth/liberty/callback", "https://jabbott20.swg.usma.ibm.com:8443/auth/liberty/callback"]'

# returns 1 for less than, 0 for equals, 2 for greater than
compareVersions 1.2.0 2.1.0.1
echo return ${comparison_result}, should be 1

compareVersions 2.1.0.1 1.2.0
echo return ${comparison_result}, should be 2

compareVersions 17.03.2.ce 17.09
echo return ${comparison_result}, should be 1

compareVersions 17.03.2.ce 17.06
echo return ${comparison_result}, should be 1

compareVersions 17.03.2.ce 17.03
echo return ${comparison_result}, should be 2

compareVersions 17.03 17.03.2.ce
echo return ${comparison_result}, should be 1

compareVersions 17.03.2.ce 17.03.02.ce
echo return ${comparison_result}, should be 2 "(special condition)"

compareVersions 1.2.1 1.1.0
echo return ${comparison_result}, should be 2

compareVersions 1.2.1 4.1.0
echo return ${comparison_result}, should be 1

compareVersions 1.2.3 1.2.3
echo return ${comparison_result}, should be 0

compareVersions 1.A.1 1.1.1
echo return ${comparison_result}, should be 2

compareVersions 1.1.1 1.B.1
echo return ${comparison_result}, should be 1

compareVersions 1.1.1 1.1.0
echo return ${comparison_result}, should be 2

echo
pullFromDocker hello-world
echo return $?, should be 0

echo
pullFromDocker hello-world 5 5
echo return $?, should be 0

echo
pullFromDocker hello-world X 5
echo return $?, should be non-0

echo
pullFromDocker hello-world 1 X
echo return $?, should be non-0

echo
pullFromDocker not_a_real_image_test 4 2
echo return $?, should be non-0

exit 0

SEMAPHORE_PREFIX=${DATE}
export SEMAPHORE_PREFIX
if ${is_master_HA}; then
	echo
	echo "Validating all master nodes are configured for high availability"

	SEMAPHORE=${SEMAPHORE_PREFIX}.1
	for semaphore in ${semaphore_targets}; do
		if [ -f ${semaphore} ]; then
			echo "Undetermined failure configuring master nodes - semaphore ${semaphore} still exists"
			exit 5
		fi
	done

	setSemaphore ${SEMAPHORE}		# return in semaphore_init
	if [ ${semaphore_init} != true ]; then
		echo "All master nodes are not configured for high availability, problem interfacing with etcd, or some other issue (${semaphore_init})"
		exit 6
	fi
	deleteSemaphore ${SEMAPHORE}

	echo
	echo "All master nodes configured for high availability"
fi

exit 0

ssh_command jabbott06.swg.usma.ibm.com "cd ${DEPLOY_CFC_DIR} && export SEMAPHORE_PREFIX=XXX && /bin/bash A-08-all-install-docker.sh $*" 2>&1 | tee -a ${LOG_FILE}

exit 0

ssh_command jabbott17.swg.usma.ibm.com "cd ${DEPLOY_CFC_DIR} && export SEMAPHORE_PREFIX=XXX && exit 0" 2>&1 | tee -a ${LOG_FILE}
echo $?
ssh_command jabbott17.swg.usma.ibm.com "cd ${DEPLOY_CFC_DIR} && export SEMAPHORE_PREFIX=XXX && exit 1" 2>&1 | tee -a ${LOG_FILE}
echo $?

echo
ssh_command jabbott06.swg.usma.ibm.com who
echo $?

echo
ssh_command jabbott06.swg.usma.ibm.com whoami
echo $?

echo
ssh_command jabbott06.swg.usma.ibm.com "cd /tmp && export TESTING=testing && echo \${TESTING}"
echo $?

echo
scp_command /etc/hosts jabbott06.swg.usma.ibm.com:/tmp
echo $?

echo
scp_command /opt/deployCfC jabbott06.swg.usma.ibm.com:/opt
echo $?

exit 0

echo
ssh_command root@jabbott05.swg.usma.ibm.com who
echo $?

echo
ssh_command root@jabbott06.swg.usma.ibm.com who
echo $?

echo
scp_command /etc/hosts root@jabbott05.swg.usma.ibm.com:/tmp
echo $?

echo
scp_command /etc/hosts root@jabbott06.swg.usma.ibm.com:/tmp
echo $?

exit 0

deleteSemaphore Testing
echo $?
setSemaphore Testing
echo $?
echo ${semaphore_init}
setSemaphore Testing
echo $?
echo ${semaphore_init}
deleteSemaphore Testing
echo $?

echo
check_port localhost 8500
echo $?

echo
check_import_mongo_certs_from
echo $?

