<#
        .SYNOPSIS
        Convert a PFX Certificate to Base64

        .DESCRIPTION
        IaC Tools like Terraform require certificates to be provided in Base64 format so this script converts a PFX to BASE64 ready to use

        .EXAMPLE
        PS> .\Convert-PFXtoBase64.ps1 MyWebsiteCert.pfx

        .NOTES
        Created By - Andy Roberts - andyr8939@gmail.com
        Last Updated - 3rd May 2022
        Maintained - https://github.com/andyr8939/azure
#>

$PFXCert = $args[0]
$fileContentBytes = get-content $PFXCert -AsByteStream


[System.Convert]::ToBase64String($fileContentBytes) | Out-File "$(($PFXCert)-Replace(".pfx","-base64.txt"))"
Write-Host "Your base64 cert is at - $($($PFXCert)-Replace(".pfx","-base64.txt"))"
