# deploy-services
Code for deploying/seeding the OrientMe kubernetes container-based application stack on top of an existing kubernetes installation.

## Best Practices
1.  As per the [Kubernetes Best practices] write the config files in YAML, not JSON where appropriate
2.  All pull requests must be reviewed

[Kubernetes Best practices]: http://kubernetes.io/docs/user-guide/config-best-practices/

## Initial Setup
A one-time step is required for each environment to seed the required private / confidential data, which includes:

   1.  Mongo credentials and keyfile
   2.  New Relic license keys and ids
   3.  Public and private keys for internal use
   4.  Public and private keys for nginx
   
To seed the data refer to the README file in the setup folder for instructions.

## Deploy OrientMe

   1.  Deploy OrientMe:  TBD
   
***

## Under the Hood
 
boto3:  The AWS SDK for Python boto3 module is a prerequisite for deploymentutils.  Refer to https://github.com/boto/boto3 or simply install from source via:

    $ wget https://pypi.python.org/packages/d9/6c/1063a4984d13f1b22edb30f3b97b6df7e0bdc7792ebc2f638b31f8b2ff79/boto3-1.3.1.tar.gz#md5=e6be09a90230390640873979702dd6da
    $ tar -zxvf boto3-1.3.1.tar.gz 
    $ cd boto3-1.3.1
    $ python setup.py build
    $ python setup.py install

#### Connections Utils Quick Start
First, install the library:

    $ python setup.py install

Then, from a Python interpreter:

    >>> from deploymentutils import aws
    >>> from deploymentutils import k8s
    >>> from deploymentutils import utils
    >>> hostedZoneId = aws.getRoute53HostedZoneId('connectionsadmin.com')
    >>> k8s.waitForNodesToBeAvailabile()
    >>> utils.executeCommand('kubectl get pods')
    
