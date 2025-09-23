## Scripts

## configureRedis.sh
This script configures Redis for OnPrem. Setting the Highway settings for Redis Host, Redis Port and if applicable Redis Password.

## configureReverseProxy.sh
This script configures the /social redirect for Orientme to OnPrem Connections environments. Giving it a base for the new Connections features.

## createZip.sh
This script will create a Zip containing saved images, configuration files and scripts for use by OnPrem Customers using Orient Me in their organisation.

## deployConnections.py

## deployPinkCFC.sh
This script will orchestrate a Pink Deployment onto CFC.  Download Latest Zip, Deploy CFC, Provision storage, Deploy Pink

## getLatestZip.sh
This script will download the latest HybridCloud Zip from Artifactory

## mongodb-nfs-volumes-creation.sh
This script must be used only in test environments. It will create PVs to be used by Mongo in K8s cluster on CFC

## solr-nfs-volumes-creation.sh
This script must be used only in test environments. It will create PVs and PVCs to be used by Solr in K8s cluster on CFC.

## zookeeper-nfs-volumes-creation.sh
This script must be used only in test environments. It will create PVs and PVCs to be used by zookeeper in K8s cluster on CFC

## persistent-storage-wrapper.sh 
This script will run all Persistent Storage Volume creation scripts 