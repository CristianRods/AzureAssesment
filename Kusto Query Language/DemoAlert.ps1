﻿<#
DemoAlert.Ps1
Written by Taiob M Ali
SqlWorldWide.com

This script will create 
    A resource group 
    A logical SQL server
    Empty sample databases
    Create Log Analytics Workspace
    Setting up an action group (Azure Alert)
    Creates a Log Alert Rule (Scheduled Query Rule type) using Kusto Query Language
    Clean up code at the end

Script can take between 5~8 minutes during my test. Mileage will vary in your case

Credit:
https://docs.microsoft.com/en-us/azure/sql-database/sql-database-get-started-powershell
https://gallery.technet.microsoft.com/scriptcenter/Get-ExternalPublic-IP-c1b601bb
#>


# Starting with Azure PowerShell version 7.0, Azure PowerShell requires PowerShell version 5.0. 
# To check the version of PowerShell running on your machine, run the following command.
# If you have an outdated version, 
# visit https://docs.microsoft.com/en-us/powershell/scripting/setup/installing-windows-powershell?view=powershell-6#upgrading-existing-windows-powershell.

break
# Run below code if you need to check what version of PowerShell you are running
# $PSVersionTable.PSVersion

# Run below code if Az Module is not in your profile 
Import-Module Az 

# Sign in to Azure
#$VerbosePreference = $DebugPreference = "Continue"
Connect-AzAccount

#if you need to see the list of your subscription
#$SubscriptionList =Get-AzSubscription
#$SubscriptionList
#Use below code if you have multiple subscription and you want to use a particular one
Set-AzContext -SubscriptionId '18d92f52-ac34-4379-ab8b-5a5106f1c54e'

<#
Breaking change warnings are a means for the cmdlet authors to communicate with the end users any upcoming breaking changes in the cmdlet. Most of these changes will be taking effect in the next breaking change release.
How do I get rid of the warnings?
To suppress these warning messages, set the environment variable 'SuppressAzurePowerShellBreakingChangeWarnings' to 'true'.
#>
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

# Declare variables
# The region and resource group name
$resourceGroupName = "sqlalertdemo1"
$rgLocation = "East US"  
# Log Analytics workspace name
$workspaceName = "Sqlalertdemo2"
# The logical server name: Use a random value or replace with your own value (do not capitalize)
$sqlServerName = "sqlalertdemoserver"
# The database name
$alertDemoDatabase = "sqlalertdemodatabase"

# Set an admin login and password for your database
# The login information for the server
$adminlogin = "taiob"
#Replace with password file location
$password = Get-Content "C:\password.txt"

# The ip address range that you want to allow to access your server - change as appropriate
$ipinfo = Invoke-RestMethod http://ipinfo.io/json 
$startip = $ipinfo.ip
$endip = $ipinfo.ip 

#Check if resource group exist
$resGrpChk = Get-AzResourceGroup `
    -Name $resourceGroupName `
    -ev notPresent `
    -ea 0

if ($resGrpChk)
  {  
    #Delete resource group
    Remove-AzResourceGroup `
        -Name $resourceGroupName -Confirm   
    Write-Host 'Resource group deleted' `
        -fore white `
        -back green
  }
 
#Creates new resource group
New-AzResourceGroup `
    -Name $resourceGroupName `
    -Location $rgLocation    

$resGrpChk = Get-AzResourceGroup `
    -Name $resourceGroupName `
    -ev Present `
    -ea 1
if ($resGrpChk)
{
Write-Host 'Resource group created' `
    -fore white `
    -back green 
 }  
  
#Create a Azure SQL Server
New-AzSqlServer `
    -ResourceGroupName $resourceGroupName `
    -ServerName $sqlServerName `
    -Location $rgLocation `
    -SqlAdministratorCredentials $(New-Object -TypeName System.Management.Automation.PSCredential `
    -ArgumentList $adminlogin, $(ConvertTo-SecureString -String $password -AsPlainText -Force))

#Configure a server firewall rule for job server
 New-AzSqlServerFirewallRule `
    -ResourceGroupName $resourceGroupName `
    -ServerName $sqlServerName `
    -FirewallRuleName "TaiobDesktop" `
    -StartIpAddress $startip `
    -EndIpAddress $endip

#Set Allow access to Azure services 
New-AzSqlServerFirewallRule `
    -ServerName $sqlServerName `
    -ResourceGroupName $resourceGroupName  `
    -AllowAllAzureIPs

#Create an empty database
New-AzSqlDatabase  `
    -ResourceGroupName $resourceGroupName `
    -ServerName $sqlServerName `
    -DatabaseName $alertDemoDatabase `
    -Edition "Standard" `
    -RequestedServiceObjectiveName "S0" `
    -MaxSizeBytes 10737418240 

#Create a log analytics workspace
New-AzOperationalInsightsWorkspace `
    -Location $rgLocation `
    -Name $workspaceName `
    -Sku Standard `
    -ResourceGroupName $resourceGroupName

# List of solutions to enable for the log analytics workspace you create above
$Solutions = "Security", "Updates", "SQLAssessment"
# Add solutions
foreach ($solution in $Solutions) {
    Set-AzOperationalInsightsIntelligencePack `
    -ResourceGroupName $resourceGroupName `
    -WorkspaceName $workspaceName `
    -IntelligencePackName $solution -Enabled $true
}

# Setting up Azure SQL Database to send diagonstic data to log analytics workspace created above
$workspaceId = (Get-AzResource -name $workspaceName).ResourceId
$databaseId = (Get-AzsqlDatabase -ServerName $sqlServerName -DatabaseName $alertDemoDatabase -ResourceGroupName $resourceGroupName).ResourceId

# Make sure your subscription is registered for microsoft.insights
# If you get an error about 'not registered' read this
# https://kasunkodagoda.com/2019/03/10/registering-azure-resource-providers-to-enable-azure-features/
Set-AzDiagnosticSetting `
    -WorkspaceId $workspaceId `
    -ResourceId $databaseId `
    -Enabled $True `
    -Name "sqlalertdemo"

#Setting up action group to use with the alert
$emailaddress = 'taiob@sqlworldwide.com'
$phoneNumber = 9784272092
$emailDBA = 
New-AzActionGroupReceiver `
    -Name 'emailDBA' `
    -EmailAddress $emailaddress
$smsDBA = 
New-AzActionGroupReceiver  `
    -Name 'smsDBA' -SmsReceiver `
    -CountryCode '1' `
    -PhoneNumber $phoneNumber 
$phoneDBA = 
New-AzActionGroupReceiver `
    -Name 'phoneDBA' `
    -VoiceReceiver -VoiceCountryCode '1' `
    -VoicePhoneNumber $phoneNumber 
 
Set-AzActionGroup `
    -Name 'notifydbadeadlock' `
    -ResourceGroupName $resourceGroupName `
    -ShortName 'deadlock' `
    -Receiver $emailDBA,$smsDBA,$phoneDBA

# Retreive action group id
$actionGroupId =(Get-AzResource -name 'notifydbadeadlock').ResourceId

<#
I am using a simple Kusto query here for demo purpose.
In production I will use this one:
AzureMetrics
| where ResourceProvider == "MICROSOFT.SQL"
| where TimeGenerated >=ago(60min)
| where MetricName in ('deadlock')
| parse _ResourceId with * "/microsoft.sql/servers/" Resource // subtract Resource name for _ResourceId
| summarize Deadlock_max_60Mins = max(Maximum) by Resource, MetricName
#>

# Creating the Azure alert
$source =
New-AzScheduledQueryRuleSource  `
    -Query "AzureMetrics | where MetricName == 'deadlock' "  `
    -DataSourceId $workspaceId

$schedule = 
New-AzScheduledQueryRuleSchedule `
    -FrequencyInMinutes 15 `
    -TimeWindowInMinutes 30
    
$triggerCondition = 
New-AzScheduledQueryRuleTriggerCondition `
    -ThresholdOperator  "GreaterThan" `
    -Threshold 0 
    
$aznsActionGroup = 
New-AzScheduledQueryRuleAznsActionGroup `
    -ActionGroup $actionGroupId `
    -EmailSubject "Deadlock Found" 

$alertingAction = 
New-AzScheduledQueryRuleAlertingAction `
    -AznsAction $aznsActionGroup `
    -Severity "3" `
    -Trigger $triggerCondition

New-AzScheduledQueryRule `
    -ResourceGroupName $resourceGroupName `
    -Location $rgLocation `
    -Action $alertingAction `
    -Enabled $true `
    -Description "This alert will be fired when a deadlock is found in last 30 minutes " `
    -Source $source `
    -Schedule $schedule `
    -Name "Found Deadlock Alert"

# Enable the log analytics auditing policy of an Azure SQL server   
Set-AzSqlServerAudit `
    -ResourceGroupName $resourceGroupName `
    -ServerName $sqlServerName `
    -LogAnalyticsTargetState Enabled `
    -WorkspaceResourceId $workspaceId
    
#Run SimulateDeadlock.sql script

#Clean up by removing resource group name
#Run this command after you are done testing with all other script
#Remove-AzResourceGroup -ResourceGroupName $resourceGroupName
 