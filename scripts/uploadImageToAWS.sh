#!/bin/bash

SCRIPT_NAME=$(basename ${0})
logTimestamp() { echo "$(date +"%Y-%m-%d %H:%M:%S") "; }
logIt() { echo "$(logTimestamp) $PRG $@"; }
logInfo() { logIt "INFO: " "$@"; }
logErro() { logIt "ERRO: " "$@"; }
logWarn() { logIt "WARN: " "$@"; }

USAGE="
usage:  $SCRIPT_NAME
	[--help]

        Environment requirements:
         . Python 2 version 2.6.5+ or Python 3 version 3.3+
           Installation instructions: https://packaging.python.org/guides/installing-using-linux-tools/#centos-rhel
           e.g.: 
              sudo yum install python-pip python-wheel

         . AWS Command Line Interface installed.
           Installation instructions: http://docs.aws.amazon.com/cli/latest/userguide/installing.html
           e.g.:
              pip install awscli --upgrade --user

         . Boto3 (Amazon Web Services (AWS) SDK for Python)
           Installation instructions: https://boto3.readthedocs.io/en/latest/guide/quickstart.html
           e.g.:
              pip install boto3

         . AWS credentials configured under ~/.aws/credentials.
           Instructions: https://boto3.readthedocs.io/en/latest/guide/quickstart.html#configuration
           e.g.:
              aws configure

	Required arguments (content between <> are values examples):
         --artifactoryImageName=<connections-docker.artifactory.cwp.pnp-hcl.com/middleware/mongodb>
         --artifactoryImageTag=<3.4.4-r0-20170808_062606>
         --awsImageName=<middleware/mongodb>

        Optional arguments:
         --debug
             Verbose mode (uploadImageToECR.py .. --debug)
         --skipPush
             Will not push the image to AWS (uploadImageToECR.py .. --skipPush)

  Example:
  ./$SCRIPT_NAME \\
  --artifactoryImageName=connections-docker.artifactory.cwp.pnp-hcl.com/middleware/mongodb \\
  --artifactoryImageTag=3.4.4-r0-20170808_062606 \\
  --awsImageName=middleware/mongodb \\
  --debug
"

WORKDIR=$(pwd)
TMP_WORKiDIR=$(mktemp -d)
cd $TMP_WORKDIR

# Download: https://github.ibm.com/cloud-operations/travisutils/blob/master/push/uploadImageToECR.py
downloadYmls() {
  echo ""
  # Download the YML files with icci@us.ibm.com credentials:
  logInfo "Downloading cloud-operations/travisutils/blob/master/push/uploadImageToECR.py"
  echo ""
  TOKEN="0fc2408c6107bc7048e1f476f104c957972dd6af"
  OWNER="cloud-operations"
  REPO="travisutils"
  PATH_FILE="push/uploadImageToECR.py"
  FILE="https://github.ibm.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
  curl -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github.v3.raw" \
  -O \
  -L $FILE

  chmod +x uploadImageToECR.py
  echo ""
  logInfo "uploadImageToECR.py downloaded at: $(pwd)"
}

DEBUG=""
SKIP_PUSH=""
ARTIFACTORY_IMAGE_NAME=""
ARTIFACTORY_IMAGE_TAG=""
AWS_IMAGE_NAME=""

CMD_GET_ARG_VAL="echo \${arg} | awk -F= '{ print \$2 }' | sed 's/,/ /g'"
for arg in $*; do
  if [ ${arg} = --debug ]; then
		DEBUG=${arg}
  elif [ ${arg} = --skipPush ]; then
		SKIP_PUSH=${arg}
  else
    echo ${arg} | grep -q -e --artifactoryImageName=
		if [ $? -eq 0 ]; then
			ARTIFACTORY_IMAGE_NAME=$(eval $CMD_GET_ARG_VAL)
      continue
		fi

    echo ${arg} | grep -q -e --artifactoryImageTag=
		if [ $? -eq 0 ]; then
			ARTIFACTORY_IMAGE_TAG=$(eval $CMD_GET_ARG_VAL)
      continue
		fi

    echo ${arg} | grep -q -e --awsImageName=
		if [ $? -eq 0 ]; then
			AWS_IMAGE_NAME=$(eval $CMD_GET_ARG_VAL)
      continue
		fi
  fi
done

if [ -z "$ARTIFACTORY_IMAGE_NAME" ] || \
   [ -z "$ARTIFACTORY_IMAGE_TAG" ] || \
   [ -z "$AWS_IMAGE_NAME" ]; then
     echo ""
     logErro "Invalid arguments."
     echo "${USAGE}"
     exit 1
fi

downloadYmls

# uploadImageToECR.py uses the standard $AWS_IMAGE_NAME:latest. Thus creating tag as needed...
logInfo "Creating tag $AWS_IMAGE_NAME:latest"
echo "$ARTIFACTORY_IMAGE_NAME:$ARTIFACTORY_IMAGE_TAG $AWS_IMAGE_NAME:latest"

docker tag $ARTIFACTORY_IMAGE_NAME:$ARTIFACTORY_IMAGE_TAG $AWS_IMAGE_NAME:latest

echo ""
logInfo "Pushing image $ECR_REPOSITORY_URI/$AWS_IMAGE_NAME:$ARTIFACTORY_IMAGE_TAG to AWS ECR..."

# Pushing to AWS
./uploadImageToECR.py \
--namespace connections-docker \
--imageName $AWS_IMAGE_NAME \
--version $ARTIFACTORY_IMAGE_TAG $DEBUG $SKIP_PUSH

# Get back to the folder where this script was called from
cd $WORKDIR
# Delete temp folder
rm -rf $TMP_WORKDIR

