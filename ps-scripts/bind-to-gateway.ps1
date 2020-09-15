# PS script to Bind to PBI on-prem gateway

## SIGN IN WITH MA

write-host "`n...Sign in using MA"
$userAdminPassword = $(mauserPassword) | ConvertTo-SecureString -asPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($env:userAdminUsername, $userAdminPassword)
Connect-PowerBIServiceAccount `
	-Credential $credential 


## GET WORKSPACE

$workspace = Get-PowerBIWorkspace -Name $env:workspacename


## TAKE OVER DS WITH MA

write-host "`n...TakeOver dataset with MA"

# get all datasets in workspace
$datasetsResp = Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/datasets" `
	-Method Get `
	| ConvertFrom-Json 

# get only the target dataset 
$dataset = $datasetsResp.value | Where-Object {$_.name -eq $env:datasetname}
 
# take over 
Invoke-PowerBIRestMethod `
	-Url "groups/$($workspace.id)/datasets/$($dataset.id)/Default.TakeOver" `
	-Method Post `
	-ErrorAction Stop;

write-host "Take over with MA complete..." -ForegroundColor Green;


## BIND TO GATEWAY

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


## SET THE REFRESH SCHEDULE (If provided)

if($env:scheduleJson -ne $null)
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


## REFRESH THE DATASET 

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



## ASSIGN DS BACK TO SP

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
#>