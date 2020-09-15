$Psversion = (Get-Host).Version

if($Psversion.Major -ge 7)
{
	if (!(Get-Module "DataGateway")) {
		Install-Module -Name DataGateway 
	}

	$securePassword = "[client secret here]" | ConvertTo-SecureString -AsPlainText -Force;
	$ApplicationId ="[client/app id]";
	$Tenant = "[AAD tenant id]";
	$GatewayName = "MyLocalGateway";
	$RecoverKey = "Demo@123" | ConvertTo-SecureString -AsPlainText -Force;
	$userIDToAddasAdmin = "[AAD account with a PBI pro license Object Id]" 

	#Gateway Login
	Connect-DataGatewayServiceAccount -ApplicationId $ApplicationId -ClientSecret $securePassword  -Tenant $Tenant

	#Installing Gateway
	Install-DataGateway -AcceptConditions 

	#Configuring Gateway
	$GatewayDetails = Add-DataGatewayCluster -Name $GatewayName -RecoveryKey $RecoverKey -OverwriteExistingGateway

	#Add User as Admin
	Add-DataGatewayClusterUser -GatewayClusterId $GatewayDetails.GatewayObjectId -PrincipalObjectId $userIDToAddasAdmin -AllowedDataSourceTypes $null -Role Admin

} else {

	exit 1

}