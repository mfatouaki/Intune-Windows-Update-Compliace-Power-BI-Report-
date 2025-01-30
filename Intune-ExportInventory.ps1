###############################################################################
# Intune-ExportInventory.ps1
# Version: 1.4
# Date   : 2024-12-18
# Author : Mehdi FATOUAKI
###############################################################################
# Purpose:
# Exports Intune inventory data to a CSV file using Microsoft Graph API,
# then uploads it to SharePoint via CSOM.
###############################################################################
# Required permissions:
# - DeviceManagementManagedDevices.Read.All
###############################################################################

###############################################################################
## Variables
###############################################################################
$WorkingDirectory      = "C:\Scripts\Intune-ExportInventory"
$OutputCSVFile         = "\\*.csv"

$AADClientApplicationCredentialsFile = "Insert .xml credentials path here"
$TenantId = "insert tenant ID here"

###############################################################################
## Functions
###############################################################################

function Get-CredentialsFromXML {
    param (
        [Parameter(Mandatory = $true)][string]$filePath
    )
    try {
        $creds = Import-CliXml -Path $filePath
        return $creds
    } catch {
        Write-Host "Error reading credentials from XML file: $($_.Exception.Message)"
        return $null
    }
}

function Get-AzureADToken {
    param(
        [Parameter(Mandatory = $true)][string]$TenantId,
        [Parameter(Mandatory = $true)][string]$ClientId,
        [Parameter(Mandatory = $true)][string]$ClientSecret
    )
    try {
        $body = @{
            grant_type    = "client_credentials"
            scope         = "https://graph.microsoft.com/.default"
            client_id     = $ClientId
            client_secret = $ClientSecret
        }
        $response = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -ContentType "application/x-www-form-urlencoded" -Body $body
        Write-Host "Token acquired successfully."
        return $response.access_token
    } catch {
        Write-Host "Error retrieving Azure AD Token: $($_.Exception.Message)"
        return $null
    }
}

function Get-IntuneDevices {
    param(
        [Parameter(Mandatory = $true)][string]$AccessToken
    )
    try {
        $headers = @{ Authorization = "Bearer $AccessToken" }
        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
        
        $allDevices = @()
        do {
            $response = Invoke-RestMethod -Headers $headers -Method Get -Uri $uri
            $allDevices += $response.value

            if ($response.'@odata.nextLink') {
                $uri = $response.'@odata.nextLink'
            } else {
                $uri = $null
            }
        } while ($uri)

        return $allDevices
    } catch {
        Write-Host "Error retrieving Intune devices: $($_.Exception.Message)"
        return @()
    }
}

###############################################################################
## Main
###############################################################################

Set-Location $WorkingDirectory
Start-Transcript "IntuneInventoryExport_Transcript.txt"

try {
    Write-Host "Authenticating to Azure AD..."

    $Creds = Get-CredentialsFromXML -filePath $AADClientApplicationCredentialsFile

    if (-not $Creds) {
        throw "Failed to retrieve credentials from XML."
    }

    $ClientId = $Creds.UserName
    $ClientSecret = $Creds.GetNetworkCredential().Password

    $AccessToken = Get-AzureADToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
    if (-not $AccessToken) {
        throw "Failed to acquire access token."
    }

    Write-Host "Retrieving Intune devices..."
# Retrieve devices using the function
$Devices = Get-IntuneDevices -AccessToken $AccessToken

# Check if there are any devices
if ($Devices.Count -eq 0) {
    Write-Host "No devices found in Intune inventory."
} else {
    # Export all properties of the devices to a CSV file
    Write-Host "Exporting all device data to CSV..."
    
    # Export to CSV with all properties
    $Devices | Export-Csv -Path $OutputCSVFile -NoTypeInformation -Encoding UTF8

    Write-Host "Device data exported to $OutputCSVFile"
}


} catch {
    Write-Host "Error: $($_.Exception.Message)"
} finally {
    Stop-Transcript
    Write-Host "Script completed."
}
