
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
## SIGN IN WITH MA
## ------------------------------------------------------
write-host "`n...Sign in using MA"
$userAdminPassword = $(mauserPassword) | ConvertTo-SecureString -asPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($env:userAdminUsername, $userAdminPassword)
Connect-PowerBIServiceAccount `
	-Credential $credential 


## ------------------------------------------------------
## TAKE OVER WORKSPACE with MA 
## ------------------------------------------------------
write-host "...Taking over dataset with MA";

# Get workspace
$workspace = Get-PowerBIWorkspace -Name $env:workspacename

# get all datasets in workspace
$datasetsResp = Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/datasets" `
	-Method Get `
	| ConvertFrom-Json 

# get only the target dataset 
$dataset = $datasetsResp.value | Where-Object {$_.name -eq $env:datasetname}
 
# take over the dataset 
Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/datasets/$($dataset.id)/Default.TakeOver" `
	-Method Post `
	-ErrorAction Stop;

write-host "Take over with MA complete..." -ForegroundColor Green;


## ------------------------------------------------------
## BIND TO GATEWAY
## ------------------------------------------------------

# Discover bindable gateways
write-host "`n...Discover Gateways"
$gatewayDataSources = Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/datasets/$($dataset.id)/Default.DiscoverGateways" `
	-Method GET | ConvertFrom-Json `
	-ErrorAction Stop;	

# get only the target gateway
$gateway = $gatewayDataSources.value | Where-Object {$_.name -eq $env:targetGatewayName} 
write-host "Found Gateway '$env:targetGatewayName'; gatewayObjectId=$($gateway.id)" -ForegroundColor Green

# Bind 
write-host "`n...Binding to Gateway"
$bindReqBody = @{
	gatewayObjectId = "$($gateway.id)"
} | ConvertTo-Json

Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/datasets/$($dataset.id)/Default.BindToGateway" `
	-Method Post `
	-Body $bindReqBody `
	-ErrorAction Stop;
	
write-Host "Gateway binding completed" -ForegroundColor Green;


## ------------------------------------------------------
## SET THE REFRESH SCHEDULE (If provided)
## ------------------------------------------------------
if($null -ne $env:scheduleJson)
{
	write-Host "`n...Creating Refresh Schedule...";
	
	$refreshBody = @{
	value = @{
		enabled = 'true'
		notifyOption = "NoNotification"
		days = @("Sunday","Tuesday","Friday","Saturday")
		times = @("07:00","11:30","16:00","23:30")
		localTimeZoneId = "UTC"
	}			
	} | ConvertTo-Json

	Invoke-PowerBIRestMethod `
		-Method PATCH `
		-Url "groups/$($workspace.id)/datasets/$($dataset.id)/refreshSchedule" `
		-Body $env:scheduleJson `
		-ErrorAction Stop;
		
	write-Host "Created Refresh Schedule" -ForegroundColor Green;
}


## ------------------------------------------------------
## REFRESH THE DATASET 
## ------------------------------------------------------
# Note!!! only a max of 8 refreshes allowed in the non-premium workspace, after which 400/Bad Requests will be recieved 
# Note2 - Refresh must be issued after the bind to gateway otherwise the gateway's datasource will not be mapped.
 
write-host "`n...Refreshing dataset"
# other options: MailOnCompletion, NoNotification, MailOnFailure
# Note: using NoNotification for poc, but if using MailOnFailure, MailOnCompletion will need to setup emails via the api otherwise will recieved 400/Bad Request  
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
## ASSIGN DS BACK TO SP
## ------------------------------------------------------

# wait for 5 secs
Start-Sleep -s 5

write-host "`n...Take back ownership with the SP account"
$clientsec = "$(client_secret)" | ConvertTo-SecureString -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $env:client_id, $clientsec 
Connect-PowerBIServiceAccount -ServicePrincipal -Credential $credential -TenantId $env:tenant_id

# take over 
Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/datasets/$($dataset.id)/Default.TakeOver" `
	-Method Post `
	-ErrorAction Stop;
	
write-Host "Take over to SP completed" -ForegroundColor Green;
