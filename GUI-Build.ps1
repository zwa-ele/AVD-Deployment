#######################################################################################
#######################################################################################
###################################// ZWA-ELE //#######################################
#######################################################################################
############################// AVD POC Frontend | XAML //##############################
#######################################################################################
#######################################################################################


#----------------------------------------------------------------------------------------------------------------------------------------------------#
#######################################################################################
#########################// New Directory & Start Logs //##############################
#######################################################################################
$TestlogFilePath = Test-Path -Path "C:\ProgramData\ZWA-ELE\AVD-POC\Library"

if ($TestlogFilePath -eq $false) {
        New-Item -ItemType "directory" -Path "C:\ProgramData\ZWA-ELE\AVD-POC\Library" 
        New-Item -ItemType "directory" -Path "C:\ProgramData\ZWA-ELE\AVD-POC\Logs" 
}

else 

{ 


} 
Start-Transcript -Path "C:\ProgramData\ZWA-ELE\AVD-POC\Logs\GUI.log"
CD $PSScriptRoot

[void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

#----------------------------------------------------------------------------------------------------------------------------------------------------#
#######################################################################################
############################// XAML Import & Clean  //#################################
#######################################################################################

Add-Type -AssemblyName presentationframework, presentationcore
$wpf = @{ }
$inputXML = Get-Content -Path ".\MainWindow.xaml"
$inputXMLClean = $inputXML -replace 'mc:Ignorable="d"','' -replace "x:N",'N' -replace 'x:Class=".*?"','' -replace 'd:DesignHeight="\d*?"','' -replace 'd:DesignWidth="\d*?"',''
[xml]$xaml = $inputXMLClean
$reader = New-Object System.Xml.XmlNodeReader $xaml
$tempform = [Windows.Markup.XamlReader]::Load($reader)
$namedNodes = $xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]")
$namedNodes | ForEach-Object {$wpf.Add($_.Name, $tempform.FindName($_.Name))}

#----------------------------------------------------------------------------------------------------------------------------------------------------#
#######################################################################################
########################//  Run XAML & Save Variables  //##############################
#######################################################################################

$wpf.Submit.add_Click({

$fileToCheck = "C:\ProgramData\ZWA-ELE\AVD-POC\Library\lib.json"
if (Test-Path $fileToCheck -PathType leaf)
{
    Remove-Item $fileToCheck
}


        #Convert form to Vars
        $SecurityID = $wpf.SGObjectID.text
        $Domain = $wpf.ManagedDomainName.text
        $Prefix = $wpf.NamingPrefix.text
        $DomainPassword = $wpf.DomainPassword.password
        $SubID = $wpf.SubscriptionID.text
        $Region = $wpf.region.SelectedItem.name



$Data = @{
        SecurityObjectID = $SecurityID
        Domain  = $Domain
        Prefix = $Prefix
        DomainPassword = $DomainPassword
        Subsciption = $SubID
        Region = $region

}

$Data | ConvertTo-Json | Add-Content -Path "C:\ProgramData\ZWA-ELE\AVD-POC\Library\lib.json"




$wpf.AVD_Window.Close() | Out-Null

#----------------------------------------------------------------------------------------------------------------------------------------------------#
#######################################################################################
##############################// Install & Connnect //#################################
#######################################################################################

#Trust PSGallery
Set-PSRepository -Name "PSGallery" -InstallationPolicy "Trusted"

#Install Module
Write-Host Installing Az Modules
Install-Module -Name Az
Install-Module -Name Az.DesktopVirtualization -RequiredVersion 2.0.1
Install-Module -Name Az.ADDomainServices

Write-Host Importing Az Modules
#Import Module
Import-Module -Name Az.DesktopVirtualization
Import-Module -Name Az.Resources
Import-Module -Name Az.Network
Import-Module -Name Az.Storage
Import-Module -Name Az.ADDomainServices


Write-Host Connecting to AzureAD
Connect-AzureAD
Write-Host Connected to AzureAD

Write-Host Connecting to Azure Account
Connect-AzAccount
Write-Host Connected to Azure Account

#----------------------------------------------------------------------------------------------------------------------------------------------------#
#######################################################################################
#############################// Run Build Enviroment //################################
#######################################################################################

Write-Host Running Build Enviroment PS
.\Build-Enviroment.ps1

#----------------------------------------------------------------------------------------------------------------------------------------------------#
#######################################################################################
#####################// Finished, Print Logs and Display Message //####################
#######################################################################################


        [System.Windows.MessageBox]::Show("This application and its scripts have now completed.`r`nWhats next?`r`nGo check in Azure for your new Resource Group, VNet, Storage Account & Share. Then publish your image to your hostpool.", "Script Finished")
})
$wpf.AVD_Window.ShowDialog() | Out-Null


Stop-Transcript