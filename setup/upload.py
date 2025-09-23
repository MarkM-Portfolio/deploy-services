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

import sys,re,os,time,logging,logging.handlers,traceback
from optparse import OptionParser
from deploymentutils import config
from deploymentutils import aws

#---------------------------------------------------------------------------------------------
# Main
#---------------------------------------------------------------------------------------------

#Set variables
logFile = '/tmp/%s.log' % (sys.argv[0].replace('.py',''))
timestamp = str(time.strftime('%Y%m%d.%H%M%S',time.localtime()))
bucket = 'connectionsCloud-connections-<env>.keys'
fileLocation = '../microservices/connections/environment'

#Parse the input options
parser = OptionParser()
parser.add_option("--environmentName", dest="environmentName", help="The name of the environment.  Example: 'Beta'")
parser.add_option("--fileLocation", dest="fileLocation", help="The directory that contains the files to encrypt and upload.  Default: '../microservices/connections/environment'")
parser.add_option("--kmsArn", dest="kmsArn", help="The KMS ARN to encrypt the file contents with")
parser.add_option("--bucket", dest="bucket", help="The S3 bucket.  Default: 'connectionsCloud-connections-<env>.keys'")
parser.add_option("-d", "--debug", dest="debug", action="store_true", help="Enable debugging")
(options, args) = parser.parse_args()

#Setup a logger
logger = logging.getLogger('root')
if options.debug:
   logger.setLevel(logging.DEBUG)
else:
   logger.setLevel(logging.INFO)
formatter = logging.Formatter('[%(asctime)-15s] [%(threadName)s] %(levelname)s %(message)s')
handler = logging.StreamHandler()
handler.setFormatter(formatter)
logger.addHandler(handler)
config.logger = logger

logger.info('Called with args: %s' % (sys.argv))

if not options.environmentName:
   raise Exception('Argument --environmentName required.  Execute -h for usage')
if not options.kmsArn:
   raise Exception('Argument --kmsArn required.  Execute -h for usage')

#Normalize variables
if options.fileLocation:
   fileLocation = options.fileLocation.rstrip('/')
else:
   logger.info('Argument --fileLocation not provided.  Assuming "%s"...' % (fileLocation))
if options.bucket:
   bucket = options.bucket
else:
   bucket = bucket.replace("<env>", options.environmentName)
   logger.info('Argument --bucket not provided.  Assuming "%s"...' % (bucket))

#Create the bucket
aws.createS3Bucket(bucket)

#Define the files to encrypt and upload
filenames = []
filenames.append('environment.properties')

#Make sure all of the files exist before attempting to upload
for filename in filenames:
   logger.info('Looking for file %s/%s...' % (fileLocation,filename))
   if os.path.exists('%s/%s' % (fileLocation,filename)):
      logger.info('Found file %s' % (filename))
   else:
      raise Exception('File %s missing in location %s.  Please create and re-run' % (filename,fileLocation))

#Encrypt and upload the files
for filename in filenames:
   aws.encrypteAndUploadFileToS3(options.kmsArn,bucket,'%s' % (filename),'%s/%s' % (fileLocation,filename))

logger.info('Execution complete')
