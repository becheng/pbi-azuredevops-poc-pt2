# Powering up your Power BI Report deployments with Azure DevOps and Powershell!   

This article is the follow-up to our [Deploying Power BI reports using Azure Devops](https://github.com/becheng/pbi-azuredevops-poc) sample.  That sample showed how to develop a pipleline to automate the deployment of a Power BI report using [Azure Devops](https://dev.azure.com/) with the easy to use [PowerBI Actions](https://marketplace.visualstudio.com/items?itemName=maikvandergaag.maikvandergaag-power-bi-actionshttps://marketplace.visualstudio.com/items?itemName=maikvandergaag.maikvandergaag-power-bi-actions) add-in.  This time around, we take it up a notch and do everything with Powershell to address several areas where the first sample fell short to really *power up* the Power BI report deployments.     

## This time around...
- **Use of a service principal** instead of a user account to mange the lifecyle of the Power BI reports.  Using a service principal is best practice and does not incur the overhead of using account with a PowerBI pro license.
- **Use of a on-premise gateway**.  Not all reporting data sources are built same and so you may found yourself in need of gateway to connect your reports on-premise data sources.  This sample demostrates how to provision a gateway using a Powershell script using a service pricipal and the binding of a report's dataset to a gateway as part of part of a release pipeline.  For those fortunate enough to use cloud data sources, we got you covered and provide an alterative Powershell script to use.  
- **Automating the dataset's refresh schedule** as part of the  pipeline, *because why wouldn't you?* 
- **Adding a user account (with Power BI pro account) to the workspace**.  *But didn't you just say we should be using a service principal?*, you ask.  Well yes, we did, and it is still the  preferred practice, but at the time of writing this, the gateway binding is limited to using a user account, so we will need that user account just to perform that task within our script.  That being said, you cannot sign into your Power BI portal using a service principal, so adding a user account to the workspace comes in handy to eyeball changes of your deployments.        
   
### 1.0 Creating the serivce principal
We start things off by creating the service principal to manage our reports and the environments. To create the service principal, we i) register an app with a secret in Azure AD, ii) assign it with Power BI API permissions, iii) create a new security group and add the app as a as a member, and lastly iv) allow that group with access   to PowerBI APIs and the ability to create new workspaces in the Power BI portal. 

1. Follow this [msdoc](https://docs.microsoft.com/en-us/power-bi/developer/embedded/embed-service-principal#get-started-with-a-service-principal) to set up the service principal with access to the PowerBI Apis.  **Important**: Skip steps 4 & 5 because we do these dynanically via the script. 
2. In your [Azure portal](https://https://portal.azure.com/), select your Azure active directory app, go to its *API permissions*, click *Add a permission*, select *Power BI Service* and add the *Delegated* permissions of `Dataset.ReadWrite.All` and `Workspace.ReadWrite.All`.
   <img src="./images/aad_pbi_api_permissions.jpg" width=450> 
3. Sign in to your [Power BI portal](https://powerbi.microsoft.com/) with an admin account, go to *Settings* (Gear Icon), *Admin Portal*, *Tenant settings*.
4. Under *Developer settings*, go to *Allow service principals to use PowerBI APIs*, enable it and add the security group and *Apply*.
   <img src="./images/pbi_dev_settings.jpg" width=550>   
5. Under *Workspace settings*, go to *Create workspaces*, enable it and add the security group and *Apply*.
   <img src="./images/pbi_workspace_settings.jpg" width=550>

### 2.0 Installing the Power BI Gateway
We use a *nifty* Powershell script to provision the gateway under a service principal account.  Again this feature is under preview at the time of this writing so if you prefer to just use a user account, follow this [msdoc](https://docs.microsoft.com/en-us/data-integration/gateway/service-gateway-install) instead.

1. Download the [gateway.ps1](./ps-scripts/gateway.ps1) script to the local machine where your on-premise datasource resides. 
2. Update the script variables including the app client Id, tenant Id, secret and the email of user account with PowerBI pro license.  
3. Run the script, e.g. `./gateway.ps1` and check your Task Manager to confirm the gateway is running.

   <img src="./images/gateway_process.jpg" width=250> 
4. Sign in to your [Power BI portal](https://powerbi.microsoft.com/) with your user account, go to *Settings*, *Manage Gateways* and confirm your named gateway is listed under *Gateway Clusters*.

   <img src="./images/pbi_gateway.jpg" width=250> 
5. Select the gateway and click *Add Data Source* (located at the top).
6. Name the data source, e.g. `my-gateway-datasource` and specify the connection values to the local data source.  In our case, we used a local Sql Server instance, enabled SQL authenication, and connected with a service level database username and password.

   <img src="./images/pbi_gateway_datasrc.jpg" width=450>   
7. Make a note of the gateway name because it will be used later to setup our devops pipeline.

### 3.0 Parameterizing the PowerBI Report datasource
For context, our deployment Powershell scripts depends on the best practice of using parameterized data sources. If your reports already do this, *Awesome!*, just move on to the next section.

1. Open your report using your [Power BI Desktop](https://powerbi.microsoft.com/en-us/desktop/) editor, expand *Transform data* and select *Data source settings*.
   <img src="./images/datasrc_settings.jpg" width=450> 
2. Select the *Change Source...* button to open the report's data source (in our case, it was Sql Server) window.
3. Select the *Server* dropdown and select *New Parameter...*  
   <img src="./images/pbidesk_paramstart.jpg" width=250>
4. In the *Manage Parameters* window: 
   - Add new parameter for the database server, e.g. `dbServerParam`.
   - Check the Required checkbox to make the parameter mandatory
   - Enter your default server (typically your development instance) in the *Current Value* field.     
   <img src="./images/dbServerParam.jpg" width=250>
5. Repeat the above step and add new parameter for the database name, e.g. `dbServerName`.
6. Make note of both parameter names because they will be used later to set up the pipeline.

### 4.0 A break down of the Powershell script
Before we get into creating the devops pipelines, let's break down our deployment scripts and explain what they'll doing.  Where possible we leverage the *[MicrosoftPowerBIMgmt](https://docs.microsoft.com/en-us/powershell/power-bi/overview?view=powerbi-ps)* Powershell cmdlets, because *why revent the wheel?* otherwise we use the *Invoke-PowerBIRestMethod* cmdlet (also part of *MicrosoftPowerBIMgmt* module) to invoke any of the Power BI Rest APIs where functionality is not covered by the cmdlets.  The nice thing about using these cmdlets is the authorization access token is taken care for you for your entire session once you've signed in using the *Connect-PowerBIServiceAccount* cmdlet.

**[deploy-pbixreport.ps1](./ps-scripts/deploy-pbixreport.ps1) script (for cloud only data sources)**
1. Sign in using the service principal.
2. Retrieve the target workspace and create it if it does not exist.
3. Add the admin user to the workspace if user does not already exist.
4. Upload the report and overwrite the older version (if one exisits.
5. Take over the report's dataset using the service principal.
6. Update the dataset's data source's parameters.
7. Update the dataset's data source's credentials.
8. Update/Set the scheduled refresh of the dataset.
9. Invoke a dataset refresh.  

**[deploy-report-with-gateway.ps1](./ps-scripts/deploy-pbixreport-with-gateway.ps1) script (for on-premise datasources)**

Step 1-6 are identical to the above.

7. Sign in using the admin user account.
8. Take over the report's dataset using the admin user account.
9. Look up the target gateway and bind it to the dataset.
10. Update/Set the scheduled refresh of the dataset.
11. Invoke a dataset refresh.
12. Take (back) the report's dataset using the service principal.    


### 5.0 Putting it all together in Azure DevOps
We use [Azure Devops](https://dev.azure.com/) to build our devops pipelines.

1. Sign into your [Azure Devops](https://dev.azure.com) instance and create a new project, e.g. `my-pbidevops-pipeline`.
2. Add your .pbix files to the project's repo.
3. Download a copy of the [deploy-report-with-gateway.ps1](./ps-scripts/deploy-pbixreport-with-gateway.ps1) or [deploy-pbixreport.ps1](./ps-scripts/deploy-pbixreport.ps1) (if using cloud datasources) and upload it to your project's repo.

   <img src="./images/azdevops_repo.jpg" width=450>

#### 5.1 Create a Pipeline
We construct a simple build pipeline that publishes our files for deployment.

1. Create a new *Pipeline*, e.g. `my-pbidevops-build`.
2. Copy the following yaml script and save it to the pipeline.  This script publishes the .pbix and .ps1 files so the (deployment) *Release* pipeline has access to them.
      
   ```
    trigger:
    - master

    pool:
      vmImage: 'ubuntu-latest'

    steps:
    - task: CopyFiles@2
      displayName: 'Copy Files to: Staging Artifact'
      inputs:
        Contents: |
          *.pbix 
          *.ps1
        TargetFolder: '$(Build.ArtifactStagingDirectory)'
        OverWrite: true
    - task: PublishBuildArtifacts@1
      displayName: 'Publish Artifact: drop'

   ```
   
   <img src="./images/azdevops_build.jpg" width=450>

3. Save and run the build pipeline.
   
#### 5.2 Create a Release Pipeline
We create the release pipeline that utizilies our Powershell script to deploy the published reports to the Power BI portal.

1. Create a new *Release* pipeline, e.g. `my-pbidevops-release`.
2. Add an artifact and choose the newly created build pipeline source.

  <img src="./images/azdevops_rel_artifact.jpg" width=450>

3. Add a new Stage with an *Empty Job* and provide a name, e.g. `Deploy PBI Report`.

4. Click on the "+" (*Add a task to the Agent Job*), search and add a *Powershell Task*.    
5. Name the task, e.g. `Install PS Modules` and copy and paste the content below as an *Inline* script.  This will install the Powershell cmdlets used by the deployment Powershell scripts. 
  
    ```
    Install-Module -Name MicrosoftPowerBIMgmt.Profile -Verbose -Scope CurrentUser -Force
    Install-Module -Name MicrosoftPowerBIMgmt.Workspaces -Verbose -Scope CurrentUser -Force
    Install-Module -Name MicrosoftPowerBIMgmt.Reports -Verbose -Scope CurrentUser -Force
    Install-Module -Name MicrosoftPowerBIMgmt.Data -Verbose -Scope CurrentUser -Force
    ```
   
   <img src="./images/azdevops_reltask1.jpg" width=450>

6. Click on the "+" (*Add a task to the Agent Job*) again and add another *Powershell Task*.
7. Name the task, e.g. `Run PS deploy script`, select a *File Path* type, click the elipses *...* and select either the *deploy-pbixreport-with-gateway.ps1* or *deploy-pbixreport.ps1* file.  Note: Path is visible only if the build pipeline from section 3 ran successfully.
   
   <img src="./images/azdevops_psscript.jpg" width=350>

   <img src="./images/azdevops_reltask2.jpg" width=450>
8. Save the Release.

#### 5.3 Define the Variables
*We're on the home stretch!*  Here, we set up the variables referenced by the script using the *Pipeline Variables* and *Variable Groups*.  Pipeline variables are available to a particular pipeline and can be scoped with *Release* so they are accessible to the entire pipeline or scoped to a particular *Stage* within the pipeline.  Variable Groups are available across multiple pipelines and similarily can scoped to a Release or a Stage.  To keep our variables nice and tidy, we define our global variables as *Pipeline Variables* and environment specific (eg. Production, Dev, QA) variables as a *Variable Group* and tie it to a Stage.

**Pipeline Variables**
1.  Click the *Variables* link in the pipeline.
2.  Make sure *Pipeline variables* is selected on the left nav and add the following variables:
    | Variable Name | Value | Type | Scope |
    | ------------- | ----- | ---- | ----- |
    | tenantId | [ Tenant Id of the registered AAD app ] | Plain text | Release |
    | clientId | [ Client Id of the registered AAD app ] | Plain text | Release |
    | clientSecret | [ Client secret of the registered AAD app ] | Secret | Release |
    | pbixFilePath | [ File path to the published .pbix file] | Plain text | Release |
    | userAdminEmail | [ Email addresss of the PowerBI Pro user account] | Plain text | Release |
    | userAdminPassword | [ Password of the PowerBI Pro user account] | Secret | Release |
    | dbServerParamName | [ PowerBI report parameter name of the database server] | Plain text | Release |
    | dbNameParamName | [ PowerBI report parameter name of the database name] | Plain text | Release |
    | dbUserName* | [ Database service account user name ] | Plain text | Release |
    | dbUserPassword* | [ Database service account password ] | Secret | Release |

- *The dbUserName and dbUserPassword variables are required only if using the [deploy-pbixreport.ps1](./ps-scripts/deploy-pbixreport.ps1) script.
- To set up a variable as a Secret type, click the lock icon located to the right of the varable text field.
- The pbixFilePath is the path to the publised .pbix file with a format: `$(System.DefaultWorkingDirectory)/_[project_name]/drop/[report_name].pbix`.  
Example: $(System.DefaultWorkingDirectory)/_**my-pbidevops-pipeline**/drop/**my-powerbi-report**.pbix` 

**Variable Groups**
1. Click on the *Variable groups* in the left nav and click *Manage variable groups*.
2. Click on *+ Variable group*, name the group, e.g. `my-variable-group` 
3. Add the following variables:
   | Variable Name | Value |
   | ------------- | ----- |
   | workspacename | [ workspace name ] |
   | dbServerParamValue | [ database server name ] |
   | dbNameParamValue | [ database name ] |
   | gatewayName | [ gateway name ] |
   | scheduleJson | [ json string of the dataset refresh schedule ] |
  
- Example of scheduleJson value: 
    ```
    { 
      "value": {
        "enabled":"true",
        "notifyOption":"NoNotification", 
        "days": ["Sunday", "Tuesday","Thursday", "Saturday"], 
        "times": ["07:00", "11:30", "16:00", "23:30"],
        "localTimeZoneId": "UTC" 
      } 
    } 
    ```

    <img src="./images/azdevops_vargroup.jpg" width=350>

1. Save the group and go back to the Release, edit it, select *Variables*, *Variable groups*, and select *Link variable group* and link the variable group to the stage.
   
   <img src="./images/azdevops_linkvargrp.jpg" width=350>
2. Click *Link* to the save linkage.

**Resolving Secret Variables**

Variables marked as secret in either in *Variable Groups* or *Pipeline Variables* require extra set up so our powershell script can decrypt the variables to use them.  
1. Click *Tasks* in your pipeline, click on the *Run PS deploy script* and select its *Environment Variables* section.
2. Enter the folllowing to decrypt all our secret variables:
   | Name | Value |
   | ------------- | ----- |
   | clientSecret | $(clientSecret) |
   | userAdminPassword | $(userAdminPassword) |
   | dbUserName* | $(dbUserName) | 
   | dbUserPassword* | $(dbUserPassword) |  
   *only applicable if using a cloud datasource
3. Save the Release.
    
### 6.0 Running it end to end
1. Run the Build pipeline.
2. Run the Release pipeline. 
3. Sign into your [Power BI portal](https://powerbi.microsoft.com/en-us/landing/signin/) using the admin user account and confirm your new named is workspace is present, the report is deployed and its dataset with all its settings (gateway connection, data source credentials, database parameters, scheduled refresh) are as expected.  
**Important:** recall this workspace and all its artifacts was provisioned by the service principal so in order to check the dataset's settings, the page will prompt you to "Take Over" the dataset with the admin user account that you signed in with.  In doing so, you will need to re-bind the gateway (if using one) datasource.  Once rebinded, you will be able to check the rest of the dataset's settings.
  <img src="./images/pbiportal_deployed.jpg" width=550>

### 7.0 Applying to real world scenarios
So now that you got this sample working, *what now?*  *How do I apply to this to a real world scenario?*  The good news, you can take all learnings here and tweak it to align to your real world scenarios.  Without getting too deep into the details here, by using a combination of creating/cloning the different *Stages* in a *Release* pipeline and *Variable Groups* to hold environment specific variables, you have the abililty to deploy different reports to different report environments (workspaces).

Below is an example of an Azure Devops Release pipeline deploying a Tradewinds and Contoso Power BI report to the each of their respected environment workspaces.

<img src="./images/azdevops_extended.jpg" width=500>

### 8.0 Final Thoughts
There isn't much you *can't* do with [MicrosoftPowerBIMgmt Powershell cmdlets](https://docs.microsoft.com/en-us/powershell/power-bi/overview?view=powerbi-ps) and [Power BI Rest APIs](https://docs.microsoft.com/en-us/rest/api/power-bi/) to have a fully functional CI/CD pipeline to manage the lifecyle of your Power BI reports.  Those looking to do more than what a Power BI Azure Devops add-in can offer (see our [first sample](https://github.com/becheng/pbi-azuredevops-poc)) or have a more complex reporting environment with gateways, this recipe of using Powershell and Azure Devops is a viable option.  To close off the series, we are  planning to recreate this sample using the [Github Actions](https://github.com/features/actions) as our third and last article.          

One final word...at the time of writing, [Power BI Deployment Pipelines is in public preview](https://powerbi.microsoft.com/en-us/blog/introducing-power-bi-deployment-pipelines-preview/) that provides a low-code way to set up release pipelines right in the your Power BI portal for those with Power BI Premium.       





