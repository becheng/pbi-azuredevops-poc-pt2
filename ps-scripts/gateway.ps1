$Psversion = (Get-Host).Version

if($Psversion.Major -ge 7)
{
	if (!(Get-Module "DataGateway")) {
		Install-Module -Name DataGateway 
	}

	$securePassword = "~~7Cl5R.u2Ur_N.~N93fgZVSkAT.vo0pH7" | ConvertTo-SecureString -AsPlainText -Force;
	$ApplicationId ="174407ec-539b-4f4c-822f-77639278931a";
	$Tenant = "9e54649d-2ff3-4f06-9561-d81f12cfcfa6";
	$GatewayName = "MyLocalGateway";
	$RecoverKey = "Demo@123" | ConvertTo-SecureString -AsPlainText -Force;
	$userIDToAddasAdmin = "3152448a-5865-4cc9-9f5a-f64b53aba876" #anothertenantadmin@bencheng.onmicrosoft.com

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