# Huddo Boards for HCL Connections CP

Deploying Huddo Boards into HCL Connections Component Pack (Kubernetes)

## Prerequisites:

    1. HCL Component Pack is installed and running
    
    2. WebSphere environment with Web Server (or another reverse proxy)
    
    3. kubectl is installed
    
    4. helm is installed
    
    5. SMTP gateway setup for email notifications if required
    
## SSL / Network setup
Huddo Boards in Connections Component Pack (CP) uses the existing CP infrastructure.

The UI and API each require a unique route:

* UI for Boards: [CONNECTIONS_URL]/boards. We will refer to this as BOARDS_URL
* API Gateway: [CONNECTIONS_URL]/api-boards. We will refer to this as API_URL

Configuring an IBM HTTP WebServer as reverse proxy, [please see here](https://docs.huddo.com/boards/cp/httpd/#configure-reverse-proxy)

## Setup OAuth
You will need to setup an OAuth application with HCL Connections for Huddo Boards to function, please see here (Click on link below):

Provider | Registration/Documentation | Callback URL
------------ | ------------- | -------------
HCL Connections | [huddoboards](https://docs.huddo.com/boards/connections/auth-on-prem/) | https://[CONNECTIONS_URL]/boards/auth/connections/callback

## Storage
#### S3
Huddo Boards for Component Pack deploys a Minio service. Please follow [S3 storage details here](https://docs.huddo.com/boards/cp/minio/) to configure the NFS mount.

#### Mongo
Huddo Boards uses the Mongo database already deployed inside the Component Pack. There is no configuration required.

## Licence Key
Huddo Boards / Activities Plus is a free entitlement however it requires a licence key from (https://store.huddo.com). For more details [see here](https://docs.huddo.com/boards/cp/store/).

## Update Config file (boards-cp.yaml)
Construct a YAML file to override values in the chart based on [this template](boards-cp.yaml).  Descriptions as below.

##### Kubernetes variables:
Key | Description
------------ | -------------
global.env.APP_URI | https://[BOARDS_URL] (For e.g. https://connections.example.com/boards)
webfront.env.API_GATEWAY | https://[API_URL] (For e.g., https://connections.example.com/api-boards)
webfront.ingress.hosts | The hostname must match other Ingresses defined in your CP environment (**kubectl get ingresses --all-namespaces** - If all ingresses start with * you must match the pattern). For e.g., *.cnx.cwp-pnp-hcl.com
core.ingress.hosts | The hostname must match other Ingresses defined in your CP environment (**kubectl get ingresses --all-namespaces** - If all ingresses start with * you must match the pattern). For e.g., *.cnx.cwp-pnp-hcl.com
minio.nfs.server | IP address of the NFS Server file mount (e.g. 192.168.10.20)

##### Boards variables:
Key | Description
------------ | -------------
global.repository | your-private-docker-repo:port/connections
global.imageTag | (**Optional**) boards-helmchart-date-tag. **Starting from C7**, It's added to Huddoboards helm charts. 
global.imagePullSecret | (**Optional**: secret that is already created for use with Docker registries authentication) myregkey. **Starting from C7**, It's added to Huddoboards helm charts.
core.env.NOTIFIER_EMAIL_HOST | SMTP gateway hostname, ie smtp.ethereal.com
core.env.NOTIFIER_EMAIL_USERNAME | (**Optional**) SMTP gateway authentication. Setting a value will enable auth and use the default port of 587
core.env.NOTIFIER_EMAIL_PASSWORD | (**Optional**) SMTP gateway authentication password
core.env.NOTIFIER_EMAIL_PORT | 	(**Optional**) SMTP gateway port.
core.env.NOTIFIER_EMAIL_FROM_NAME | (**Optional**) Emails are sent from this name. Default: Huddo Boards
core.env.NOTIFIER_EMAIL_FROM_EMAIL | (**Optional**) Emails are sent from this email address. Default: no-reply@huddoboards.com
core.env.NOTIFIER_EMAIL_SUPPORT_EMAIL | (**Optional**) Support link shown in emails. Default: support@huddoboards.com
core.env.NOTIFIER_EMAIL_HELP_URL | (**Optional**) Help link shown in new user welcome email. Default: (https://docs.huddo.com/boards/howto/knowledgebase/)
licence.env.LICENCE | Register your Organisation and download your Free 'Activities Plus' licence key from store.huddo.com. See **Licence Key**.
user.env.CONNECTIONS_NAME | (**Optional**) If you refer to 'Connections' by another name, set it here
user.env.CONNECTIONS_CLIENT_ID | OAuth client-id, usually huddoboards. It is the id of the application registered for OAuth (See **Setup OAuth**)
user.env.CONNECTIONS_CLIENT_SECRET | OAuth client-secret as configured in **Setup OAuth**
user.env.CONNECTIONS_URL | 	HCL Connections URL, ie https://connections.example.com
user.env.CONNECTIONS_ADMINS | "[\"admin1@company.example.com\", \"boss2@company.example.com\", \"PROF_GUID_3\"]"
user.env.ENSURE_TEAMS | [See here](https://docs.huddo.com/boards/env/teams/) for details on the values available if you want the Huddo Boards On-Premise in Microsoft Teams.

[**Note**: Do not change rest of the variables. For e.g., <service_name>.image.name]

##### Activity migration variables (if you're considering migrating existing activities to Activities Plus):

The Activity migration chart will be deployed separately but use the same config file. The variables are [described here](https://docs.huddo.com/boards/cp/migration/).

## Deploy Boards Helm Chart
Get the kudos-boards-cp chart version available on the HCL Harbor repository:
```
helm search repo [ HARBOR_HELM_REPO_NAME ] --devel | grep kudos-boards-cp | grep -v activity | awk {'print $2'}
```
where [ HARBOR_HELM_REPO_NAME ] is the local Helm repo name of the HCL Harbor repository.

sample output:

```
3.1.1
```

Install the Boards services via our Helm chart

[Note: --recreate-pods ensures all images are up to date. This will cause downtime].

```
helm upgrade kudos-boards-cp [ HARBOR_HELM_REPO_NAME ]/kudos-boards-cp -i --version [ HUDDO_BOARD_CP_CHART_VERSION ] -f [ BOARDS_CP_YAML ] --namespace connections --recreate-pods
```
where [ HUDDO_BOARD_CP_CHART_VERSION ] is the chart version returned by the previous command and [ BOARDS_CP_YAML ] is the values override YAML file constructed above.

For example:

```
helm upgrade kudos-boards-cp v-connections-helm/kudos-boards-cp -i --version -f 3.1.1 -f boards-cp.yaml --namespace connections --recreate-pods
```


## Deploy activity-migration Helm Chart (if you're considering migrating existing activities to Activities Plus)
Before installing activity-migration, update the same configuration **boards-cp.yaml** file for migration variables.

Get the kudos-boards-cp-activity-migration chart version available on the HCL Harbor repository:
```
helm search repo [ HARBOR_HELM_REPO_NAME ] --devel | grep kudos-boards-cp-activity | awk {'print $2'}
```

sample output:

```
3.1.0
```

Install the activity-migration service via our Helm chart

[Note: --recreate-pods ensures all images are up to date. This will cause downtime].

```
helm upgrade kudos-boards-cp-activity-migration [ HARBOR_HELM_REPO_NAME ]/kudos-boards-cp-activity-migration -i --version [ HUDDO_BOARD_CP_ACTIVITY_MIGRATION_CHART_VERSION ] -f [ BOARDS_CP_YAML ] --namespace connections --recreate-pods
```
Where [HUDDO_BOARD_CP_ACTIVITY_MIGRATION_CHART_VERSION] is the chart version returned by the previous command.

For example:

```
helm upgrade kudos-boards-cp-activity-migration v-connections-helm/kudos-boards-cp-activity-migration -i --version 3.1.0 -f boards-cp.yaml --namespace connections --recreate-pods
```

## Integrations
#### HCL Connections
* [Apps Menu](https://docs.huddo.com/boards/connections/apps-menu-on-prem/)
* [Widgets](https://docs.huddo.com/boards/connections/widgets-on-prem/)

#### Microsoft Teams
* [Install On-Premise App](https://docs.huddo.com/boards/msgraph/teams-on-prem/)

## Migrate Activities data
Please follow the [instructions here](https://docs.huddo.com/boards/cp/migration/)
