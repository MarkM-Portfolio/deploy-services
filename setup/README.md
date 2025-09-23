## Prerequsites

   1.  Python 2.6 or higher
   2.  boto3 python module.  See [Under the Hood]
   3.  toscanautils python module:  See [Under the Hood]

[Under the Hood]: https://github.ibm.com/toscana/deploy-kubernetes#under-the-hood

## Instructions
   1.  Copy the setup directory to a secure location on the filesystem (such as /root)
   2.  Provide values in each of the files within the setup directory
   3.  Run:  python upload.py --kmsArn=<kmsarn> --environmentName=<environment>   
           eg python upload.py --kmsARN=arn:aws:kms:us-east-1:768118602852:key/5e290e20-c9d1-4762-8ae8-9760ee3f1ca3 --EnvironmentName=EndToEndTest
           EnvironmentName must match EXACTLY what you put in Environment Name in AWS for a new Deploy
   4.  Destroy the setup directory

## Manifest
   - newrelic:  New Relic license key,  Insights key, and Insights account id 
   - private.pem:  Run an "ssh-keygen -t rsa" to generate a new public and private key, name it private.pem
   - public.pem:  Run an "ssh-keygen -t rsa" to generate a new public and private key, name it public.pem