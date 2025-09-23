#!/bin/bash

set -o errexit
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
	
	echo "Hello"	
}



upgrade

echo "Clean exit"
exit 0
