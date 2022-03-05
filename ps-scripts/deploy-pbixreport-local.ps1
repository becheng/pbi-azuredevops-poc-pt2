## usage: ./deploy-pbixreport-local.ps1

## dependancies:
# Install-Module -Name MicrosoftPowerBIMgmt.Profile -Verbose -Scope CurrentUser -Force
# Install-Module -Name MicrosoftPowerBIMgmt.Workspaces -Verbose -Scope CurrentUser -Force
# Install-Module -Name MicrosoftPowerBIMgmt.Reports -Verbose -Scope CurrentUser -Force
# Install-Module -Name MicrosoftPowerBIMgmt.Data -Verbose -Scope CurrentUser -Force

$env:clientid = "[App Reg clientId]"
$env:clientsecret = "[App Reg clientSecret]"
$env:tenantId = "[AAD tenantId]"
$env:reportName = "[pbix report name]"
$env:workspacename = "[name of workspace]"
$env:userAdmin = "[AAD account eg. admin@contoso.onmicrosoft.com]"
$env:pbixFilePath= "[path\report-name.pbix]"
$env:dbServerParamName = "[pbix param name of db Server]"
$env:dbNameParamName = "[pbix param name of db Name]"
$env:dbNameParamValue = "[databaseName]"
$env:dbServerParamValue = "[database server eg. dbServerName.database.windows.net]"
$env:dbUserName = "[db admin username]"
$env:dbUserPassword = "[db admin password]"

write-host "tenantId: $env:tenantId"
write-host "clientId: $env:clientId"
write-host "clientsecret: $env:clientsecret"
write-host "workspacename: $env:workspacename"
write-host "pbixFilePath: $env:pbixFilePath"
write-host "reportName: $env:reportName"
write-host "userAdminEmail: $env:userAdmin"
write-host "dbServerParamName: $env:dbServerParamName"
write-host "dbServerParamValue: $env:dbServerParamValue"
write-host "dbNameParamName: $env:dbNameParamName"	
write-host "dbNameParamValue: $env:dbNameParamValue"
write-host "dbUserName: $env:dbUserName"	
write-host "dbUserPassword: $env:dbUserPassword"
	
$ErrorActionPreference = "Stop"
#$ErrorActionPreference = "silentlycontinue"

## ------------------------------------------------------
## 1. SIGN IN WITH SP
## ------------------------------------------------------
write-host "`nSign in with SP"
$clientsec = "$env:clientsecret" | ConvertTo-SecureString -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $env:clientId, $clientsec
 
Connect-PowerBIServiceAccount `
	-ServicePrincipal `
	-Credential $credential `
	-TenantId $env:tenantId

write-host "`Sign in with SP complete" -ForegroundColor Green;

## ------------------------------------------------------
## 2. MANAGE WORKSPACE
## ------------------------------------------------------
write-host "`nManage Workspace"
$workspace = Get-PowerBIWorkspace `
	-Name $env:workspacename

# create the workspace if it does not exists
if($null -eq $workspace){
	
	New-PowerBIWorkspace `
		-Name $env:workspacename
	
	$workspace = Get-PowerBIWorkspace `
		-Name $env:workspacename

		write-host "Created new $env:workspacename workspace" -ForegroundColor Green;
		
} else {
	write-host "'$env:workspacename' workspace already exists" -ForegroundColor Green;
}

## ------------------------------------------------------
# 3. ADD AN ADMIN USER TO THE WORKSPACE
## ------------------------------------------------------
write-host "`nAdding admin user to the workspace"

# check if the admin user already exists 
$wsusersResponse = Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/users" `
	-Method GET `
	| ConvertFrom-Json 
	
$wsusers = $wsusersResponse.value | where-object {$_.emailAddress -eq $env:userAdmin} 
if ($null -eq $wsusers) {

	Add-PowerBIWorkspaceUser `
	   -Id $($workspace.id) `
	   -UserPrincipalName $env:userAdmin `
	   -AccessRight "Admin"

	Write-Host "Added user '$env:userAdmin' to '$env:workspacename' workspace." -ForegroundColor Green;

} else {
	write-host "User $env:userAdmin' already has access to the '$env:workspacename' workspace." -ForegroundColor Green;
}

## ------------------------------------------------------
## 4. UPLOAD PBIX REPORT
## ------------------------------------------------------
write-host "`nImporting .pbix report."
$new_report = New-PowerBIReport `
	-Path $env:pbixFilePath `
	-Name $env:reportName `
	-ConflictAction "CreateOrOverwrite" `
	-Workspace $workspace

write-Host ".pbix report uploaded" -ForegroundColor Green;

# Get the report again because the dataset id is not immediately available with New-PowerBIReport
$new_report = Get-PowerBIReport `
	-WorkspaceId "$($workspace.id)" `
	-Id $new_report.id;

## ------------------------------------------------------
## 5. Take over the DATASET
## ------------------------------------------------------

write-host "`nTake over the dataset with the SP"

# get the embedded dataset of the new report
$dataset = Get-PowerBIDataset `
	-WorkspaceId "$($workspace.id)" `
	-Id $new_report.datasetId; 
	
# take over 
Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/datasets/$($dataset.id)/Default.TakeOver" `
	-Body "" `
	-Method Post; 

write-host "Take over with SP complete" -ForegroundColor Green;

## ------------------------------------------------------
## 6. UPDATE DB PARAMS
## ------------------------------------------------------

#Change the database server and db / params
write-host "`nUpdating DB params"

$dbParams = @{
	updateDetails = @(
		[pscustomobject]@{name=$env:dbServerParamName;newValue=$env:dbServerParamValue}
		[pscustomobject]@{name=$env:dbNameParamName;newValue=$env:dbNameParamValue}	
	)
} | ConvertTo-Json

Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/datasets/$($dataset.id)/Default.UpdateParameters" `
	-Method POST `
	-Body $dbParams; 

write-host "DB param change complete" -ForegroundColor Green;

## ------------------------------------------------------
## 7. UPDATE DATASET'S DATASOURCE CREDENTIALS
## ------------------------------------------------------
write-host "`nUpdating datasource credentials" 

# Get the dataset's datasources
$datasrcResp = Get-PowerBIDatasource `
   -DatasetId $($dataset.id) `
   -WorkspaceId $($workspace.id);

# update credentials
$patchBody = @{
	"credentialDetails" = @{
	  "credentials" = "{""credentialData"":[{""name"":""username"",""value"":""$env:dbUserName""},{""name"":""password"",""value"":""$env:dbUserPassword""}]}"
	  "credentialType" = "Basic"
	  "encryptedConnection" =  "Encrypted"
	  "encryptionAlgorithm" = "None"
	  "privacyLevel" = "Organizational"
	  "useEndUserOAuth2Credentials" = "False"
	}
  } | ConvertTo-Json

# NOTE!!!!!! - if the update credential call is erring out, run the patch directly 
# using Postman against the url https://api.powerbi.com/v1.0/myorg/gateways/$($datasrcResp.gatewayId)/datasources/$($datasrcResp.datasourceid)
# and comment the following lines to get the access token the complete url 
#   $headers = Get-PowerBIAccessToken | ConvertTo-Json
#   Write-Host $headers
#   Write-Host "gateways/$($datasrcResp.gatewayId)/datasources/$($datasrcResp.datasourceid)" `

Invoke-PowerBIRestMethod `
-Url "gateways/$($datasrcResp.gatewayId)/datasources/$($datasrcResp.datasourceid)" `
-Method Patch `
-Body $patchBody `
-ContentType "application/json"

write-host "DB credentials updated" -ForegroundColor Green;


## ------------------------------------------------------
## 8. SET THE REFRESH SCHEDULE (If provided)
## ------------------------------------------------------
if($null -ne $env:scheduleJson)
{
	write-Host "`nCreating Refresh Schedule...";
	
	Invoke-PowerBIRestMethod `
		-Method PATCH `
		-Url "groups/$($workspace.id)/datasets/$($dataset.id)/refreshSchedule" `
		-Body $env:scheduleJson; 
		
	write-Host "Saved Refresh Schedule" -ForegroundColor Green;
}

## ------------------------------------------------------
## 9. REFRESH THE DATASET 
## ------------------------------------------------------

# Note!!! only a max of 8 refreshes allowed in the non-premium workspace, after which 400/Bad Requests will be recieved 
# Note2 - Refresh must be issued after the bind to gateway otherwise the gateway's datasource will not be mapped.
 
write-host "`nRefreshing dataset"
# Note: using NoNotification for sample, but if using MailOnFailure, MailOnCompletion will need to setup emails via the api otherwise will recieved 400/Bad Request  
$refreshBody = @{
	notifyOption ="NoNotification" 
} | ConvertTo-Json

Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/datasets/$($dataset.id)/refreshes" `
	-Method POST `
	-Body $refreshBody;

write-Host "Refresh completed" -ForegroundColor Green;

