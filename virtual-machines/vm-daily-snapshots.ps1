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

########################################################################################

# Set Subscription 
# Set-AzContext -SubscriptionId $subscription_Id

# Set Generic Variables
# Force Date to NZ Time as Runbook is in West Europe so causes issues with Date Overlap
$nzDate = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::Now,"New Zealand Standard Time")
$mydate = "$($nzDate.Day)-$($nzDate.Month)-$($nzDate.Year)"
$snapshotPrefix = "AutoSnapshot"

# Get All VMs in the subscription to take snapshots of
$vm = Get-AzVM | Where-Object Name -notlike "*meraki*"

foreach ($item in $vm) {
    
    # Get OS Disk ID
    $disk_source_snapshot = $item.StorageProfile.OsDisk.ManagedDisk.Id

    # Set Snapshot Name
    $snapshotName = "$snapshotPrefix-$($item.Name)-$mydate"

    # Check if snapshot name is over the 80 character limit and truncate
    if ($snapshotName.Length -ge "80") {
        Write-Output "Snapshot name is too big - $($snapshotName)" -ForegroundColor Red -BackgroundColor White
        $shortName = ($item.Name).substring(0,40)
        $snapshotName = "$snapshotPrefix-$($shortName)-$mydate"
        Write-Output "New Snapshot Name - $($snapshotName)"
    }

    # Process OS Disk Snapshot
    $os_snapshot =  New-AzSnapshotConfig -SourceUri $disk_source_snapshot -Location $item.Location -CreateOption copy -Incremental
    New-AzSnapshot -Snapshot $os_snapshot -SnapshotName $snapshotName -ResourceGroupName $item.ResourceGroupName

    # Now check if any data disks and loop through all attached

    if ($item.StorageProfile.DataDisks.Name -eq "") {
        # exit as not data disks found
    }
    else {

        # Define variables needed for rest of the foreach
        $location = $item.Location

        # Define data disk names for next loop if more than 1 disks
        $datadisks = $item.StorageProfile.DataDisks

        foreach ($item in $datadisks) {

            # Get Data Disk ID
            $datadisk_id = (Get-AzDisk -DiskName $item.Name | Where-Object Location -eq $location).Id

            # Added below for when disks are not in the same resouce group as the VM - Happened for OCC
            $datadisk_rsg = (Get-AzDisk -DiskName $item.Name | Where-Object Location -eq $location).ResourceGroupName

            # Set Snapshot Name
            $snapshotName = "$snapshotPrefix-$($item.Name)-$mydate"
            
            # Check if snapshot name is over the 80 character limit and truncate
            if ($snapshotName.Length -ge "80") {
                Write-Output "Snapshot name is too big - $($snapshotName)" -ForegroundColor Red -BackgroundColor White
                $shortName = ($item.Name).substring(0,40)
                $snapshotName = "$snapshotPrefix-$($shortName)-$mydate"
                Write-Output "New Snapshot Name - $($snapshotName)"
            }

            # Process Data Disk Snapshot
            $datadisk_snapshot =  New-AzSnapshotConfig -SourceUri $datadisk_id -Location $location -CreateOption copy -Incremental
            New-AzSnapshot -Snapshot $datadisk_snapshot -SnapshotName $snapshotName -ResourceGroupName $datadisk_rsg
        }
    }
}

#####################################
# Cleanup old snapshots

$DaysBack = "-4"
$CurrentDate = Get-Date
$DateToDelete = $CurrentDate.AddDays(($DaysBack))

# Get all Snapshots that meet criteria for cleanup 
$snapshots_to_cleanup = Get-AzSnapshot | Where-Object { $_.TimeCreated -lt $DateToDelete -and $_.Name -like "*$snapshotPrefix*" }

# Get Resource Groups for each snapshot so we can remove the locks to allow delete
$resourcegroups_for_locks = $snapshots_to_cleanup.ResourceGroupName | Select-Object -Unique

# Get all Resource Locks that will be removed, add them to an array to later re-create and then delete
$lockdetails = @()
foreach ($item in $resourcegroups_for_locks) {
    $lockdetails += Get-AzResourceLock -ResourceGroupName $item
    Get-AzResourceLock -ResourceGroupName $item | Remove-AzResourceLock -Force
}

# Cleanup all the snapshots
foreach ($item in $snapshots_to_cleanup) {
    Remove-AzSnapshot -SnapshotName $item.Name -ResourceGroupName $item.ResourceGroupName -Force -AsJob
}

# Wait for jobs to finish before adding locks back
Write-Output "Waiting for Remove Snapshot Jobs to Finish"
Get-Job -Command 'Remove-AzSnapshot*' | Wait-Job -Timeout 600

# Recreate all the resource locks with the original details
foreach ($item in $lockdetails) {
    
    # handle error if notes doesnt exist otherwise it fails, and set to empty string
    if(Get-Member -inputobject $item.Properties -name "notes" -Membertype Properties){
        $notes = $item.Properties.notes
        }else{
            $notes = " "
        }
    New-AzResourceLock -LockLevel $item.Properties.level -LockNotes $notes -LockName $item.Name -ResourceGroupName $item.ResourceGroupName -Force
}
