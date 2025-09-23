#!/bin/bash -
#title           :logging.sh
#description     :Bash logging lib.
#version         :0.1
#usage           :source logging.sh
#==============================================================================
#!/bin/bash

logIt() { echo "$(date +[%d/%m/%Y" "%T" "%Z]) $@"; }
logInfo() { logIt "INFO: " "$@"; }
logErr() { logIt "ERROR: " "$@"; }
