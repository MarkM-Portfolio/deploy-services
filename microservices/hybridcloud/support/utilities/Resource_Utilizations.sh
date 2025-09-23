#!/bin/bash
# Initial author: on Thursday June 4 15:26:49 GMT 2020
#
# History:
# --------
# Thursday June 4 15:26:49 GMT 2020
#	Initial version
#
#
>logfile.md
echo -e "\n\n---------------------------------------------------"
echo "|Please wait. writing logs in logfile.md in CWD...|"
echo -e "---------------------------------------------------"
{
# script contents here
echo -e "#################### PERSISTENT VOLUME TYPE ###############################################\n"
kubectl describe pv "$(kubectl get pv|head -2|grep -v NAME|awk '{print $1}')"|grep Type
echo -e "\n================="
echo "Get all PV --"
echo "================="
kubectl get pv -n connections
echo -e "\n================="
echo "Get all PVC --"
echo "================="
kubectl get pvc -n connections
echo -e "\n###################################################################################################################################################################\n"
echo -e "###################################################################################################################################################################\n"
echo "================="
echo "Get All Nodes..."
echo -e "=================\n"
kubectl get nodes
echo -e "\n###################################################################################################################################################################\n"
echo "###################################################################################################################################################################"
echo "====================="
echo "Get All Namespaces..."
echo -e "=====================\n"
kubectl get namespaces
echo -e "\n###################################################################################################################################################################\n"
echo "###################################################################################################################################################################"
echo "========================================"
echo "Get All PODs in Connections Namespace..."
echo -e "========================================\n"
kubectl get pods -n connections
echo -e "\n###################################################################################################################################################################\n"
echo "###################################################################################################################################################################"
echo "================="
echo "Get All Events..."
echo "================="
kubectl get events --sort-by=.metadata.creationTimestamp -n connections
echo -e "\n###################################################################################################################################################################\n"
echo -e "###################################################################################################################################################################\n"

helm_v=$(echo `helm version 2>&1 | grep 'version' 2>&1|cut -d: -f3|cut -d, -f1`)
echo -e "#################### HELM #########################################################################################################################################\n"
echo -e "helm version is..${helm_v}\n"
echo -e "Helm Charts List.."
echo -e "=================\n"
helm ls
echo -e "\n###################################################################################################################################################################\n"
echo -e "#################### DISK USAGE WORKER NODES ###############################################\n"
servers=$(kubectl get node|grep -v master|grep -v NAME|awk '{print $1}'|sed ':a;N;$!ba;s/\n/ /g')
echo "Total Number of Worker Nodes = $(echo ${servers[@]}|sed "s/ /\n/g"|wc -l)"
for server in $servers; do
  echo "------------------------------------------------------"
  echo "================================================================"
  echo "Worker Node Disk Utilization : $server ..."
  echo "================================================================"
  ssh -o LogLevel=QUIET -tt $server 'df -Ph'
  echo -e "\n------------------------------------------------------"
done
echo -e "\n############################################################################################\n"

echo "######################################################################################"
echo "#      Checking the health status of Deployment and resources assosiated with it     #"
echo -e "######################################################################################\n"
echo -e "Analysing POD distribution per node..\n"
echo "POD Distribution For :  analysisservice"
echo "======================================="
kubectl get po -n connections -l app=analysisservice,mService=analysisservice,name=analysisservice -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  appregistry-client"
echo "======================================="
kubectl get po -n connections -l app=appregistry-client,mService=appregistry-client -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  appregistry-service"
echo "======================================="
kubectl get po -n connections -l app=appregistry-service,mService=appregistry-service -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  cnx-ingress"
echo "======================================="
kubectl get po -n connections -l app=cnx-ingress,chart=cnx-ingress,component=controller,heritage=Helm,mService=cnx-ingress,release=cnx-ingress -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  community-suggestions"
echo "======================================="
kubectl get po -n connections -l app=community-suggestions,mService=community-suggestions,name=community-suggestions -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  elasticsearch-client"
echo "======================================="
kubectl get po -n default -l app=elasticsearch-client,chart=elasticsearch,heritage=Helm,release=elasticstack   -o wide | grep elasticsearch|awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  elasticsearch-master"
echo "======================================="
kubectl get po -n default -l app=elasticsearch-master,chart=elasticsearch,heritage=Helm,release=elasticstack  -o wide | grep elasticsearch|awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  haproxy"
echo "======================================="
kubectl get po -n connections -l heritage=Helm,mService=haproxy,name=haproxy,release=infrastructure -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  indexingservice"
echo "======================================="
kubectl get po -n connections -l app=indexingservice,mService=indexingservice,name=indexingservice -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"  
echo -e "\nPOD Distribution For :  itm-services"
echo "======================================="
kubectl get po -n connections -l app=itm-services,mService=itm-services,release=orientme -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  kibana"
echo "======================================="
kubectl get po -n default -l app=kibana,release=elasticstack  -o wide | grep kibana|awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  mail-service"
echo "======================================="
kubectl get po -n connections -l app=mail-service,mService=mail-service  -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  middleware-graphql"
echo "======================================="
kubectl get po -n connections -l app=middleware-graphql,mService=middleware-graphql,name=middleware-graphql -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  mongodb"
echo "======================================="
kubectl get po -n connections -l app=mongo,chart=mongodb,heritage=Helm,mService=mongodb,release=infrastructure,role=mongo-rs -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  mw-proxy"
echo "======================================="
kubectl get po -n connections -l name=mw-proxy -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  orient-web-client"
echo "======================================="
kubectl get po -n connections -l app=orient-web-client,mService=orient-web-client,name=orient-web-client -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  people-idmapping"
echo "======================================="
kubectl get po -n connections -l app=people-idmapping,mService=people-idmapping -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  people-migrate"
echo "======================================="
kubectl get po -n connections -l app=people-migrate,mService=people-migrate -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  people-relation"
echo "======================================="
kubectl get po -n connections -l app=people-relation,mService=people-relation -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  people-scoring"
echo "======================================="
kubectl get po -n connections -l app=people-scoring,mService=people-scoring -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  redis-sentinel"
echo "======================================="
kubectl get po -n connections -l app=redis-sentinel,chart=redis-sentinel,heritage=Helm,mService=redis-sentinel,release=infrastructure -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  retrievalservice"
echo "======================================="
kubectl get po -n connections -l app=redis-server,chart=redis,heritage=Helm,mService=redis-server,release=infrastructure -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  retrievalservice"
echo "======================================="
kubectl get po -n connections -l app=retrievalservice,mService=retrievalservice,name=retrievalservice -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  sanity"
echo "======================================="
kubectl get po -n connections -l app=sanity,mService=sanity,release=sanity -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  sanity-watcher"
echo "======================================="
kubectl get po -n connections -l app=sanity-watcher,chart=sanity-watcher,heritage=Helm,mService=sanity-watcher,release=sanity-watcher -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  solr"
echo "======================================="
kubectl get po -n connections -l app=solr,chart=solr-basic,heritage=Helm,mService=solr,release=orientme -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo -e "\nPOD Distribution For :  zookeeper"
echo "======================================="
kubectl get po -n connections -l app=zookeeper,chart=zookeeper,heritage=Helm,mService=zookeeper,release=orientme -o wide | awk '{print $7, ":", $1, ":", $2}'|sed "s/\/1//g"
echo
set -euo pipefail

echo -e "Iterating...\n"
#util() {
#    kubectl get nodes --no-headers | awk '{print $1}' | xargs -I {} sh -c 'echo {} ; kubectl describe node {} | grep Allocated -A 5 | grep -ve Event -ve Allocated -ve percent -ve -- ; echo '
#}

echo -e "\n######################################################################################"
echo "#      Checking the pods with max restarts                                           #"
echo -e "######################################################################################\n"
kubectl get pods -n connections --sort-by='.status.containerStatuses[0].restartCount'|grep -v "Running     0"|grep -v "Completed   0"
echo -e "\n######################################################################################\n"
echo "######################################################################################"
echo "#      DDescribing the pods with max restarts                                           #"
echo -e "######################################################################################\n"

restartedpods=$(kubectl get pods -n connections --sort-by='.status.containerStatuses[0].restartCount'|grep -v "Running     0"|grep -v "Completed   0"|awk '{print $1}'|grep -v NAME| sed ':a;N;$!ba;s/\n/ /g')

for pd in $restartedpods; do
  echo "------------------------------------------------------"
  echo "================================================================"
  echo "Describe Restarted pod...$pd"
  echo "================================================================"
  kubectl describe pod $pd -n connections
  echo -e "\n------------------------------------------------------"
done
echo -e "\n######################################################################################"


nodes=$(kubectl get node --no-headers -o custom-columns=NAME:.metadata.name)

pod_with_issues() {
	echo "==========================================="
	echo "==========================================="
        echo -e "Pods not in Running or Completed State:..."
	echo "==========================================="
	echo "========================================================================================="
        kubectl get pods --all-namespaces --field-selector=status.phase!=Running | grep -v Completed
        }

top_mem_pods() {
	echo "==========================================="
	echo "==========================================="
        echo -e "Top Pods According to Memory Limits:..."
	echo "==========================================="
	echo "==========================================="
        for node in $(kubectl get node | awk {'print $1'} | grep -v NAME)
        do kubectl describe node $node | sed -n "/Non-terminated Pods/,/Allocated resources/p"| grep -P -v "terminated|Allocated|Namespace"
        done | grep '[0-9]G' | awk -v OFS=' \t' '{if ($9 >= '2Gi') print $2," ", $9}' | sort -k2 -r | column -t

        }
top_cpu_pods() {
	echo "==========================================="
	echo "==========================================="
        echo -e "Top Pods According to CPU Limits:..."
	echo "==========================================="
	echo "==========================================="
        for node in $(kubectl get node | awk {'print $1'} | grep -v NAME)
        do kubectl describe node $node | sed -n "/Non-terminated Pods/,/Allocated resources/p" | grep -P -v "terminated|Allocated|Namespace"
        done | awk -v OFS=' \t' '{if ($5 ~/^[2-9]+$/) print $2, $5}' | sort -k2 -r | column -t
        }


for node in $nodes; do
  echo -e "\n############################################################################################"
  echo "############################################################################################"
  echo "Node Utilization : $node ...\n"
  echo "############################################################################################"
  echo -e "############################################################################################\n"
  kubectl describe node "$node" | sed '1,/Non-terminated Pods/d'
  pod_with_issues
  echo -e "=========================================================================================\n"
  top_mem_pods
  echo -e "===========================================\n"
  top_cpu_pods
  echo -e "===========================================\n\n"
  echo -e "###########################End Of Node Utilization : $node##########################\n"
done

} > logfile.md &  >/dev/null 2>&1 2> /dev/null
for ((i = 0 ; i <= 100 ; i+=2)); do     echo -ne "▓\e[s] ($i%)\e[u";     sleep 1; done
echo -e "\n\n\n`date`:Cluster Logs are ready.\n\n"''
