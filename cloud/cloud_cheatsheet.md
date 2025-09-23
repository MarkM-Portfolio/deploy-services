## Prereqs for going to Cloud

-    Be configured to run with at least 3 replicas (if the chart deploys containers)
-    Minimise the number of settings they expose in the Settings Git Repository
-    Define resource limits for memory and CPU
-    The application must run as a non-root user inside the container
-    The container must correctly handle the TERM signal that Kubernetes will send to PID 1 to facilitate pod shutdown without service disruption
-    The container must contain both liveness and readiness probes (Any exception e.g. sidecar must be approved by Bryan Osenbach)
-    Pods must be configured for auto-scaling unless it is deemed that it is not beneficial for the application
-    The values of any secrets that the chart exposes in the Settings Git Repository must change between environment
-    Your values.yaml must not contain sensitive data for secrets unless they are substituted by the Setting Git Repository
-    Create the tester application (Optional)
-    Yaml files associated with the Tester Images must have Resource Limits supplied
-    No K8s alpha resources on Production Cloud
-    SSO ID to access to Governor to submit requests : Request access to Governor
        - https://usam.svl.ibm.com:9443/AM/index.jsp
        - System : SSO-BU01-SB
        - Roles : 
           - To access Governor : [Governor-Product-cc] and [Governor-Product-cc-Requests] 
           - To access Kibana Infra Logs :  [G-Role-SB-Microservices-Connections]
		- Kibana-co-Infrastructure
		- Kibana-cc-I1
		- Kibana-cc-A3
		- Kibana-cc-IR3
		- Kibana-cc-S3
		- Kibana-cc-G3
           - For those chosen few to need to approve Governor Requests to D0 : Governor-Product-cc-Approvals-D0
 - There are 2 modes of deployment : Install and Upgrade
       
## Pipeline Requirements

What the Pipeline will do :
- Pipeline will auto build the tester image with the primary image using the same tag
- Pipeline will upload all built images to AWS
- Pipeline will upload the Helm Chart to AWS
- Pipeline will trigger an upgrade of the microservice (with default values)
- Pipeline will create a Helm Chart that includes the tag of the 'good build'.  No need to provide an image.tag substitiution
- Pipeine will automatically set the image repository to the AWS repo.  No need to provide an image.repository substitution
- Pipeline assumes no substitutions.  Pipeline cannot know about custom substitutions that a developer adds ad-hoc and thus will not deploy them.  Helm Chart should deploy to Cloud with default values

## What the Pipeline will not do:
- Pipeline will not register the Chart Set.  Each Squad is responsbile for managing on which environment their service is deployed to.  
- Pipeline will not Install a Chart.  Each Squad is reponsible for the first time installation of the Helm Charts and working feedback with the Cloud Operations team to get their service deployed.
- At this time, your Chart Set must not go beyond I1 (unless specifically requested)

## Configure your Repository for the Pipeline and Governor
 - as per https://github.ibm.com/connections/loopback-microservice-pack
  
## Configure your Chart Set
 - Browse to: https://www.governor.infrastructure.conncloudk8s.com/#/releasegroups
 - Click the + button
 - Choose the Environments.  Select I1
 - Enter the chart name e.g. haproxy  
 - Enter emails for notifications
 - Click Save

## Install your Helm Chart
Prereqs:
 - Know the Chart Name and Version of the Helm Chart you wish to Install.  
    - Discover this from the pipeline of the build you wish to deploy
    - e.g. In https://connjenk.swg.usma.ibm.com/jenkins/view/CNext/job/connections/job/haproxy/job/master/62/console, the Helm Chart created and uploaded to AWS was :  haproxy-0.1.0-1.7.5-20170915-163524.tgz
    - Thus :
        - Version is : 0.1.0-1.7.5-20170915-163524
        - Chart Name is : haproxy
            - NB : Chart Name must match the name given in the Chart set

Procedure
 - Browse to : https://www.governor.infrastructure.conncloudk8s.com/#/requests
 - Enter Username and Password (NB : This is your SSO Id above)
 - Select Action : Install
 - Set Product to : cc
 - Set Chart name as to what was created in the Chart set above e.g. haproxy
 - Set release to the name of your service.  e.g. haproxy (NB : Must be unique on the System you are deploying to)
 - Set Org to : connections
 - Set version to the Helm Chart version e.g. 0.1.0-1.7.5-20170915-163524
 - For first time install, you will need to supply the image.repository as a substitution (NB: Must be in json format)
	 - Substitutions
	    - key : image
	    - value :  { "repository": "905409959051.dkr.ecr.us-east-1.amazonaws.com/connections-docker" }
 - Environments : Set to I1

## Review with the Cloud Operations

## IBM Connections Pink Dependencies
https://github.ibm.com/cloud-operations/connections-cloud/tree/master/settings/connections <br />

Across our services, we are depandant on values set in the cloud operations repo: https://github.ibm.com/cloud-operations/connections-cloud/tree/master/settings <br />

Environment specific values, which will override the default values at deployment time <br />
 - ic_host <br />
 - newrelic enablement <br />
 - Resource settings e.g. CPU/Memory <br />
 - Passwords <br />

Without access to this repo, IBM Connections Pink Services will break.  e.g. Redis Password set in Pink must sync with the Redis Password set in Green <br />

## Accessing Cloud Environments
SSH to 
 - Use your SSO credentials

I1 : kubestarterpub.i1.conncloudk8s.com <br />
IR3 : kubestarterpub.ir3.conncloudk8s.com <br />
A3 : kubestarterpub.a3.conncloudk8s.com <br />
G3 : kubestarterpub.g3.conncloudk8s.com <br />
S3 : kubestarterpub.s3.conncloudk8s.com <br />

## Links

## Link to Governor
 - https://www.governor.infrastructure.conncloudk8s.com/#/pipelines <br />

## Links to NewRelic Dashboards
I1: 	https://rpm.newrelic.com/accounts/1142670/plugins/31009 <br />
IR3: 	https://rpm.newrelic.com/accounts/665801/plugins/31015 <br />
A3:	https://rpm.newrelic.com/accounts/587831/plugins/31017 <br />
S3:	https://rpm.newrelic.com/accounts/1361560/plugins/31018 <br />
G3:	https://rpm.newrelic.com/accounts/410367/plugins/31016 <br />

## Links to Kibana dashboards
I1: https://kibana.i1.conncloudk8s.com/app/kibana#/home?_g=() <br />
IR3: https://kibana.ir3.conncloudk8s.com/app/kibana#/home?_g=() <br />
A3: https://kibana.a3.conncloudk8s.com/app/kibana#/home?_g=() <br />
G3: https://kibana.g3.conncloudk8s.com/app/kibana#/home?_g=() <br />
S3: https://kibana.s3.conncloudk8s.com/app/kibana#/home?_g=() <br />

## Link to IBM Connections Pink Runbooks
https://github.ibm.com/cloud-operations/runbooks/tree/master/connection-cloud/Connections-Pink <br />

## Link to IBM Connections ElastAlerts
https://github.ibm.com/cloud-operations/elastalert-service/tree/master/rules/connections <br />
 - NB: Certain alerts will trigger a PagerDuty alert and a subsequent PTB/TB/SWAT.  Look for a pagerduty section in the alert.

## Slack Channels
ic-prod-alerts <br />
ic-preprod-alerts <br />

## FAQ / Notes

Q. What content MUST I include in my values.yaml file to satisfy Pipeline and Onprem requirements? <br />
A. 
```
namespace: connections
image:
    repository: artifactory.swg.usma.ibm.com:6562
    tag: latest    
```

Q. how could I connect to i1 Kubernetes <br />
A. SSH to kubestarterpub.i1.conncloudk8s.com <br />

NB: If a change is made to the environment settings e.g. https://github.ibm.com/cloud-operations/connections-cloud/blob/master/settings/connections/I1.yaml, any Helm Chart that consumes that value must be upgraded. <br />
This is especially important for the connections-env helm chart.  i.e. If you change a value in I1.yaml, that is consumed by the Config Map, that change will not make it into the Config Map until such point as the connections-env helm chart is refreshed. <br />

Q. How do I protect my external facing application in the Cloud <br />
A. Add the following annotation to your service yaml 
```
{{- if (and (not (empty .Values.deploymentType)) (eq .Values.deploymentType "cloud") ) }}
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-internal: 0.0.0.0/0
{{- end }}
```
e.g. https://github.ibm.com/connections/haproxy/blob/master/deployment/helm/haproxy/templates/service.yaml

Q. Is it possible to set up alerts on Kibana? <br />
A. we are using https://github.com/Yelp/elastalert/tree/master/example_rules but havent been able to get the kibanaplugin to work yet for you to configure your rules via the ui <br />
however, you can just add your alerts yaml files to https://github.ibm.com/cloud-operations/elastalert-service/tree/master/rules <br />
create a connections folder and add <nameOfRule>.yaml <br />
example at: https://github.ibm.com/cloud-operations/elastalert-service/blob/master/rules/infrastructure/example.yaml <br />
if you are using pager duty for your alerts, you need to set the service key in: <br />
https://github.ibm.com/cloud-operations/connections-cloud/tree/master/settings <br />
and update the placeholders in: https://github.ibm.com/cloud-operations/elastalert-service/blob/master/chart/elastalert/templates/secret.yaml#L16 <br />
and https://github.ibm.com/cloud-operations/elastalert-service/blob/master/chart/elastalert/templates/deployment.yaml#L40 <br />

Q. How can I get more debug information from K8s <br />
A. kubectl -n connections get events

Q. What are the Resource limits on the Cloud <br />
A. Cloud Operations define namespace limits : https://github.ibm.com/cloud-operations/namespace-config/blob/master/chart/namespace/values.yaml
we need to stay within the bounds of a m4.2xl

Q. What are the official change windows for production environments? <br />
A.
```
>  S3: 13:00 - 19:00 (GMT)  
>  G3: 20:00 - 02:00 (GMT)
>  A3: 00:00 - 06:00 (GMT)
```

Q. How do I manually upload a Helm Chart to Governor <br />
A. 
```
curl -SLOk http://icekubes.swg.usma.ibm.com/helm/charts/<chartname>.tgz
PATHTOCHART=\<path to chart>
id=\<your governor login username>
pw=\<your governor login password>
CREDS=$id:$pw
CREDSBASE64=$(echo -n ${CREDS} | base64 -w 0)
curl -H "Authorization: Basic ${CREDSBASE64}" -F "file=@${PATHTOCHART}.tgz" -F "product=cc" -X PUT "https://requests.governor.infrastructure.conncloudk8s.com/chart"
```
Q.  How do I get root access to DO <br />
A.
```
Request the role: Kubestarter-D0-SUDO in USAM (see above)
Connect to kubestarterpub.d0.conncloudk8s.com as your SSO user
To switch to root: sudo su
```

Q. What version of K8s is running on Cloud Environments <br />
A. k8s 1.8.5 <br />
