#!/bin/bash

# Script designed to work with the following Jenkins job: https://ics-connect-jenkins.swg-devops.com/view/Private%20Cloud/job/Component%20Pack/job/Configure-Blue/

set -o errexit
#set -o xtrace

# Uncomment this section and fill in the values to run this script manually
# FTP3USER=
# FTP3PASS=
# master=
# connections_dmgr=
# ic_ssh_user=
# ic_ssh_password=
# ic_admin_username=
# ic_admin_password=
# wasPath=
# http_server=			# FQHN
# http_server_path=
# configure_om=			# true or false
# configureRedis=		# true or false
# migrate_people=		# true or false
# configure_es_metrics=		# true or false
# migrate_metric_data=		# true or flase
# configure_es_typeahead=	# true or false

function configure_ihs_om {

	http_server_path=$1
	master=$2
	protocol=http://	# TODO support https enviornments where http is blocked
	DATE=`date +%Y%m%d%H%M%S`

	# Make sure HTTP server is started
	echo
	echo "Ensuring HTTP server is started.."
	${http_server_path}/bin/envvars-std
	${http_server_path}/bin/apachectl start

	# Backup httpd.conf
	echo
	echo "Making a backup of httpd.conf"
	sudo rm -rf ${http_server_path}/conf/httpd.conf.*
	sudo cp ${http_server_path}/conf/httpd.conf ${http_server_path}/conf/httpd.conf.${DATE}

	# Setting up ProxyPass and ProxyPassReverse configuration
	changes=()
	changeSize=0
	echo
	echo "Setting up ProxyPass and ProxyPassReverse configuration in httpd.conf"
	sudo sed -i '/#ProxyPreserveHost On/s/#//g' ${http_server_path}/conf/httpd.conf
	sudo sed -i '/ProxyPreserveHost Off/s/ProxyPreserveHost Off//g' ${http_server_path}/conf/httpd.conf
	if grep -q "ProxyPreserveHost On" ${http_server_path}/conf/httpd.conf; then
		echo "ProxyPreserveHost setting found, skip"
	else
		echo "ProxyPreserveHost not found"
		changes+=("\tProxyPreserveHost On")
		changeSize=$((changeSize+1))
	fi

	proxyPass='\tProxyPass /social '
	ending='/social'
	proxyPassReverse='\tProxyPassReverse /social '
	changes+=("$proxyPass${protocol}${master}:32080$ending")
	changes+=("$proxyPassReverse${protocol}${master}:32080$ending")
	proxyPass='\tProxyPass /itm '
	ending='/itm'
	proxyPassReverse='\tProxyPassReverse /itm '
	changes+=("$proxyPass${protocol}${master}:32080$ending")
	changes+=("$proxyPassReverse${protocol}${master}:32080$ending")
	proxyPass='\tProxyPass /appreg '
	ending='/appreg/'
	proxyPassReverse='\tProxyPassReverse /appreg '
	changes+=("$proxyPass${protocol}${master}:32080$ending")
	changes+=("$proxyPassReverse${protocol}${master}:32080$ending")
	proxyPass='\tProxyPass /appregistry '
	ending='/appregistry'
	proxyPassReverse='\tProxyPassReverse /appregistry '
	changes+=("$proxyPass${protocol}${master}:32080$ending")
	changes+=("$proxyPassReverse${protocol}${master}:32080$ending")
	proxyPass='\tProxyPass /community_suggestions/api/recommend/communities '
	ending='/community_suggestions/api/recommend/communities'
	proxyPassReverse='\tProxyPassReverse /community_suggestions/api/recommend/communities '
	changes+=("$proxyPass${protocol}${master}:32080$ending")
	changes+=("$proxyPassReverse${protocol}${master}:32080$ending")

	sudo sed -i "/\/itm/d" ${http_server_path}/conf/httpd.conf
	sudo sed -i "/\/social/d" ${http_server_path}/conf/httpd.conf
	sudo sed -i "/\/appreg/d" ${http_server_path}/conf/httpd.conf
	sudo sed -i "/\/appregistry/d" ${http_server_path}/conf/httpd.conf
	sudo sed -i "/\/community_suggestions/d" ${http_server_path}/conf/httpd.conf

	linenumber=$(grep -n "<IfModule mod_ibm_ssl.c>" ${http_server_path}/conf/httpd.conf | grep -Eo '^[^:]+')
	if [[ "$linenumber" == "" ]]; then
		echo "<IfModule mod_ibm_ssl.c>" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "Listen 0.0.0.0:443" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "    <VirtualHost *:443>" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "${changes[0]}" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "${changes[1]}" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "${changes[2]}" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "${changes[3]}" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "${changes[4]}" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "${changes[5]}" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "${changes[6]}" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "${changes[7]}" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "${changes[8]}" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "${changes[9]}" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		if [[ "$changeSize" == "1" ]]; then
			echo "${changes[10]}" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		fi
		echo "    SSLEnable" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "    SSLProtocolDisable SSLv2 SSLv3" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "    SSLAttributeSet 471 1" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "    CustomLog logs/ssl_access_log combined" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "    <IfModule mod_rewrite.c>" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "        RewriteEngine On" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "        RewriteLog logs/rewrite.log" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "        RewriteLogLevel 9" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "        Include conf/ihs-upload-rewrite.conf" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "    </IfModule>" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "    </VirtualHost>" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
		echo "</IfModule>" | sudo tee -a ${http_server_path}/conf/httpd.conf > /dev/null
	else
		target=`expr ${linenumber} + 3`
		sudo cp ${http_server_path}/conf/httpd.conf /tmp/
		for redirect in "${changes[@]}"
		do
			sudo awk -v n=${target} -v s="${redirect}" 'NR == n {print s} {print}' ${http_server_path}/conf/httpd.conf | sudo tee /tmp/newhttpd.conf > /dev/null
			sudo mv -f /tmp/newhttpd.conf ${http_server_path}/conf/httpd.conf
			sudo rm -f  /tmp/newhttpd.conf
			target=$((target+1))
		done
	fi

	# Ensure the required modules are applied
	echo
	echo "Ensuring the required modules are applied in httpd.conf"
	sudo sed -i '/#LoadModule proxy_/s/#//g' ${http_server_path}/conf/httpd.conf
	linenumber=$(grep -n "LoadModule proxy_module modules/mod_proxy.so" ${http_server_path}/conf/httpd.conf | grep -Eo '^[^:]+')
	if [[ "$linenumber" == "" ]]; then
		placeForIt=$(grep -n "LoadModule " ${http_server_path}/conf/httpd.conf | grep -Eo '^[^:]+' | tail -1)
		target=$((placeForIt+1))
		sudo awk -v n=${target} -v s="LoadModule proxy_module modules/mod_proxy.so" 'NR == n {print s} {print}' ${http_server_path}/conf/httpd.conf | sudo tee /tmp/newhttpd.conf > /dev/null
		sudo mv -f /tmp/newhttpd.conf ${http_server_path}/conf/httpd.conf
		sudo rm -rf  /tmp/newhttpd.conf
	fi
	linenumber=$(grep -n "LoadModule proxy_connect_module modules/mod_proxy_connect.so" ${http_server_path}/conf/httpd.conf | grep -Eo '^[^:]+')
	if [[ "$linenumber" == "" ]]; then
			placeForIt=$(grep -n "LoadModule " ${http_server_path}/conf/httpd.conf | grep -Eo '^[^:]+' | tail -1)
			target=$((placeForIt+1))
			sudo awk -v n=${target} -v s="LoadModule proxy_connect_module modules/mod_proxy_connect.so" 'NR == n {print s} {print}' ${http_server_path}/conf/httpd.conf | sudo tee /tmp/newhttpd.conf > /dev/null
			sudo mv -f /tmp/newhttpd.conf ${http_server_path}/conf/httpd.conf
			sudo rm -rf  /tmp/newhttpd.conf
	fi
	linenumber=$(grep -n "LoadModule proxy_ftp_module modules/mod_proxy_ftp.so" ${http_server_path}/conf/httpd.conf | grep -Eo '^[^:]+')
	if [[ "$linenumber" == "" ]]; then
			placeForIt=$(grep -n "LoadModule " ${http_server_path}/conf/httpd.conf | grep -Eo '^[^:]+' | tail -1)
			target=$((placeForIt+1))
			sudo awk -v n=${target} -v s="LoadModule proxy_ftp_module modules/mod_proxy_ftp.so" 'NR == n {print s} {print}' ${http_server_path}/conf/httpd.conf | sudo tee /tmp/newhttpd.conf > /dev/null
			sudo mv -f /tmp/newhttpd.conf ${http_server_path}/conf/httpd.conf
			sudo rm -rf  /tmp/newhttpd.conf
	fi
	linenumber=$(grep -n "LoadModule proxy_http_module modules/mod_proxy_http.so" ${http_server_path}/conf/httpd.conf | grep -Eo '^[^:]+')
	if [[ "$linenumber" == "" ]]; then
			placeForIt=$(grep -n "LoadModule " ${http_server_path}/conf/httpd.conf | grep -Eo '^[^:]+' | tail -1)
			target=$((placeForIt+1))
			sudo awk -v n=${target} -v s="LoadModule proxy_http_module modules/mod_proxy_http.so" 'NR == n {print s} {print}' ${http_server_path}/conf/httpd.conf | sudo tee /tmp/newhttpd.conf > /dev/null
			sudo mv -f /tmp/newhttpd.conf ${http_server_path}/conf/httpd.conf
			sudo rm -rf  /tmp/newhttpd.conf
	fi

	# Apply the changes by restarting the HTTP server gracefully
	echo
	echo "Restarting HTTP server gracefully"
	${http_server_path}/bin/apachectl graceful || exit 1
}

function configure_dmgr_om {

	confPath="$1"
	HOSTNAME=`hostname --fqdn`
	xmlFile=$confPath"LotusConnections-config.xml"
	xsdFile=$confPath"service-location.xsd"

	# XSD update
	set +e
	echo "Checking xsdFile"
	echo $xsdFile
	setAlready=$(grep $xsdFile -n -e'<xsd:enumeration value="orient')
	if [[ -z "${setAlready}" ]]; then
		echo "xsd setup"
		updateLine=$(grep -n "xsd:enumeration " ${xsdFile} | grep -Eo '^[^:]+' | tail -1)
		sudo awk -v n=$updateLine -v s='            <xsd:enumeration value="orient" />' 'NR == n {print s} {print}' $xsdFile | sudo tee /tmp/newxsdFile.xsd > /dev/null
		sudo mv -f /tmp/newxsdFile.xsd $xsdFile
		sudo rm -rf /tmp/newxsdFile.xsd
	else
		echo "Skipping xsd, already configured"
	fi

	# XML update
	setAlready=$(grep $xmlFile -n -e "<sloc:hrefPathPrefix>/social</sloc:hrefPathPrefix>")
	if [[ -z "${setAlready}" ]]; then
		echo "Setup xml file"
		updateLine=$(grep -n "sloc:serviceReference " ${xmlFile} | grep -Eo '^[^:]+' | tail -1)
		target=$((updateLine-1))
		line1="    <sloc:serviceReference bootstrapHost=\""${HOSTNAME}"\" bootstrapPort=\""2809"\" clusterName=\"""\" enabled=\""true"\" serviceName=\""orient"\" ssl_enabled=\""true"\">"
		line2="        <sloc:href>"
		line3="            <sloc:hrefPathPrefix>/social</sloc:hrefPathPrefix>"
		line4="            <sloc:static href=\""http://${HOSTNAME}"\" ssl_href=\""https://${HOSTNAME}"\"/>"
		line5="            <sloc:interService href=\""https://${HOSTNAME}"\"/>"
		line6="        </sloc:href>"
		line7="    </sloc:serviceReference>"

		lineArray=("${line1}" "${line2}" "${line3}" "${line4}" "${line5}" "${line6}" "${line7}")

		echo "updateLine = $updateLine"
		sudo cp $xmlFile /tmp/LotusConnections-config.xml
		for entry in "${lineArray[@]}"
		do
			sudo awk -v n=$updateLine -v s="${entry}" 'NR == n {print s} {print}' $xmlFile | sudo tee /tmp/LotusConnections-config.xml > /dev/null
			sudo mv -f /tmp/LotusConnections-config.xml $xmlFile
			sudo rm -rf /tmp/LotusConnections-config.xml
			updateLine=$((updateLine+1))
		done
	else
		echo "Skipping orient setup, already configured"
	fi

	setAlready=$(grep $xmlFile -n -e .*'<genericProperty name="actioncenter"')
	if [[ -z "${setAlready}" ]]; then
		echo "Checking genericProperty setup"
		updateLine=$(grep -n "genericProperty " ${xmlFile} | grep -Eo '^[^:]+' | tail -1)
		sudo awk -v n=$updateLine -v s='                <genericProperty name="actioncenter">enabled</genericProperty>' 'NR == n {print s} {print}' $xmlFile | sudo tee /tmp/LotusConnections-config.xml > /dev/null
		sudo mv -f /tmp/LotusConnections-config.xml $xmlFile
		sudo rm -rf /tmp/LotusConnections-config.xml
	else
		echo "Skipping genericProperty setup, already configured"
	fi
}

function configure_dmgr_typeahead {

	confPath="$1"
	lccXmlFile=$confPath"LotusConnections-config.xml"
	searchXmlFile=$confPath"search-config.xml"

	# LCC XML update
	setAlready=$(grep $lccXmlFile -n -e .*'<genericProperty name="quickResultsEnabled">true')
	if [[ -z "${setAlready}" ]]; then
		echo "Setting quickResultsEnabled genericProperty to true"
		sudo sed -i 's/name="quickResultsEnabled">false/name="quickResultsEnabled">true/g' ${lccXmlFile}
	else
		echo "quickResultsEnabled already set to true."
	fi

	# search-config.xml
	setAlready=$(grep $searchXmlFile -n -e .*'property name="quickResults"')
	if [[ -z "${setAlready}" ]]; then
		updateLine=$(grep -n "<propertySettings>" ${searchXmlFile} | grep -Eo '^[^:]+' | tail -1)
		updateLine=$(($updateLine+1))
		line1="		<property name=\"quickResults\">"
		line2="			<propertyField name='quick.results.elasticsearch.indexing.enabled' value='true'/>"
		line3="			<propertyField name='quick.results.use.solr.for.queries' value='false'/>"
		line4="		</property>"
		lineArray=("${line1}" "${line2}" "${line3}" "${line4}")

		for entry in "${lineArray[@]}"
		do
			sudo awk -v n=$updateLine -v s="${entry}" 'NR == n {print s} {print}' ${searchXmlFile} | sudo tee /tmp/search-config.xml > /dev/null
			sudo mv -f /tmp/search-config.xml ${searchXmlFile}
			sudo rm -rf /tmp/search-config.xml
			updateLine=$((updateLine+1))
		done
	else
		# Ensure values are set correctly if property exists
		echo
		echo "Found quick results property already exists. Ensuring values are set correctly..."
		sudo sed -i "s/'quick.results.elasticsearch.indexing.enabled' value='false'/'quick.results.elasticsearch.indexing.enabled' value='true'/g" ${searchXmlFile}
		sudo sed -i "s/'quick.results.use.solr.for.queries' value='true'/'quick.results.use.solr.for.queries' value='false'/g" ${searchXmlFile}
		echo "done"
	fi

}

function syncNodes() {

	wasPath=$1
	ic_admin_username=$2
	ic_admin_password=$3
	HOSTNAME=`hostname --fqdn`

	# Stop cluster
	clusterLocation=`ls ${wasPath}/AppServer/profiles/Dmgr01/config/temp/download/cells/`
	files=`ls ${wasPath}/AppServer/profiles/Dmgr01/config/temp/download/cells/${clusterLocation}/clusters/`
	clusters=($files)
	for cluster in "${clusters[@]}"; do
		echo
		echo "Stopping $cluster"
		sudo ${wasPath}/AppServer/profiles/Dmgr01/bin/wsadmin.sh -lang jython -f configureBlue-stopCluster.py.erb ${cluster} -user ${ic_admin_username} -password ${ic_admin_password}
	done
	echo

	# Stop node agents
	appServers=( $(ls . ${wasPath}/AppServer/profiles | grep AppSrv) )
	for appServer in "${appServers[@]}"; do
		status=$(sudo ${wasPath}/AppServer/profiles/${appServer}/bin/serverStatus.sh nodeagent -username ${ic_admin_username} -password ${ic_admin_password} | awk '{print $NF}' | tail -n 1)
		if [ "${status}" = "STARTED" ]; then
			echo "Stopping node agent: ${appServer}"
			sudo ${wasPath}/AppServer/profiles/${appServer}/bin/stopNode.sh -username ${ic_admin_username} -password ${ic_admin_password}
		fi
	done

	# syncNode
	echo "Syncing node"
	sudo ${wasPath}/AppServer/profiles/AppSrv01/bin/syncNode.sh ${HOSTNAME} 8879 -username ${ic_admin_username} -password ${ic_admin_password}

	# Start node agents
	for appServer in "${appServers[@]}"; do
		echo
		echo "Starting node agent: ${appServer}"
		sudo ${wasPath}/AppServer/profiles/${appServer}/bin/startNode.sh
	done

	# Start cluster
	for cluster in "${clusters[@]}"; do
		echo
		echo "Starting $cluster"
		sudo ${wasPath}/AppServer/profiles/Dmgr01/bin/wsadmin.sh -lang jython -f configureBlue-startCluster.py.erb ${cluster} -user ${ic_admin_username} -password ${ic_admin_password}
	done
}

function setup_yum() {

	FTP3USER=$1
	FTP3PASS=$2
	homeFolder=$3

	if [ -f /${homeFolder}/ibm-yum.sh ]; then
		rm -f /${homeFolder}/ibm-yum.sh
	fi
	cd /${homeFolder}

	set +o errexit
	wget --tries=1 --user=${FTP3USER} --password=${FTP3PASS} ftp://ftp3.linux.ibm.com/redhat/ibm-yum.sh
	if [ $? -ne 0 ]; then
		echo
		echo "Failed to get ibm-yum.sh from ftp3.linux.ibm.com. Trying a different repo..."
		wget --tries=1 --user=${FTP3USER} --password=${FTP3PASS} ftp://ftp3-ca.linux.ibm.com/redhat/ibm-yum.sh
		if [ $? -ne 0 ]; then
			echo "Failed to get ibm-yum.sh from ftp3-ca.linux.ibm.com. Giving up"
			exit 1
		else
			sed -i -e 's/ftp3.linux.ibm.com/ftp3-ca.linux.ibm.com/g' /${homeFolder}/ibm-yum.sh
			yum clean all
			sudo rm -rf /etc/yum.repos.d/ibm-yum-*.repo
		fi
	fi
	set -o errexit
	chmod 777 /${homeFolder}/ibm-yum.sh
}

function download_file() {

	SCRIPT=$1
	PATH_FILE=$2

	# Download files with icci@us.ibm.com credentials:
	echo
	echo "Downloading ${SCRIPT}"
	TOKEN="0fc2408c6107bc7048e1f476f104c957972dd6af"
	OWNER="connections"
	REPO="deploy-services"
	sudo rm -f ${SCRIPT}
	PATH_FILE="${PATH_FILE}/${SCRIPT}"
	FILE="https://github.ibm.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
	curl -H "Authorization: token $TOKEN" \
	-H "Accept: application/vnd.github.v3.raw" \
	-O \
	-L $FILE
}

function restart_metrics() {

	wsadmin_dir=$1
	wasadmin=$2
	wasadmin_pwd=$3

	cd ${wsadmin_dir}
	version=$(sudo sh versionInfo.sh | grep "IBM WebSphere Application Server Network Deployment" -A 1 | grep Version | awk {'print $2'})

	echo "AdminControl.invoke('WebSphere:name=ApplicationManager,process=ConnectionsCluster,platform=proxy,node=$(hostname)Node01,version=${version},type=ApplicationManager,mbeanIdentifier=ApplicationManager,cell=$(hostname)Cell01,spec=1.0', 'stopApplication', '[MetricsEventCapture]')" | sudo tee ${wsadmin_dir}/stop_metrics.py > /dev/null
	echo "AdminControl.invoke('WebSphere:name=ApplicationManager,process=ConnectionsCluster,platform=proxy,node=$(hostname)Node01,version=${version},type=ApplicationManager,mbeanIdentifier=ApplicationManager,cell=$(hostname)Cell01,spec=1.0', 'stopApplication', '[Metrics]')" | sudo tee -a ${wsadmin_dir}/stop_metrics.py > /dev/null

	set +o errexit
	sudo sh wsadmin.sh -lang jython -username ${wasadmin} -password ${wasadmin_pwd} -f stop_metrics.py
	set -o errexit

	echo "AdminControl.invoke('WebSphere:name=ApplicationManager,process=ConnectionsCluster,platform=proxy,node=$(hostname)Node01,version=${version},type=ApplicationManager,mbeanIdentifier=ApplicationManager,cell=$(hostname)Cell01,spec=1.0', 'startApplication', '[Metrics]')" | sudo tee ${wsadmin_dir}/start_metrics.py > /dev/null
	echo "AdminControl.invoke('WebSphere:name=ApplicationManager,process=ConnectionsCluster,platform=proxy,node=$(hostname)Node01,version=${version},type=ApplicationManager,mbeanIdentifier=ApplicationManager,cell=$(hostname)Cell01,spec=1.0', 'startApplication', '[MetricsEventCapture]')" | sudo tee -a ${wsadmin_dir}/start_metrics.py > /dev/null

	sudo sh wsadmin.sh -lang jython -username ${wasadmin} -password ${wasadmin_pwd} -f start_metrics.py
}

function disableSSLTypeAhead() {

	wsadmin_dir=$1
	wasadmin=$2
	wasadmin_pwd=$3

	cd ${wsadmin_dir}

	echo "AdminTask.deleteDynamicSSLConfigSelection('[-dynSSLConfigSelectionName SearchToES_node_$(hostname)Node01_ConnectionsCluster -scopeName (cell):$(hostname)Cell01:(node):$(hostname)Node01:(server):ConnectionsCluster ]')" | sudo tee ${wsadmin_dir}/disableSSL.py > /dev/null
	echo "AdminTask.deleteSSLConfig('[-alias ESSearchSSLSettings -scopeName (cell):$(hostname)Cell01 ]')" | sudo tee -a ${wsadmin_dir}/disableSSL.py > /dev/null
	echo "AdminTask.deleteKeyStore('[-keyStoreName ESCloudKeyStore -scopeName (cell):$(hostname)Cell01 ]')" | sudo tee -a ${wsadmin_dir}/disableSSL.py > /dev/null
	echo "AdminConfig.save()" | sudo tee -a ${wsadmin_dir}/disableSSL.py > /dev/null

	sudo sh wsadmin.sh -lang jython -username ${wasadmin} -password ${wasadmin_pwd} -f disableSSL.py
}

function deleteESCloudSSLSettings() {

	wsadmin_dir=$1
	wasadmin=$2
	wasadmin_pwd=$3

	cd ${wsadmin_dir}

	# NOT SOMETHING A CUSTOMER WILL DO - We are only deleting for automation purposes (incase metrics is already enabled), as it won't allow is to follow the metrics steps when type-ahead is enabled
	echo "AdminTask.deleteDynamicSSLConfigSelection('[-dynSSLConfigSelectionName SSLToES_node_$(hostname)Node01_ConnectionsCluster -scopeName (cell):$(hostname)Cell01:(node):$(hostname)Node01:(server):ConnectionsCluster ]')" | sudo tee ${wsadmin_dir}/deleteESCloudSSLSettings.py > /dev/null
	echo "AdminTask.deleteSSLConfig('[-alias ESCloudSSLSettings -scopeName (cell):$(hostname)Cell01 ]')" | sudo tee -a ${wsadmin_dir}/deleteESCloudSSLSettings.py > /dev/null
	echo "AdminConfig.save()" | sudo tee -a ${wsadmin_dir}/deleteESCloudSSLSettings.py > /dev/null

	sudo sh wsadmin.sh -lang jython -username ${wasadmin} -password ${wasadmin_pwd} -f deleteESCloudSSLSettings.py
}

# Verify secrets
if [ ${configureRedis} = true ]; then
	if ! [[ "$(kubectl get secrets -o jsonpath={.items[*].metadata.name} -n connections)" =~ "redis-secret" ]]; then
		echo "redis-secret must exist in order to configure redis"
		exit 1
	fi
fi

if [ ${configure_es_metrics} = true ]; then
	if ! [[ "$(kubectl get secrets -o jsonpath={.items[*].metadata.name} -n connections)" =~ "elasticsearch-secret" ]]; then
		echo "elasticsearch-secret must exist in order to configure elasticsearch metrics"
		exit 1
	fi
fi

if [ -z "${ic_ssh_user}" ]; then
	ic_ssh_user="root"
fi

if [ "${ic_ssh_user}" == "root" ]; then
	homeFolder="/${ic_ssh_user}"
else
 	homeFolder="/home/${ic_ssh_user}"
fi

# Determine OS
distributor=`lsb_release -i | awk '{ print $3 }'`
if [ "${distributor}" = RedHatEnterpriseServer ]; then
	YUM="sudo FTP3USER=${FTP3USER} FTP3PASS=${FTP3PASS} ${homeFolder}/ibm-yum.sh"
elif [ "${distributor}" = CentOS ]; then
	YUM="yum"
else
	echo "Unsupported OS"
	exit 1
fi

# Set up YUM and sshpass
if [ "${FTP3USER}" = "" -o "${FTP3PASS}" = "" ]; then
	echo "FTP3USER and FTP3PASS are required for YUM"
	exit 1
else
	echo
	echo "Configuring ibm-yum on $(hostname -f)"
	setup_yum ${FTP3USER} ${FTP3PASS} ${homeFolder}

	# Install sshpass
	echo
	echo "Installing sshpass on $(hostname -f)"
	${YUM} install -y sshpass
fi

# Determine paths
pathEnding="/LotusConnections-config/"
pathFind="${wasPath}/AppServer/profiles/Dmgr01/config/cells"
path=$(sshpass -p ${ic_ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${ic_ssh_user}@${connections_dmgr} "find ${wasPath}/AppServer/profiles/Dmgr01/config/cells/ -name *\"Cell01\"")
confPath="${path}/${pathEnding}"
xmlFile=$confPath"LotusConnections-config.xml"
xsdFile=$confPath"service-location.xsd"
wsadmin_dir=${wasPath}/AppServer/profiles/Dmgr01/bin

# Configure Orient Me
if [ ${configure_om} = true ]; then
	# Configure IHS for orient me
	typeset -f configure_ihs_om | sshpass -p ${ic_ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${ic_ssh_user}@${http_server} "$(cat); configure_ihs_om ${http_server_path} ${master} || exit 1"

	# Configure dmgr for orient me
	typeset -f configure_dmgr_om | sshpass -p ${ic_ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${ic_ssh_user}@${connections_dmgr} "$(cat); configure_dmgr_om ${confPath} || exit 1"
fi

# Configure Redis
if [ ${configureRedis} = true ]; then
	echo
	echo "Configuring Redis..."
	download_file configureRedis.sh scripts
	encoded_redis_pass=$(kubectl get secret redis-secret -n connections -o yaml | grep secret: | awk '{ print $2 }')
	decoded_redis_pass=$(echo ${encoded_redis_pass} | base64 --decode)
	sudo bash configureRedis.sh -m ${master} -po 30379 -ic https://${http_server} -pw ${decoded_redis_pass} -ic_u ${ic_admin_username} -ic_p ${ic_admin_password} || exit 1
fi

# Copy certs to dmgr for metrics and/or typeahead
if [ ${configure_es_metrics} = true -o ${configure_es_typeahead} = true ]; then
	# Remove old files
	sudo rm -f chain-ca.pem elasticsearch-metrics.p12

	# Get new files from secret
	kubectl get secret elasticsearch-secret -n connections -o=jsonpath="{.data['chain-ca\.pem']}" | base64 -d | sudo tee chain-ca.pem > /dev/null
	kubectl get secret elasticsearch-secret -n connections -o=jsonpath="{.data['elasticsearch-metrics\.p12']}" | base64 -d | sudo tee -a elasticsearch-metrics.p12 > /dev/null

	# Remove old files on dmgr
	sshpass -p ${ic_ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${ic_ssh_user}@${connections_dmgr} "sudo rm -f /tmp/chain-ca.pem /tmp/elasticsearch-metrics.p12"

	# Copy new files to dmgr
	sshpass -p ${ic_ssh_password} sudo scp -o StrictHostKeyChecking=no chain-ca.pem elasticsearch-metrics.p12 ${ic_ssh_user}@${connections_dmgr}:/tmp
fi

# Configure Elasticsearch Metrics
if [ ${configure_es_metrics} = true ]; then
	# Find out if type-ahead is enabled, and if it is, remove SSL settings in order to enable metrics
	typeAheadStatus=$(sshpass -p ${ic_ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${ic_ssh_user}@${connections_dmgr} "grep quickResultsEnabled ${xmlFile}")
	if [[ "${typeAheadStatus}" =~ "true" ]]; then
		echo ""
		echo "Found type-ahead is already configured so removing the SSL settings in order to configure metrics.."
		echo "Attempting to delete the Dynamic outbound endpoint and ESCloudSSLSettings SSL configurations for Metrics incase metrics was previously configured"
		echo "(OK if it fails as it will not exist if metrics has never been enabled)"
		set +o errexit
		typeset -f deleteESCloudSSLSettings | sshpass -p ${ic_ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${ic_ssh_user}@${connections_dmgr} "$(cat); deleteESCloudSSLSettings ${wsadmin_dir} ${ic_admin_username} ${ic_admin_password}"
		echo ""
		echo "Removing type-ahead SSL settings (will fail if type-ahead was enabled before metrics)"
		typeset -f disableSSLTypeAhead | sshpass -p ${ic_ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${ic_ssh_user}@${connections_dmgr} "$(cat); disableSSLTypeAhead ${wsadmin_dir} ${ic_admin_username} ${ic_admin_password}"
		set -o errexit
	else
		echo "Type-ahead is not configured yet - proceeding with metrics configuration"
	fi

	download_file config_blue_metrics.py "microservices/hybridcloud/bin"

	# Run script
	echo ""
	echo "Running python config_blue_metrics.py"
	python config_blue_metrics.py --skipSslCertCheck true --pinkhost ${master} | sudo tee config_blue_metrics.log
	if grep -q "HTTP Error 404: Not Found" config_blue_metrics.log; then
  		echo "404 Error expected if metrics has already been configured."
		echo "If you need to change the elasticsearch host, then manually change it in the highway"
		echo "Continuing.."
	fi

	# Restart metrics
	echo ""
	echo "Restarting metrics"
	typeset -f restart_metrics | sshpass -p ${ic_ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${ic_ssh_user}@${connections_dmgr} "$(cat); restart_metrics ${wsadmin_dir} ${ic_admin_username} ${ic_admin_password} || exit 1"

	# Create python script to import files
	sshpass -p ${ic_ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${ic_ssh_user}@${connections_dmgr} "sudo rm -f /tmp/import.py; echo \"execfile('esSecurityAdmin.py')\" | sudo tee ${wsadmin_dir}/import.py > /dev/null; echo \"enableSslForMetrics('/tmp/elasticsearch-metrics.p12', 'password', '/tmp/chain-ca.pem', '30099')\" | sudo tee -a ${wsadmin_dir}/import.py > /dev/null"

	# Import
	echo ""
	echo "Configuring SSL for metrics"
	sshpass -p ${ic_ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${ic_ssh_user}@${connections_dmgr} "cd ${wsadmin_dir}; sudo sh wsadmin.sh -lang jython -username ${ic_admin_username} -password ${ic_admin_password} -f import.py"

	# Create python script to switch to ES
	if [ ${migrate_metric_data} = true ]; then
		sshpass -p ${ic_ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${ic_ssh_user}@${connections_dmgr} "sudo rm -f /tmp/es_switch.py; echo \"execfile('metricsEventCapture.py')\" | sudo tee ${wsadmin_dir}/es_switch.py > /dev/null; echo \"MigraterService.migrate()\" | sudo tee -a ${wsadmin_dir}/es_switch.py > /dev/null; echo \"switchMetricsToElasticSearch()\" | sudo tee -a ${wsadmin_dir}/es_switch.py > /dev/null"
	else
		sshpass -p ${ic_ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${ic_ssh_user}@${connections_dmgr} "sudo rm -f /tmp/es_switch.py; echo \"execfile('metricsEventCapture.py')\" | sudo tee ${wsadmin_dir}/es_switch.py > /dev/null; echo \"switchMetricsToElasticSearch()\" | sudo tee -a ${wsadmin_dir}/es_switch.py ? /dev/null"
	fi

	# Switch to ES
	echo ""
	echo "Enabling metrics"
	sshpass -p ${ic_ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${ic_ssh_user}@${connections_dmgr} "cd ${wsadmin_dir}; sudo sh wsadmin.sh -lang jython -username ${ic_admin_username} -password ${ic_admin_password} -f es_switch.py"
fi

# Configure Elasticsearch type-ahead
if [ ${configure_es_typeahead} = true ]; then
	# Create python script to set up type-ahead
	sshpass -p ${ic_ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${ic_ssh_user}@${connections_dmgr} "sudo rm -f /tmp/typeahead.py; echo \"execfile('searchAdmin.py')\" | sudo tee ${wsadmin_dir}/typeahead.py > /dev/null; echo \"SearchService.setESQuickResultsBaseUrl('https://${master}:30099')\" | sudo tee -a ${wsadmin_dir}/typeahead.py > /dev/null; echo \"execfile('esSearchAdmin.py')\" | sudo tee -a ${wsadmin_dir}/typeahead.py > /dev/null; echo \"enableSslForESSearch('/tmp/elasticsearch-metrics.p12', 'password', '/tmp/chain-ca.pem', '30099')\" | sudo tee -a ${wsadmin_dir}/typeahead.py > /dev/null; echo \"SearchService.createESQuickResultsIndex()\" | sudo tee -a ${wsadmin_dir}/typeahead.py > /dev/null"

	# Run script
	echo
	echo "Setting ES host details in highway and creating QuickResults Index"
	sshpass -p ${ic_ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${ic_ssh_user}@${connections_dmgr} "cd ${wsadmin_dir}; sudo sh wsadmin.sh -lang jython -username ${ic_admin_username} -password ${ic_admin_password} -f typeahead.py"
	echo "Error can be expected if index already exists - confirm in log"

	# XML update
	echo
	echo "Configuring Connections for type-ahead"
	typeset -f configure_dmgr_typeahead | sshpass -p ${ic_ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${ic_ssh_user}@${connections_dmgr} "$(cat); configure_dmgr_typeahead ${confPath} || exit 1"
fi

# Sync nodes and restart cluster
if [ ${configure_om} = true -o ${configureRedis} = true -o ${configure_es_metrics} = true -o ${configure_es_typeahead} = true ]; then
	LIST="configureBlue-stopCluster.py.erb configureBlue-startCluster.py.erb"
	for f in ${LIST}; do
		typeset -f download_file | sshpass -p ${ic_ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${ic_ssh_user}@${connections_dmgr} "$(cat); download_file $f scripts || exit 1"
	done
	typeset -f syncNodes | sshpass -p ${ic_ssh_password} ssh -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no -n ${ic_ssh_user}@${connections_dmgr} "$(cat); syncNodes ${wasPath} ${ic_admin_username} ${ic_admin_password} || exit 1"
fi

# Migrate people
if [ ${migrate_people} = true ]; then
	command="npm run start migrate:clean"
	echo "Running: ${command}"
	kubectl exec -n connections -it $(kubectl get pods -n connections | grep people-migrate | awk '{print $1}') -- ${command}
fi
