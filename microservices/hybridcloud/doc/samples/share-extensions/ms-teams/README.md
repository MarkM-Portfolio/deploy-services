# Enable Microsoft Teams Share within Share -
## MS Teams Share –
The appregistry extension in this folder enables sharing connections pages to Microsoft Teams through Share icon. The json can either be imported from file or copied / pasted into the code editor of the appregistry client to create the extension.

### Share Icon –

![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/9fb2fc00-f096-11eb-8c36-e1a1c6c106db)

On clicking Share icon, following dropdown is available with option MS Teams Share.

![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/cd984080-f096-11eb-8a04-3d4aae45c51c)

On clicking the MS Teams Share, following pop up will appear and one will be able to share current connection’s page link or respective blog’s/wiki’s/forum’s link to any Team/Channel in Microsoft Teams.


![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/06381a00-f097-11eb-8ab5-7eddf1490555)

The json from ms-teams-share-extension.json can either be imported from file or copied / pasted into the code editor of the appregistry client to create the extension. This extension is used to enable sharing of connections pages to Microsoft Teams through Share icon.



### Procedure for enabling slack chat integration - 

### STEP 1 - Registering the Extension

For Customizer to insert this customization:

Put all the files present in this folder onto the Connections environment in a <b> /pv-connections/customizations/share-extensions/ms-teams </b> directory.


NOTE - The files are present at following locations -

    https://git.cwp.pnp-hcl.com/connections/deploy-services/blob/master/microservices/hybridcloud/doc/samples/share-extensions/ms-teams/connections-teams-share-extension-8.0.js

    https://git.cwp.pnp-hcl.com/connections/deploy-services/blob/master/microservices/hybridcloud/doc/samples/share-extensions/ms-teams/ms-teams-share-extension.json



### STEP 3 – Appregistry Extension  


1.	Launch the appregistry UI at /appreg/apps URL (requires admin access) or navigate to https://yourConnectionsUrl.com/appreg/apps.
2.	In the apps manager, click New App.
3.	On the Code Editor page, either clear the default outline json that is created by default and then paste in the json (if already copied to clipboard from the appropriate json file) or click Import, browse for the JSON file containing the application, and select the file.
    The code that you import is validated and error messages display in the editing pane, where you can make corrections if needed.  

NOTE - The json is present at following location

    https://git.cwp.pnp-hcl.com/connections/deploy-services/tree/master/microservices/hybridcloud/doc/samples/share-extensions/ms-teams/ms-teams-share-extension.json

4.	Copy/Import the content of the JSON file in the appreg.

    ![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/9ea30c80-fe95-11eb-8fcb-6a15445afe08)

5.	Click Save to save the imported app.
6.	A new card should be displayed in the app list; enable or disable, as necessary.
7.	After enabling the extension, on clicking ‘Share’ icon, the option ‘MS Teams Share’ will appear in the dropdown. On clicking ‘MS Teams Share’, a pop up will appear and one will be able to share current connection’s page link or respective blog’s/wiki’s/forum’s link to any Team/Channel in MS Teams.
