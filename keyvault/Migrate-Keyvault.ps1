<#
        .SYNOPSIS
        Backup Secrets and Certificates from an Azure Keyvault and Restore to another Keyvault

        .DESCRIPTION
        There is no native way to migrate Secrets and Certificates from one Keyvault to another without exporting the items one by one.
        This script allows you to specify two keyvaults and providing you have access, to copy the secrets to the new vault.

        .EXAMPLE
        PS> .\Migrate-Keyvault.ps1 -SubscriptionID "MySub" -SourceKeyVault "kv-original" -DestKeyVault "kv-new"

        .NOTES
        Created By - Andy Roberts - andyr8939@gmail.com
        Last Updated - 27th July 2022
#>

param(
    [Parameter(Mandatory = $true)]
    [string] $SubscriptionID,

    [Parameter(Mandatory = $true)]
    [string] $SourceKeyvault,

    [Parameter(Mandatory = $true)]
    [string] $DestKeyvault
)

## Set your subscription
Set-AzContext -Subscription $SubscriptionID

############################################################################
# Backup Secrets

$secrets = Get-AzKeyVaultSecret -VaultName $SourceKeyvault | Where-Object ContentType -NotLike "*application*" #avoid getting certificates
foreach (${item} in ${secrets}) {
    Backup-AzKeyVaultSecret -VaultName $item.VaultName -Name $item.Name -OutputFile "$($item.Name).secret" | Out-Null
    Write-Output "Exporting Secret - $($item.Name) from Keyvault - $($item.VaultName)"
}

# Restore Secrets

$secretsToRestore = (Get-ChildItem -Path . -Filter *.secret).Name
foreach (${item} in ${secretsToRestore}) {
    Restore-AzKeyVaultSecret -VaultName $DestKeyvault -InputFile $item | Out-Null
    Write-Output "Importing Secret - $item to Keyvault - $DestKeyvault"
}

############################################################################

# Backup Certs
$certsToBackup = Get-AzKeyVaultCertificate -VaultName $SourceKeyvault
foreach (${item} in ${certsToBackup}) {
    Backup-AzKeyVaultCertificate -VaultName $item.VaultName -Name $item.Name -OutputFile "$($item.Name).cert" | Out-Null
    Write-Output "Exporting Certificate - $($item.Name) from Keyvault - $($item.VaultName)"
}

# Restore Certs
$certsToRestore = (Get-ChildItem -Path . -Filter *.cert).Name
foreach (${item} in ${certsToRestore}) {
    Restore-AzKeyVaultCertificate -VaultName $DestKeyvault -InputFile $item | Out-Null
    Write-Output "Importing Certificate - $item to Keyvault $DestKeyvault"
}

############################################################################

# Cleanup Backed Up Files
Write-Output "Cleaning up transfer files"
Remove-Item *.secret | Out-Null
Remove-Item *.cert | Out-Null

