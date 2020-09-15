# Deploying  Power BI reports using Azure Devops Part II

This article is the follow-up to the [Deploying Power BI reports using Azure Devops](https://github.com/becheng/pbi-azuredevops-poc) proof of concept.  It addresses several limitations of the original PoC along with some added features to automate the deployment of the Power BI reports.    

## Goals of this PoC:
1. **Use of the Service Principal** instead of Master Account within the Azure pipelines.
2. Use of  PowerBI Gateways (for on-prem datasources) and the **re-binding of PowerBI dataset to a gateway** in the Release pipeline.
3. The **configuration of a PowerBI schedule** in the Release pipeline using the Power BI rest apis.
4. **Installing a local gateway using a PS script using a Service Principal** (in Public Preview).     
   
This time around we will be using the Powershell exclusively; using a combination of and the appropriate Power BI PS modules and Rest apis.

### Setting up a Serivce Principal(SP)
Here we will be uisng a SP to access the various Power BI permissions.  At a high level, to create a SP, we will: 
- Register an app with a secret in the Azure AD.  Make sure to use the same Azure AD tenant that underpins the desired PowerBI service.
- Assign the appropriate Power BI API permissions to the SP. 
- Create a security group in Azure AD and assign the SP to it.
- Within Power BI service, allow the SP access to the Power BI APIs via the security group.
- And finally, add the SP to the workspaces 

1. Follow these [msdoc instructions](https://docs.microsoft.com/en-us/power-bi/developer/embedded/embed-service-principal#get-started-with-a-service-principal) to set up a SP with access to the PowerBI Apis and workspaces.
2. Within the Azure portal, assign the PowerBI Rest *Delegated* permissions, *Dataset.ReadWrite.All* and *Workspace.ReadWrite.All*  to the SP.  **Imporant!** Provide tenant wide consent by clicking *Grant admin consent for Default Directory* within the app's *API Permissions* blade. 
   
### Setting up the Power BI Gateway 
1. Install the gateway on a local machine
2. Start the gateway
3. Sign in using the PBI pro account that is on same tenant as the workspaces of the reports.
4. Configure the gateway with name and recovery key.
5. Make sure the gateway is running.
6. Login to the PBI Service with the above PBI pro account, goto the settings > manage gateways and confirm the gateway is present.
7. Click on the gateway and click *Add datasources to use the gateway*.
8. Set up a connect to the local datasource, i.e. ODBC, SQL Server.
   Note: try using the SQL auth, username/password instead for the PoC.

      
### TODOs
1. Document the workaround done for the limitation that an SP can't seem to do the binding to a gateway; only works with a MA account.  
2. Document the mapping the logic to bind to the gateway, i.e update the db params to match the gateway's datasource and make sure to refresh so the mapping occurs.
3. Document the step to  map a secret variable to the PS task in the pipelne
4. Document the use of variable groups in Azure devops to bind environment specific variables to a stage vs common varaibles used at the Release.

