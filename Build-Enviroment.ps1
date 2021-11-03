#######################################################################################
#######################################################################################
###################################// ZWA-ELE //#######################################
#######################################################################################
#########// Create AADDS, Resource Groups, Storage Account VM & Network //#############
#######################################################################################
#######################################################################################

#----------------------------------------------------------------------------------------------------------------------------------------------------#
#######################################################################################
######################// Set Form Variables & Connect  //##############################
#######################################################################################

[void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

#Import Libary
$Library = Get-Content 'C:\ProgramData\ZWA-ELE\AVD-POC\Library\lib.json' | Out-String | ConvertFrom-Json

#Libary Vars -> Static
$SubscriptionID = $Library.Subsciption
$FriendlyName = $Library.Prefix
$ObjectID = $Library.SecurityObjectID
$ManagedDomainName = $Library.Domain
$Password = $Library.DomainPassword
$Location = $Library.Region


#Static Var
$RDPip = "202.174.37.69"
$StorageAccountName = "fslogics1"
$ShareName = "fslshare"
$HostPoolType = "Pooled"
$MaxSessionLimit = "7"
$LoadBalancerType = "Breadthfirst"
$PasswordGen2 = ([char[]]([char]33..[char]95) + ([char[]]([char]97..[char]126)) + 0..9 | sort {Get-Random})[0..8] -join ''
$PasswordGen3 = -join ((65..90) + (97..122) | Get-Random -Count 5 | % {[char]$_})

#Var + Text
$HostPoolName = $FriendlyName + "-Desktop"
$AaddsDomainName = "AADS." + $ManagedDomainName
$NSGName = $FriendlyName + "-aaddsNSG"
$ResourceGroupName_Global = $FriendlyName + "-Global"
$ResourceGroupName_AADDS = $FriendlyName + "-AADDS"
$VMname = $FriendlyName + "-GI"
$PublicIPName = $FriendlyName + "-PublicIP"
$VnetName_Global = $FriendlyName + "-GlobalVNET"
$SubnetName_AADDS = $FriendlyName + "-AADDSSubNet"
$SubNetName_WVD = $FriendlyName + "-WVDSubNet"
$AaddsAdminUserUpn = "AADS-Administrator@" + $ManagedDomainName
$PasswordProfile = New-Object -TypeName Microsoft.Open.AzureAD.Model.PasswordProfile
$PasswordProfile.Password = $Password
$AppGroupName = $FriendlyName + '-AppGroup'
$WorkSpaceName = $FriendlyName + '-WorkSpace'
$VMLocalAdminUser = $FriendlyName + '-localadmin'
$Plaintext = "W" + $PasswordGen2 + $PasswordGen3
$VMLocalAdminSecurePassword = "W" + $PasswordGen2 + $PasswordGen3 | ConvertTo-SecureString -Force -AsPlainText

#Storage String
$StorageString1 = "/subscriptions/" + $SubscriptionID
$StorageString2 = "/resourceGroups/" + $ResourceGroupName_Global
$StorageString3 = "/providers/Microsoft.Storage/storageAccounts/" + $StorageAccountName
$StorageString4 = "/fileServices/default/fileshares/" + $ShareName
$StorageScope = $StorageString1 + $StorageString2 + $StorageString3 + $StorageString4

#AADDS String
$AADDSString1 = "/subscriptions/" + $SubscriptionID
$AADDSString2 = "/resourceGroups/" + $ResourceGroupName_Global
$AADDSString3 = "/providers/Microsoft.Network/virtualNetworks/" + $VnetName_Global
$AADDSString4 = "/subnets/" + $SubnetName_AADDS
$AADDSScope = $AADDSString1 + $AADDSString2 + $AADDSString3 + $AADDSString4

#Tag
function Get-AusTime {
  $time = Get-Date
  $AUStime = $Time.AddHours(11.0)
  return $AusTime
}

#----------------------------------------------------------------------------------------------------------------------------------------------------#
#######################################################################################
############################// Resource Group Creation //##############################
#######################################################################################

Write-Host Creating Resource Groups

New-AzResourceGroup `
-Name $ResourceGroupName_Global  `
-Location $Location  `

New-AzResourceGroup `
  -Name $ResourceGroupName_AADDS `
  -Location $Location

#----------------------------------------------------------------------------------------------------------------------------------------------------#
#######################################################################################
########################// Virtual Network & Subnet Creation //########################
#######################################################################################

Write-Host Creating Network and SNETs


$WVDSubnet = New-AzVirtualNetworkSubnetConfig `
  -Name $SubNetName_AADDS `
  -AddressPrefix 10.0.1.0/24 `

$AaddsSubnet = New-AzVirtualNetworkSubnetConfig `
  -Name $SubnetName_WVD `
  -AddressPrefix 10.0.2.0/24 `

# Create the virtual network in which you will enable Azure AD Domain Services.
  New-AzVirtualNetwork `
  -ResourceGroupName $ResourceGroupName_Global `
  -Location $Location `
  -Name $VnetName_Global `
  -AddressPrefix 10.0.0.0/16 `
  -Subnet $AaddsSubnet,$WVDSubnet `

#----------------------------------------------------------------------------------------------------------------------------------------------------#
#######################################################################################
############################// Virtual Network Permisions //###########################
#######################################################################################


# Create a rule to allow inbound TCP port 3389 traffic from Microsoft secure access workstations for troubleshooting
$nsg201 = New-AzNetworkSecurityRuleConfig -Name AllowRD `
    -Access Allow `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 201 `
    -SourceAddressPrefix $RDPip `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange 3389

# Create a rule to allow TCP port 5986 traffic for PowerShell remote management
$nsg301 = New-AzNetworkSecurityRuleConfig -Name AllowPSRemoting `
    -Access Allow `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 301 `
    -SourceAddressPrefix AzureActiveDirectoryDomainServices `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange 5986

# Create the network security group and rules
$nsg = New-AzNetworkSecurityGroup `
    -Name $NSGName `
    -ResourceGroupName $ResourceGroupName_Global `
    -Location $Location `
    -SecurityRules $nsg201,$nsg301

# Get the existing virtual network resource objects and information
$vnet_NSG = Get-AzVirtualNetwork -Name $VnetName_Global -ResourceGroupName $ResourceGroupName_Global
$subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet_NSG -Name $SubnetName_AADDS
$addressPrefix = $subnet.AddressPrefix

# Associate the network security group with the virtual network subnet
Set-AzVirtualNetworkSubnetConfig -Name $SubnetName_AADDS `
    -VirtualNetwork $vnet_NSG `
    -AddressPrefix $addressPrefix `
    -NetworkSecurityGroup $nsg
$vnet_NSG | Set-AzVirtualNetwork


#----------------------------------------------------------------------------------------------------------------------------------------------------#
#######################################################################################
############################// Storage Account Creation //#############################
#######################################################################################

Write-Host Creating Storage Account and FSL Share

New-AzStorageAccount `
        -ResourceGroupName $ResourceGroupName_Global  `
        -AccountName $storageAccountName  `
        -Location $location  `
        -Type Standard_LRS  `
        -AccessTier Hot

New-AzRmStorageShare `
        -ResourceGroupName $ResourceGroupName_Global `
        -StorageAccountName $storageAccountName `
        -Name $ShareName

#----------------------------------------------------------------------------------------------------------------------------------------------------#
#######################################################################################
########################// NTFS Share Creation & Permisions //#########################
#######################################################################################

Update-AzStorageAccountNetworkRuleSet  `
      -ResourceGroupName $ResourceGroupName_Global  `
      -Name $storageAccountName  `
      -DefaultAction allow

Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName_Global -Name $VnetName_Global | Set-AzVirtualNetworkSubnetConfig -Name $SubNetName_WVD -AddressPrefix 10.0.2.0/24 -ServiceEndpoint "Microsoft.Storage" | Set-AzVirtualNetwork
$subnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName_Global -Name $VnetName_Global | Get-AzVirtualNetworkSubnetConfig -Name $SubNetName_WVD

$FileShareContributorRole = Get-AzRoleDefinition "Storage File Data SMB Share Contributor" 
#Assign the custom role to the target identity with the specified scope.
New-AzRoleAssignment -ObjectId $ObjectID -RoleDefinitionName $FileShareContributorRole.Name -Scope $StorageScope

#----------------------------------------------------------------------------------------------------------------------------------------------------#
#######################################################################################
######################// AADDS Admin & Admin Group Creation  //########################
#######################################################################################

Write-Host Creating AADDS
Write-Host ..............
Write-Host "This can take upto 30 minutes, please ensure you do not loose connection to the internet"
Write-Host ..............

#Create AADDS Admin Service Account
New-AzureADUser `
      -DisplayName "AADS Administrator" `
      -UserPrincipalName $AaddsAdminUserUpn `
      -Passwordprofile $PasswordProfile `
      -AccountEnabled $true `
      -MailNickName "AADS-Administrator"

New-AzureADServicePrincipal -AppId "2565bd9d-da50-47d4-8b85-4c97f669dc36"

# Group Creation and delegated 
$GroupObjectId = Get-AzureADGroup `
  -Filter "DisplayName eq 'AADS Administrator'" | `
  Select-Object ObjectId


if (!$GroupObjectId) {
  $GroupObjectId = New-AzureADGroup -DisplayName "AAD DC Administrators" `
    -Description "Delegated group to administer Azure AD Domain Services" `
    -SecurityEnabled $true `
    -MailEnabled $false `
    -MailNickName "AADDCAdministrators"
  }
else {
  Write-Output "Admin group already exists."
}

$UserObjectId = Get-AzureADUser `
  -Filter "UserPrincipalName eq '$AaddsAdminUserUpn'" | `
  Select-Object ObjectId

Add-AzureADGroupMember -ObjectId $GroupObjectId.ObjectId -RefObjectId $UserObjectId.ObjectId
Register-AzResourceProvider -ProviderNamespace Microsoft.AAD


#----------------------------------------------------------------------------------------------------------------------------------------------------#
#######################################################################################
#################################// Enable AADDS  //###################################
#######################################################################################

Write-Host Deploying AADDS


# Azure AD Domain Services for the directory.
$replicaSetParams = @{
  Location = $Location
  SubnetId = $AADDSScope
}

$replicaSet = New-AzADDomainServiceReplicaSet @replicaSetParams

$domainServiceParams = @{
  Name = $AaddsDomainName
  ResourceGroupName = $ResourceGroupName_AADDS
  DomainName = $AaddsDomainName
  ReplicaSet = $replicaSet
}
New-AzADDomainService @domainServiceParams

#----------------------------------------------------------------------------------------------------------------------------------------------------#
#######################################################################################
###########################// Enable AADDS Auth to Share  //###########################
#######################################################################################


Set-AzStorageAccount `
    -ResourceGroupName $ResourceGroupName_Global `
    -Name $storageAccountName `
    -EnableAzureActiveDirectoryDomainServicesForFile $true


#----------------------------------------------------------------------------------------------------------------------------------------------------#
#######################################################################################
###########################// Create HostPool & WorkSpace  //##########################
#######################################################################################

Write-Host "Registering the subscription for Microsoft.DesktopVirtualization"
Register-AzResourceProvider -ProviderNamespace Microsoft.DesktopVirtualization

Write-Host Creating HostPool and Workspace
Write-Host 

New-AzWvdHostPool -ResourceGroupName $ResourceGroupName_Global `
  -Name $HostPoolName `
  -WorkspaceName $WorkSpaceName `
  -HostPoolType $HostPoolType `
  -LoadBalancerType $LoadBalancerType `
  -Location eastus `
  -DesktopAppGroupName $AppGroupName `
  -PreferredAppGroupType Desktop 

New-AzWvdWorkspace -ResourceGroupName $ResourceGroupName_Global `
  -Name $WorkSpaceName `
  -Location 'eastus' `
  -FriendlyName $WorkSpaceName `
  -ApplicationGroupReference $null

Write-Host Created HostPool and Workspace

#----------------------------------------------------------------------------------------------------------------------------------------------------#
#######################################################################################
#############################// Create Blank Gold Image  //############################
#######################################################################################

Add-Type -AssemblyName System.Windows.Forms
$UserResponse= [System.Windows.Forms.MessageBox]::Show("Would you like to create a blank gold image VM now?" , "Gold Image Creation" , 4)

if ($UserResponse -eq "YES" ) 
{
 
Write-Host Creating Blank Gold Image
Write-Host \\
Write-Host "This can take up to 10 minutes, please wait...."


New-AzPublicIpAddress `
-Name $PublicIPName `
-ResourceGroupName $ResourceGroupName_Global `
-Location $Location `
-AllocationMethod 'Static'  `
-SKU 'Basic' `
-IpAddressVersion = 'IPv4'


$Credential = New-Object System.Management.Automation.PSCredential ($VMLocalAdminUser, $VMLocalAdminSecurePassword)

$ImageName = "MicrosoftWindowsDesktop:Windows-10:21h1-evd:latest"

# Create the VM
New-AzVM `
  -ResourceGroupName $ResourceGroupName_Global `
  -Name $VMName `
  -Location $Location `
  -ImageName $ImageName `
  -Size Standard_B2ms `
  -VirtualNetworkName $VnetName_Global `
  -SubnetName $SubNetName_WVD `
  -SecurityGroupName $NSGName `
  -PublicIpAddressName $PublicIPName `
  -Credential $Credential `
  -OpenPorts 3389 `
  -Verbose


  [System.Windows.MessageBox]::Show("The username and password for your new VM is about to be displayed on screen. Please ensure you take note of these, as they are not saved anywhere after you close the window.", "Warning!")

  [System.Windows.MessageBox]::Show("Your new VM has been created. The local admin user name is $VMLocalAdminUser and the password for the account is $plaintext", "Local Admin & Password")
  

} 

else 

{ 
 

} 
