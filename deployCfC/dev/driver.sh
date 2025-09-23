#! /bin/bash
# Initial author: on Sun Feb  5 15:26:49 GMT 2017
#
# History:
# --------
# Sun Feb  5 15:26:49 GMT 2017
#	Initial version
#
#

# bash 3.2 on Mac OS X 10.12 no longer compatible
#. ./00-all-config.sh
. `dirname "$0"`/dev.sh

bash `dirname "$0"`/copy.sh $*
ssh root@${BOOT} "echo 'echo \${TERMCAP} | grep -q screen; if [ \$? -ne 0 -a \"\${SUDO_USER}\" = \"\" ]; then echo run in screen; exit 1; fi' > ${DEPLOY_CFC_DIR}/exec.sh; echo $* > ${DEPLOY_CFC_DIR}/.last_args.txt; echo 'if [ ! -f \$1 ]; then bash ${DEPLOY_CFC_DIR}/deployCfC.sh $* \$*; else script=\$1; shift; bash \${script} \`cat ${DEPLOY_CFC_DIR}/.last_args.txt\` \$*; fi' >> ${DEPLOY_CFC_DIR}/exec.sh"
echo
echo "Run on boot node:  bash ${DEPLOY_CFC_DIR}/exec.sh"
echo

