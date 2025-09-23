# Enable Slack Chat Integration in Connections-  
## SLACK 1-1 CHAT  
The appregistry extension in this folder enable 1-1 chat from the important to me bar, the bizcard and the user profile page in Connections.
The json can either be imported from file or copied / pasted into the code editor of the appregistry client to create the extensions.  

### Important To Me –
#### Start a chat directly from Slack Chat Bubble present in Important to Me:  

![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/aa466680-ae96-11eb-8838-9cd3a90f3eea)

#### Start a chat directly from bizcard present in Important to Me:  

![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/04472c00-ae97-11eb-9beb-f8b27d1d4cae)  

Start a 1-1 chat with user via standard https: web link which will ask the user if they wish to continue in the Slack desktop client or the web browser.  

### Bizcard & Profiles -  

#### Start a chat directly from the bizcard:  

![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/9bac7f00-ae97-11eb-81f6-db3e7e85b577)  

#### Start a chat directly from the profile:  

![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/b7b02080-ae97-11eb-8d0c-40e9e5f8f51b)  

Start a 1-1 chat with user via standard https: web link which will ask the user if they wish to continue in the Slack desktop client or the web browser.  

The json from slackChat.json can either be imported from file or copied / pasted into the code editor of the appregistry client to create the extension. This one extension is used to enable the 1-1 chat for both bizcard, profile page and ITM bubble.



### Procedure for enabling slack chat integration -  

### STEP 1 - Slack Environment 

- Login to Slack –  
  https://slack.com/get-started#/createnew  
  
  ![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/a4ea1b80-ae98-11eb-9161-8e8ec512851e)  
 
- Create a workspace or open any of the workspaces available for you.  
  
  ![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/de228b80-ae98-11eb-8d9a-352a86473ab0)
  
 - Navigate to following URL - 
   https://api.slack.com/apps/  
  
   ![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/04e0c200-ae99-11eb-9635-61398b5c63fb)  
  
 - Create a new App or select any existing app.  
 
   #### For new Apps,  
   - For creating a new App click on the option ‘Create New App’ and provide the ‘App Name’ and select the ‘Development Slack Workspace’ from the dropdown, then click ‘Create App’.  
   
     ![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/89cbdb80-ae99-11eb-9898-a0765d9d29b1)  
   
   - The newly created app will appear in the app list.  
   
     ![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/a8ca6d80-ae99-11eb-83b4-e5a975870c20)  
   
   - Click on the newly created App for ex. Test Slack Chat. Within Features Tab on left hand panel, then select ‘OAuth & Permissions’.
   
     ![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/ca2b5980-ae99-11eb-8aac-81ad1611993b)
     
   - Scroll down to section ‘Scopes’ and add following permissions to ‘User Token Scopes’.
     - users:read
     - users:read.email  
     
     ![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/55a4ea80-ae9a-11eb-8d4e-ff54a8815bf0)  
     
   - Now scroll up and click on ‘Install to Workspace’ to generate OAuth Tokens. It will ask to grant the permissions. Select ‘Allow’.  
   
     ![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/7a00c700-ae9a-11eb-9c0c-557b734e174f)  
     
   - Copy the User OAuth Token, we need to provide this OAuth Token within the slack extension in App registry.  
   
     ![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/a1f02a80-ae9a-11eb-8346-97f648f58a26)  
     
   #### Or for existing apps,  
   
   - Click on any existing ‘App’ for ex. Test Connection Integration.  
   
     ![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/e67bc600-ae9a-11eb-8a2a-ce577f2680aa) 
     
   - Within Features Tab on left hand panel, select ‘OAuth & Permissions’.
   
     ![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/07441b80-ae9b-11eb-8720-f15c85f7d461)
     
   - Copy the User OAuth Token, we need to provide this OAuth Token within slack extension in App registry. Make sure to check by scrolling down, that within section ‘Scopes’, following permissions are present within ‘User Token Scopes’.
     - users:read
     - users:read.email  
     
     ![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/39ee1400-ae9b-11eb-9bb4-fa57781b6290)  
     
### STEP 2 - Registering the Customizer Extension  

For Customizer to insert this customization:  

Put all the files present in this folder onto the Connections environment in a /pv-connections/customizations/slackChat directory.  

NOTE - The files are present at following location  

       https://git.cwp.pnp-hcl.com/connections/deploy-services/tree/master/microservices/hybridcloud/doc/samples/slack/customizations/slackChat
       
### STEP 3 – Appregistry Extension  

1.	Launch the appregistry UI at /appreg/apps URL (requires admin access) or navigate to https://yourConnectionsUrl.com/appreg/apps.
2.	In the apps manager, click New App.
3.	On the Code Editor page, either clear the default outline json that is created by default and then paste in the json (if already copied to clipboard from the appropriate json file) or click Import, browse for the JSON file containing the application, and select the file.
    The code that you import is validated and error messages display in the editing pane, where you can make corrections if needed.  
    
    NOTE - The json is present at following location  
    
           https://git.cwp.pnp-hcl.com/connections/deploy-services/tree/master/microservices/hybridcloud/doc/samples/slack/customizations/slackChat  
    
4.	Copy the ‘OAuth Token’ from Step 1 within the ‘description’ in the json.  

    ![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/e3350a00-ae9b-11eb-9eb2-fee0290ef859)

5.	Click Save to save the imported app.
6.	A new card should be displayed in the app list; enable or disable, as necessary.
7.	On enabling the extension, the slack chat icon will appear in profile ui, bizcard ui and bizcard present in itm. On clicking the slack chat icon, it will be re-directed to slack chat if the user is a valid slack chat one.  


NOTE – Connections Slack Chat Integration is not supported in IE as slack does not provide support in IE. For more details, please refer to the link or the screenshot –  

https://slack.com/intl/en-in/help/articles/115002037526-Minimum-requirements-for-using-Slack#:~:text=Note%3A%20Google%20Chrome%20is%20the%20only%20browser%20that%20supports%20Slack%20Calls.  

![image](https://media.git.cwp.pnp-hcl.com/user/3209/files/5fc7e880-ae9c-11eb-992a-1dc7f9952520)





   

   
