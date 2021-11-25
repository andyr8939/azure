<#
    .SYNOPSIS
    Automatically grow the allocated storage of an Azure SQL Elastic Pool from an Azure Runbook

    .DESCRIPTION
    When executed from an Azure Monitor Runbook Trigger, this script will expand the elastic pool by
    its specified amount, up to a hard limit.
    It also won't scale if it doesn't meet a scaling threshold, initially defined as 85%

    Created by Andy Roberts (andyr8939@gmail.com)

    .PARAMETER WebhookData
    Raw data passed to the runbook from Azure Monitor

    .PARAMETER poolIncreaseMB
    How much space to add to the pool on each scale event.  Initially set at 50 GB.

    .PARAMETER poolIncreaseLimitMB
    A hard limit of how big the pool can increase too.  Initially set at 1 TB.
#>

param
(
[Parameter (Mandatory=$false)]
[object] $WebhookData,
[Parameter (Mandatory= $false)]
[String] $poolIncreaseMB = "51200", # 50GB
[Parameter (Mandatory= $false)]
[String] $poolIncreaseLimitMB = "1048576" # 1TB
)

$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Connect-AzAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

Write-Output "This runbook was started from webhook $WebhookName."
# Collect Webhook Data and convert to use with JSON
$WebhookBody = (ConvertFrom-Json -InputObject $WebhookData.RequestBody)

# Obtain the WebhookBody containing the AlertContext and any details we need
$AlertContext = [object] ($WebhookBody.data).context
$SubId = $AlertContext.subscriptionId
$ResourceGroupName = $AlertContext.resourceGroupName
$ResourceType = $AlertContext.resourceType
$ResourceName = $AlertContext.resourceName
$status = ($WebhookBody.data).status
$threshold = $WebhookBody.data.context.condition.allOf.threshold

# Write results to output for logging
Write-output "Subscription - $SubId"
Write-output "RSG Name - $ResourceGroupName"
Write-output "Resource Type - $ResourceType"
Write-output "Resrouce Name - $ResourceName"
Write-output "Status - $status"
Write-output "Threshold - $threshold"

# Only scale if over 85% allocated, to give chance to manually clean up on earlier 80% trigger with just email
if ($threshold -le 85) {
    Write-Output "Threshold is $threshold which does not require scaling.  Email only sent."
    Write-Output "Scaling Occurs once threshold is over 90%"
    Exit   
}

# As its over 85% threshold, prepare to scale
# Get Resources for SQL and Elastic Pool
$sqlServer = Get-AzSqlServer -ResourceGroupName $ResourceGroupName
$elasticPool = Get-AzSqlElasticPool -ElasticPoolName $ResourceName -ResourceGroupName $ResourceGroupName -ServerName $sqlserver.ServerName

# Add 50GB to the current size
$newElasticPoolStorageGB = $elasticpool.StorageMB + $poolIncreaseMB # Add 50GB

# Check new size and if it will exceed 1TB as a hard limit to prevent runaway scale
if ($newElasticPoolStorageGB -ge $poolIncreaseLimitMB) {
    $failError = "Elastic Pool Size for $ResourceName will exceed its allowed upper limit of $($poolIncreaseLimitMB /1024) GB so cannot scale"
    Write-Output $failError
    throw $failError
}

Write-Output "Current Elastic Pool Size for $ResourceName is $($elasticpool.StorageMB /1024) GB"
Write-Output "Scaling Elastic Pool $ResourceName to $($newElasticPoolStorageGB /1024) GB"

# Scale Elastic Pool to new size
$elasticpool | Set-AzSqlElasticPool -StorageMB $newElasticPoolStorageGB

Write-Output "New Elastic Pool Size for $ResourceName is $($newElasticPoolStorageGB /1024) GB"
