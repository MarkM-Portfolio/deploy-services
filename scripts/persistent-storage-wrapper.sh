#! /bin/bash

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

bash mongodb-nfs-volumes-creation.sh $* && \
bash solr-nfs-volumes-creation.sh $* && \
bash zookeeper-nfs-volumes-creation.sh $*
exit $?

