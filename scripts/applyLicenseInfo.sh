#!/bin/bash
###################################################################
#IBM Confidential
#
#
#OCO Source Materials
#
#
#Copyright IBM Corp. 2017, 2017
#
#
#The source code for this program is not published or otherwise
#divested of its trade secrets, irrespective of what has been
#deposited with the U.S. Copyright Office.
#
###################################################################
#title           :applyLicenseInfo.sh
#description     :This script checks the bash scripts in a file and if they are missing the IBM license details; adds it. Will also make sure any permissions on the files changed are reset.
#version         :0.2
#usage                 :applyLicenseInfo.sh <Root Directory>
#=================================================================================================
if [ $# -ne 1 ]; then
    echo ""
    echo "USAGE:  ./applyLicenseInfo.sh <Root Directory>";
    echo "EXAMPLE: ./applyLicenseInfo.sh /opt/Scripts/";
    echo ""
    exit;
fi
filesfound=($(grep -RL --include \*.sh "IBM Confidential" $1))
countOfFiles=($(grep -RL --include \*.sh "IBM Confidential" $1 | wc -l))
license="###################################################################
#IBM Confidential
#
#
#OCO Source Materials
#
#
#Copyright IBM Corp. 2017, 2017
#
#
#The source code for this program is not published or otherwise
#divested of its trade secrets, irrespective of what has been
#deposited with the U.S. Copyright Office.
#
###################################################################"
count=0
while [ $count -lt $countOfFiles ]
do
	levelOfFile="$(stat --format='%a' ${filesfound[$count]})"
	if [ $count -lt 1 ]; then
		echo "${filesfound[$count]}" > /tmp/filesMissingLicenses.txt
		echo "Starting Value for ${filesfound[$count]}: $levelOfFile" > /tmp/filePermissions.txt
	else
		echo "${filesfound[$count]}" >> /tmp/filesMissingLicenses.txt
		echo "Starting Value for ${filesfound[$count]}: $levelOfFile" >> /tmp/filePermissions.txt
	fi
	filePath="${filesfound[$count]}"
	echo "$license" | cat - $filePath > temp && mv temp $filePath
	chmod $levelOfFile ${filesfound[$count]}
	levelOfFile="$(stat --format='%a' ${filesfound[$count]})"
	echo "Ending Value for ${filesfound[$count]}  : $levelOfFile" >> /tmp/filePermissions.txt
	count=$(( count + 1 ))
done
if [ $countOfFiles -lt 1 ]; then
	echo "All files are under license"
fi
