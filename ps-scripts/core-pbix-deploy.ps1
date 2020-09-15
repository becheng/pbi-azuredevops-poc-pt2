$env:client_id = "174407ec-539b-4f4c-822f-77639278931a"
$env:tenant_id = "9e54649d-2ff3-4f06-9561-d81f12cfcfa6"
$env:datasetname = "customer-report"
$env:workspacename = "customerZ"
$env:userAdmin = "anothertenantadmin@benchenggmail.onmicrosoft.com"
$env:pbixFilePath= "C:\Users\bencheng\temp\customer-report-v2.pbix"
$env:dbServerParamName = "dbServerParam"
$env:dbNameParamName = "dbNameParam"

#onprem datasource
$env:dbServerParamValue = "localhost\SQLEXPRESS"
$env:dbNameParamValue = "customerzdb"

# online datasources
#$env:dbServerParamValue = "customerxdbsvr.database.windows.net"
#$env:dbNameParamValue = "customerXdb"


# ---------------------------------

# variables 
write-host "client.id: $env:client_id"
write-host "tenant.id: $env:tenant_id"
write-host "tenant.id: $env:datasetname"
write-host "tenant.id: $env:workspacename"
write-host "userAdmin: $env:userAdmin"
write-host "pbixFilePath: $env:pbixFilePath"
write-host "dbServerParamName: $env:dbServerParamName"
write-host "dbServerParamValue: $env:dbServerParamValue"
write-host "dbNameParamName: $env:dbNameParamName"	
write-host "dbNameParamValue: $env:dbNameParamValue"	

#write-host "client_secret: $(client_secret)"


## SIGN IN WITH SP

write-host "`n...sign in with SP"
#$clientsec = "$(client_secret)" | ConvertTo-SecureString -AsPlainText -Force
$clientsec = "~~7Cl5R.u2Ur_N.~N93fgZVSkAT.vo0pH7" | ConvertTo-SecureString -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $env:client_id, $clientsec 
Connect-PowerBIServiceAccount `
	-ServicePrincipal `
	-Credential $credential `
	-TenantId $env:tenant_id


## MANAGE WORKSPACE

write-host "`n...Manage Workspace"
$workspace = Get-PowerBIWorkspace `
	-Name $env:workspacename

# create the workspace if it does not exists
if($null -eq $workspace){
	
	write-host "- creating new $env:workspacename workspace"
	
	$newWS = @{
		name = $env:workspacename
	} | ConvertTo-Json

	Invoke-PowerBIRestMethod `
		-Url "groups?workspaceV2=True" `
		-Method POST -Verbose `
		-Body $newWS `
		-ErrorAction Stop;

	$workspace = Get-PowerBIWorkspace `
		-Name $env:workspacename
		
} else {
	write-host "- $env:workspacename workspace already exists"
}

write-Host "Workspace complete" -ForegroundColor Green;


# ADD AN ADMIN USER TO THE WORKSPACE

write-host "`n...Adding admin user to the workspace"
# check if the admin user already exists 
$wsusersResponse = Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/users" `
	-Method GET `
	| ConvertFrom-Json 
	
$wsusers = $wsusersResponse.value | where-object {$_.emailAddress -eq $env:userAdmin} 
if ($null -eq $wsusers) {

	Write-Host "- Adding user '$env:userAdmin' to '$env:workspacename' workspace."
	$userReqBody = @{
		 emailAddress = $env:userAdmin
		 groupUserAccessRight = "Admin"
	 }  |  ConvertTo-Json

	Invoke-PowerBIRestMethod `
		-Url "groups/$($workspace.id)/users" `
		-Method Post `
		-Body $userReqBody `
		-ErrorAction Stop;
	
} else {
	write-host "- User $env:userAdmin' already has access to the '$env:workspacename' workspace."
}

write-Host "Admin user added to workspace" -ForegroundColor Green;


## UPLOAD PBIX REPORT

write-host "`n...Importing .pbix report."
New-PowerBIReport `
	-Path $env:pbixFilePath `
	-Name $env:datasetname `
	-ConflictAction "CreateOrOverwrite" `
	-Workspace $workspace
write-Host ".pbix report uploaded" -ForegroundColor Green;


## UPDATE DB PARAMS

write-host "`n...Take over the dataset with SP"
# list all datasets
$datasetsResp = Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/datasets" `
	-Method GET `
	| ConvertFrom-Json

# get only the target dataset 
$dataset = $datasetsResp.value | Where-Object {$_.name -eq $env:datasetname}
 
# take over 
Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/datasets/$($dataset.id)/Default.TakeOver" `
	-Method Post `
	-ErrorAction Stop;

write-host "Take over with SP complete" -ForegroundColor Green;


#Change the database server and db / params
write-host "`n...Update the DB params"
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




<# Update the dataset's credentials -- ONLY for online datasources

$env:dbusername = "wabbit"
$dbPswd = "Engineno9"

write-host "`n...Updating dataset db credentials"
$boundGateway = Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/datasets/$($dataset.id)/Default.GetBoundGatewayDataSources" `
	-Method GET `
	| ConvertFrom-Json `

$dsCredential = @{
	credentialType = "Basic"
	basicCredentials = @{            
		username = $env:dbusername
		password = $dbPswd
	}
} | ConvertTo-Json 
$dsCredential = @{
	credentialType ="Basic"
	basicCredentials = @{            
		username = $env:dbusername
		password = "$(dbpassword)"
	}
} | ConvertTo-Json 

write-host "$dsCredential + $($boundGateway.value.gatewayId) + $($boundGateway.value.id)"
Invoke-PowerBIRestMethod `
	-Url "gateways/$($boundGateway.value.gatewayId)/datasources/$($boundGateway.value.id)" `
	-Method PATCH `
	-Body $dsCredential 
#>