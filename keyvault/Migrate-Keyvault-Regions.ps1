<#
        .SYNOPSIS
        Backup Secrets and Certificates from an Azure Keyvault and Restore to another Keyvault in another region

        .DESCRIPTION
        There is no native way to migrate Secrets and Certificates from one Keyvault to another without exporting the items one by one.
        This is also not supported accross regions.
        This script allows you to specify two keyvaults which can be in different regions, and providing you have access, to copy the secrets to the new vault.

        .EXAMPLE
        PS> .\Migrate-Keyvault-Regions.ps1 -SubscriptionID "MySub" -SourceKeyVault "kv-original" -DestKeyVault "kv-new"

        .NOTES
        Created By - Andy Roberts - andyr8939@gmail.com
        Last Updated - 28th July 2022
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
Write-Output "Connecting to Azure Subscription - $SubscriptionID - with Powershell "
Set-AzContext -Subscription $SubscriptionID | Out-Null
Write-Output "Connecting to Azure Subscription - $SubscriptionID - with AZ CLI "
az account set --subscription $SubscriptionID

############################################################################
# Backup Secrets

$secrets = Get-AzKeyVaultSecret -VaultName $SourceKeyvault | Where-Object ContentType -NotLike "*application*" #avoid getting certificates
foreach (${item} in ${secrets}) {
    Write-Output "Exporting Secret - $($item.Name) from Keyvault - $($item.VaultName)"
    az keyvault secret download --file "$($item.Name).secret" --name $($item.Name) --vault-name $($item.VaultName) --output none
}

# Restore Secrets

$secretsToRestore = (Get-ChildItem -Path .\* -Include "*.secret").BaseName
foreach (${item} in ${secretsToRestore}) {
    Write-Output "Importing Secret - $item to Keyvault $DestKeyvault"
    az keyvault secret set --vault-name $DestKeyvault -n $item -f "$item.secret" --output none
    az keyvault secret set-attributes --vault-name $DestKeyvault -n $item --tags copied_from=$SourceKeyvault --output none
    Remove-Item "$item.secret" | Out-Null
}

############################################################################

# Backup Certs
$certsToBackup = Get-AzKeyVaultCertificate -VaultName $SourceKeyvault
foreach (${item} in ${certsToBackup}) {
    Write-Output "Exporting Certificate - $($item.Name) from Keyvault - $($item.VaultName)"
    az keyvault secret download --file "$($item.Name).pfx" --encoding base64 --name $($item.Name) --vault-name $($item.VaultName) --output none
}

$certsToRestore = (Get-ChildItem -Path .\* -Include "*.pfx").BaseName #Only Get CER as dont want duplicates
foreach (${item} in ${certsToRestore}) {
    Write-Output "Importing Certificate - $item to Keyvault $DestKeyvault"
    az keyvault certificate import --vault-name $DestKeyvault -n $item -f "$item.pfx" --output none
    az keyvault certificate set-attributes --vault-name $DestKeyvault -n $item --tags copied_from=$SourceKeyvault --output none
    Remove-Item "$item.pfx" | Out-Null
}
