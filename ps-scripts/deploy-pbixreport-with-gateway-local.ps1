## usage: ./deploy-pbixreport-with-gateway-local.ps1
## dependancies:
# Install-Module -Name MicrosoftPowerBIMgmt.Profile -Verbose -Scope CurrentUser -Force
# Install-Module -Name MicrosoftPowerBIMgmt.Workspaces -Verbose -Scope CurrentUser -Force
# Install-Module -Name MicrosoftPowerBIMgmt.Reports -Verbose -Scope CurrentUser -Force
# Install-Module -Name MicrosoftPowerBIMgmt.Data -Verbose -Scope CurrentUser -Force

$env:tenantId = "[AAD tenant id]"
$env:clientid = "[AAD app/client id]"
$env:clientsecret = "[AAP app client secret]"
$env:reportName = "[PBI report/dataset name]"
$env:workspacename = "[PBI workspace name]"
$env:userAdminEmail = "[AAD user account with PBI pro license that is the admin of the on-prem gateway]"
$env:userAdminPassword="[The above AAD user's password]"
$env:pbixFilePath= "[Full local file path of .pbix report]"
$env:dbServerParamName = "[The param NAME used in pbix report used to store the db Server]"
$env:dbNameParamName = "[The param NAME used in pbix report used to store the db Name]"
$env:gatewayName = "[The name of the on-prem gateway]"

#onprem datasource
$env:dbServerParamValue = "[The param VALUE used in pbix report used to store the db Server, e.g. 'localhost\SQLEXPRESS']"
$env:dbNameParamValue = "[The param VALUE used in pbix report used to store the db Server, e.g. 'mydb']"

write-host "clientId: $env:clientId"
write-host "clientsecret: $env:clientsecret"
write-host "tenantId: $env:tenantId"
write-host "workspacename: $env:workspacename"
write-host "userAdminEmail: $env:userAdminEmail"
write-host "pbixFilePath: $env:pbixFilePath"
write-host "dbServerParamName: $env:dbServerParamName"
write-host "dbServerParamValue: $env:dbServerParamValue"
write-host "dbNameParamName: $env:dbNameParamName"	
write-host "dbNameParamValue: $env:dbNameParamValue"
write-host "reportName: $env:reportName"
	

## ------------------------------------------------------
## 1. SIGN IN WITH SP
## ------------------------------------------------------
write-host "`n...sign in with SP"
$clientsec = "$env:clientsecret" | ConvertTo-SecureString -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $env:clientId, $clientsec
 
Connect-PowerBIServiceAccount `
	-ServicePrincipal `
	-Credential $credential `
	-TenantId $env:tenantId

## ------------------------------------------------------
## 2. MANAGE WORKSPACE
## ------------------------------------------------------
write-host "`n...Manage Workspace"
$workspace = Get-PowerBIWorkspace `
	-Name $env:workspacename

# create the workspace if it does not exists
if($null -eq $workspace){
	
	write-host "- creating new $env:workspacename workspace"
	New-PowerBIWorkspace `
		-Name $env:workspacename
	
	$workspace = Get-PowerBIWorkspace `
		-Name $env:workspacename
		
} else {
	write-host "- $env:workspacename workspace already exists"
}

## ------------------------------------------------------
# 3. ADD AN ADMIN USER TO THE WORKSPACE
## ------------------------------------------------------
write-host "`n...Adding admin user to the workspace"
# check if the admin user already exists 
$wsusersResponse = Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/users" `
	-Method GET `
	| ConvertFrom-Json 
	
$wsusers = $wsusersResponse.value | where-object {$_.emailAddress -eq $env:userAdminEmail} 
if ($null -eq $wsusers) {

	Write-Host "- Adding user '$env:userAdminEmail' to '$env:workspacename' workspace."
	Add-PowerBIWorkspaceUser `
	   -Id $($workspace.id) `
	   -UserPrincipalName $env:userAdminEmail `
	   -AccessRight "Admin"

} else {
	write-host "- User $env:userAdminEmail' already has access to the '$env:workspacename' workspace."
}

## ------------------------------------------------------
## 4. UPLOAD PBIX REPORT
## ------------------------------------------------------
write-host "`n...Importing .pbix report."
$new_report = New-PowerBIReport `
	-Path $env:pbixFilePath `
	-Name $env:reportName `
	-ConflictAction "CreateOrOverwrite" `
	-Workspace $workspace

write-Host ".pbix report uploaded";

# Get the report again because the dataset id is not immediately available with New-PowerBIReport
$new_report = Get-PowerBIReport `
	-WorkspaceId "$($workspace.id)" `
	-Id $new_report.id

## ------------------------------------------------------
## 5. UPDATE DB PARAMS
## ------------------------------------------------------
write-host "`n...Take over the dataset with the SP"

# get the embedded dataset of the new report
$dataset = Get-PowerBIDataset `
   -WorkspaceId "$($workspace.id)" `
   -Id $new_report.datasetId 
   
# take over 
Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/datasets/$($dataset.id)/Default.TakeOver" `
	-Method Post `
	-ErrorAction Stop;

write-host "Take over with SP complete"

#Change the database server and db / params
write-host "`n...Update its DB params"

$dbParams = @{
	updateDetails = @(
		[pscustomobject]@{name=$env:dbServerParamName;newValue=$env:dbServerParamValue}
		[pscustomobject]@{name=$env:dbNameParamName;newValue=$env:dbNameParamValue}	
	)
} | ConvertTo-Json

Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/datasets/$($dataset.id)/Default.UpdateParameters" `
	-Method POST `
	-Body $dbParams `
	-ErrorAction Stop;
	
write-host "DB param change complete";


## ------------------------------------------------------
##  6. BIND GATEWAY
## ------------------------------------------------------

# 6.1 Sign in with user account
write-host "`n...Sign in using user account"

$userAdminPassword = $env:userAdminPassword | ConvertTo-SecureString -asPlainText -Force
$uacreds= New-Object System.Management.Automation.PSCredential($env:userAdminEmail, $userAdminPassword)
Connect-PowerBIServiceAccount `
	-Credential $uacreds

# 6.2 take over dataset with user account
write-host "`n...Take over dataset with user account"

Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/datasets/$($dataset.id)/Default.TakeOver" `
	-Method Post `
	-ErrorAction Stop;

# 6.3 Discover bindable gateways
write-host "`n...Discover Gateways using datasetid: $($dataset.id)"

$gatewayDataSources = Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/datasets/$($dataset.id)/Default.DiscoverGateways" `
	-Method GET | ConvertFrom-Json `
	-ErrorAction Stop;	

#write-host $gatewayDataSources

# 6.3 get only the target gateway
$gateway = $gatewayDataSources.value | Where-Object {$_.name -eq $env:gatewayName}
write-host "Found Gateway '$env:gatewayName'; gatewayObjectId=$($gateway.id)"

# 6.4 Bind 
write-host "`n...Binding to Gateway"
$bindReqBody = @{
	gatewayObjectId = "$($gateway.id)"
} | ConvertTo-Json

Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/datasets/$($dataset.id)/Default.BindToGateway" `
	-Method Post `
	-Body $bindReqBody `
	-ErrorAction Stop;
	
write-Host "Gateway binding completed";

## ------------------------------------------------------
## 7. SET THE REFRESH SCHEDULE (If provided)
## ------------------------------------------------------

if($null -ne $env:scheduleJson)
{
	write-Host "`n...Creating Refresh Schedule...";
	
	Invoke-PowerBIRestMethod `
		-Method PATCH `
		-Url "groups/$($workspace.id)/datasets/$($dataset.id)/refreshSchedule" `
		-Body $env:scheduleJson `
		-ErrorAction Stop;
		
	write-Host "Saved Refresh Schedule";
}

## ------------------------------------------------------
## 8. REFRESH THE DATASET 
## ------------------------------------------------------

# Note!!! only a max of 8 refreshes allowed in the non-premium workspace, after which 400/Bad Requests will be recieved 
# Note2 - Refresh must be issued after the bind to gateway otherwise the gateway's datasource will not be mapped.
 
write-host "`n...Refreshing dataset"
# Note: using NoNotification for sample, but if using MailOnFailure, MailOnCompletion will need to setup emails via the api otherwise will recieved 400/Bad Request  
$refreshBody = @{
	notifyOption ="NoNotification" 
} | ConvertTo-Json

Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/datasets/$($dataset.id)/refreshes" `
	-Method POST `
	-Body $refreshBody `
	-ErrorAction Stop;

write-Host "Refresh completed" -ForegroundColor Green;

## ------------------------------------------------------
## 9. ASSIGN DS BACK TO SP
## ------------------------------------------------------

# wait for 5 secs
Start-Sleep -s 5

write-host "`n...Take back ownership with the SP account"
$clientsec = "$env:clientSecret" | ConvertTo-SecureString -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $env:clientId, $clientsec
 
Connect-PowerBIServiceAccount -ServicePrincipal -Credential $credential -TenantId $env:tenantId

# take over 
Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/datasets/$($dataset.id)/Default.TakeOver" `
	-Method Post `
	-ErrorAction Stop;
	
write-Host "Take over to SP completed"