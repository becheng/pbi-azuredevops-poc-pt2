
write-host "client.id: $env:client_id"
write-host "client_secret: $env:clientsecret"
write-host "tenant.id: $env:tenant_id"
write-host "datasetname: $env:datasetname"
write-host "workspacename: $env:workspacename"
write-host "userAdminUsername: $env:userAdminUsername"
write-host "pbixFilePath: $env:pbixFilePath"
write-host "dbServerParamName: $env:dbServerParamName"
write-host "dbServerParamValue: $env:dbServerParamValue"
write-host "dbNameParamName: $env:dbNameParamName"	
write-host "dbNameParamValue: $env:dbNameParamValue"	


## ------------------------------------------------------
## 1. SIGN IN WITH SP
## ------------------------------------------------------
write-host "`n...sign in with SP"
$clientsec = "$env:clientsecret" | ConvertTo-SecureString -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $env:client_id, $clientsec
 
Connect-PowerBIServiceAccount `
	-ServicePrincipal `
	-Credential $credential `
	-TenantId $env:tenant_id


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

write-Host "Workspace complete" -ForegroundColor Green;


## ------------------------------------------------------
# 3. ADD AN ADMIN USER TO THE WORKSPACE
## ------------------------------------------------------
write-host "`n...Adding admin user to the workspace"

# check if the admin user already exists 
$wsusersResponse = Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/users" `
	-Method GET `
	| ConvertFrom-Json 
	
$wsusers = $wsusersResponse.value | where-object {$_.emailAddress -eq $env:userAdminUsername} 
if ($null -eq $wsusers) {

	Write-Host "- Adding user '$env:userAdminUsername' to '$env:workspacename' workspace."
	Add-PowerBIWorkspaceUser `
	   -Id $($workspace.id) `
	   -UserPrincipalName $env:userAdminUsername `
	   -AccessRight "Admin"

} else {
	write-host "- User $env:userAdminUsername' already has access to the '$env:workspacename' workspace."
}

write-Host "Admin user added to workspace" -ForegroundColor Green;


## ------------------------------------------------------
## 4. UPLOAD PBIX REPORT
## ------------------------------------------------------
write-host "`n...Importing .pbix report."
$new_report = New-PowerBIReport `
	-Path $env:pbixFilePath `
	-Name $env:datasetname `
	-ConflictAction "CreateOrOverwrite" `
	-Workspace $workspace
    #-ConflictAction "CreateOrOverwrite" `
    
write-Host ".pbix report uploaded" -ForegroundColor Green;

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
#-Name "$env:datasetname" `
   
# take over 
Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/datasets/$($dataset.id)/Default.TakeOver" `
	-Method Post `
	-ErrorAction Stop;

write-host "Take over with SP complete" -ForegroundColor Green;

#Change the database server and db / params
write-host "`n...Update it DB params"

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
	
write-host "DB param change complete" -ForegroundColor Green;


## ------------------------------------------------------
## 6. UPDATE DATASET'S DATASOURCE CREDENTIALS
## ------------------------------------------------------
write-host "`n...Updating datasource credentials" -ForegroundColor Green

# Get the dataset's datasources
$datasrcResp = Get-PowerBIDatasource `
   -DatasetId $($dataset.id) `
   -WorkspaceId $($workspace.id) `

# update credentials
$dsCredential = @{
	credentialType = "Basic"
	basicCredentials = @{            
		username = $env:dbusername
		password = $env:dbpassword
	}
} | ConvertTo-Json 

Invoke-PowerBIRestMethod `
	-Url "gateways/$($datasrcResp.gatewayId)/datasources/$($datasrcResp.datasourceid)" `
	-Method PATCH `
	-Body $dsCredential `
	-ErrorAction Stop;

write-host "DB credentials updated" -ForegroundColor Green;