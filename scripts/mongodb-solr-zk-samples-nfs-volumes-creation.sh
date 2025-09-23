#!/bin/bash -
#title           :zookeeper-nfs-volumes-creation.sh
#description     :This script must be used only in test environments.
#                 It will create PVs and PVCs to be used by zookeeper in K8s cluster on CFC.
#version         :0.1
#usage		       :zookeeper-nfs-volumes-creation.sh
#=================================================================================================
#!/bin/bash

logErr() {
  logIt "ERRO: " "$@"
}

logInfo() {
  logIt "INFO: " "$@"
}

logIt() {
    echo "$@"
}

PATH=/usr/bin:/bin:/usr/sbin:/sbin:${PATH}
export PATH
set -o errexit
set -o pipefail

useLocal=false
ha=false
usage() {
  logIt ""
  logIt "Usage: ./mongodb-solr-zk-samples-nfs-volumes-creation.sh [OPTION]"
  logIt "Must not be used in production. It will do:"
  logIt "Install and set up a basic NFS server configuration based of customer provided samples"
  logIt ""
  logIt "-f, --force   If PVs or PVCs already exist, it will recreate it, removing all current data."
  logIt "-uZ, --useZip  Use local PV and PVC scripts."
  logIt "-hA, --highA   High availablity deployment used for setting up connections to storage node"
}

createAndSetUpVolumes() {
  force
}

force() {

  # Check if NFS is installed, otherwise, install it
  if [[ $(rpm -qa nfs-utils | wc -l) -lt 1 ]]; then
    logInfo "nfs-utils not installed yet. Installing..."
    yum -y install nfs-utils
    if [[ $(rpm -qa nfs-utils | wc -l) -lt 1 ]]; then
      logErr "nfs-utils not installed, and the attempt to install has failed. Please, install it manually and try again. Exiting."
      exit 1
    fi
  fi

  # clean PVs and PVCs
  set +o errexit
  kubectl delete -f fullPVCs.yml &> /dev/null
  kubectl delete -f fullPVs_NFS.yml &> /dev/null
  set -o errexit
  if [ ${ha} = false ]; then
    # Clean up Volumes, and map them for NFS
    logInfo "Configuring NFS..."
    touch /etc/exports #If not exist, will create
    cp -n /etc/exports /etc/exports.bkp
    IFS='\.' read -a DEC_IP <<< "$(hostname -i)"
    VOLUMES=$(cat fullPVs_NFS.yml | grep path: | awk '{ print $2 }')
    for VOLUME in $VOLUMES; do
      mkdir -p $VOLUME
      chmod -R 777 $VOLUME
      rm -rf $VOLUME/*
      chmod -R 777 $VOLUME
      sed -i "/${VOLUME////\\/}/d" /etc/exports
      echo "$VOLUME        ${DEC_IP[0]}.0.0.0/255.0.0.0(rw,no_root_squash)" >> /etc/exports
    done
    rm -f /etc/exports.bkp

    # Enable and start resources for NFS
    systemctl enable rpcbind
    systemctl enable nfs-server
    systemctl enable nfs-lock
    systemctl enable nfs-idmap
    systemctl start rpcbind
    systemctl start nfs-server
    systemctl start nfs-lock
    systemctl start nfs-idmap

    # Restart NFS server and configure the firewall
    systemctl restart nfs-server
    set +o errexit
    firewall-cmd --permanent --zone=public --add-service=nfs
    firewall-cmd --reload
    set -o errexit

    logInfo "NFS successfully configured!"
  fi

  #
  logInfo "Validating PVs..."
  sh validatePV_NFS_YAML.sh --force fullPVs_NFS.yml

  # Create the PVs and PVCs:
  logInfo "Creating PVs and PVCs..."
  kubectl apply -f fullPVs_NFS.yml
  kubectl apply -f fullPVCs.yml

  # Ensure the PVCs got bound... (200 seconds of max time)
  i="1"
  ATTEMPTS=200
  while [ $i -lt $ATTEMPTS ]
  do
    PVCs_BOUND_N=$(kubectl get -f fullPVCs.yml | awk '{ print $2 }' | grep -v Bound | wc -l)
    if [[ $PVCs_BOUND_N -gt 1 ]]; then
      if [[ $(( i % 5 )) -eq 0 ]]; then
        logInfo "One or more PVCs not ready yet. Waiting #$i of $ATTEMPTS..."
      fi
      sleep 1
    else
      break
    fi
    let i=i+1
    if [[ i -eq 200 ]]; then
      kubectl get -f fullPVs_NFS.yml
      kubectl get -f fullPVCs.yml
      logErr "One or more PVs and PVCs never got status 'Bound' after $ATTEMPTS seconds. Exiting."
      exit 1
    fi
  done
  logIt ""
  logInfo "PVs and PVCs successfully configured!"
  kubectl get -f fullPVs_NFS.yml
  kubectl get -f fullPVCs.yml
  logIt ""

  logInfo "Done!"
}

downloadYmls() {
  LIST="fullPVs_NFS.yml fullPVCs.yml validatePV_NFS_YAML.sh"

  if [ ${useLocal} = false ]; then
    # Download the YML files with icci@us.ibm.com credentials:
    logInfo "Download YMLs..."
    TOKEN="0fc2408c6107bc7048e1f476f104c957972dd6af"
    OWNER="connections"
    REPO="deploy-services"

    for file in ${LIST}; do
	PATH_FILE="microservices/hybridcloud/doc/samples/${file}"
	FILE="https://github.ibm.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
	curl -H "Authorization: token $TOKEN" \
	-H "Accept: application/vnd.github.v3.raw" \
	-O \
	-L $FILE
    done
  else
    echo "Use local scripts"
    for file in ${LIST}; do
	if [ ! -f ${file} ]; then
		if [ -f microservices/hybridcloud/doc/samples/${file} ]; then
			cp -p microservices/hybridcloud/doc/samples/${file} .
		else
			echo "Can't find ${file}"
			exit 11
		fi
	fi
    done
  fi

  if [ ${ha} = false ]; then
    # add the NFS Server IP
    sed -i "s/___NFS_SERVER_IP___/$(hostname -i)/g" fullPVs_NFS.yml
  fi
}

# must be root/sudo
if [[ $(id -u) -ne 0 ]]; then
  logErr "Please run as root"
  exit 1
fi

logInfo "Argument list:  $*"

# Run a command to be sure you're logged
number_retries=30
retry_wait_time=5
counter=1
set +o errexit
while [ ${counter} -le ${number_retries} ]; do
	logInfo "Checking PVs... (${counter}/${number_retries})"
	kubectl get pv
	exit_status=$?
	if [ ${exit_status} -ne 0 ]; then
		echo "Not ready yet, retrying in ${retry_wait_time}s"
		sleep ${retry_wait_time}
		counter=`expr ${counter} + 1`
	else
		echo "Ready to run PV and PVC setup scripts"
		break
	fi
done
if [ ${exit_status} -ne 0 ]; then
	# kubectl will print the error message
	exit 1
fi
set -o errexit

while test $# -gt 0
do
    key="$1"
    case $key in
        -f | --force) logInfo "Script performed with -f/--force. PVCs existent will be recreated."
                      downloadYmls
                      force
                      exit 0
                      ;;
        -uZ | --useZip) logInfo "Use local PV and PVC setup scripts."
                      useLocal=true
                      ;;
        -hA | --highA) logInfo "Use a storage server for this deployment. Must use local zip"
                      useLocal=true
                      ha=true
                      ;;
	*) usage
                      exit 0
                      ;;
    esac
    shift
done

downloadYmls
# Check if PV/PVCs already exist
set +o pipefail
PVs_N=$(kubectl get -f fullPVs_NFS.yml | wc -l) &> /dev/null
PVCs_N=$(kubectl get -f fullPVCs.yml | wc -l) &> /dev/null
set -o pipefail

if [ "$PVs_N" -gt 0 ] || [ "$PVCs_N" -gt 0 ] ; then
  logIt ""
  logErr "One or more PVs/PVCs already exist. If you want to recreate them, please use -f or --force argument. Use -h or --help for usage instructions. Exiting."
  logIt ""
  exit 1
fi

# Check if directories already exist
VOLUMES=$(cat fullPVs_NFS.yml | grep path: | awk '{ print $2 }')
for VOLUME in $VOLUMES; do
  if [ -d "$VOLUME" ]; then
    logIt ""
    logErr "Directory $VOLUME already exist. If you want to recreate them, please use -f or --force argument. Use -h or --help for usage instructions. Exiting."
    logIt ""
    exit 1
  fi
done

# create the Volumes' folder, PVs and PVCs
createAndSetUpVolumes

