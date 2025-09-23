#! /bin/bash
# Initial author: on Sun Feb  5 15:26:49 GMT 2017
#
# History:
# --------
# Sun Feb  5 15:26:49 GMT 2017
#	Initial version
#
#

# For IBM Cloud private 1.2.1 and 2.1.0.1

# Work to do marked in XYZZY

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

umask 022


# return 0 if port on host negotiates successfully
# function resets errexit to ignore so calling script must reset if desired
function check_port() {
	set +o errexit
	set -o pipefail
	set +o nounset

	number_retries=60
	connect_wait_time=5
	retry_wait_time=10
	if [ ${debug} = true ]; then
		nc_debug=-v	# -v -v
	else
		nc_debug=""
	fi

	CHECK_PORT_USAGE="usage:  check_port sHost nPort [bCheckSSL=false] [nNumberTries=${number_retries}] [nConnectWaitTime=${connect_wait_time}] [nRetryWaitTime=${retry_wait_time}]"

	if [ "$2" = "" ]; then
		echo "${CHECK_PORT_USAGE}"
		exit 109
	fi
	host=$1
	port=$2
	echo
	printf "Checking ${host}:${port}"
	if [ "$3" = true ]; then
		echo " with SSL"
		check_ssl=--ssl
	elif [ "$3" = false -o "$3" = "" ]; then
		echo
		check_ssl=""
	else
		echo "${CHECK_PORT_USAGE}"
		exit 110
	fi
	if [ "$4" != "" ]; then
		number_retries=$4
	fi
	if [ "$5" != "" ]; then
		connect_wait_time=$5
	fi
	if [ "$6" != "" ]; then
		retry_wait_time=$6
	fi
	set -o nounset

	counter=1
	while [ ${counter} -le ${number_retries} ]; do
		echo "Checking ${host}:${port} (${counter}/${number_retries})"
		nc ${nc_debug} ${check_ssl} --wait ${connect_wait_time} ${host} ${port} < /dev/null
		if [ $? -ne 0 ]; then
			echo "	FAILED, retrying in ${retry_wait_time}s"
			sleep ${retry_wait_time}
			counter=`expr ${counter} + 1`
		else
			echo "	OK"
			return 0
		fi
	done
	echo "Maximum attempts reached, giving up"
	return 1
}


# return 0 if argument has ipv4 format, returns non-0 otherwise
# function resets errexit to ignore so calling script must reset if desired
function is_ipv4() {
	set +o errexit
	set -o pipefail
	set +o nounset

	if [ "$1" = "" ]; then
		echo "usage:  is_ipv4 sHost"
		exit 108
	fi
	set -o nounset
	host=$1
	resolve_ip_return_result=""

	if [ "`echo ${host} | sed 's/\.//g' | sed 's/[0-9]*//'`" = "" ]; then
		# ipv4 address, already theoretically resolved
		# not handling ipv6 yet
		# but make sure it is a valid ipv4 address
		octet_count=0
		for octet in `echo ${host} | sed 's/\./ /g'`; do
			if [ ${octet} -lt 1 -o ${octet} -gt 255 ]; then
				echo "IP address has invalid octet ranges:  ${host}"
				return 101
			fi
			octet_count=`expr ${octet_count} + 1`
		done
		if [ ${octet_count} -ne 4 ]; then
			echo "IP address has invalid number of octets:  ${host}"
			return 102
		fi
	else
		return 103
	fi
	return 0
}


# return is in resolve_ip_return_result
# function resets errexit to ignore so calling script must reset if desired
function resolve_ip() {
	set +o errexit
	set -o pipefail
	set +o nounset

	if [ "$1" = "" ]; then
		echo "usage:  resolve_ip sHost"
		exit 100
	fi
	set -o nounset
	host=$1
	resolve_ip_return_result=""

	is_ipv4 ${host}
	if [ $? -eq 0 ]; then
		resolve_ip_return_result="${host}"
		return 0
	fi

	resolve_ip_return_result=`host ${host} | grep "has address" | head -1 | awk '{ print $NF }'`
	if [ "${resolve_ip_return_result}" = "" ]; then
		echo "${host} is not resolvable with host, trying alternative"
		resolve_ip_return_result=`ping -c 1 ${host} 2>&1 | grep '^PING ' | grep 'bytes of data.$' | awk '{ print $3 }' | sed -e 's/(//' -e 's/)//'`
		if [ "${resolve_ip_return_result}" = "" ]; then
			echo "${host} is not resolvable with ping, giving up"
			return 102
		else
			echo "OK"
		fi
	fi
	return 0
}


# function resets errexit to ignore so calling script must reset if desired
function validate_ic_host() {
	set +o errexit
	set -o pipefail
	set +o nounset

	if [ "$2" = "" ]; then
		echo "usage:  validate_ic_host sInfoString sFQHN"
		exit 103
	fi
	set -o nounset
	info_string="$1"
	ic_host=$2

	mkdir -p ${CONFIG_DIR}
	touch ${CONFIG_DIR}/${HOSTNAME}

	echo ${ic_host} | grep -q ://
	if [ $? -eq 0 ]; then
		echo "${info_string} - ${ic_host} - must specify a FQHN, not a URL"
		return 104
	fi
	echo ${ic_host} | grep -q '\.'
	if [ $? -eq 1 ]; then
		echo "${info_string} - ${ic_host} - must specify a FQHN"
		return 105
	fi
	resolve_ip ${ic_host}
	if [ $? -ne 0 -o "${resolve_ip_return_result}" = "" ]; then
		echo "${info_string} - ${ic_host} - is not resolvable"
		return 106
	fi
	if [ ${skip_configure_redis} != true ]; then
		# Check that the url that is required to configure redis in B-26-master-configure-redis.sh is available
		ic_host_response=`curl -L --insecure -o /dev/null -w '%{http_code}' --connect-timeout 60 "${ic_host}/homepage/orgadmin/adminapi.jsp"`
		if [[ "$ic_host_response" =~ ^(3[0-9][0-9]$|^000$) ]]; then
			echo "ic_server_behind_proxy=true" >> ${CONFIG_DIR}/${HOSTNAME}
		elif [ "$ic_host_response" -eq 200 ]; then
			# Check for non-zero size of adminapi.jsp page, otherwise indicating invalid page
			ichost_resp_length=`curl -L --insecure -v -w '%{size_download}' "${ic_host}/homepage/orgadmin/adminapi.jsp"`
			if [ "$ichost_resp_length" -eq 0 ]; then
				echo "Unable to reach Connections server on ${ic_host}/homepage/orgadmin/adminapi.jsp. Please make sure host is correct and Connections is running."       	    
				return 107
			fi
		else
			echo "Unable to reach Connections server on ${ic_host}/homepage/orgadmin/adminapi.jsp. Please make sure host is correct and Connections is running."
			return 108
		fi
	fi
}


# return is in is_number
# returns true if whole number, false for other
isNum () {
	set -o errexit
	set -o pipefail
	set -o nounset

	set +o nounset
	if [ "$1" = "" ]; then
		echo "usage:  isNum nWholeNumber"
		return 100
	fi
	set -o nounset

	if [ "`echo ${1} | sed -e 's/#/@/g' -e 's/^-//' -e 's/[0-9]/#/g' -e 's/#//g'`" = "" ]; then
		is_number=true
	else
		is_number=false
	fi
}


# Expects notation of W.X.Y.Z
# return is in comparison_result
# returns 1 for less than, 0 for equals, 2 for greater than
compareVersions () {
	set -o errexit
	set -o pipefail
	set -o nounset

	set +o nounset
	if [ "$2" = "" ]; then
		echo "usage:  compareVersions version1 version1"
		exit 207
	fi
	set -o nounset
	v1="$1"
	v2="$2"

	comparison_result=""
	if [[ ${v1} > ${v2} ]]; then
		comparison_result=2
	fi
	if [[ ${v1} < ${v2} ]]; then
		if [ "${comparison_result}" != "" ]; then
			# special condition such as 1.01.2 compared to 1.1.2 results
			# in both < and > being true which is actually =
			comparison_result=0
		else
			comparison_result=1
		fi
	fi
	if [[ ${v1} = ${v2} ]]; then
		if [ "${comparison_result}" != "" ]; then
			echo "Unknown error event"
			exit 209
		else
			comparison_result=0
		fi
	fi

	if [ ${debug} = true ]; then
		if [ ${comparison_result} -eq 1 ]; then
			echo "${v1} is less than ${v2}"
		elif [ ${comparison_result} -eq 0 ]; then
			echo "${v1} equals ${v2}"
		elif [ ${comparison_result} -eq 2 ]; then
			echo "${v1} is greater than ${v2}"
		else
			echo "Unknown failure event"
			exit 212
		fi
	fi
}


# Delete this once we are sure the newer, better implementation works
# Expects notation of X.Y.Z
# return is in comparison_result
# returns 1 for less than, 0 for equals, 2 for greater than
compareVersionsObsolete () {
	set -o errexit
	set -o pipefail
	set -o nounset

	set +o nounset
	if [ "$2" = "" ]; then
		echo "usage:  compareVersions version1 version1"
		exit 207
	fi
	set -o nounset
	v1="$1"
	v2="$2"

	v1_major=`echo ${v1} | awk -F. '{ print $1 }'`
	v1_minor=`echo ${v1} | awk -F. '{ print $2 }'`
	v1_fix=`echo ${v1} | awk -F. '{ print $3 }'`
	v2_major=`echo ${v2} | awk -F. '{ print $1 }'`
	v2_minor=`echo ${v2} | awk -F. '{ print $2 }'`
	v2_fix=`echo ${v2} | awk -F. '{ print $3 }'`

	v1_parse_test=`echo ${v1} | awk -F. '{ print $4 }'`
	v2_parse_test=`echo ${v2} | awk -F. '{ print $4 }'`
	if [ "${v1_parse_test}" != "" -o "${v2_parse_test}" != "" ]; then
		echo "Input does not follow X.Y.Z requirement:"
		echo "	${v1}"
		echo "	${v2}"
		exit 212
	fi

	if [ ${debug} = true ]; then
		echo
		echo "Comparing ${v1_major}.${v1_minor}.${v1_fix} to ${v2_major}.${v2_minor}.${v2_fix}"
	fi

	for number in ${v1_major} ${v1_minor} ${v1_fix} ${v2_major} ${v2_minor} ${v2_fix}; do
		isNum ${number}
		if [ ${is_number} = false ]; then
			echo
			echo "Input does not follow X.Y.Z requirement:"
			echo "	${v1}"
			echo "	${v2}"
			exit 208
		fi
	done

	if [ ${v1_major} -gt ${v2_major} ]; then
		comparison_result=2
	elif [ ${v1_major} -eq ${v2_major} ]; then
		if [ ${v1_minor} -gt ${v2_minor} ]; then
			comparison_result=2
		elif [ ${v1_minor} -eq ${v2_minor} ]; then
			if [ ${v1_fix} -gt ${v2_fix} ]; then
				comparison_result=2
			elif [ ${v1_fix} -eq ${v2_fix} ]; then
				comparison_result=0
			elif [ ${v1_fix} -le ${v2_fix} ]; then
				comparison_result=1
			else
				echo "Unknown error event"
				exit 211
			fi
		elif [ ${v1_minor} -le ${v2_minor} ]; then
			comparison_result=1
		else
			echo "Unknown error event"
			exit 210
		fi

	elif [ ${v1_major} -le ${v2_major} ]; then
		comparison_result=1
	else
		echo "Unknown error event"
		exit 209
	fi

	if [ ${debug} = true ]; then
		if [ ${comparison_result} -eq 1 ]; then
			echo "${v1} is less than ${v2}"
		elif [ ${comparison_result} -eq 0 ]; then
			echo "${v1} equals ${v2}"
		elif [ ${comparison_result} -eq 2 ]; then
			echo "${v1} is greater than ${v2}"
		else
			echo "Unknown failure event"
			exit 212
		fi
	fi
}

function check_password_length() {
	set +o errexit
	set +o nounset

	passwd="$1"

	if [ ${#passwd} -lt 6 ]; then
		printf "\nPassword is too short: %d characters\n" "${#passwd}"
		echo "Password must be at least 6 characters"
		return 1
	else
		return 0
	fi
}

# return is in set_secret
# function resets errexit to ignore so calling script must reset if desired
function readPassword() {
	set +o errexit
	set -o pipefail
	set +o nounset

	if [ "$1" = "" ]; then
		echo "usage:  readPassword sDescriptor"
		exit 107
	fi
	set -o nounset
	descriptor="$1"
	set_secret=""

	echo
	while [ "${set_secret}" = "" ]; do
		echo
		printf "${descriptor}: "
		read -s set_secret		# -s not working #2770
		check_password_length $set_secret
		if [ $? -ne 0 ]; then
			echo
			echo "Please re-enter password"
			set_secret=""
			continue
		fi
		printf "\n${descriptor} (confirmation):  "
		read -s set_secret_confirm	# -s not working #2770
		if [ "${set_secret}" != "${set_secret_confirm}" ]; then
			echo
			echo "=== Input does not match, try again"
			set_secret=""
			continue
		fi
	done
}

function error_exit () {
	echo
	echo "Failure"
	echo
	echo "	$2"
	echo
	exit $1
}

# Ensure Docker is configured with devicemapper (either loop-lvm or direct-lvm are OK)
# function resets errexit to ignore so calling script must reset if desired
checkDockerDeviceMapper () {
	set +o errexit
	set -o pipefail
	set -o nounset

	if [ `docker info | grep "Storage Driver:" | awk '{ print $3 }'` != devicemapper ]; then
		echo "Configure Docker with devicemapper storage before proceeding."
		echo "Production deployments should use direct-lvm."
		echo "Non-production deployments can use loop-lvm."
		echo "See the Docker documentation for more information."
		return 60
	else
		return 0
	fi
}


# Ensure Docker Logging Driver is set to the default json-file so logs show up in the ICp Management Console
# function resets errexit to ignore so calling script must reset if desired
checkDockerLoggingDriver () {
	set +o errexit
	set -o pipefail
	set -o nounset

	if [ `docker info | grep "Logging Driver:" | awk '{ print $3 }'` != json-file ]; then
		echo "Configure Docker Logging Driver to json-file so logs can be seen in the Management Console"
		echo "See the Docker documentation for more information."
		return 60
	else
		return 0
	fi
}

deployjq() {
	set -o errexit
	set -o nounset

	rm -rf ${ICP_CONFIG_DIR}/jq
	cp -r ${DEPLOY_CFC_DIR}/jq/ ${ICP_CONFIG_DIR}
	jq=${ICP_CONFIG_DIR}/jq/bin/jq
	
	mkdir -p ${conn_locn}/runtime/bin
	
	if [ ! -f $jq ]; then
		return 1
	else
		return 0
	fi

}

if [ -f /root/os-config.sh ]; then
	source /root/os-config.sh
fi

# For unique creation of logs and backup files
DATE=`date +%Y%m%d%H%M%S`

PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
PRG=`basename ${0}`
TMP_TEMPLATE_SUFFIX=${PRG}.${DATE}.${RANDOM}.XXXXXX.$$
TMP_TEMPLATE=/tmp/${TMP_TEMPLATE_SUFFIX}

USAGE="
usage:	${PRG}
	[--help]

	Required arguments:
	--boot=<boot-host-FQDN>
	--master_list=<master-host1-FQDN,master-host2-FQDN,...>
	--worker_list=<worker-host1-FQDN,worker-host2-FQDN,...>
	--proxy_list=<proxy-host1-FQDN,proxy-host2-FQDN,...>

	Additional required arguments if deploying in high-availability mode:
	[--master_HA_iface=<master_HA_network_interface> e.g., eth0]
	[--master_HA_vip=<master_HA_VIP>]
	[--proxy_HA_iface=<proxy_HA_network_interface> e.g., eth0]
	[--proxy_HA_vip=<proxy_HA_VIP>]
	[--docker_storage_block_device=</dev/XXX>]

	Additional arguments if deploying dedicated infrastructure for Elasticsearch:
	--infra_worker_list=<infra_worker-host1-FQDN,infra_worker-host2-FQDN,...>

	Optional arguments if deploying in high-availability mode:
	[--master_HA_mount_registry=<NFS_mount> e.g., server-FQDN:/Connections/registry]
	[--master_HA_mount_audit=<NFS_mount> e.g., server-FQDN:/Connections/audit]

	Additional arguments if deploying with Enterprise Edition components:
	[--use_docker_ee=<Docker_EE_subscription_URL>]
	[--cfc_ee_url=<cfc_ee_url>]

	Commonly used optional arguments to reduce interactive input during install:
	[--set_redis_secret=<redis_secret_cleartext>]
	[--set_search_secret=<search_secret_cleartext>]
	[--set_solr_secret=<solr_secret_cleartext>]
	[--set_krb5_secret=<krb5_secret_filepath>]
	[--set_ic_host=<Connections_front_door_FQDN>]
	[--internal_ic=<Connections_http_server>]
	[--set_ic_admin_user=<Connections_admin_username>]
	[--set_ic_admin_password=<Connections_admin_password_cleartext>]
	[--set_elasticsearch_ca_password=<elasticsearch_ca_secret_cleartext>]
	[--set_elasticsearch_key_password=<elasticsearch_secret_cleartext>]

	Deployment lifecycle optional arguments:
	[--uninstall=clean | --uninstall=cleaner | --uninstall=cleanest ]
	[--upgrade]
	[--add_worker=<worker-host-FQDN>]
	[--add_infra_worker=<infra_worker-host-FQDN>]
	[--remove_worker=<worker-host-FQDN>]
	[--remove_infra_worker=<infra_worker-host-FQDN>]

	Optional arguments used to manage security-related steps:
	[--skip_ssh_key_generation]
	[--skip_ssh_key_validation]
	[--skip_ssh_key_distribution]
	[--pregenerated_private_key_file=<full_path/key_name>]
	[--skip_ssh_prompts]
	[--root_login_passwd=<password>]
	[--non_root_user=<user>]
	[--non_root_passwd=<passwd>]
	[--regenerate_passwords]

	Optional arguments specific to operating system modification and hardware resources:
	[--ignore_os_requirements]
	[--ignore_hardware_requirements]
	[--skip_all_os_changes]
	[--skip_rpm_installation]
	[--skip_disable_firewall]
	[--skip_disable_selinux]
	[--skip_ntp_check]
	[--skip_os_tuning]
	[--skip_hosts_modification]
	[--skip_logrotation_configuration]
	[--skip_configure_redis]
	[--configure_firewall]
	[--ext_proxy_url=<http[s]://[username:password@]host:port>]
		e.g. non-authenticated proxy: http[s]://host:port
		e.g. authenticated proxy: http[s]://username:password@host:port
	[--temporary_file_location=<path>]

	Rarely used optional arguments - only by request from Connections Support:
	[--force_uninstall]
	[--set_namespace=<namespace_name>]
	[--skip_docker_deployment]
	[--skip_kibana_deployment]
	[--skip_validation_checks]
	[--skip_port_check]
	[--skip_mysql_check]
	[--skip_disk_space_check]
	[--skip_cloud_init_check]
	[--alt_cfc_version=<CfC_version>]
	[--alt_cfc_docker_registry=<alternate_cfc_docker_registry_FQDN>]
	[--alt_cfc_docker_stream=<daily | stable>]
	[--alt_docker_version=<Docker_version>]
	[--skip_k8s_cluster_config]
	[--manual_docker_command=<command>]
	[--independent_helm_install]
	[--development_mode]
	[--debug]
	[--custom_config=<full_path/filename>]


Usage notes:
1. master_list, worker_list, infra_worker_list, and proxy_list arguments may have one or more entries in a list delimited by a space or a comma

2. --skip_all_os_changes invokes the following arguments:

	--skip_rpm_installation
	--skip_disable_firewall
	--skip_disable_selinux
	--skip_ntp_check
	--skip_os_tuning
	--skip_hosts_modification
	--skip_logrotation_configuration

3. --pregenerated_private_key_file invokes --skip_ssh_key_generation
	Note:  --pregenerated_private_key_file is often used in conjunction with
	--skip_ssh_key_distribution

4. --skip_ssh_key_distribution invokes --skip_ssh_key_generation

5. --non_root_user/--non_root_passwd and --root_login_passwd are mutually exclusive

6. If using --non_root_user/--non_root_passwd, the user must be uniform across all nodes

7. If using --root_login_passwd or --non_root_passwd, the password must be uniform across all nodes

8. If deploying with high availability, the NFS mount options are optional, but the mounts are still required.  If not using the NFS mount options, the mounts must be performed manually using NFSv4-compliant mount options.
"

if [ ${PRG} != collectLogs.sh -a ${PRG} != package.sh -a ${PRG} != copy.sh -a ${PRG} != driver.sh -a ${PRG} != deployUpdates.sh -a ${PRG} != deploySubUpdate.sh -a ${PRG} != test.sh ]; then
	if [ $# -eq 0 ]; then
		echo "${USAGE}"
		exit 12
	fi
fi

# Pre-set macros so nounset doesn't complain
BOOT=""
MASTER_LIST=""
WORKER_LIST=""
INFRA_WORKER_LIST=""
PROXY_LIST=""
master_HA_iface=""
master_HA_vip=""
proxy_HA_iface=""
proxy_HA_vip=""
master_HA_mount_registry=""
master_HA_mount_audit=""
use_docker_ee=""
uninstall=""
set_namespace=""
set_redis_secret=""
set_search_secret=""
set_solr_secret=""
set_krb5_secret=""
set_ic_host=""
internal_ic=""
set_ic_admin_user=""
set_ic_admin_password=""
set_elasticsearch_ca_password=""
set_elasticsearch_key_password=""
regenerate_passwords=false
ignore_os_requirements=false
ignore_hardware_requirements=false
add_worker=""
add_infra_worker=""
remove_worker=""
remove_infra_worker=""
root_login_passwd=""
non_root_user=""
non_root_passwd=""
pregenerated_private_key_file=""
enable_management_node=""
skip_ssh_key_generation=false
skip_ssh_key_validation=false
skip_ssh_key_distribution=false
skip_ssh_prompts=false
upgrade=false
skip_docker_deployment=false
skip_kibana_deployment=false
skip_configure_redis=false
skip_validation_checks=false
skip_port_check=false
skip_mysql_check=false
skip_disk_space_check=false
skip_cloud_init_check=false
alt_cfc_version=""
cfc_ee_url=""
docker_storage_block_device=""
alt_cfc_docker_registry=""
alt_cfc_docker_stream=""
alt_docker_version=""
skip_all_os_changes=false
skip_rpm_installation=false
skip_disable_firewall=false
skip_disable_selinux=false
skip_ntp_check=false
skip_os_tuning=false
skip_hosts_modification=false
configure_firewall=false
skip_logrotation_configuration=false
ext_proxy_url=""
temporary_file_location=""
skip_k8s_cluster_config=false
manual_docker_command=""
independent_helm_install=false
debug=false
development_mode=false
force_uninstall=false
custom_config=""
for arg in $*; do
	if [ ${arg} = --upgrade ]; then
		upgrade=true
	elif [ ${arg} = --skip_all_os_changes ]; then
		skip_all_os_changes=true
	elif [ ${arg} = --skip_rpm_installation ]; then
		skip_rpm_installation=true
	elif [ ${arg} = --skip_disable_firewall ]; then
		skip_disable_firewall=true
	elif [ ${arg} = --skip_disable_selinux ]; then
		skip_disable_selinux=true
	elif [ ${arg} = --skip_ntp_check ]; then
		skip_ntp_check=true
	elif [ ${arg} = --skip_os_tuning ]; then
		skip_os_tuning=true
	elif [ ${arg} = --skip_hosts_modification ]; then
		skip_hosts_modification=true
	elif [ ${arg} = --configure_firewall ]; then
		configure_firewall=true
	elif [ ${arg} = --skip_logrotation_configuration ]; then
		skip_logrotation_configuration=true
	elif [ ${arg} = --skip_ssh_key_generation ]; then
		skip_ssh_key_generation=true
	elif [ ${arg} = --skip_ssh_key_validation ]; then
		skip_ssh_key_validation=true
	elif [ ${arg} = --skip_ssh_key_distribution ]; then
		skip_ssh_key_distribution=true
	elif [ ${arg} = --skip_ssh_prompts ]; then
		skip_ssh_prompts=true
	elif [ ${arg} = --regenerate_passwords ]; then
		regenerate_passwords=true
	elif [ ${arg} = --skip_docker_deployment ]; then
		skip_docker_deployment=true
	elif [ ${arg} = --skip_kibana_deployment ]; then
		skip_kibana_deployment=true
	elif [ ${arg} = --skip_configure_redis ]; then
		skip_configure_redis=true
	elif [ ${arg} = --skip_validation_checks ]; then
		skip_validation_checks=true
	elif [ ${arg} = --skip_port_check ]; then
		skip_port_check=true
	elif [ ${arg} = --skip_mysql_check ]; then
		skip_mysql_check=true
	elif [ ${arg} = --skip_disk_space_check ]; then
		skip_disk_space_check=true
	elif [ ${arg} = --skip_cloud_init_check ]; then
		skip_cloud_init_check=true
	elif [ ${arg} = --skip_k8s_cluster_config ]; then
		skip_k8s_cluster_config=true
	elif [ ${arg} = --ignore_os_requirements ]; then
		ignore_os_requirements=true
	elif [ ${arg} = --ignore_hardware_requirements ]; then
		ignore_hardware_requirements=true
	elif [ ${arg} = --independent_helm_install ]; then
		independent_helm_install=true
	elif [ ${arg} = --debug ]; then
		debug=true
	elif [ ${arg} = --development_mode ]; then
		development_mode=true
	elif [ ${arg} = --force_uninstall ]; then
		force_uninstall=true
	elif [ ${arg} = --disable_management_node ]; then
		# Undocumented flag to control ICp metering and monitoring in 2.1.0.1+
		enable_management_node=false
	elif [ ${arg} = --root_check ]; then
		# Undocumented call to check root, no-op
		:
	else
		set +o errexit
		found_match=false
		echo ${arg} | grep -q -e --boot=
		if [ $? -eq 0 ]; then
			BOOT=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | egrep -q -e --master_list=\|--master=
		if [ $? -eq 0 ]; then
			MASTER_LIST=`echo ${arg} | awk -F= '{ print $2 }' | sed 's/,/ /g'`
			found_match=true
			echo ${arg} | grep -q -e --master=
			if [ $? -eq 0 ]; then
				echo "--master has been deprecated, use --master_list"
			fi
		fi
		echo ${arg} | grep -q -e --infra_worker_list=
		if [ $? -eq 0 ]; then
			INFRA_WORKER_LIST=`echo ${arg} | awk -F= '{ print $2 }' | sed 's/,/ /g'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --worker_list=
		if [ $? -eq 0 ]; then
			WORKER_LIST=`echo ${arg} | awk -F= '{ print $2 }' | sed 's/,/ /g'`
			found_match=true
		fi
		echo ${arg} | egrep -q -e --proxy_list=\|--proxy=
		if [ $? -eq 0 ]; then
			PROXY_LIST=`echo ${arg} | awk -F= '{ print $2 }' | sed 's/,/ /g'`
			found_match=true
			echo ${arg} | grep -q -e --proxy=
			if [ $? -eq 0 ]; then
				echo "--proxy has been deprecated, use --proxy_list"
			fi
		fi
		echo ${arg} | grep -q -e --master_HA_iface=
		if [ $? -eq 0 ]; then
			master_HA_iface=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --master_HA_vip=
		if [ $? -eq 0 ]; then
			master_HA_vip=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --proxy_HA_iface=
		if [ $? -eq 0 ]; then
			proxy_HA_iface=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --proxy_HA_vip=
		if [ $? -eq 0 ]; then
			proxy_HA_vip=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --uninstall=
		if [ $? -eq 0 ]; then
			uninstall=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --root_login_passwd=
		if [ $? -eq 0 ]; then
			root_login_passwd=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --non_root_user=
		if [ $? -eq 0 ]; then
			non_root_user=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --non_root_passwd=
		if [ $? -eq 0 ]; then
			non_root_passwd=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --pregenerated_private_key_file=
		if [ $? -eq 0 ]; then
			pregenerated_private_key_file=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --import_mongo_certs_from=
		if [ $? -eq 0 ]; then
			printf "\nArgument '--import_mongo_certs_from' was deprecated, thus it will be ignored. MongoDB is using Intermediate CA for Environment-Internal Trust."
			found_match=true
		fi
		echo ${arg} | grep -q -e --set_namespace=
		if [ $? -eq 0 ]; then
			set_namespace=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --set_mongo_secret=
		if [ $? -eq 0 ]; then
			printf "\nArgument '--set_mongo_secret=' was deprecated, thus it will be ignored. MongoDB is using Intermediate CA for Environment-Internal Trust."
			found_match=true
		fi
		echo ${arg} | grep -q -e --set_redis_secret=
		if [ $? -eq 0 ]; then
			set_redis_secret=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --set_search_secret=
		if [ $? -eq 0 ]; then
			set_search_secret=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --set_solr_secret=
		if [ $? -eq 0 ]; then
			set_solr_secret=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --set_krb5_secret=
		if [ $? -eq 0 ]; then
			set_krb5_secret=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --set_ic_host=
		if [ $? -eq 0 ]; then
			set_ic_host=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --internal_ic=
		if [ $? -eq 0 ]; then
			internal_ic=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --set_ic_admin_user=
		if [ $? -eq 0 ]; then
			set_ic_admin_user=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --set_ic_admin_password=
		if [ $? -eq 0 ]; then
			set_ic_admin_password=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --set_elasticsearch_ca_password=
		if [ $? -eq 0 ]; then
			set_elasticsearch_ca_password=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --regenerate_passwords=
		if [ $? -eq 0 ]; then
			regenerate_passwords=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --set_elasticsearch_key_password=
		if [ $? -eq 0 ]; then
			set_elasticsearch_key_password=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --use_docker_ee=
		if [ $? -eq 0 ]; then
			use_docker_ee=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --alt_cfc_version=
		if [ $? -eq 0 ]; then
			alt_cfc_version=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --cfc_ee_url=
		if [ $? -eq 0 ]; then
			cfc_ee_url=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --docker_storage_block_device=
		if [ $? -eq 0 ]; then
			docker_storage_block_device=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --ext_proxy_url=
		if [ $? -eq 0 ]; then
			ext_proxy_url=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --temporary_file_location=
		if [ $? -eq 0 ]; then
			temporary_file_location=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --alt_cfc_docker_registry=
		if [ $? -eq 0 ]; then
			alt_cfc_docker_registry=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --alt_cfc_docker_stream=
		if [ $? -eq 0 ]; then
			alt_cfc_docker_stream=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --alt_docker_version=
		if [ $? -eq 0 ]; then
			alt_docker_version=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --manual_docker_command=
		if [ $? -eq 0 ]; then
			extra_docker_args="-l `echo ${arg} | awk -F= '{ print $2 }'`"
			found_match=true
		fi
		echo ${arg} | grep -q -e --master_HA_mount_registry=
		if [ $? -eq 0 ]; then
			master_HA_mount_registry=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --master_HA_mount_audit=
		if [ $? -eq 0 ]; then
			master_HA_mount_audit=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --custom_config=
		if [ $? -eq 0 ]; then
			custom_config=`echo ${arg} | awk -F= '{ print $2 }'`
			found_match=true
		fi
		echo ${arg} | grep -q -e --remove_worker=
		if [ $? -eq 0 ]; then
			remove_worker=`echo ${arg} | awk -F= '{ print $2 }' | sed 's/,/ /g'`
			echo ${remove_worker} | grep -q ' '
			if [ $? -eq 0 ]; then
				echo "Can only remove one worker at a time"
				exit 11
			fi
			found_match=true
		fi
		echo ${arg} | grep -q -e --remove_infra_worker=
		if [ $? -eq 0 ]; then
			remove_infra_worker=`echo ${arg} | awk -F= '{ print $2 }' | sed 's/,/ /g'`
			remove_worker=${remove_infra_worker}
			echo ${remove_worker} | grep -q ' '
			if [ $? -eq 0 ]; then
				echo "Can only remove one infra worker at a time"
				exit 11
			fi
			found_match=true
		fi
		# can only add one worker at a time
		echo ${arg} | grep -q -e --add_worker=
		if [ $? -eq 0 ]; then
			add_worker=`echo ${arg} | awk -F= '{ print $2 }' | sed 's/,/ /g'`
			echo ${add_worker} | grep -q ' '
			if [ $? -eq 0 ]; then
				echo "Can only add one worker at a time"
				exit 11
			fi
			found_match=true
		fi

		# can only add one infra_worker at a time
		echo ${arg} | grep -q -e --add_infra_worker=
		if [ $? -eq 0 ]; then
			add_infra_worker=`echo ${arg} | awk -F= '{ print $2 }' | sed 's/,/ /g'`
			add_worker=${add_infra_worker}
			echo ${add_worker} | grep -q ' '
			if [ $? -eq 0 ]; then
				echo "Can only add one infra worker at a time"
				exit 11
			fi
			found_match=true
		fi
		if [ ${found_match} = false ]; then
			if [ ${arg} != --help ]; then
				echo "Unknown command line argument:  ${arg}"
			fi
			echo "${USAGE}"
			exit 3
		fi
		set -o errexit
	fi
done

ICP_CONFIG_DIR=/opt/ibm/connections
ICP_CONFIG_FILE=config.json

mkdir -p ${ICP_CONFIG_DIR}
if [ $? -eq 0 ]; then
	if [ ! -f ${ICP_CONFIG_DIR}/${ICP_CONFIG_FILE} ]; then
		touch ${ICP_CONFIG_DIR}/${ICP_CONFIG_FILE}
		if [ $? -ne 0 ]; then
			echo "Cannot write to ${ICP_CONFIG_DIR}/${ICP_CONFIG_FILE}" 
			exit 214
		fi
	fi
fi

# set $WORKING_DIR to the current directory
current_dir="$( cd "$( dirname "$0" )" && pwd )"
source_dir="$(echo $current_dir | sed 's/\/deployCfC//')"
WORKING_DIR=${source_dir}
if [ ${PRG} = test.sh ]; then
	WORKING_DIR=`echo ${WORKING_DIR} | sed 's@/dev@@'`
fi

# Internal definitions
DEPLOY_CFC_DIR=${WORKING_DIR}/deployCfC
LOG_FILE=/var/log/cfc.log

# Kibana dir
KIBANA_DIR=${DEPLOY_CFC_DIR}/kibana

# Elasticsearch dir
ELASTICSEARCH_DIR=${WORKING_DIR}/elasticsearch

# Generic dir to place files needed for config
CONFIG_DIR=${DEPLOY_CFC_DIR}/config

# Self identification
set +o errexit
hostname -f
if [ $? -ne 0 ]; then
	echo "Problem running: hostname -f"
	echo "This command must work for ICp install/upgrade"
	exit 22
else
        HOSTNAME=`hostname -f`
fi
set -o errexit

# etcd port
ETCD_PORT=4001

# Docker registry
DOCKER_REGISTRY=/var/lib/registry

# Docker everything else
DOCKER=/var/lib/docker
DOCKER_EXT_PROXY_DIR=/etc/systemd/system/docker.service.d
DOCKER_EXT_PROXY_CONFIG_FILE=proxies.conf
DOCKER_CONFIG_DIR=/etc/docker
DOCKER_CONFIG_FILE=daemon.json

# Cloud private audit
CP_AUDIT=/var/lib/icp/audit

# SSH
ssh_args="-o StrictHostKeyChecking=no"

# SSH key required files
SSH_KEY_FILES_BOOT="id_rsa id_rsa.pub"
SSH_KEY_DEPLOYMENT_LOCATION_BOOT=${WORKING_DIR}/keys_dir

# Logging
set +o errexit
echo ${PRG} | egrep -q '^[A-Z]-[0-9]'\|'^deployCfC.sh$'\|'^collectLogs.sh$\|deployUpdates.sh$'\|'^deploySubUpdate.sh$'\|'^validateDeployment.sh$'
exit_status=$?
set -o errexit
if [ ${exit_status} -eq 0 ]; then
	if [ "`id -u`" = 0 ]; then
		touch ${DEPLOY_CFC_DIR}/.last_args.txt ${LOG_FILE}
		chmod 600 ${DEPLOY_CFC_DIR}/.last_args.txt ${LOG_FILE}
		(
			echo
			date
			echo $0 $* 
			echo $* > ${DEPLOY_CFC_DIR}/.last_args.txt
		) >> ${LOG_FILE}
	else
		echo "Warning:  not running as root"
	fi
fi

# Ensure hardcoded install location, setup environment
set +o errexit
echo ${PRG} | egrep -q '^[A-Z]-[0-9]'\|'^deployCfC.sh$'\|'^collectLogs.sh$'\|'^test.sh$'\|'^validateDeployment.sh$'
if [ $? -eq 0 ]; then
	cd `dirname $0`
	if [ ${PRG} = test.sh ]; then
		pushd .. > /dev/null
	fi
	if [ ! -e ${DEPLOY_CFC_DIR}/deployCfC.sh -o ! -x ${DEPLOY_CFC_DIR}/deployCfC.sh ]; then
		echo "Scripts must be installed at ${DEPLOY_CFC_DIR}"
		exit 4
	fi

	sshpass_bin=${DEPLOY_CFC_DIR}/sshpass/bin/sshpass
	jq_bin=${DEPLOY_CFC_DIR}/jq/bin/jq

	setuid_bin=${DEPLOY_CFC_DIR}/setuid/bin/setuid
	for binary in ${sshpass_bin} ${jq_bin} ${setuid_bin}; do
		if [ ! -x ${binary} ]; then
			echo "Can't find ${binary}"
			exit 1
		fi
		dir=`dirname ${binary}`
		PATH=${PATH}:${dir}
	done
	
	rm -rf ${ICP_CONFIG_DIR}/jq
	cp -r ${DEPLOY_CFC_DIR}/jq/ ${ICP_CONFIG_DIR}
	jq=${ICP_CONFIG_DIR}/jq/bin/jq

fi
set -o errexit

if [ -n "${set_redis_secret}" ]; then
	check_password_length ${set_redis_secret}
	if [ $? -ne 0 ]; then
		echo
		echo "Redis password must contain a minimum of 6 characters"
		exit 216
	fi
	set -o errexit
	set -o nounset
fi
if [ -n "${set_search_secret}" ]; then
	check_password_length ${set_search_secret}
	if [ $? -ne 0 ]; then
		echo
		echo "Search password must contain a minimum of 6 characters"
		exit 217
	fi
	set -o errexit
	set -o nounset
fi
if [ -n "${set_solr_secret}" ]; then
	check_password_length ${set_solr_secret}
	if [ $? -ne 0 ]; then
		echo
		echo "Solr password must contain a minimum of 6 characters"
		exit 218
	fi
	set -o errexit
	set -o nounset
fi
if [ -n "${set_elasticsearch_ca_password}" ]; then
	check_password_length ${set_elasticsearch_ca_password}
	if [ $? -ne 0 ]; then
		echo
		echo "Elastic Search ca password must contain a minimum of 6 characters"
		exit 219
	fi
	set -o errexit
	set -o nounset
fi
if [ -n "${set_elasticsearch_key_password}" ]; then
	check_password_length ${set_elasticsearch_key_password}
	if [ $? -ne 0 ]; then
		echo
		echo "Elastic Search key password must contain a minimum of 6 characters"
		exit 220
	fi
	set -o errexit
	set -o nounset
fi


# Populate config.json
set +o errexit
# On a clean install, file is empty
if [ ! -s ${ICP_CONFIG_DIR}/${ICP_CONFIG_FILE} ]; then
	# add key value pair in json file
	${jq_bin} -n --arg deployCfC_location $DEPLOY_CFC_DIR '{"connections_location": $deployCfC_location}' > ${ICP_CONFIG_DIR}/${ICP_CONFIG_FILE}
	if [ $? -ne 0 ]; then
		echo "Could not update ${ICP_CONFIG_DIR}/${ICP_CONFIG_FILE}"
		exit 215
	fi
else
	# if configured value and current directory are the same, nothing to do
	${jq_bin} -c -r ".connections_location" ${ICP_CONFIG_DIR}/${ICP_CONFIG_FILE} | grep -q "${DEPLOY_CFC_DIR}"
	if [ $? -eq 0 ]; then
		if [ ${debug} = true ]; then
			echo
			echo "${DEPLOY_CFC_DIR} already configured in ${ICP_CONFIG_DIR}/${ICP_CONFIG_FILE}"
		fi
	else
		# values are different, replace in json
		echo
		cp -p ${ICP_CONFIG_DIR}/${ICP_CONFIG_FILE} ${ICP_CONFIG_DIR}/${ICP_CONFIG_FILE}.${DATE}
		KVP=$($jq_bin --arg deployCfC_location $DEPLOY_CFC_DIR '.connections_location = $deployCfC_location' < ${ICP_CONFIG_DIR}/${ICP_CONFIG_FILE})
		if [ $? -eq 0 ]; then
			echo "${KVP}" >| ${ICP_CONFIG_DIR}/${ICP_CONFIG_FILE}
		else
			echo "Cannot update location details in ${ICP_CONFIG_DIR}/${ICP_CONFIG_FILE}."
			exit 216
		fi
		echo
		echo "Checking changes on ${ICP_CONFIG_DIR}/${ICP_CONFIG_FILE}"
		diff ${ICP_CONFIG_DIR}/${ICP_CONFIG_FILE}.${DATE} ${ICP_CONFIG_DIR}/${ICP_CONFIG_FILE} 
	fi
fi
set -o errexit

conn_locn=$(cat $ICP_CONFIG_DIR/$ICP_CONFIG_FILE | $jq_bin -r '.connections_location')
if [ ! -d "${conn_locn}" ]; then
        echo "Cannot determine ICp install directory"
        exit 222
fi
RUNTIME_BINS=${conn_locn}/runtime
PATH=${RUNTIME_BINS}/bin:$PATH
export PATH

# Required RPMs that are not installed by default for minimal deployments
REQUIRED_RPMS="coreutils redhat-lsb-core ntp ntpdate logrotate bind-utils net-tools zip unzip lsof sysstat ethtool procps-ng util-linux bzip2 openssl openssh-clients nmap python yum-utils device-mapper-persistent-data lvm2 python-setuptools gzip bc sudo firewalld NetworkManager tcpdump socat conntrack nfs-utils"

# List of firewall packages
FIREWALL_PACKAGES="iptables firewalld"

# Package manifest + manifest.md5
pushd ${WORKING_DIR} > /dev/null
PACKAGE_LIST=`find deployCfC -type f | sort | grep -v deployCfC/dev/ | grep -v deployCfC/manifest.md5 | grep -v ‘deployCfC/\.’`
popd > /dev/null

# Increase maximum memory map areas per process
VM_MAX_MAP_COUNT=262144

# make sure worker and infra_worker nodes are on seperate machines
if [ "${INFRA_WORKER_LIST}" != "" ]; then
	infra_workerArray=(${INFRA_WORKER_LIST//,/ })
	workerArray=(${WORKER_LIST//,/ })
	for infra_worker in "${infra_workerArray[@]}"; do
		if [[ "${workerArray[@]}" =~ "${infra_worker}" ]]; then
		echo "${infra_worker} cannot be used as a generic worker and infra worker. Please use seperate machines."
		exit 40
	fi
	done
fi

# Concatenate workers and remove trailing space if only one worker
WORKER_LIST="`echo ${WORKER_LIST} ${INFRA_WORKER_LIST} | sed 's/ $//'`"

# Ensure no corruption
set +o errexit
echo ${PRG} | egrep -q '^[A-Z]-[0-9]'\|'^deployCfC.sh$'\|'^collectLogs.sh$'\|'^test.sh$'\|'^validateDeployment.sh$'
if [ $? -eq 0 ]; then
	pushd .. > /dev/null
	md5sum --strict --status -c deployCfC/manifest.md5
	if [ $? -ne 0 ]; then
		echo
		md5sum --strict -c deployCfC/manifest.md5
		echo
		printf "One or more scripts changed or corrupted, "
		if [ ${development_mode} = false ]; then
			echo "cannot continue"
			exit 8
		else
			echo "ignoring in development mode"
			echo
		fi
	fi
	popd > /dev/null
fi
set -o errexit

topology_change=0
if [ ${upgrade} = true ]; then
	topology_change=`expr ${topology_change} + 1`
fi
if [ "${uninstall}" != "" ]; then
	topology_change=`expr ${topology_change} + 1`
fi
if [ "${remove_worker}" != "" ]; then
	topology_change=`expr ${topology_change} + 1`
fi
if [ "${add_worker}" != "" ]; then
	topology_change=`expr ${topology_change} + 1`
fi
if [ ${topology_change} -gt 1 ]; then
	echo
	echo "Only one topology changing argument can be run at a time:"
	echo
	echo "	--upgrade"
	echo "	--uninstall"
	echo "	--remove_worker"
	echo "	--remove_infra_worker"
	echo "	--add_worker"
	echo "	--add_infra_worker"
	echo
	exit 9
fi

clean=0
if [ "${uninstall}" = "" ]; then
	:	# no-op, always will be, but don't want to output anything, etc
elif [ "${uninstall}" = clean ]; then
	clean=1
elif [ "${uninstall}" = cleaner ]; then
	clean=2
elif [ "${uninstall}" = cleanest ]; then
	clean=3
elif [ "${uninstall}" = preserve ]; then
	echo "Uninstall in preserve mode is not yet implemented"
	exit 17
else
	echo "Unknown uninstall mode:  ${uninstall}"
	exit 18
fi

if [ "${set_elasticsearch_ca_password}" != "" -o "${set_elasticsearch_key_password}" != "" ]; then
	if [ "${set_elasticsearch_ca_password}" = "" -o "${set_elasticsearch_key_password}" = "" ]; then
		echo "--set_elasticsearch_ca_password and --set_elasticsearch_key_password must both be set"
		exit 30
	fi
fi

# --regenerate_password flag check
if [ ${regenerate_passwords} = true -a ${upgrade} = false ]; then
	echo	
	echo "--regenerate_passwords can only be used (optionally) when upgrading."
	exit 30
elif [ ${regenerate_passwords} = false -a ${upgrade} = true ] && [ "${set_redis_secret}" != "" -o "${set_search_secret}" != "" -o "${set_solr_secret}" != "" -o "${set_elasticsearch_ca_password}" != "" -o "${set_elasticsearch_key_password}" != "" ]; then
	echo	
	echo "By default, passwords are not regenerated when upgrading, so please ensure none of the following flags are used:"
	echo "--set_redis_secret"
	echo "--set_search_secret"
	echo "--set_solr_secret"
	echo "--set_elasticsearch_ca_password"
	echo "--set_elasticsearch_key_password"
	echo
	echo "If you want to regenerate passwords during upgrade, please use the --regenerate_passwords flag."
	echo "NOTE: Doing this will mean you will need to re-import ES certs into WebSphere if using Elasticseach Metrics."
	exit 30
fi

if [ "${pregenerated_private_key_file}" != "" ]; then
	skip_ssh_key_generation=true
fi

if [ ${skip_ssh_key_distribution} = true ]; then
	skip_ssh_key_generation=true
fi

if [ ${skip_all_os_changes} = true ]; then
	skip_rpm_installation=true
	skip_disable_firewall=true
	skip_disable_selinux=true
	skip_ntp_check=true
	skip_os_tuning=true
	skip_hosts_modification=true
	skip_logrotation_configuration=true
fi

# ICp version
# Once we have a stable cadence, stop locking into a ICp version and go with the flow
CFC_VERSION_DEFAULT=1.2.1

set +o nounset
if [ "${CFC_VERSION}" != "" ]; then
	echo "Use --alt_cfc_version instead of defining CFC_VERSION"
	exit 15
fi
if [ "${alt_cfc_version}" != "" ]; then
	echo "Overriding IBM Cloud private version default from ${CFC_VERSION_DEFAULT} to ${alt_cfc_version}"
	CFC_VERSION=${alt_cfc_version}
else
	CFC_VERSION=${CFC_VERSION_DEFAULT}
fi

# General 2.1.0.1 support
compareVersions ${CFC_VERSION} 2.1.0.1
if [ ${comparison_result} = 2 -o ${comparison_result} = 0 ]; then
	# CFC_VERSION >= 2.1.0.1
	if [ ${development_mode} = false ]; then
		echo
		echo "ICp 2.1.0.1 integration still in development"
		exit 99
	fi
	if [ "${BOOT}" = "${MASTER_LIST}" -a "${BOOT}" = "${WORKER_LIST}" -a "${BOOT}" = "${PROXY_LIST}" ]; then
		:	# only supported deployment for 2.1.0.1 at the moment
	else
		if [ ${development_mode} = false ]; then
			echo
			echo "ICp 2.1.0.1 integration still in development - supporting only on single VM for now"
			exit 99
		fi
	fi
	if [ "${cfc_ee_url}" != "" ]; then
		if [ ${development_mode} = false ]; then
			echo
			echo "ICp 2.1.0.1 integration still in development - supporting only CE for now"
			exit 99
		fi
	fi
	if [ "${enable_management_node}" = "" ]; then
		enable_management_node=true
	fi
	if [ ${upgrade} = true ]; then
		if [ ${development_mode} = false ]; then
			echo
			echo "ICp 2.1.0.1 integration still in development - upgrade not supported yet"
			exit 99
		fi
	fi
else
	enable_management_node=false
fi

# Kibana version
compareVersions ${CFC_VERSION} 2.1.0.1
if [ ${comparison_result} = 1 ]; then
	# CFC_VERSION < 2.1.0.1
	KIBANA_VERSION=4.6.4 # This version is needed in order to work with the version of Elasticsearch that comes with ICp. If ICp update their version of ES, then we can update the Kibana version. If doing this, remove the hack of modifying the kibana.yml, as later Kibana versions support passing in env variables to superseed the values in the yml.
else
	KIBANA_VERSION=IRRELEVANT-PART-OF-ICP
	skip_kibana_deployment=true
fi

CALICOCTL_VERSION=v1.4.0

# Set the version of the installer build and image tag - Required because the 1.2.1 CE & EE installer build has the image tag ibmcom/cfc-installer:1.2.0
if [ "${cfc_ee_url}" != "" ]; then
	cfc_archive_version=${CFC_VERSION}
	compareVersions ${CFC_VERSION} 1.2.1
	set +o nounset		# reset in compareVersions
	if [ ${comparison_result} = 0 ]; then	# CFC_VERSION = 1.2.1
		cfc_image_version=1.2.0
	else
		cfc_image_version=${CFC_VERSION}
	fi
else
	compareVersions ${CFC_VERSION} 1.2.1
	set +o nounset		# reset in compareVersions
	if [ ${comparison_result} = 0 ]; then	# CFC_VERSION = 1.2.1
		cfc_archive_version=1.2.0
		cfc_image_version=1.2.0
	else
		cfc_archive_version=${CFC_VERSION}
		cfc_image_version=${CFC_VERSION}
	fi
fi

compareVersions ${CFC_VERSION} 2.1.0.1
if [ ${comparison_result} = 1 ]; then
	# CFC_VERSION < 2.1.0.1
	set +o nounset		# reset in compareVersions
	icp_image_name=cfc-installer
else
	icp_image_name=icp-inception
fi

compareVersions ${CFC_VERSION} 2.1.0.1
if [ ${comparison_result} = 0 -o ${comparison_result} = 2 ]; then
	# CFC_VERSION >= 2.1.0.1
	set +o nounset		# reset in compareVersions
	skip_disable_firewall=true
fi

# Set the namespace that all artifacts will be set up in
if [ "${set_namespace}" != "" ]; then
	if [ "${set_namespace}" = "default" ]; then
		echo "Not allowed to use namespace default. Please choose a different name"
		exit 200
	else
		NAMESPACE=${set_namespace}
	fi
else
	NAMESPACE=connections
fi

# SELinux support beginning with 1.2.1
skip_disable_selinux=true

# HA mount points starting with 1.2.1
semaphore_targets="${DOCKER_REGISTRY} ${CP_AUDIT}"

# Set installation directory
if [ "${cfc_ee_url}" != "" ]; then
	INSTALL_DIR=/opt/ibm-cloud-private-${CFC_VERSION}
else
	INSTALL_DIR=/opt/ibm-cloud-private-ce-${CFC_VERSION}
fi

# ICp paths
cfc_deployment_directory_cwd="${INSTALL_DIR}/cluster"
cfc_deployment_directory_path="${INSTALL_DIR}/cluster:/installer/cluster"

# etcd API
scheme=https
cert_arg_list="--cacert /etc/cfc/conf/etcd/ca.pem --cert /etc/cfc/conf/etcd/client.pem --key /etc/cfc/conf/etcd/client-key.pem"

# Do not support CFC_VERSION < 1.2.1
compareVersions ${CFC_VERSION} 1.2.1
set +o nounset		# reset in compareVersions
if [ ${comparison_result} = 1 ]; then	# CFC_VERSION < 1.2.1
	echo "IBM Cloud private versions prior to 1.2.1 are no longer supported"
	exit 200
fi
if [ "${CFC_VERSION}" = 2.1.0.0 ]; then
	echo "IBM Connections not tested with IBM Cloud private 2.1.0.0 and is not supported"
	exit 200
fi

# Upgrade scenario
day_to_day=false
if [ ${upgrade} = true ]; then
	deployed_cfc_version=""
	if [ -f /opt/ibm/cfc/version ]; then
		deployed_cfc_version=`cat /opt/ibm/cfc/version`
		if [ "${deployed_cfc_version}" != "" ]; then
			if [ "${cfc_ee_url}" != "" ]; then
				CURRENT_DEPLOYED_DIR=/opt/ibm-cloud-private-${deployed_cfc_version}
			else
				CURRENT_DEPLOYED_DIR=/opt/ibm-cloud-private-ce-${deployed_cfc_version}
			fi
			if [ ${CFC_VERSION} = ${deployed_cfc_version} ]; then
				day_to_day=true
			fi
		else
			echo "Can't determine deployed IBM Cloud private version"
			exit 10
		fi
	else
		echo "Can't determine deployed IBM Cloud private version. Cannot find the file /opt/ibm/cfc/version. If deploying on clean systems, don't use --upgrade argument."
		exit 10
	fi
else
	if [ DISABLE_THIS = yes -a -f /opt/ibm/cfc/version -a "${uninstall}" = "" -a ${PRG} = deployCfC.sh ]; then
		# upgrade == false && ICp installed == true && uninstall == false && normal deployment path == true
		echo
		echo "IBM Cloud private already exists and not in upgrade mode"
		echo
		exit 10
	fi
fi

if [ "${cfc_ee_url}" != "" ]; then
	cfc_image_name_suffix="-ee"
else
	cfc_image_name_suffix=""
fi

# Requires --independent_helm_install to utilize
# otherwise uses helm which is distributed with ICp
if [ "${HELM_VERSION}" = "" ]; then
	compareVersions ${CFC_VERSION} 2.1.0.1
	set +o nounset		# reset in compareVersions
	if [ ${comparison_result} = 1 ]; then	# CFC_VERSION < 2.1.0.1
		HELM_VERSION=v2.4.1
	else	# change this for later versions of ICp
		HELM_VERSION=v2.6.0
	fi
else
	echo "Overriding HELM_VERSION=${HELM_VERSION}"
fi

# Ports which must not be used - ICp 1.2.1
PORT_LIST_121="
80
179
443
2380
3306
${ETCD_PORT}
4194
4444
4567
4568
5000
5044
5046
8001
8080
8082
8084
8101
8181
8443
8500
8600
8743
8888
9200
9235
9300
18080
35357
"

# Ports which must not be used - ICp 1.2.1
K8S_PORT_RANGES_121="10248-10252 30000-32767"

# Ports which must not be used - ICp 2.1.0.1
PORT_LIST_2101="
80
179
443
2222
2380
3130
3306
${ETCD_PORT}
4194
4242
4444
4567
4568
5044
5046
6969
8001
8080
8082
8084
8101
8181
8443
8500
8600
8743
8888
9099
9100
9200
9235
9300
9443
18080
24007
24008
31030
31031
"

# Ports which must not be used - ICp 2.1.0.1
K8S_PORT_RANGES_2101="10248-10252 30000-32767 49152-49251"

# Essential port check list
ESSENTIAL_PORT_CHECK_LIST="
8001
8443
8500
"

# Ports to open in firewall for --configure_firewall option
FIREWALL_PORT_LIST="
${ETCD_PORT}
${ESSENTIAL_PORT_CHECK_LIST}
"

if [ "${ext_proxy_url}" != "" ]; then
	set +o nounset
	if [ -n "${http_proxy}" ] || [ -n "${https_proxy}" ] || [ -n "${ftp_proxy}" ] || [ -n "${no_proxy}" ]; then # Check for non-null/non-zero string variables
		echo "WARNING: Found one or more external proxy environment variable(s) are already set:"
		echo "http_proxy=${http_proxy}"
		echo "https_proxy=${https_proxy}"
		echo "ftp_proxy=${ftp_proxy}"
		echo "no_proxy=${no_proxy}"
		echo "This may cause unforeseen circumstances during the install."
	fi
	set -o nounset
fi

if [ "${temporary_file_location}" != "" ]; then
	compareVersions ${CFC_VERSION} 2.1.0.1
	set +o nounset		# reset in compareVersions
	if [ ${comparison_result} = 1 ]; then	# CFC_VERSION < 2.1.0.1
		echo "--temporary_file_location flag supported for ICp 2.1.0.1 and later"
		exit 65
	fi
	set +o errexit
	TMP=`mktemp "${temporary_file_location}/${PRG}.${DATE}.${RANDOM}.XXXXXX.$$"` && \
		date > "${TMP}" && \
		rm ${TMP}
	if [ $? -ne 0 ]; then
		echo "${temporary_file_location} is not a valid location for temporary files"
		exit 99
	fi
	set -o errexit

	ansible_temp_location_args="-e ANSIBLE_REMOTE_TEMP=${temporary_file_location}"
else
	ansible_temp_location_args=""
fi

compareVersions ${CFC_VERSION} 2.1.0.1
set +o nounset		# reset in compareVersions
if [ ${comparison_result} = 1 ]; then	# CFC_VERSION < 2.1.0.1
	PORT_LIST="${PORT_LIST_121}"
	K8S_PORT_RANGES="${K8S_PORT_RANGES_121}"
else	# change this for later versions of ICp
	PORT_LIST="${PORT_LIST_2101}"
	K8S_PORT_RANGES="${K8S_PORT_RANGES_2101}"
fi

YUM_INSTALL_DOCKER_OVERRIDE_FLAGS=""
YUM_INSTALL_DOCKER_OVERRIDE_FLAGS_OBSOLETE="--setopt=obsoletes=0" # issue 4486
YUM_UNINSTALL_DOCKER_OVERRIDE_FLAGS=""
YUM_UNINSTALL_DOCKER_OVERRIDE_FLAGS_OBSOLETE="--setopt=clean_requirements_on_remove=1"

if [ "${alt_docker_version}" = "" ]; then
	compareVersions ${CFC_VERSION} 2.1.0.1
	set +o nounset          # reset in compareVersions
	if [ ${comparison_result} = 0 -o ${comparison_result} = 2 ]; then
		# CFC_VERSION >= 2.1.0.1
		DOCKER_VERSION="17.06"
	else
		DOCKER_VERSION="17.03"
	fi
else
	DOCKER_VERSION="${alt_docker_version}"
	echo "Overriding DOCKER_VERSION=${DOCKER_VERSION}"
fi

set +o errexit
# special arguments for 17.03 because docker-ce-selinux from the Docker repo
# is obsoleted by container-selinux from the RHEL extras repo
echo ${DOCKER_VERSION} | grep -q '^17\.03'
if [ $? -eq 0 ]; then
	YUM_INSTALL_DOCKER_OVERRIDE_FLAGS="${YUM_INSTALL_DOCKER_OVERRIDE_FLAGS_OBSOLETE}"
	YUM_UNINSTALL_DOCKER_OVERRIDE_FLAGS="${YUM_UNINSTALL_DOCKER_OVERRIDE_FLAGS_OBSOLETE}"
fi
set -o errexit

if [ "${PIP_VERSION}" = "" ]; then
	PIP_VERSION="1.7.0"
else
	echo "Overriding PIP_VERSION=${PIP_VERSION}"
fi

if [ "${KUBECTL_VERSION}" = "" ]; then
	#KUBECTL_VERSION=`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`
	compareVersions ${CFC_VERSION} 2.1.0.1
	set +o nounset		# reset in compareVersions
	if [ ${comparison_result} = 1 ]; then	# CFC_VERSION < 2.1.0.1
		KUBECTL_VERSION="v1.7.0"
	else	# change this for later versions of ICp
		KUBECTL_VERSION="v1.8.3"
	fi
else
	echo "Overriding KUBECTL_VERSION=${KUBECTL_VERSION}"
fi

# Default admin credentials
if [ "${ADMIN_USER}" = "" ]; then
	ADMIN_USER=admin
else
	echo "Overriding ADMIN_USER=${ADMIN_USER}"
fi
if [ "${ADMIN_PASSWD}" = "" ]; then
	ADMIN_PASSWD=admin
else
	echo "Overriding ADMIN_PASSWD=${ADMIN_PASSWD}"
fi

if [ "${YUM}" = "" ]; then
	YUM=yum
else
	echo "Overriding YUM=${YUM}"
fi
set -o nounset

# Credential and SSH rules
if [ "${root_login_passwd}" != "" -a "${non_root_user}" != "" ]; then
	echo "Arguments --root_login_passwd and --non_root_user arguments are mutually exclusive"
	exit 26
fi
if [ "${non_root_passwd}" != "" -a "${non_root_user}" = "" ]; then
	echo "Arguments --non_root_passwd requires the --non_root_user argument"
	exit 27
fi
if [ ${skip_ssh_prompts} = true ]; then
	if [ "${root_login_passwd}" = "" -a "${non_root_passwd}" = "" ]; then
		echo "--skip_ssh_prompts requires the --root_login_passwd or --non_root_passwd arguments"
		exit 7
	fi
else
	if [ "${root_login_passwd}" != "" ]; then
		echo "--root_login_passwd requires the --skip_ssh_prompts argument"
		exit 28
	fi
	if [ "${non_root_passwd}" != "" ]; then
		echo "--non_root_passwd requires the --skip_ssh_prompts argument"
		exit 29
	fi
fi
if [ "${root_login_passwd}" != "" ]; then
	user=root
	user_passwd="${root_login_passwd}"
elif [ "${non_root_user}" != "" ]; then
	user=${non_root_user}
	if [ "${non_root_passwd}" != "" ]; then
		user_passwd="${non_root_passwd}"
	else
		user_passwd=""
	fi
else
	user=root
	user_passwd=""
fi

if [ "${alt_cfc_docker_stream}" != "" ]; then
	if [ "${alt_cfc_docker_stream}" != daily -a "${alt_cfc_docker_stream}" != stable ]; then
		echo "${USAGE}"
		echo
		echo "--alt_cfc_docker_stream must be set to daily or stable"
		echo
		exit 14
	fi
fi

if [ "${alt_cfc_docker_registry}" != "" ]; then
	docker_registry="${alt_cfc_docker_registry}/"
else
	docker_registry=""
fi
if [ "${alt_cfc_docker_stream}" != "" ]; then
	docker_stream="${alt_cfc_docker_stream}"
	docker_prod_args=""
else
	docker_stream=ibmcom
	docker_prod_args="--net=host -t"
fi
if [ ${debug} = true ]; then
	cfc_debug1="-e ANSIBLE_CALLBACK_WHITELIST=profile_tasks,timer"
	cfc_debug2="-vvv"
else
	cfc_debug1=""
	cfc_debug2=""
fi

# Verify boot, master, worker, or proxy are defined
if [ ${PRG} != package.sh -a ${PRG} != collectLogs.sh -a ${PRG} != deployUpdates.sh -a ${PRG} != deploySubUpdate.sh ]; then
	if [ "${BOOT}" = "" -o "${MASTER_LIST}" = "" -o "${WORKER_LIST}" = "" -o "${PROXY_LIST}" = "" ]; then
		echo "Missing boot, master_list, worker_list, or proxy_list definitions"
		echo "BOOT = ${BOOT}"
		echo "MASTER_LIST = ${MASTER_LIST}"
		echo "WORKER_LIST = ${WORKER_LIST}"
		echo "PROXY_LIST = ${PROXY_LIST}"
		exit 5
	fi
fi

check_worker=""
if [ "${remove_worker}" != "" ]; then
	check_worker="${remove_worker}"
fi
if [ "${add_worker}" != "" ]; then
	check_worker="${add_worker}"
fi
if [ "${check_worker}" != "" ]; then
	found_worker=false
	for host in ${WORKER_LIST}; do
		for worker in ${check_worker}; do
			if [ ${host} = ${worker} ]; then
				found_worker=true
			fi
		done
	done
	if [ ${found_worker} = false ]; then
		echo
		echo "Can't find ${check_worker} in worker list:"
		echo
		echo "	${WORKER_LIST}"
		echo
		echo "When adding or removing a generic or infrastructure worker, that worker node must be in the generic or infrastructure worker list"
		echo
		exit 10
	fi
fi

# Determine high availability and validate input
is_master_HA=false
num_master=`echo ${MASTER_LIST} | wc -w`
if [ ${num_master} -gt 1 -o "${master_HA_vip}" != "" -o "${master_HA_iface}" != "" ]; then
	if [ ${num_master} -ne 3 -a ${num_master} -ne 5 ]; then
		echo
		echo "master node high availability topology requires 3 or 5 nodes"
		exit 24
	fi
	is_master_HA=true
	if [ "${master_HA_iface}" = "" -o "${master_HA_vip}" = "" ]; then
		echo
		echo "--master_HA_iface and --master_HA_vip are mandatory arguments for master node high availability topology"
		exit 20
	fi
	set +o errexit
	is_ipv4 ${master_HA_vip}
	if [ $? -ne 0 ]; then
		echo
		echo "--master_HA_vip must specify an IPv4 address"
		exit 22
	fi
	set -o errexit
fi
is_proxy_HA=false
num_proxy=`echo ${PROXY_LIST} | wc -w`
if [ ${num_proxy} -gt 1 -o "${proxy_HA_vip}" != "" -o "${proxy_HA_iface}" != "" ]; then
	compareVersions ${CFC_VERSION} 2.1.0.1
	if [ ${comparison_result} = 1 ]; then	# CFC_VERSION < 2.1.0.1
		if [ ${num_proxy} -ne 3 -a ${num_proxy} -ne 5 ]; then
			echo
			echo "proxy high availability mode requires 3 or 5 nodes"
			exit 25
		fi
	else
		:	# for ICp 2.1.0.1 and later, can be 2 or more, no fixed number
	fi
	is_proxy_HA=true
	if [ "${proxy_HA_iface}" = "" -o "${proxy_HA_vip}" = "" ]; then
		echo "--proxy_HA_iface and --proxy_HA_vip are mandatory arguments for proxy high availability topology"
		exit 21
	fi
	set +o errexit
	is_ipv4 ${proxy_HA_vip}
	if [ $? -ne 0 ]; then
		echo "--proxy_HA_vip must specify an IPv4 address"
		exit 23
	fi
	set -o errexit
fi

if [ ${is_master_HA} = true -a ${is_proxy_HA} = false ] || [ ${is_proxy_HA} = true -a ${is_master_HA} = false ]; then
	echo "High availability mode required for both master and proxy"
	exit 60
fi

if [ ${is_master_HA} = true -o ${is_proxy_HA} = true ]; then
	if [ "${cfc_ee_url}" = "" ]; then
		echo "High Availability for ${CFC_VERSION} requires IBM Cloud private Enterprise Edition"
		exit 60
	fi
	if [ "${docker_storage_block_device}" = "" ]; then
		if [ ${skip_docker_deployment} = false ]; then
			echo "High Availability for ${CFC_VERSION} requires Docker storage block device"
			exit 60
		fi
	fi
else
	if [ "${master_HA_mount_registry}" != "" -o "${master_HA_mount_audit}" != "" ]; then
		echo "master HA NFS mounts only needed for HA"
		exit 60
	fi
fi

# Reset docker_storage_block_device=ignore to docker_storage_block_device=""
# so all subsequent logic based on docker_storage_block_device="" works.
# This reset must be after the HA check above.
if [ "${docker_storage_block_device}" = ignore ]; then
	docker_storage_block_device=""
fi
if [ ${skip_docker_deployment} = true ]; then
	checkDockerDeviceMapper
	if [ $? -ne 0 ]; then
		echo "Please configure Docker with devicemapper storage before proceeding."
		exit 60
	fi
	set -o errexit

	checkDockerLoggingDriver
	if [ $? -ne 0 ]; then
		echo "Please configure Docker Logging Driver to json-file before proceeding."
		exit 60
	fi
	set -o errexit
fi

# Consolidate the list of VMs and remove duplicates
HOST_LIST=""
set +o errexit
set +o nounset
for host in ${BOOT} ${MASTER_LIST} ${WORKER_LIST} ${PROXY_LIST}; do
	echo ${HOST_LIST} | grep -q "${host}"
	if [ $? -eq 1 ]; then
		HOST_LIST="${HOST_LIST} ${host}"
	fi
done
set -o nounset

# Deployment script non-entry points must run as root
echo ${HOST_LIST} | grep -q ${HOSTNAME}
if [ $? -eq 0 ]; then
	if [ ${PRG} != deployCfC.sh -a ${PRG} != validateDeployment.sh ]; then
		if [ "`id -u`" != 0 ]; then
			echo "Must be root to run - use su, sudo, or login as root before executing"
			exit 4
		fi
	fi
fi

is_boot=false
if [ ${HOSTNAME} = "${BOOT}" ]; then
	is_boot=true
fi

is_master=false
for host in ${MASTER_LIST}; do
	if [ ${HOSTNAME} = ${host} ]; then
		is_master=true
	fi
done

is_proxy=false
for host in ${PROXY_LIST}; do
	if [ ${HOSTNAME} = ${host} ]; then
		is_proxy=true
	fi
done

is_worker=false
for host in ${WORKER_LIST}; do
	if [ ${HOSTNAME} = ${host} ]; then
		is_worker=true
	fi
done

# Determine whether to run script on node based on its role
echo ${PRG} | grep -q '^[A-Z]-[0-9]'
if [ $? -eq 0 ]; then		# not deployCfC.sh, etc
	node_type=`echo ${PRG} | awk -F- '{ print $3 }'`
	if [ ${node_type} = all ]; then
		check_list="${HOST_LIST}"
	elif [ ${node_type} = boot ]; then
		check_list=${BOOT}
	elif [ ${node_type} = master ]; then
		check_list=${MASTER_LIST}
	elif [ ${node_type} = worker ]; then
		check_list=${WORKER_LIST}
	elif [ ${node_type} = proxy ]; then
		check_list=${PROXY_LIST}
	else
		echo "Unknown node type"
		exit 2
	fi

	echo
	if ${is_boot}; then
		echo "--- My node type is:  boot (${HOSTNAME})"
	fi
	if ${is_master}; then
		echo "--- My node type is:  master (${HOSTNAME})"
	fi
	if ${is_proxy}; then
		echo "--- My node type is:  proxy (${HOSTNAME})"
	fi
	if ${is_worker}; then
		echo "--- My node type is:  worker (${HOSTNAME})"
	fi

	run_here=false
	for host in ${check_list}; do
		if [ ${HOSTNAME} = ${host} ]; then
			run_here=true
		fi
	done

	echo
	if [ ${run_here} = true ]; then
		echo "--- Running $0 on node type ${node_type} (${HOSTNAME})"
	else
		echo "--- Not running $0, requires node type ${node_type} (${HOSTNAME})"
		exit 0
	fi
	echo "--- Topology:"
	echo "---	boot node: ${BOOT}"
	echo "---	master nodes: `echo ${MASTER_LIST} | sed 's/ /, /g'`"
	echo "---	worker nodes: `echo ${WORKER_LIST} | sed 's/ /, /g'`"
	echo "---	proxy nodes: `echo ${PROXY_LIST} | sed 's/ /, /g'`"
fi

# boot co-location with master required
co_location=false
for master in ${MASTER_LIST}; do
	if [ ${BOOT} = ${master} ]; then
		co_location=true
	fi
done
if [ ${co_location} = false ]; then
	set +o errexit
	echo ${PRG} | egrep -q '^collectLogs.sh$'
	exit_status=$?
	set -o errexit
	if [ ${exit_status} -eq 1 ]; then
		echo
		echo "boot node co-location with a master node required"
		exit 40
	fi
fi

# DO NOT CALL THIS FUNCTION DIRECTLY
function _sshpass_command() {
	set +o errexit
	set -o pipefail
	set +o nounset

	USAGE="
usage modes (just like scp and ssh):
	_sshpass_command scp source(s) destination
	_sshpass_command ssh node command(s)
"

	if [ "$3" = "" ]; then
		echo "${USAGE}"
		exit 110
	fi
	set -o nounset
	if [ "$1" = ssh ]; then
		type=ssh
		shift
		target_host=`echo $1 | sed 's/.*@//'`
		shift
		target_args="$*"
	elif [ "$1" = scp ]; then
		if [ $# -gt 3 ]; then
			echo "Bug in scp scripting, only one source allowed in copy"
			exit 130
		fi

		type=scp
		shift
		target_location=`echo $* | awk '{ print $NF }'`
		target_host=`echo ${target_location} | awk -F: '{ print $1 }' | sed 's/.*@//'`
		target_directory=`echo ${target_location} | awk -F: '{ print $2 }'`
		set -- "${@:1:$(($#-1))}"
		source_args="$*"

		echo ${source_args} | grep -q '^/'
		if [ $? -ne 0 ]; then
			echo "Source must be absolute path"
			exit 130
		fi
		echo ${target_directory} | grep -q '^/'
		if [ $? -ne 0 ]; then
			echo "Target directory must be absolute path"
			exit 130
		fi

		source_directory=`dirname ${source_args}`
		source_item=`basename ${source_args}`
	else
		echo "${USAGE}"
		exit 111
	fi

	if [ "${target_host}" = "" ]; then
		echo "Parsing error"
		exit 111
	fi
	if [ ${target_host} = ${HOSTNAME} ]; then
		# Note:  could just run the commands locally,
		# but I want to detect when this situation is happening
		echo "Should not ssh to self"
		return 113
	fi

	if [ ${debug} = true ]; then
		exec_debug_flags="set -o xtrace; "
	else
		exec_debug_flags=""
	fi

	exit_status=0
	if [ "${user_passwd}" != "" ]; then
		if [ ${user} != root ]; then
			if [ ${type} = ssh ]; then
				# ensure unique
				TMP=`mktemp ${TMP_TEMPLATE}` && \
				chmod 700 ${TMP} && \
				echo 'set -o errexit; set -o pipefail; set -o nounset' > ${TMP} && \
				echo "${exec_debug_flags}${target_args}" >> ${TMP} && \
				scp_command ${TMP} ${target_host}:/tmp && \
				HOME=`eval echo ~${user}` ${setuid_bin} ${user} ${sshpass_bin} -p ${user_passwd} ssh ${ssh_args} -C ${target_host} sudo -n /bin/bash ${DEPLOY_CFC_DIR}/H-02-all-remote-exec.sh ${TMP} && \
				rm -f ${TMP}
				exit_status=$?
			else
				tar -C ${source_directory} -cBf - ${source_item} | HOME=`eval echo ~${user}` ${setuid_bin} ${user} ${sshpass_bin} -p ${user_passwd} ssh ${ssh_args} -C ${target_host} sudo -n tar -C ${target_directory} -xpBf -

				exit_status=$?
			fi
		else
			if [ ${type} = ssh ]; then
				sshpass -p ${user_passwd} ssh ${ssh_args} -C ${target_host} ${target_args}
				exit_status=$?
			else
				sshpass -p ${user_passwd} scp ${ssh_args} -Cpr ${source_args} ${target_location}
				exit_status=$?
			fi
		fi

		if [ ${exit_status} -eq 0 ]; then
			return 0
		elif [ ${exit_status} -eq 5 ]; then
			echo "Provided ${user} password did not work"
			echo "Retrying with SSH keys which may not work if this step was not completed"
		else
			if [ ${debug} = true ]; then
				if [ "${user_passwd}" != "" ]; then
					echo "${type} ${user} +password failed (1) ${exit_status}"
				else
					echo "${type} ${user} -password failed (1) ${exit_status}"
				fi
			fi
			exit ${exit_status}
		fi
	fi
	if [ "${user_passwd}" = "" -o ${exit_status} -eq 5 ]; then
		if [ ! -f ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}/id_rsa -a "${uninstall}" != "" ]; then
			keys=""
		else
			keys="-i ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}/id_rsa"
			if [ ! -f ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}/id_rsa ]; then
				if [ "${pregenerated_private_key_file}" != "" -a -f "${pregenerated_private_key_file}" ]; then
					keys="-i ${pregenerated_private_key_file}"
				fi
			fi
		fi
		if [ ${user} != root ]; then
			if [ ${type} = ssh ]; then
				# ensure unique
				TMP=`mktemp ${TMP_TEMPLATE}` && \
				chmod 700 ${TMP} && \
				echo 'set -o errexit; set -o pipefail; set -o nounset' > ${TMP} && \
				echo "${exec_debug_flags}${target_args}" >> ${TMP} && \
				scp_command ${TMP} ${target_host}:/tmp && \
				HOME=`eval echo ~${user}` ${setuid_bin} ${user} ssh ${ssh_args} ${keys} -C ${target_host} sudo -n /bin/bash ${DEPLOY_CFC_DIR}/H-02-all-remote-exec.sh ${TMP} && \
				rm -f ${TMP}
				exit_status=$?
			else
				tar -C ${source_directory} -cBf - ${source_item} | HOME=`eval echo ~${user}` ${setuid_bin} ${user} ssh ${ssh_args} ${keys} -C ${target_host} sudo -n tar -C ${target_directory} -xpBf -
				exit_status=$?
			fi
		else
			if [ ${type} = ssh ]; then
				ssh ${ssh_args} ${keys} -C ${target_host} ${target_args}
				exit_status=$?
			else
				scp ${ssh_args} ${keys} -Cpr ${source_args} ${target_location}
				exit_status=$?
			fi
		fi
		if [ ${exit_status} -eq 0 ]; then
			return 0
		fi
	fi
	if [ ${debug} = true ]; then
		if [ "${user_passwd}" != "" ]; then
			echo "${type} ${user} +password failed (2) ${exit_status}"
		else
			echo "${type} ${user} -password failed (2) ${exit_status}"
		fi
	fi
	exit 112
}


# function resets errexit to ignore so calling script must reset if desired
function ssh_command() {
	set +o errexit
	set -o pipefail
	set +o nounset

	if [ "$2" = "" ]; then
		echo "usage:  ssh_command node command(s)"
		exit 120
	fi
	set -o nounset

	_sshpass_command ssh $*
	if [ $? -ne 0 ]; then
		return 121
	fi
}


# function resets errexit to ignore so calling script must reset if desired
function scp_command() {
	set +o errexit
	set -o pipefail
	set +o nounset

	if [ "$2" = "" ]; then
		echo "usage:  scp_command source destination"
		exit 130
	fi
	set -o nounset

	_sshpass_command scp $*
	if [ $? -ne 0 ]; then
		return 131
	fi
}


# diagnostics and dump of JSON when things go wrong
function dumpJSON() {
	set -o errexit
	set -o pipefail
	set -o nounset

	set +o nounset
	if [ "$4" = "" ]; then
		echo "usage:  dumpJSON nExitStatus nHTTPResponseCode sHTTPBodyFile sMessage"
		exit 100
	fi
	set -o nounset
	exit_status=$1
	http_response=$2
	http_body_file=$3
	message="$4"

	echo "${message} - (${exit_status} : ${http_response})"
	echo
	set +o errexit
	python -mjson.tool ${http_body_file}
	if [ $? -ne 0 ]; then
		cat ${http_body_file}
	fi
	set -o errexit
}


# set a semaphore and indicate whether it is a create or update
# returns state in semaphore_init as true or false
# where true means create and false means update
function setSemaphore() {
	set -o errexit
	set -o pipefail
	set -o nounset

	set +o nounset
	if [ "$1" = "" ]; then
		echo "usage:  setSemaphore sSemaphoreName"
		exit 145
	fi
	set -o nounset
	semaphore=$1

	TMP=`mktemp ${TMP_TEMPLATE}`		# ensure unique

	set +o errexit
	semaphore_init=undefined
	echo "Checking semaphore ${semaphore}"
	http_response=`curl -sL -w '%{http_code}' -o ${TMP} ${cert_arg_list} ${scheme}://master.cfc:${ETCD_PORT}/v2/keys/${semaphore} -XPUT -d value="${HOSTNAME}"`
	exit_status=$?
	set -o errexit
	if [ ${debug} = true ]; then
		dumpJSON ${exit_status} ${http_response} ${TMP} "Diagnostic for setting ${semaphore}"
	fi
	if [ ${exit_status} != 0 -o \( "${http_response}" != 200 -a "${http_response}" != 201 \) -o "`jq -r .node.value ${TMP}`" != ${HOSTNAME} ]; then
		dumpJSON ${exit_status} ${http_response} ${TMP} "Error setting semaphore ${semaphore}"
		rm -f ${TMP}
		exit 140
	fi
	if [ ${http_response} = 201 ]; then	# Created
		if [ `jq -r .prevNode.value ${TMP}` = null ]; then
			semaphore_init=true
			echo "Created semaphore ${semaphore}"
		else
			dumpJSON ${exit_status} ${http_response} ${TMP} "Create and update conflict"
			rm -f ${TMP}
			exit 141
		fi
	elif [ ${http_response} = 200 ]; then	# OK (update)
		if [ `jq -r .prevNode.value ${TMP}` = null ]; then
			dumpJSON ${exit_status} ${http_response} ${TMP} "Update with create conflict"
			rm -f ${TMP}
			exit 142
		else
			semaphore_init=false
			echo "Updated semaphore ${semaphore}"
		fi
	else
		dumpJSON ${exit_status} ${http_response} ${TMP} "Unknown"
		rm -f ${TMP}
		exit 143
	fi
	if [ ${semaphore_init} != true -a ${semaphore_init} != false ]; then
		dumpJSON ${exit_status} ${http_response} ${TMP} "Unknown semaphore error condition"
		rm -f ${TMP}
		exit 144
	fi
	rm -f ${TMP}
}


function deleteSemaphore() {
	set -o errexit
	set -o pipefail
	set -o nounset

	TMP=`mktemp ${TMP_TEMPLATE}`		# ensure unique

	set +o nounset
	if [ "$1" = "" ]; then
		echo "usage:  deleteSemaphore sSemaphoreName"
		exit 101
	fi
	set -o nounset
	semaphore=$1

	echo "Deleting semaphore ${semaphore}"
	set +o errexit
	http_response=`curl -sL -w '%{http_code}' -o ${TMP} ${cert_arg_list} ${scheme}://master.cfc:${ETCD_PORT}/v2/keys/${semaphore} -XDELETE`
	exit_status=$?
	set -o errexit
	if [ ${debug} = true ]; then
		dumpJSON ${exit_status} ${http_response} ${TMP} "Diagnostic for deleting ${semaphore}"
	fi
	if [ ${exit_status} != 0 -o ${http_response} != 200 ]; then
		dumpJSON ${exit_status} ${http_response} ${TMP} "Error deleting semaphore ${semaphore}"
		rm -f ${TMP}
	else
		echo "Deleted semaphore ${semaphore}"
	fi
	rm -f ${TMP}
}


# returns 0 or non-0 for success and failure, respectively
function validateSSHKey () {
	set -o errexit
	set -o pipefail
	set -o nounset

	set +o nounset
	if [ "$1" = "" ]; then
		echo "usage:  validateSSHKey sNodeHostname"
		exit 101
	fi
	set -o nounset
	node=$1

	set +o errexit
	resolve_ip ${node}	# result in resolve_ip_return_result
	if [ $? -ne 0 ]; then
		echo "Unable to resolve ${node}"
		return 112
	else
		ip=${resolve_ip_return_result}
	fi

	echo "Validating SSH key setup for ${user}@${node} (${ip})"
	if [ ${user} != root ]; then
		HOME=`eval echo ~${user}` ${setuid_bin} ${user} ssh ${ssh_args} -i ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}/id_rsa ${ip} "echo Success"
	else
		ssh ${ssh_args} -i ${SSH_KEY_DEPLOYMENT_LOCATION_BOOT}/id_rsa ${ip} "echo Success"
	fi
	set -o errexit
	return $?
}


# returns 0 or non-0 for success and failure, respectively
function validateSSHKeys () {
	set -o errexit
	set -o pipefail
	set -o nounset

	set +o nounset
	if [ "$1" = "" ]; then
		echo "usage:  validateSSHKeys sNode1 Node2 ... Node3"
		exit 101
	fi
	set -o nounset

	echo
	set +o errexit
	ssh_key_failure=false
	for node in $*; do
		validateSSHKey ${node}
		exit_status=$?
		if [ ${exit_status} -ne 0 ]; then
			echo "FAILED to validate SSH keys for ${node} - (${exit_status})"
			ssh_key_failure=true
		fi
	done
	set -o errexit
	if [ ${ssh_key_failure} = true ]; then
		return 111
	else
		return 0
	fi
}


# function resets errexit to ignore so calling script must reset if desired
function uninstallKibana () {
	set +o errexit

	if [ ${skip_kibana_deployment} = true ]; then
		echo "Not uninstalling Kibana"
	else
		if [ ${HOSTNAME} != ${BOOT} ]; then
			echo "Kibana only deployed on first master node"
		else
			if [ ! -x /usr/bin/docker ]; then
				echo "Docker not installed so skipping Kibana uninstall"
			else
				echo "Shutting down Kibana before re-installing"
				docker stop kibana
				sleep 5
				docker kill kibana
				echo "OK if kill container is an error"
				sleep 5
				docker rm -f kibana
				echo "OK if Device is Busy error"
			fi
		fi
	fi
}


# function resets errexit to ignore so calling script must reset if desired
# returns 0 or non-0 for success and failure, respectively
function pullFromDocker () {
	set -o errexit
	set -o pipefail
	set -o nounset

	NUMBER_RETRIES_DEFAULT=3
	RETRY_WAIT_TIME_DEFAULT=30

	set +o nounset
	if [ "$1" = "" ]; then
		echo "usage:  pullFromDocker s[Registry]Component:Version [nNumberRetries=${NUMBER_RETRIES_DEFAULT}] [nRetryWaitTimeSeconds=${RETRY_WAIT_TIME_DEFAULT}]"
		echo
		echo "example:	pullfromDocker kibana:${KIBANA_VERSION}"
		echo "example:	pullfromDocker kibana:${KIBANA_VERSION} 3 3"
		return 4
	fi
	component=$1
	if [ "$2" = "" ]; then
		number_retries=${NUMBER_RETRIES_DEFAULT}
	else
		number_retries=$2
		isNum ${number_retries}
		if [ ${is_number} = false ]; then
			echo "Not a number:  ${number_retries}"
			set +o errexit
			return 2
		fi
	fi
	if [ "$3" = "" ]; then
		retry_wait_time=${RETRY_WAIT_TIME_DEFAULT}
	else
		retry_wait_time=$3
		isNum ${retry_wait_time}
		if [ ${is_number} = false ]; then
			echo "Not a number:  ${retry_wait_time}"
			set +o errexit
			return 3
		fi
	fi
	set -o nounset

	echo "Number of retries:  ${number_retries}"
	echo "Retry wait time:  ${retry_wait_time}s"
	counter=1
	set +o errexit
	while [ ${counter} -le ${number_retries} ]; do
		echo "Pulling image:  ${component}"
		docker pull ${component}
		if [ $? -ne 0 ]; then
			echo "  failed to pull image, retrying in ${retry_wait_time}s"
			sleep ${retry_wait_time}
			counter=`expr ${counter} + 1`
		else
			break
		fi
	done
	if [ ${counter} -gt ${number_retries} ]; then
		echo "Maximum attempts reached, giving up"
		return 1
	else
		return 0
	fi
}


function download_ICp_EE () {
	set -o errexit
	set -o pipefail
	set -o nounset

	# List of required fies
	compareVersions ${CFC_VERSION} 2.1.0.1
	if [ ${comparison_result} = 1 ]; then
		# CFC_VERSION < 2.1.0.1
		required_files=( "ibm-cloud-private-installer-${cfc_archive_version}.tar.gz" "ibm-cloud-private-x86_64-${cfc_archive_version}.tar.gz" )
	else
		required_files=( "ibm-cloud-private-x86_64-${cfc_archive_version}.tar.gz" )
	fi

	echo
	# Check if ${cfc_ee_url} is a URL
	if echo "${cfc_ee_url}" | egrep -q 'http.*://|ftp://'; then
		echo "Detected that the cfc_ee_url flag ${cfc_ee_url} is a URL"
		input_type=url

		# Download the required files
		echo
		echo "Downloading images"
		for i in "${required_files[@]}"; do
			wget -nv -P ${TMP} ${cfc_ee_url}/$i
		done

	else	# Assuming ${cfc_ee_url} is a local directory and not a URL
		echo "Detected that the cfc_ee_url flag ${cfc_ee_url} is a local directory"
		input_type=local
	fi

	echo
	echo "Preparing Cloud private ${CFC_VERSION} EE for loading into Docker"
	mkdir -p ${INSTALL_DIR}/cluster/images
	rm -f ${INSTALL_DIR}/cluster/images/ibm-cloud-private-x86_64-${cfc_archive_version}.tar.gz
	if [ ${input_type} == "url" ]; then
		mv ${TMP}/ibm-cloud-private-x86_64-${cfc_archive_version}.tar.gz ${INSTALL_DIR}/cluster/images/
	else
		cp ${cfc_ee_url}/ibm-cloud-private-x86_64-${cfc_archive_version}.tar.gz ${INSTALL_DIR}/cluster/images/
	fi
	echo "Finished extraction from ${cfc_ee_url}"
}


# exits non-0 on failure
function verifyOperationalServer() {
	echo
	echo "Verifying server is operational"
	port_list="${ESSENTIAL_PORT_CHECK_LIST}"
	if [ ${is_master} = true ]; then
		host_check_list="localhost master.cfc"
	else
		host_check_list="master.cfc"
	fi

	for host in ${host_check_list}; do
		for port in ${port_list}; do
			check_port ${host} ${port} true
			if [ $? -ne 0 ]; then
				exit 2
			fi
		done
	done
}


# function resets errexit to non-ignore so calling script must reset if desired
function modifyJSON () {
	set -o errexit
	set -o pipefail
	set -o nounset

	set +o nounset
	if [ "$1" = "" ]; then
		echo "usage:  modifyJSON sFile key value"
		exit 101
	fi
	file="$1"
	key="$2"
	value="$3"
	set -o nounset

	TMP=`mktemp ${TMP_TEMPLATE}`		# ensure unique
	if [ ! -f ${file} ]; then
		echo
		echo "Can't find JSON file ${file}"
		exit 188
	fi
	if [ ! -f ${file}.${DATE} ]; then
		echo
		echo "Backing up ${file}"
		cp -p ${file} ${file}.${DATE}
	fi
	set -o errexit
	${jq_bin} ".${key} = ${value}" ${file} > ${TMP}
	echo
	echo "Checking changes on ${file}"
	set +o errexit
	diff ${file}.${DATE} ${TMP}
	set -o errexit
	mv ${TMP} ${file}
	chmod 644 ${file}
	set -o errexit
}


# function resets errexit to non-ignore so calling script must reset if desired
# returns 0 or non-0 for success and failure, respectively
function runDockerHelloWorldTest () {
	set +o errexit
	set -o pipefail
	set -o nounset

	number_retries=3
	retry_wait_time=30
	counter=1
	while [ ${counter} -le ${number_retries} ]; do
		docker run hello-world
		if [ $? -ne 0 ]; then
			if [ ${counter} -eq ${number_retries} ]; then
				echo "	FAILED"
			else
				echo "	FAILED, retrying in ${retry_wait_time}s"
				sleep ${retry_wait_time}
			fi
			counter=`expr ${counter} + 1`
		else
			echo "	OK"
			return 0
		fi
	done
	echo "Maximum attempts reached, giving up"
	return 1
}


# function resets errexit to ignore so calling script must reset if desired
# returns 0 or non-0 for success and failure, respectively
function doSomethingFunctionTemplate () {
	set +o errexit
	set -o pipefail
	set -o nounset

	set +o nounset
	if [ "$1" = "" ]; then
		echo "usage:  doSomethingFunctionTemplate sArg1"
		exit 101
	fi
	arg1=$1
	set -o nounset

	if true; then
		return 0
	else
		return 1
	fi
}


set -o errexit
set -o pipefail
set -o nounset

if [ ${debug} = true ]; then
	set -o xtrace
fi

