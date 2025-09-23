#!/bin/bash

set -o pipefail

logErr() {
	logIt "ERRO: " "$@"
}

logInfo() {
	logIt "INFO: " "$@"
}

logIt() {
	echo "$@"
}

upgrade() {

	{
    kubectl delete svc redis
  	kubectl delete deploy redis
  } &> /dev/null

	kubectl create -f deploy_fromscript.yaml
}

upgrade

echo "Clean exit"
exit 0
