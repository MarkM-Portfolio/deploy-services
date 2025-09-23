#!/bin/bash -
#title           :mongodb-nfs-volumes-creation.sh
#description     :This script must be used only in test environments.
#                 It will create PVs to be used by Mongo in K8s cluster on CFC.
#version         :0.1
#usage		       :bash mongodb-nfs-volumes-creation.sh
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

usage() {
  logIt ""
  logIt "Usage: ./mongodb-nfs-volumes-creation.sh [OPTION]"
  logIt "Must not be used in production. It will do:"
  logIt "Install and set up a basic NFS server configuration"
  logIt "Create the pv.yml of: https://github.ibm.com/connections/deploy-services/tree/master/microservices/hybridcloud/templates/mongodb"
  logIt ""
  logIt "-f, --force   If PVs or PVCs already exist, it will recreate it, removing all current data."
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
  {
    kubectl delete -f pvc.yml
    kubectl delete -f pv.yml
  } &> /dev/null

  # Clean up Volumes, and map them for NFS
  logInfo "Configuring NFS..."
  touch /etc/exports #If not exist, will create
  cp -n /etc/exports /etc/exports.bkp
  IFS='\.' read -a DEC_IP <<< "$(hostname -i)"
  VOLUMES=$(cat pv.yml | grep path: | awk '{ print $2 }')
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
  firewall-cmd --permanent --zone=public --add-service=nfs
  firewall-cmd --reload

  logInfo "NFS successfully configured!"

  # Create the PVs and PVCs:
  logInfo "Creating PVs..."
  kubectl apply -f pv.yml

  # Ensure the PVs got ready... (200 seconds of max time)
  i="1"
  ATTEMPTS=200
  while [ $i -lt $ATTEMPTS ]
  do
    PVs_AVAILABLE_N=$(kubectl get -f pv.yml | grep -v Available | wc -l)
    if [[ $PVs_AVAILABLE_N -gt 1 ]]; then
      if [[ $(( i % 5 )) -eq 0 ]]; then
        logInfo "One or more PVs not ready yet. Waiting..."
        logInfo "One or more PVs not ready yet. Waiting #$i of $ATTEMPTS..."
      fi
      sleep 1
    else
      break
    fi
    let i=i+1
    if [[ i -eq 200 ]]; then
      kubectl get -f pv.yml
      kubectl get -f pvc.yml
      logErr "One or more PVs and PVCs never got status 'Bound' after $ATTEMPTS seconds. Exiting."
      exit 1
    fi
  done
  logIt ""
  logInfo "PVs successfully configured!"
  kubectl get -f pv.yml
  logIt ""

  logInfo "Done!"
}

downloadYmls() {
  # Download the YML files with icci@us.ibm.com credentials:
  logInfo "Download YMLs..."
  TOKEN="0fc2408c6107bc7048e1f476f104c957972dd6af"
  OWNER="connections"
  REPO="mongodb"
  PATH_FILE="deployment/kubernetes/pv.yml"
  FILE="https://github.ibm.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
  curl -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github.v3.raw" \
  -O \
  -L $FILE
  PATH_FILE="deployment/kubernetes/pvc.yml"
  FILE="https://github.ibm.com/api/v3/repos/$OWNER/$REPO/contents/$PATH_FILE"
  curl -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github.v3.raw" \
  -O \
  -L $FILE

  # add the NFS Server IP
  sed -i "s/___NFS_SERVER_IP___/$(hostname -i)/g" pv.yml
}

# must be root/sudo
if [[ $(id -u) -ne 0 ]]; then
  logErr "Please run as root"
  exit 1
fi

# Run a command to be sure you're logged
logInfo "Checking PVs..."
kubectl get pv
if [ $? -ne 0 ]; then
  # kubectl will print the error message
  exit 1
fi

while test $# -gt 0
do
    case "$1" in
        -f | --force) logInfo "Script performed with -f/--force. PVCs existent will be recreated."
                      downloadYmls
                      force
                      exit 0
                      ;;
                   *) usage
                      exit 0
                      ;;
    esac
    shift
done

downloadYmls
# Check if PV/PVCs already exist
{
  PVs_N=$(kubectl get -f pv.yml | wc -l)
  PVCs_N=$(kubectl get -f pvc.yml | wc -l)
} &> /dev/null

if [ "$PVs_N" -gt 0 ] || [ "$PVCs_N" -gt 0 ] ; then
  logIt ""
  logErr "One or more PVs/PVCs already exist. If you want to recreate them, please use -f or --force argument. Use -h or --help for usage instructions. Exiting."
  logIt ""
  exit 1
fi

# Check if directories already exist
VOLUMES=$(cat pv.yml | grep path: | awk '{ print $2 }')
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
