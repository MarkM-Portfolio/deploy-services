#!/bin/bash

sed -i "s/enabled=0/enabled=1/g" /etc/yum.repos.d/kubernetes.repo

echo -e "\nChecking existing version of Kubernetes on your system...."
k8_version=$(rpm -q --queryformat '%{VERSION}' kubeadm|cut -d: -f1|cut -d. -f1,2)
echo -e "\n$k8_version"

if [[ "$k8_version" = "1.11" ]];then

    echo -e "\nkubeadm version is "$k8_version" upgrading to 1.12.10"
    yum upgrade -y kubeadm-1.12.10-0 --disableexcludes=kubernetes;
    sleep 10

    echo -e "\nkubeadm version is now `rpm -q --queryformat '%{VERSION}' kubeadm|cut -d: -f1`"
    echo -e "\napplying upgrade to set K8s version 1.12.10"
    kubeadm upgrade apply v1.12.10 -y;
    sleep 10

    echo -e "\nDraining the Master..."
    kubectl drain conn03cp.cnx.cwp.pnp-hcl.com --ignore-daemonsets=true --force --delete-local-data --timeout=2m;
    sleep 15

    array=$(kubectl get pods -n connections|grep -E -- 'redis-|cnx-ingress'|cut -d" " -f1|sed ':a;N;$!ba;s/\n/ /g')
    for t in ${array[@]} ; do 
        kubectl delete pod $t -n connections
    done

    sleep 15

    echo -e "\nUpgrading the Kubernetes kubeadm and kubelet package version ..."
    yum upgrade -y kubelet-1.12.10-0 kubeadm-1.12.10-0 kubectl-1.12.10-0 --disableexcludes=kubernetes;
    yum downgrade -y kubelet-1.12.10 kubeadm-1.12.10 kubectl-1.12.10-0 --disableexcludes=kubernetes;

    echo -e "\nRestarting kubelet..."
    systemctl daemon-reload;
    systemctl restart kubelet;
    sleep 15

    echo -e "\nUncordoning Master ..."
    kubectl uncordon conn03cp.cnx.cwp.pnp-hcl.com;
    sleep 30

    echo -e "\nVerifying if node is upgraded successfully.."
    des_version="1.12.10"
    cur_version=$(kubectl get nodes|awk '{ print $5 }'|grep -v VERSION|cut -c2-8)
    
    while [[ "$cur_version" != "$des_version" ]]
    do
        echo -e "\nK8s version NOT yet successfully updated FROM "$k8_version" to "$des_version" sleeping for 60 seconds"
    	sleep 10
    	if [[ "$cur_version" = "$des_version" ]];then
            echo -e "\nK8s version is successfully upgraded FROM "$k8_version" to "$des_version""
        else
            echo -e "\nK8s version DID NOT successfully upgraded FROM "$k8_version" to "$des_version""
        fi
    done

    if [[ "$cur_version" = "$des_version" ]];then
        echo -e "\nK8s version is successfully upgraded FROM "$k8_version" to "$des_version""
    else
        echo -e "\nK8s version DID NOT successfully upgraded FROM "$k8_version" to "$des_version""
    fi

    RPC=$(kubectl get pods --all-namespaces|grep -e 1/1 -e 2/2|wc -l)
    SECONDS=0
    for i in {1..25}
    do
      RPC=$(kubectl get pods --all-namespaces|grep -e 1/1 -e 2/2|wc -l);

	  if [ $RPC = 94 ]; then
	      break
	  fi

	  if [ $SECONDS = 1200 ]; then
	      break
	  fi
      echo "$SECONDS SECONDS SINCE UNCORDONED: Ready PODS count is $RPC < 94, sleeping for 40 seconds";
	  sleep 40
    done

elif [[ "$k8_version" = "1.12" ]];then

    echo -e "\nkubeadm version is "$k8_version" upgrading to 1.13.12"
    yum upgrade -y kubeadm-1.13.12-0 --disableexcludes=kubernetes;
    sleep 10

    echo -e "\nkubeadm version is now `rpm -q --queryformat '%{VERSION}' kubeadm|cut -d: -f1`"
    echo -e "\napplying upgrade to set K8s version 1.13.12"
    kubeadm upgrade apply v1.13.12 -y;
    sleep 10

    echo -e "\nDraining the Master..."
    kubectl drain conn03cp.cnx.cwp.pnp-hcl.com --ignore-daemonsets=true --force --delete-local-data --timeout=2m;
    sleep 15

    array=$(kubectl get pods -n connections|grep -E -- 'redis-|cnx-ingress'|cut -d" " -f1|sed ':a;N;$!ba;s/\n/ /g')
    for t in ${array[@]} ; do 
        kubectl delete pod $t -n connections
    done
    sleep 15

    echo -e "\nUpgrading the Kubernetes kubeadm and kubelet package version ..."
    yum upgrade -y kubelet-1.13.12-0 kubeadm-1.13.12-0 kubectl-1.13.12-0 --disableexcludes=kubernetes;
    yum downgrade -y kubelet-1.13.12 kubeadm-1.13.12 kubectl-1.13.12-0 --disableexcludes=kubernetes;

    echo -e "\nRestarting kubelet..."
    systemctl daemon-reload;
    systemctl restart kubelet;
    sleep 15

    echo -e "\nUncordoning Master ..."
    kubectl uncordon conn03cp.cnx.cwp.pnp-hcl.com;
    sleep 30

    echo -e "\nVerifying if node is upgraded successfully..."
    des_version="1.13.12"
    cur_version=$(kubectl get nodes|awk '{ print $5 }'|grep -v VERSION|cut -c2-8)

    while [[ "$cur_version" != "$des_version" ]]
    do
        echo -e "\nK8s version NOT yet successfully updated FROM "$k8_version" to "$des_version" sleeping for 60 seconds"
    	sleep 10
    	if [[ "$cur_version" = "$des_version" ]];then
            echo -e "\nK8s version is successfully upgraded FROM "$k8_version" to "$des_version""
        else
            echo -e "\nK8s version DID NOT successfully upgraded FROM "$k8_version" to "$des_version""
        fi
    done

    if [[ "$cur_version" = "$des_version" ]];then
        echo -e "\nK8s version is successfully upgraded FROM "$k8_version" to "$des_version""
    else
        echo -e "\nK8s version DID NOT successfully upgraded FROM "$k8_version" to "$des_version""
    fi

    RPC=$(kubectl get pods --all-namespaces|grep -e 1/1 -e 2/2|wc -l)
    SECONDS=0
    for i in {1..25}
    do
      RPC=$(kubectl get pods --all-namespaces|grep -e 1/1 -e 2/2|wc -l);

	  if [ $RPC = 94 ]; then
	      break
	  fi

	  if [ $SECONDS = 1200 ]; then
	      break
	  fi
      echo "$SECONDS SECONDS SINCE UNCORDONED: Ready PODS count is $RPC < 94, sleeping for 40 seconds";
	  sleep 40
    done

elif [[ "$k8_version" = "1.13" ]];then

    echo -e "\nkubeadm version is "$k8_version" upgrading to 1.14.10"
    yum upgrade -y kubeadm-1.14.10-0 --disableexcludes=kubernetes;
    sleep 10

    echo -e "\nkubeadm version is now `rpm -q --queryformat '%{VERSION}' kubeadm|cut -d: -f1`"
    echo -e "\napplying upgrade to set K8s version 1.14.10"
    kubeadm upgrade apply v1.14.10 -y;
    sleep 10

    echo -e "\nDraining the Master..."
    kubectl drain conn03cp.cnx.cwp.pnp-hcl.com --ignore-daemonsets=true --force --delete-local-data --timeout=2m;
    sleep 15

    array=$(kubectl get pods -n connections|grep -E -- 'redis-|cnx-ingress'|cut -d" " -f1|sed ':a;N;$!ba;s/\n/ /g')
    for t in ${array[@]} ; do 
        kubectl delete pod $t -n connections
    done
    sleep 15

    echo -e "\nUpgrading the Kubernetes kubeadm and kubelet package version ..."
    yum install -y kubelet-1.14.10-0 kubeadm-1.14.10 kubectl-1.14.10-0 --disableexcludes=kubernetes
    yum downgrade -y kubelet-1.14.10 kubeadm-1.14.10 kubectl-1.14.10 --disableexcludes=kubernetes
    
    echo -e "\nRestarting kubelet..."
    systemctl daemon-reload;
    systemctl restart kubelet;
    sleep 15

    echo -e "\nUncordoning Master ..."
    kubectl uncordon conn03cp.cnx.cwp.pnp-hcl.com;
    sleep 30

    echo -e "\nVerifying if node is upgraded successfully..."
    des_version="1.14.10"
    cur_version=$(kubectl get nodes|awk '{ print $5 }'|grep -v VERSION|cut -c2-8)

    while [[ "$cur_version" != "$des_version" ]]
    do
        echo -e "\nK8s version NOT yet successfully updated FROM "$k8_version" to "$des_version" sleeping for 60 seconds"
    	sleep 10
    	if [[ "$cur_version" = "$des_version" ]];then
            echo -e "\nK8s version is successfully upgraded FROM "$k8_version" to "$des_version""
        else
            echo -e "\nK8s version DID NOT successfully upgraded FROM "$k8_version" to "$des_version""
        fi
    done

    if [[ "$cur_version" = "$des_version" ]];then
        echo -e "\nK8s version is successfully upgraded FROM "$k8_version" to "$des_version""
    else
        echo -e "\nK8s version DID NOT successfully upgraded FROM "$k8_version" to "$des_version""
    fi

    RPC=$(kubectl get pods --all-namespaces|grep -e 1/1 -e 2/2|wc -l)
    SECONDS=0
    for i in {1..25}
    do
      RPC=$(kubectl get pods --all-namespaces|grep -e 1/1 -e 2/2|wc -l);

	  if [ $RPC = 94 ]; then
	      break
	  fi

	  if [ $SECONDS = 1200 ]; then
	      break
	  fi
      echo "$SECONDS SECONDS SINCE UNCORDONED: Ready PODS count is $RPC < 94, sleeping for 40 seconds";
	  sleep 40
    done

elif [[ "$k8_version" = "1.14" ]];then

    echo -e "\nkubeadm version is "$k8_version" upgrading to 1.15.10"
    yum upgrade -y kubeadm-1.15.10-0 --disableexcludes=kubernetes;
    sleep 10

    echo -e "\nkubeadm version is now `rpm -q --queryformat '%{VERSION}' kubeadm|cut -d: -f1`"
    echo -e "\napplying upgrade to set K8s version 1.15.10"
    kubeadm upgrade apply v1.15.10 -y;
    sleep 10

    echo -e "\nDraining the Master..."
    kubectl drain conn03cp.cnx.cwp.pnp-hcl.com --ignore-daemonsets=true --force --delete-local-data --timeout=2m;
    sleep 15

    array=$(kubectl get pods -n connections|grep -E -- 'redis-|cnx-ingress'|cut -d" " -f1|sed ':a;N;$!ba;s/\n/ /g')
    for t in ${array[@]} ; do 
        kubectl delete pod $t -n connections
    done
    sleep 15

    echo -e "\nUpgrading the Kubernetes kubeadm and kubelet package version ..."
    yum upgrade -y kubelet-1.15.10-0 kubeadm-1.15.10 kubectl-1.15.10-0 --disableexcludes=kubernetes
    yum downgrade -y kubelet-1.15.10 kubeadm-1.15.10 kubectl-1.15.10-0 --disableexcludes=kubernetes;

    echo -e "\nRestarting kubelet..."
    systemctl daemon-reload;
    systemctl restart kubelet;
    sleep 15

    echo -e "\nUncordoning Master ..."
    kubectl uncordon conn03cp.cnx.cwp.pnp-hcl.com;
    sleep 30

    echo -e "\nVerifying if node is upgraded successfully..."
    des_version="1.15.10"
    cur_version=$(kubectl get nodes|awk '{ print $5 }'|grep -v VERSION|cut -c2-8)

    while [[ "$cur_version" != "$des_version" ]]
    do
        echo -e "\nK8s version NOT yet successfully updated FROM "$k8_version" to "$des_version" sleeping for 60 seconds"
    	sleep 10
    	if [[ "$cur_version" = "$des_version" ]];then
            echo -e "\nK8s version is successfully upgraded FROM "$k8_version" to "$des_version""
        else
            echo -e "\nK8s version DID NOT successfully upgraded FROM "$k8_version" to "$des_version""
        fi
    done

    if [[ "$cur_version" = "$des_version" ]];then
        echo -e "\nK8s version is successfully upgraded FROM "$k8_version" to "$des_version""
    else
        echo -e "\nK8s version DID NOT successfully upgraded FROM "$k8_version" to "$des_version""
    fi

    RPC=$(kubectl get pods --all-namespaces|grep -e 1/1 -e 2/2|wc -l)
    SECONDS=0
    for i in {1..25}
    do
      RPC=$(kubectl get pods --all-namespaces|grep -e 1/1 -e 2/2|wc -l);

	  if [ $RPC = 94 ]; then
	      break
	  fi

	  if [ $SECONDS = 1200 ]; then
	      break
	  fi
      echo "$SECONDS SECONDS SINCE UNCORDONED: Ready PODS count is $RPC < 94, sleeping for 40 seconds";
	  sleep 40
    done

elif [[ "$k8_version" = "1.15" ]];then

    echo -e "\nkubeadm version is "$k8_version" upgrading to 1.16.7"
    yum upgrade -y kubeadm-1.16.7-0 --disableexcludes=kubernetes;
    sleep 10

    echo -e "\nkubeadm version is now `rpm -q --queryformat '%{VERSION}' kubeadm|cut -d: -f1`"
    echo -e "\napplying upgrade to set K8s version 1.16.7"
    kubeadm upgrade apply v1.16.7 -y || kubeadm upgrade apply v1.16.7 --ignore-preflight-errors=CoreDNSUnsupportedPlugins -y;
    sleep 10

    echo -e "\nDraining the Master..."
    kubectl drain conn03cp.cnx.cwp.pnp-hcl.com --ignore-daemonsets=true --force --delete-local-data --timeout=2m;
    sleep 15

    array=$(kubectl get pods -n connections|grep -E -- 'redis-|cnx-ingress'|cut -d" " -f1|sed ':a;N;$!ba;s/\n/ /g')
    for t in ${array[@]} ; do 
        kubectl delete pod $t -n connections
    done
    sleep 15

    echo -e "\nUpgrading the Kubernetes kubeadm and kubelet package version ..."
    yum upgrade -y kubelet-1.16.7-0 kubeadm-1.16.7 kubectl-1.16.7-0 --disableexcludes=kubernetes;
    yum downgrade -y kubelet-1.16.7 kubeadm-1.16.7 kubectl-1.16.7-0 --disableexcludes=kubernetes;

    echo -e "\nRestarting kubelet..."
    systemctl daemon-reload;
    systemctl restart kubelet;
    sleep 15

    echo -e "\nUncordoning Master ..."
    kubectl uncordon conn03cp.cnx.cwp.pnp-hcl.com;
    sleep 30

    echo -e "\nVerifying if node is upgraded successfully..."
    des_version="1.16.7"
    cur_version=$(kubectl get nodes|awk '{ print $5 }'|grep -v VERSION|cut -c2-8)

    while [[ "$cur_version" != "$des_version" ]]
    do
        echo -e "\nK8s version NOT yet successfully updated FROM "$k8_version" to "$des_version" sleeping for 60 seconds"
    	sleep 10
    	if [[ "$cur_version" = "$des_version" ]];then
            echo -e "\nK8s version is successfully upgraded FROM "$k8_version" to "$des_version""
        else
            echo -e "\nK8s version DID NOT successfully upgraded FROM "$k8_version" to "$des_version""
        fi
    done

    if [[ "$cur_version" = "$des_version" ]];then
        echo -e "\nK8s version is successfully upgraded FROM "$k8_version" to "$des_version""
    else
        echo -e "\nK8s version DID NOT successfully upgraded FROM "$k8_version" to "$des_version""
    fi

    RPC=$(kubectl get pods --all-namespaces|grep -e 1/1 -e 2/2|wc -l)
    SECONDS=0
    for i in {1..25}
    do
      RPC=$(kubectl get pods --all-namespaces|grep -e 1/1 -e 2/2|wc -l);

	  if [ $RPC = 94 ]; then
	      break
	  fi

	  if [ $SECONDS = 1200 ]; then
	      break
	  fi
      echo "$SECONDS SECONDS SINCE UNCORDONED: Ready PODS count is $RPC < 94, sleeping for 40 seconds";
	  sleep 40
    done

elif [[ "$k8_version" = "1.16" ]];then

    echo -e "\nkubeadm version is "$k8_version" upgrading to 1.17.2"
    yum upgrade -y kubeadm-1.17.2-0 --disableexcludes=kubernetes;
    sleep 10

    echo -e "\nkubeadm version is now `rpm -q --queryformat '%{VERSION}' kubeadm|cut -d: -f1`"
    echo -e "\napplying upgrade to set K8s version 1.17.2"
    kubeadm upgrade apply v1.17.2 -y;
    sleep 10

    echo -e "\nDraining the Master..."
    kubectl drain conn03cp.cnx.cwp.pnp-hcl.com --ignore-daemonsets=true --force --delete-local-data --timeout=2m;
    sleep 15

    array=$(kubectl get pods -n connections|grep -E -- 'redis-|cnx-ingress'|cut -d" " -f1|sed ':a;N;$!ba;s/\n/ /g')
    for t in ${array[@]} ; do 
        kubectl delete pod $t -n connections
    done
    sleep 15

    echo -e "\nUpgrading the Kubernetes kubeadm and kubelet package version ..."
    yum upgrade -y kubelet-1.17.2-0 kubeadm-1.17.2 kubectl-1.17.2-0 --disableexcludes=kubernetes;
    yum downgrade -y kubelet-1.17.2 kubeadm-1.17.2 kubectl-1.17.2-0 --disableexcludes=kubernetes;

    echo -e "\nRestarting kubelet..."
    systemctl daemon-reload;
    systemctl restart kubelet;
    sleep 15

    echo -e "\nUncordoning Master ..."
    kubectl uncordon conn03cp.cnx.cwp.pnp-hcl.com;
    sleep 30

    echo -e "\nVerifying if node is upgraded successfully..."
    des_version="1.17.2"
    cur_version=$(kubectl get nodes|awk '{ print $5 }'|grep -v VERSION|cut -c2-8)

    while [[ "$cur_version" != "$des_version" ]]
    do
        echo -e "\nK8s version NOT yet successfully updated FROM "$k8_version" to "$des_version" sleeping for 60 seconds"
    	sleep 10
    	if [[ "$cur_version" = "$des_version" ]];then
            echo -e "\nK8s version is successfully upgraded FROM "$k8_version" to "$des_version""
        else
            echo -e "\nK8s version DID NOT successfully upgraded FROM "$k8_version" to "$des_version""
        fi
    done

    if [[ "$cur_version" = "$des_version" ]];then
        echo -e "\nK8s version is successfully upgraded FROM "$k8_version" to "$des_version""
    else
        echo -e "\nK8s version DID NOT successfully upgraded FROM "$k8_version" to "$des_version""
    fi

    RPC=$(kubectl get pods --all-namespaces|grep -e 1/1 -e 2/2|wc -l)
    SECONDS=0
    for i in {1..25}
    do
      RPC=$(kubectl get pods --all-namespaces|grep -e 1/1 -e 2/2|wc -l);

	  if [ $RPC = 94 ]; then
	      break
	  fi

	  if [ $SECONDS = 1200 ]; then
	      break
	  fi
      echo "$SECONDS SECONDS SINCE UNCORDONED: Ready PODS count is $RPC < 94, sleeping for 40 seconds";
	  sleep 40
    done

fi
