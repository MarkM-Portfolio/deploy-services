#title           :configureReverseProxy.sh
#description     :This script configures the /social redirect for Orientme to OnPrem Connections environments. Giving it a base for the new Connections features.
#version         :0.4
#usage                 :configureReverseProxy.sh <OrientMe URL> <OrientMe Port> <ITM Port> <appregistry-client Port> <appregistry-service Port> <community_suggestions Port> <ITM Port> <HTTPServer path> <optional Overwrite previous /social setting y/n if no setting is enter n is the default>
#=================================================================================================
#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

logErr() {
  logIt "ERRO: " "$@"
}

logInfo() {
  logIt "INFO: " "$@"
}

logIt() {
    echo "$@"
}

logIt() {
    echo "$@"
}

echo "$#"
if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ $# -lt 7 ] || [ $# -gt 8 ] || [ $# -eq 8 ] && [ "$8" != "-y" ] && [ "$8" != "-Y" ] && [ "$8" != "-yes" ] && [ "$8" != "-Yes" ] && [ "$8" != "-n" ] && [ "$8" != "-N" ] && [ "$8" != "-no" ] && [ "$8" != "-No" ] ; then
    echo ""
    echo "USAGE:  ./configureReverseProxy.sh <OrientMe URL> <OrientMe Port> <appregistry-client Port> <appregistry-service Port> <community_suggestions Port> <ITM Port> <HTTPServer path> <optional Overwrite previous /social setting y/n if no setting is enter n is the default>";
    echo "EXAMPLE: ./configureReverseProxy.sh http://cfcserver.domain.com 30969 31100 30285 32212 30427 /opt/IBM/HTTPServer/"
    echo "EXAMPLE: ./configureReverseProxy.sh https://cfcserver.domain.com 30969 31100 30285 32212 30427 /opt/IBM/HTTPServer/ -y"
    echo ""
    exit 1;
fi
if [[ $1 != "https://"* ]] && [[ $1 != "http://"* ]]; then
	echo "error: YOU MUST SPECIFY THE PROTOCOL FOR YOUR OrientMe SYSTEM"
	exit 1
fi
acceptedEntry='^[0-9]+$'
if ! [[ $2 =~ $acceptedEntry ]] ; then
	echo "error: ONE OF YOUR PORT IS OFF. THEY MUST ALL BE NUMBERS "
   	exit 1
fi

echo $7 | grep -q HTTPServer
if [ $? -ne 0 ]; then
        echo "error: YOU MUST SPECIFY THE PATH TO THE HTTPServer DIRECTORY OF YOUR SYSTEM"
        exit 1
fi

confPath=""	
if [[ "$7" == */ ]]; then
	path="$7"
else
	path=$7"/"
fi 

#Informing the user of possible changes to their system
while true; do
    read -p "This program will enable the HTTPServer proxy modules and gracefully restart your HTTPServer. Your current settings will be backed up. Do you wish to continue? y/n?" yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
done

#Loading the file paths required and the creating the paths for the redirect
confPath=$path"conf/httpd.conf"
confBin=$path"bin/"
confBackup=$path"conf/Pre_OrientMe_Backup_httpd.conf"
proxyPass='\tProxyPass /social '
ending='/social'
proxyPassReverse='\tProxyPassReverse /social '
changes=()
changeSize=0
if [ $# -eq 8 ]
then
	if [ "$8" == "-y" ] || [ "$8" == "-Y" ] || [ "$8" == "-yes" ] || [ "$8" == "-Yes" ]
	then
		overwrite='Yes'
	else
		overwrite='No'
	fi
else
	overwrite='No'
fi

sed -i '/#ProxyPreserveHost On/s/#//g' $confPath
sed -i '/ProxyPreserveHost Off/s/ProxyPreserveHost Off//g' $confPath
echo "confPath = $confPath"
echo "Check grep"
grep -n "Proxy" $confPath
if grep -q "ProxyPreserveHost On" $confPath; then
	echo "ProxyPreserveHost setting found, skip"
else
	echo "ProxyPreserveHost not found"
	changes+=("\tProxyPreserveHost On")
	changeSize=$((changeSize+1))
fi

changes+=("$proxyPass$1:$2$ending")
changes+=("$proxyPassReverse$1:$2$ending")
proxyPass='\tProxyPass /itm '
ending='/itm'
proxyPassReverse='\tProxyPassReverse /itm '
changes+=("$proxyPass$1:$3$ending")
changes+=("$proxyPassReverse$1:$3$ending")
proxyPass='\tProxyPass /appreg '
ending='/appreg'
proxyPassReverse='\tProxyPassReverse /appreg '
changes+=("$proxyPass$1:$4$ending")
changes+=("$proxyPassReverse$1:$4$ending")
proxyPass='\tProxyPass /appregistry '
ending='/appregistry'
proxyPassReverse='\tProxyPassReverse /appregistry '
changes+=("$proxyPass$1:$5$ending")
changes+=("$proxyPassReverse$1:$5$ending")
proxyPass='\tProxyPass /community_suggestions/api/recommend/communities '
ending='/community_suggestions/api/recommend/communities'
proxyPassReverse='\tProxyPassReverse /community_suggestions/api/recommend/communities '
changes+=("$proxyPass$1:$6$ending")
changes+=("$proxyPassReverse$1:$6$ending")
#Checking if the changes will overwrite previous settings
if [ "$overwrite" == "Yes" ]; then
	sed -i "/\/itm/d" $confPath
	sed -i "/\/social/d" $confPath
	sed -i "/\/appreg/d" $confPath
	sed -i "/\/appregistry/d" $confPath
	sed -i "/\/community_suggestions/d" $confPath
else
	if grep 'ProxyPassReverse /itm' $confPath; then
		echo "YOU ARE TRYING TO OVERWRITE A PREVIOUS CONFIGURATION - NO CHANGE MADE"
		exit 0;
	fi
	if grep 'ProxyPass /itm' $confPath; then
		echo "YOU ARE TRYING TO OVERWRITE A PREVIOUS CONFIGURATION - NO CHANGE MADE"
		exit 0;
        fi
	if grep 'ProxyPassReverse /social' $confPath; then
		echo "YOU ARE TRYING TO OVERWRITE A PREVIOUS CONFIGURATION - NO CHANGE MADE"
		exit 0;
	fi
        if grep 'ProxyPass /social' $confPath; then
		echo "YOU ARE TRYING TO OVERWRITE A PREVIOUS CONFIGURATION - NO CHANGE MADE"
		exit 0;
	fi
	if grep 'ProxyPassReverse /appreg' $confPath; then
		echo "YOU ARE TRYING TO OVERWRITE A PREVIOUS CONFIGURATION - NO CHANGE MADE"
		exit 0;
	fi
	if grep 'ProxyPass /appreg' $confPath; then
		echo "YOU ARE TRYING TO OVERWRITE A PREVIOUS CONFIGURATION - NO CHANGE MADE"
		exit 0;
	fi
	if grep 'ProxyPassReverse /appregistry' $confPath; then
		echo "YOU ARE TRYING TO OVERWRITE A PREVIOUS CONFIGURATION - NO CHANGE MADE"
		exit 0;
	fi
	if grep 'ProxyPass /appregistry' $confPath; then
		echo "YOU ARE TRYING TO OVERWRITE A PREVIOUS CONFIGURATION - NO CHANGE MADE"
		exit 0;
	fi

	if grep 'ProxyPassReverse /community_suggestions/api/recommend/communities' $confPath; then
		echo "YOU ARE TRYING TO OVERWRITE A PREVIOUS CONFIGURATION - NO CHANGE MADE"
		exit 0;
	fi
	if grep 'ProxyPass /community_suggestions/api/recommend/communities' $confPath; then
		echo "YOU ARE TRYING TO OVERWRITE A PREVIOUS CONFIGURATION - NO CHANGE MADE"
		exit 0;
	fi
fi

#Making backup of previous settings
cp $confPath $confBackup
echo "httpd.conf has been backed up to $confBackup"

#Ensuring the required tag is applied and adding the redirect settings
linenumber=$(grep -n "<IfModule mod_ibm_ssl.c>" $confPath | grep -Eo '^[^:]+')
if [[ "$linenumber" == "" ]]; then
	echo "<IfModule mod_ibm_ssl.c>" >> $confPath
	echo "Listen 0.0.0.0:443" >> $confPath
	echo "    <VirtualHost *:443>" >> $confPath
	echo "${changes[0]}" >> $confPath
	echo "${changes[1]}" >> $confPath
	echo "${changes[2]}" >> $confPath
	echo "${changes[3]}" >> $confPath
	echo "${changes[4]}" >> $confPath
	echo "${changes[5]}" >> $confPath
	echo "${changes[6]}" >> $confPath
	echo "${changes[7]}" >> $confPath
	echo "${changes[8]}" >> $confPath
	echo "${changes[9]}" >> $confPath
	if [[ "$changeSize" == "1" ]]; then
	        echo "${changes[10]}" >> $confPath
	fi
	echo "    SSLEnable" >> $confPath
	echo "    SSLProtocolDisable SSLv2 SSLv3" >> $confPath
	echo "    SSLAttributeSet 471 1" >> $confPath
	echo "    CustomLog logs/ssl_access_log combined" >> $confPath
	echo "    <IfModule mod_rewrite.c>" >> $confPath
	echo "        RewriteEngine On" >> $confPath
	echo "        RewriteLog logs/rewrite.log" >> $confPath
	echo "        RewriteLogLevel 9" >> $confPath
	echo "        Include conf/ihs-upload-rewrite.conf" >> $confPath
	echo "    </IfModule>" >> $confPath
	echo "    </VirtualHost>" >> $confPath
	echo "</IfModule>" >> $confPath	
else
        target=`expr ${linenumber} + 3`
	cp $confPath /tmp/
	for redirect in "${changes[@]}"
	do
		awk -v n=$target -v s="$redirect" 'NR == n {print s} {print}' $confPath > /tmp/newhttpd.conf
		mv -f /tmp/newhttpd.conf $confPath
		rm -rf  /tmp/newhttpd.conf
		target=$((target+1))
	done
fi

#Ensure the required modules are applied
sed -i '/#LoadModule proxy_/s/#//g' $confPath
linenumber=$(grep -n "LoadModule proxy_module modules/mod_proxy.so" $confPath | grep -Eo '^[^:]+')
if [[ "$linenumber" == "" ]]; then
	placeForIt=$(grep -n "LoadModule " $confPath | grep -Eo '^[^:]+' | tail -1)
	target=$((placeForIt+1))
	awk -v n=$target -v s="LoadModule proxy_module modules/mod_proxy.so" 'NR == n {print s} {print}' $confPath > /tmp/newhttpd.conf
	mv -f /tmp/newhttpd.conf $confPath
        rm -rf  /tmp/newhttpd.conf
fi
linenumber=$(grep -n "LoadModule proxy_connect_module modules/mod_proxy_connect.so" $confPath | grep -Eo '^[^:]+')
if [[ "$linenumber" == "" ]]; then
        placeForIt=$(grep -n "LoadModule " $confPath | grep -Eo '^[^:]+' | tail -1)
        target=$((placeForIt+1))
        awk -v n=$target -v s="LoadModule proxy_connect_module modules/mod_proxy_connect.so" 'NR == n {print s} {print}' $confPath > /tmp/newhttpd.conf
        mv -f /tmp/newhttpd.conf $confPath
        rm -rf  /tmp/newhttpd.conf
fi
linenumber=$(grep -n "LoadModule proxy_ftp_module modules/mod_proxy_ftp.so" $confPath | grep -Eo '^[^:]+')
if [[ "$linenumber" == "" ]]; then
        placeForIt=$(grep -n "LoadModule " $confPath | grep -Eo '^[^:]+' | tail -1)
        target=$((placeForIt+1))
        awk -v n=$target -v s="LoadModule proxy_ftp_module modules/mod_proxy_ftp.so" 'NR == n {print s} {print}' $confPath > /tmp/newhttpd.conf
        mv -f /tmp/newhttpd.conf $confPath
        rm -rf  /tmp/newhttpd.conf
fi
linenumber=$(grep -n "LoadModule proxy_http_module modules/mod_proxy_http.so" $confPath | grep -Eo '^[^:]+')
if [[ "$linenumber" == "" ]]; then
        placeForIt=$(grep -n "LoadModule " $confPath | grep -Eo '^[^:]+' | tail -1)
        target=$((placeForIt+1))
        awk -v n=$target -v s="LoadModule proxy_http_module modules/mod_proxy_http.so" 'NR == n {print s} {print}' $confPath > /tmp/newhttpd.conf
        mv -f /tmp/newhttpd.conf $confPath
        rm -rf  /tmp/newhttpd.conf
fi

#Apply the changes with a graceful http server restart
cd $confBin
./apachectl graceful
echo "HTTPServer configuration for Connections to pink complete!"
logIt() {
	echo "Done!"
}

