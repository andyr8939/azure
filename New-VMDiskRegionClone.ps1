<#
        .SYNOPSIS
        Create Azure VM Disk from Snapshot in a new region

        .DESCRIPTION
        Azure doesn't support moving VM Disks from one region to another unless you move the entire VM.
        So this script allows you to take a snapshot of an existing disk one region and create another disk in another region and resource group based on that snapshot
        and then swap the OS disk with the new one.

        .EXAMPLE
        PS> .\New-VMDiskRegionClone.ps1 -Subscription "MyTestSub" -SourceVM "vm-us1-web-1" -SourceRegionCode "us1" -TargetResourceGroup "rg-us2-webapp" -TargetRegionCode "us2" -TargetLocation "eastus2"

        .NOTES
        Created By - Andy Roberts - andyr8939@gmail.com
        Last Updated - 3rd May 2022
        Maintained - https://github.com/andyr8939/azure
#>

param(
    [Parameter(Mandatory = $true)]
    [string] $Subscription,

    [Parameter(Mandatory = $true)]
    [string] $SourceVM,

    [Parameter(Mandatory = $true)]
    [string] $SourceRegionCode,

    [Parameter(Mandatory = $true)]
    [string] $TargetResourceGroup,

    [Parameter(Mandatory = $true)]
    [string] $TargetRegionCode,

    [Parameter(Mandatory = $true)]
	[string] $TargetLocation
)

Set-AzContext -Subscription $Subscription

$sourceRSG = (Get-AzVM -Name $SourceVM).ResourceGroupName
$OrignalVM = Get-AzVM -Name $SourceVM

#######################################
# Create OS Disk from latest snapshot

# Get Source Disk Name
$sourceDisk = Get-AzDisk -ResourceGroupName $OrignalVM.ResourceGroupName -DiskName $OrignalVM.StorageProfile.OsDisk.Name
# Create New Disk Name with region changes
$targetDiskNewName = ($sourceDisk.Name -Replace ($SourceRegionCode, $TargetRegionCode))
# Get most recent snapshot for this VM
$snapshotFiltered = Get-AzSnapshot | Where-Object Name -like "*$SourceVM*" | Sort-Object TimeCreated -Descending | Select-Object -First 1 Name
$snapshot = Get-AzSnapshot -SnapshotName $snapshotFiltered.Name
# Create New Disk in current region
$diskConfig = New-AzDiskConfig -Location $sourceDisk.Location -CreateOption Copy -SourceResourceId $snapshot.Id -Zone $sourceDisk.Zones -osType "Windows" -SkuName $sourceDisk.Sku.Name

Write-Host "Creating New Disk from Latest Snapshot - $($snapshotFiltered.Name)" -BackgroundColor Green -ForegroundColor Black

New-AzDisk -DiskName $targetDiskNewName -Disk $diskConfig -ResourceGroupName $OrignalVM.ResourceGroupName


# Copy this Disk to the new Region
$newDisk = Get-AzDisk -ResourceGroupName $OrignalVM.ResourceGroupName -DiskName $targetDiskNewName

# Create the target disk config, adding the sizeInBytes with the 512 offset, and the -Upload flag
# If this is an OS disk, add this property: -OsType $sourceDisk.OsType
$targetDiskconfig = New-AzDiskConfig -SkuName $newDisk.Sku.Name -UploadSizeInBytes $($newDisk.DiskSizeBytes + 512) -Location $TargetLocation -CreateOption 'Upload' -Zone $newDisk.Zones -osType "Windows"

# Create the target disk (empty)
Write-Host "Creating New Disk $targetDiskNewName in $TargetResourceGroup and region $TargetLocation" -BackgroundColor Green -ForegroundColor Black
$targetDisk = New-AzDisk -ResourceGroupName $TargetResourceGroup -DiskName $targetDiskNewName -Disk $targetDiskconfig

# Get a SAS token for the source disk, so that AzCopy can read it
$sourceDiskSas = Grant-AzDiskAccess -ResourceGroupName $sourceRSG -DiskName $targetDiskNewName -DurationInSecond 86400 -Access 'Read'

# Get a SAS token for the target disk, so that AzCopy can write to it
$targetDiskSas = Grant-AzDiskAccess -ResourceGroupName $TargetResourceGroup -DiskName $targetDiskNewName -DurationInSecond 86400 -Access 'Write'

# Begin the copy!
Write-Host "Starting Copy of Source Disk to New Region and Resource Group" -BackgroundColor Green -ForegroundColor Black
azcopy copy $sourceDiskSas.AccessSAS $targetDiskSas.AccessSAS --blob-type PageBlob

# Revoke the SAS so that the disk can be used by a VM
Revoke-AzDiskAccess -ResourceGroupName $OrignalVM.ResourceGroupName -DiskName $targetDiskNewName

# Revoke the SAS so that the disk can be used by a VM
Revoke-AzDiskAccess -ResourceGroupName $TargetResourceGroup -DiskName $targetDiskNewName

# Swap the disks on the new VM
# Get the new disk that you want to swap in
$destinationVM = Get-AzVM -ResourceGroupName $TargetResourceGroup -Name ($SourceVM -Replace ($SourceRegionCode, $TargetRegionCode))
$disk = Get-AzDisk -ResourceGroupName $TargetResourceGroup -Name $targetDiskNewName
# Set the VM configuration to point to the new disk 
Write-Host "Swapping the OS Disk on $($destinationVM.Name) for new disk $targetDiskNewName from $($destinationVM.StorageProfile.OsDisk.Name)" -BackgroundColor Green -ForegroundColor Black
Set-AzVMOSDisk -VM $destinationVM -ManagedDiskId $disk.Id -Name $disk.Name 
# Update the VM with the new OS disk
Update-AzVM -ResourceGroupName $TargetResourceGroup -VM $destinationVM



