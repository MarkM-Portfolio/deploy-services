##############################################################################################
#
# IBM Confidential
#
# OCO Source Materials
#
# Unique Identifier = L-MSCR-7BCD3
#
# (c) Copyright IBM Corp. 2008
# The source code for this program is not published or other-
# wise divested of its trade secrets, irrespective of what has
# been deposited with the U.S. Copyright Office.
##############################################################################################

import sys,re,os,time,logging,logging.handlers,traceback,base64,shutil
from mako.template import Template
from optparse import OptionParser
from deploymentutils import aws
from deploymentutils import k8s
from deploymentutils import microservices
from deploymentutils import metadata
from deploymentutils import utils
from deploymentutils import config
from deploymentutils import properties


#---------------------------------------------------------------------------------------------
# Main
#---------------------------------------------------------------------------------------------

#Set variables
logFile = '/tmp/%s.log' % (sys.argv[0].replace('.py',''))
timestamp = str(time.strftime('%Y%m%d.%H%M%S',time.localtime()))
assetsDir = '/home/centos/kube-assets'
s3PrivateKeyBucket = 'connectionsCloud-connections-<env>.keys'
s3PrivateKeyFiles = []
s3PrivateCerts = []
k8s.assetsDir = assetsDir
microservices.microservicesDir = '/usr/local/git/deploy-services/microservices/connections'
microservicesToDeploy = None


#Parse the input options
parser = OptionParser()
parser.add_option("--environmentName", dest="environmentName", help="The name of the environment.  Example: 'Beta'")
parser.add_option("--bucket", dest="bucket", help="The S3 bucket.  Default: 'connectionsCloud-connections-<env>.keys'")
parser.add_option("--microservices", dest="microservices", help="The microservices to deploy. If not specified, all microservices under microservices/connections/templates will be deployed.")
parser.add_option("-d", "--debug", dest="debug", action="store_true", help="Enable debugging")
parser.add_option("-i", "--insecure", dest="insecure", action="store_true", help="Do not cleanup confidential files (to debug issues)")
(options, args) = parser.parse_args()

#Setup a logger
logger = logging.getLogger('root')
if options.debug:
   logger.setLevel(logging.DEBUG)
else:
   logger.setLevel(logging.INFO)
formatter = logging.Formatter('[%(asctime)-15s] [%(threadName)s] %(levelname)s %(message)s')
handler = logging.handlers.RotatingFileHandler(logFile, backupCount=10, maxBytes=10240000)
handler.setFormatter(formatter)
logger.addHandler(handler)
handler = logging.StreamHandler()
handler.setFormatter(formatter)
logger.addHandler(handler)
config.logger = logger

if not options.environmentName and not options.bucket:
   raise Exception('Argument --environmentName or --bucket required.  Execute -h for usage')

if options.bucket:
   s3PrivateKeyBucket = options.bucket
else:
   s3PrivateKeyBucket = s3PrivateKeyBucket.replace("<env>", options.environmentName)
   logger.info('Argument --bucket not provided.  Assuming "%s"...' % (s3PrivateKeyBucket))

if options.microservices:
   microservicesToDeploy = map(str.strip, options.microservices.split(','))

#Note the input args and save to a file to easily re-run
logger.info('Called with args: %s' % (sys.argv))
if not os.path.exists('/home/centos/deployConnections.sh'):
   f = open('/home/centos/deployConnections.sh','w')
   f.write('cd %s; python -u %s' % (os.path.dirname(os.path.abspath(__file__)),' '.join(sys.argv)))
   f.close()

environmentProperties = properties.Properties(contents=aws.decryptData(aws.downloadDataFromS3(s3PrivateKeyBucket,'environment.properties')))

#Get the ECR login and set a login secret.  This replaces: auto_token_generation.sh
#TODO:  Update myregkey to something that makes sense such as ecrlogin or dockerlogin.  If changed every .yml file needs to be updated
ecrServer,ecrUsername,ecrPassword = aws.getECRLogin()
k8s.setECRLoginSecret('myregkey',ecrServer,ecrUsername,ecrPassword)

template = Template(filename='../microservices/connections/environment/config.yml').render(environment=environmentProperties.getProperties())

open('/tmp/config.yml','w').write(template)
k8s.create('/tmp/config.yml','configmap','connections-env')
if not options.insecure:
   os.unlink('/tmp/config.yml')

deploymentProperties = {
   'environment': options.environmentName
} 


microservices.generateManifests(deploymentProperties, microservicesToDeploy)
microservices.createFromManifests('service')
microservices.createFromManifests('deployment')

route53HostedZoneId = aws.getRoute53HostedZoneId(environmentProperties.getProperty('publicDomainName'))
logger.info('Route53 hosted zone id: %s' % (route53HostedZoneId))

for service in k8s.getServiceNames():
   loadBalancerData = k8s.getLoadBalancerData(service)
   if loadBalancerData:
       aws.addRoute53CNAMERecord(route53HostedZoneId,'%s.%s.%s' % (loadBalancerData['hostname'], environmentProperties.getProperty('environmentName'), environmentProperties.getProperty('publicDomainName')),loadBalancerData['ingress'])

logger.info('Execution complete')
