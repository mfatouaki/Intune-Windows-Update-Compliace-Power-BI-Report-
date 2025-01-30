###############################################################################
# WU_ComplianceReport.ps1
# Version: 1.0
# Date   : 2024-10-21
# Author : Mehdi FATOUAKI
###############################################################################
# History:
#  1.0: Original version
###############################################################################
# Required permissions:
#  - Intune Service Administrator
###############################################################################
# IMPORTANT:
#  - Ensure that the account running this script is not an admin account.
#  - The script requires an active internet connection to download patch lists.
###############################################################################
# Script principles:
#  Generates an Intune Patch Compliance report by performing the following steps:
#   1. Prompt for the path to the Intune device data CSV file.
#   2. Import Intune device data.
#   3. Download and create the Microsoft Patch List.
#   4. Calculate patch compliance status for each device.
#   5. Generate and output the compliance report in CSV format.
###############################################################################


###############################################################################
## Variables 
###############################################################################

# User Input Section
$DeviceList = "*.csv"

# Script Variables
$WorkingFolder = "insert path here"    
$startTime = Get-Date
$Date = Get-Date -Format "MMMM dd, yyyy"
$OutFileMP = "$WorkingFolder\MicrosoftPatchList.csv"
$OutFileLP = "$WorkingFolder\MicrosoftLatestPatchList.csv"
$MergeOverallFile = "$WorkingFolder\MergeOverallFile.csv"
$IntuneUpdatesReport = "$WorkingFolder\Report\intuneupdatesreport.csv"
$PatchingMonth = ""
$PatchReleaseDays = 0

$LogFile = "$WorkingFolder\Log\WindowsUpdateComplianceReport.log"

###############################################################################
## Stript Start
###############################################################################

# Start logging
Start-Transcript -Path $LogFile -Append

# Create working folder if not present
if (-not (Test-Path -Path $WorkingFolder)) {
    New-Item -ItemType Directory -Path $WorkingFolder -Force
}

###############################################################################
Write-Host "Step 1: Import Intune Device Dump"
###############################################################################

$DevicesInfos = Import-Csv -Path $DeviceList |
    Select-Object @{
        Name = "DeviceId"; Expression = { $_.("id") }
    }, @{
        Name = "DeviceName"; Expression = { $_.("deviceName") }
    }, @{
        Name = "OSVersion"; Expression = { $_.("osVersion") }
    }, @{
        Name = "Primary user UPN"; Expression = { $_.("userPrincipalName") }
    }, @{
        Name = "Last Synch Date"; Expression = { $_.("lastSyncDateTime") }
    }, @{
        Name = "JoinType"; Expression = { $_.JoinType }
    }, @{
        Name = "Model"; Expression = { $_.Model }
    }, @{
        Name = "Total storage"; Expression = { $_.("totalStorageSpaceInBytes") }
    }, @{
        Name = "Free storage"; Expression = { $_.("freeStorageSpaceInBytes") }
    }, @{
        Name = "OS"; Expression = { $_.("operatingSystem") }
    }

###############################################################################
Write-Host "Step 2: Downloading and Creating Microsoft Patch List"
###############################################################################

$buildInfoArray = @()

# Add each Build and Operating System to the array
"26100,Windows 11 24H2","22631,Windows 11 23H2","22623,Windows 11 22H2","22621,Windows 11 22H2 B1","22471,Windows 11 21H2","22468,Windows 11 21H2 B6","22463,Windows 11 21H2 B5",
"22458,Windows 11 21H2 B4","22454,Windows 11 21H2 B3","22449,Windows 11 21H2 B2","22000,Windows 11 21H2 B1","21996,Windows 11 Dev",
"19045,Windows 10 22H2","19044,Windows 10 21H2","19043,Windows 10 21H1","19042,Windows 10 20H2","19041,Windows 10 2004","19008,Windows 10 20H1",
"18363,Windows 10 1909","18362,Windows 10 1903","17763,Windows 10 1809","17134,Windows 10 1803","16299,Windows 10 1709 FC","15254,Windows 10 1709",
"15063,Windows 10 1703","14393,Windows 10 1607","10586,Windows 10 1511","10240,Windows 10 1507","9600,Windows 8.1",
"7601,Windows 7" | ForEach-Object {
    $buildInfo = New-Object -TypeName PSObject
    $buildInfo | Add-Member -MemberType NoteProperty -Name "Build" -Value ($_ -split ",")[0]
    $buildInfo | Add-Member -MemberType NoteProperty -Name "OperatingSystem" -Value ($_ -split ",")[1]
    $buildInfoArray += $buildInfo
}

$CollectedData = $BuildDetails = $PatchDetails = $MajorBuilds = $LatestPatches = @()
$BuildDetails = $buildInfoArray

# Download Windows Master Patch List
$URI = "https://aka.ms/Windows11UpdateHistory"
$CollectedData += (Invoke-WebRequest -Uri $URI -UseBasicParsing -ErrorAction Continue).Links
$URI = "https://support.microsoft.com/en-us/help/4043454"
$CollectedData += (Invoke-WebRequest -Uri $URI -UseBasicParsing -ErrorAction Continue).Links

# Filter Windows Master Patch List
if ($CollectedData) {
    $CollectedDataAll = ($CollectedData | Where-Object { $_.class -eq "supLeftNavLink" -and $_.outerHTML -notmatch "mobile" }).outerHTML
    $CollectedData = ($CollectedData | Where-Object { $_.class -eq "supLeftNavLink" -and $_.outerHTML -match "KB" -and $_.outerHTML -notmatch "out-of-band" -and $_.outerHTML -notmatch "Preview" -and $_.outerHTML -notmatch "mobile" }).outerHTML
    $PatchTuesdayOSBuilds = $CollectedData | ForEach-Object { if ($_ -match 'OS Build (\d+\.\d+)') { $matches[1] } }
    $CollectedDataPreview = $CollectedDataAll | Select-String -Pattern '(?<=<a class="supLeftNavLink" data-bi-slot="\d+" href="\/en-us\/help\/\d+">).*?(?=<\/a>)' | ForEach-Object {
        if ($_ -match 'KB' -and $_ -notmatch 'out-of-band' -and $_ -match 'Preview' -and $_ -notmatch 'mobile') { $_ }
    }
    $OSPreBuilds = [regex]::Matches($CollectedDataPreview, '\d+\.\d+').Value | Sort-Object -Unique
    $PreviewOSBuilds = $OSPreBuilds -join "`n"
    $CollectedDataOutofBand = $CollectedDataAll | Select-String -Pattern '(?<=<a class="supLeftNavLink" data-bi-slot="\d+" href="\/en-us\/help\/\d+">).*?(?=<\/a>)' | ForEach-Object {
        if ($_ -match 'KB' -and $_ -match 'out-of-band' -and $_ -notmatch 'Preview' -and $_ -notmatch 'mobile') { $_ }
    }
    $OSOOBBuilds = [regex]::Matches($CollectedDataOutofBand, '\d+\.\d+').Value | Sort-Object -Unique
    $OutofBandOSBuilds = $OSOOBBuilds -join "`n"
}

# Consolidate the Master Patch and Format the output
foreach ($Line in $CollectedData) {
    $ReleaseDate = $PatchID = ""
    $Builds = @()
    $ReleaseDate = (($Line.Split(">")[1]).Split("&")[0]).trim()
    if ($ReleaseDate -match "build") { $ReleaseDate = ($ReleaseDate.split("-")[0]).trim() }
    $PatchID = ($Line.Split(";-") | Where-Object { $_ -match "KB" }).trim()
    $Builds = ($Line.Split(",) ") | Where-Object { $_ -like "*.*" }).trim()
    foreach ($BLD in $Builds) {
        $MjBld = $MnBld = ""
        $MjBld = $BLD.Split(".")[0]
        $MnBld = $BLD.Split(".")[1]
        foreach ($Line1 in $BuildDetails) {
            $BldNo = $OS = ""
            $BldNo = $Line1.Build
            $OS = $Line1.OperatingSystem
            $MajorBuilds += $BldNo
            if ($MjBld -eq $BldNo) { break }
            else { $OS = "Unknown" }
        }
        $PatchDetails += [PSCustomObject] @{
            OperatingSystem = $OS
            Build           = $BLD
            MajorBuild      = $MjBld
            MinorBuild      = $MnBld
            PatchID         = $PatchID
            ReleaseDate     = $ReleaseDate
        }
    }
}

$MajorBuilds = $MajorBuilds | Select-Object -Unique | Sort-Object -Descending
$PatchDetails = $PatchDetails | Select-Object OperatingSystem, Build, MajorBuild, MinorBuild, PatchID, ReleaseDate -Unique | Sort-Object MajorBuild, PatchID -Descending
$PatchDetails | Export-Csv -Path $OutFileMP -NoTypeInformation

# Finalize Patch List
if ($PatchingMonth) {
    foreach ($Bld in $MajorBuilds) {
        $LatestPatches += $PatchDetails | Where-Object {
            $_.MajorBuild -eq $Bld -and
            $_.ReleaseDate -match $PatchingMonth.Year -and
            $_.ReleaseDate -match $PatchingMonth.Month
        } | Sort-Object PatchID -Descending | Select-Object -First 1
    }
} else {
    $Today = Get-Date
    $LatestDate = ($PatchDetails | Select-Object -First 1).ReleaseDate
    $DiffDays = ([datetime]$Today - [datetime]$LatestDate).Days
    if ([int]$DiffDays -gt [int]$PatchReleaseDays) {
        foreach ($Bld in $MajorBuilds) {
            $LatestPatches += $PatchDetails | Where-Object { $_.MajorBuild -eq $Bld } | Sort-Object PatchID -Descending | Select-Object -First 1
        }
    } else {
        $Month = ((Get-Date).AddMonths(-1)).ToString("MMMM dd, yyyy").Split(" ,")[0]
        $Year = ((Get-Date).AddMonths(-1)).ToString("MMMM dd, yyyy").Split(" ,")[1]
        $PatchingMonth = [PSCustomObject]@{ Month = $Month; Year = $Year }
        foreach ($Bld in $MajorBuilds) {
            $LatestPatches += $PatchDetails | Where-Object {
                $_.MajorBuild -eq $Bld -and
                $_.ReleaseDate -match $PatchingMonth.Year -and
                $_.ReleaseDate -match $PatchingMonth.Month
            } | Sort-Object PatchID -Descending | Select-Object -First 1
        }
        # Adding Latest Patches for Other Builds Missing above
        $M = ((Get-Date).ToString("MMMM dd, yyyy")).split(" ,")[0]
        $Y = ((Get-Date).ToString("MMMM dd, yyyy")).split(" ,")[1]
        foreach ($Bld1 in $MajorBuilds) {
            $Found = 0
            foreach ($Line in $LatestPatches) {
                $Bld2 = ""
                $Bld2 = $Line.MajorBuild
                if ($Bld1 -eq $Bld2) { $Found = 1; break }
            }
            if ($Found -eq 0) {
                $LatestPatches += $PatchDetails | Where-Object {
                    $_.MajorBuild -eq $Bld1 -and
                    $_.ReleaseDate -notlike "$M*$Y"
                } | Sort-Object PatchID -Descending | Select-Object -First 1
            }
        }
    }
}

$LatestPatches = $LatestPatches | Select-Object OperatingSystem, Build, MajorBuild, MinorBuild, PatchID, ReleaseDate, @{ Name = "OSVersion"; Expression = { "10.0.$($_.Build)" } }
$LatestPatches | Export-Csv -Path $OutFileLP -NoTypeInformation

# Determine most recent patch date
$mostRecentDate = $LatestPatches | Sort-Object -Property ReleaseDate -Descending | Select-Object -First 1
$patchtuesday = $mostRecentDate.ReleaseDate

# Import all released patches
$AllReleasedPatchs = Import-Csv -Path $OutFileMP
$AllReleasedPatchs = $AllReleasedPatchs | Select-Object OperatingSystem, Build, MajorBuild, MinorBuild, PatchID, ReleaseDate, @{ Name = "OSVersion"; Expression = { "10.0.$($_.Build)" } }
$AllReleasedPatchs | Export-Csv -Path $OutFileMP -NoTypeInformation

# Create Intune Device Hardware Info
$IntuneDeviceHardwareInfo = @()
foreach ($AllReleasedPatch in $AllReleasedPatchs) {
    $PatchStatus = if ($LatestPatches.OSversion -contains $AllReleasedPatch.osversion) { "Compliant" } else { "Non-Compliant" }
    $timeSpan = (Get-Date).Subtract([DateTime]::ParseExact($AllReleasedPatch.ReleaseDate, "MMMM d, yyyy", [CultureInfo]::InvariantCulture))
    $NotPatchSince = if ($PatchStatus -eq 'Compliant') { "Compliant" } else { $timeSpan.Days.ToString() + " days" }
    $RequiredPatch = if ($PatchStatus -eq "Compliant") {
        "Compliant"
    } else {
        $matchingPatch = $LatestPatches | Where-Object { $_.MajorBuild -eq $AllReleasedPatch.MajorBuild -and $_.OSVersion -eq $AllReleasedPatch.OSVersion }
        if ($matchingPatch) { "Compliant" } else {
            $latestMajorBuildPatches = $LatestPatches | Where-Object { $_.MajorBuild -eq $AllReleasedPatch.MajorBuild }
            if ($latestMajorBuildPatches) {
                $latestMajorBuildPatches.PatchID -join ", "
            } else { "BNE" }
        }
    }

    $IntuneDeviceHSProps = [ordered] @{
        OperatingSystem = $AllReleasedPatch.OperatingSystem
        OSVersion       = $AllReleasedPatch.OSVersion
        Build           = $AllReleasedPatch.Build
        MajorBuild      = $AllReleasedPatch.MajorBuild
        MinorBuild      = $AllReleasedPatch.MinorBuild
        PatchID         = $AllReleasedPatch.PatchID
        ReleaseDate     = $AllReleasedPatch.ReleaseDate
        PatchStatus     = $PatchStatus
        NotPatchSince   = $NotPatchSince
        RequiredPatch   = $RequiredPatch
    }

    $IntuneDeviceHSobject = New-Object -Type PSObject -Property $IntuneDeviceHSProps
    $IntuneDeviceHardwareInfo += $IntuneDeviceHSobject
}

$FinalReport = $IntuneDeviceHardwareInfo | Select-Object OperatingSystem, OSVersion, Build, MajorBuild, MinorBuild, PatchID, ReleaseDate, PatchStatus, NotPatchSince, RequiredPatch
$FinalReport | Export-Csv -Path $MergeOverallFile -NoTypeInformation

###############################################################################
Write-Host "Step 3: Generating Windows Updates Compliance Report"
###############################################################################

$compliantCount = 0
$manualCheckCount = 0
$nonCompliantCount = 0
$complianceReport = @()
$totalDevices = $DevicesInfos.Count
$progress = 0

foreach ($device in $DevicesInfos) {
    $deviceName = $device."DeviceName"
    $Model = $device.Model
    $OS = $device.OS
    $Totalstorage = ($device."Total storage" / 1024).ToString("N2")
    $Freestorage = ($device."Free storage" / 1024).ToString("N2")
    $deviceOSVersion = $device."OSVersion"
if (-not [string]::IsNullOrWhiteSpace($deviceOSVersion) -and $deviceOSVersion -match "\.") {
    $OSVersion = $deviceOSVersion.Split(".")[2]
} else {
    $OSVersion = "Unknown"
}

$OSVersionV = switch ($OSVersion) {
    '10240' { 'Win10-1507' }
    '10586' { 'Win10-1511' }
    '14393' { 'Win10-1607' }
    '15063' { 'Win10-1703' }
    '16299' { 'Win10-1709' }
    '17134' { 'Win10-1803' }
    '17763' { 'Win10-1809' }
    '18362' { 'Win10-1903' }
    '18363' { 'Win10-1909' }
    '19041' { 'Win10-2004' }
    '19042' { 'Win10-20H2' }
    '19043' { 'Win10-21H1' }
    '19044' { 'Win10-21H2' }
    '19045' { 'Win10-22H2' }
    '22000' { 'Win11-21H2' }
    '22621' { 'Win11-22H2' }
    '22631' { 'Win11-23H2' }
    '26100' { 'Win11-24H2' }
    '0'     { 'No OS version' }
    '7601'  { 'Win7-Or-Server' }
    $null   { 'No OS version' }
    default { $deviceOSVersion }
}
     
    
    $JoinType = $device.JoinType
    $PrimaryUserUPN = $device."Primary user UPN"
    $matchingPatch = $LatestPatches | Where-Object { $_.OSVersion -eq $deviceOSVersion }
    $complianceStatus = if ($matchingPatch.OSVersion -ge $deviceOSVersion) { "Compliant" } else { "Non-Compliant" }
    $notPatchSince = $FinalReport | Where-Object { $_.OSVersion -eq $deviceOSVersion } | Select-Object -ExpandProperty NotPatchSince
    $notPatchSince = if ([string]::IsNullOrWhiteSpace($notPatchSince)) { "Manually Check" } else { $notPatchSince }
    $PatchID = $FinalReport | Where-Object { $_.OSVersion -eq $deviceOSVersion } | Select-Object -ExpandProperty PatchID
    $PatchID = if ([string]::IsNullOrWhiteSpace($PatchID)) { "Manually Check Installed KB" } else { $PatchID }
    $ReleaseDate = $FinalReport | Where-Object { $_.OSVersion -eq $deviceOSVersion } | Select-Object -ExpandProperty ReleaseDate
    $ReleaseDate = if ([string]::IsNullOrWhiteSpace($ReleaseDate)) { "Manually Check Release Date" } else { $ReleaseDate }
    $RequiredPatch = $FinalReport | Where-Object { $_.OSVersion -eq $deviceOSVersion } | Select-Object -ExpandProperty RequiredPatch
    $RequiredPatch = if ([string]::IsNullOrWhiteSpace($RequiredPatch)) { "Manually Check Required Patch" } else { $RequiredPatch }
    $LastSynch = $device."Last Synch Date"

    if ($RequiredPatch -eq "Compliant") { $compliantCount++ }
    elseif ($RequiredPatch -eq "Manually Check Required Patch") { $manualCheckCount++ }
    else { $nonCompliantCount++ }

    $reportRow = [PSCustomObject] @{
        "DeviceName"                 = $deviceName
        "PrimaryUserUPN"             = $PrimaryUserUPN
        "OS"                         = $OS
        "Model"                      = $Model
        "Totalstorage (GB)"          = $Totalstorage
        "Freestorage (GB)"           = $Freestorage

        "LastSynch"                  = $LastSynch
        "OSVersion"                  = $OSVersionV
        "InstalledKB"                = $PatchID
        "InstalledKB_ReleaseDate"    = $ReleaseDate
        "PatchingStatus"             = $complianceStatus
        "DevcieNotPatchSince_InDays" = $notPatchSince
        "Latest_RequiredPatch"       = $RequiredPatch
    }
    $complianceReport += $reportRow
    $progress++
    $percentComplete = [String]::Format("{0:0.00}", ($progress / $totalDevices) * 100)
    Write-Progress -Activity "Generating WUfB Compliance Report" -Status "Progress: $percentComplete% Complete" -PercentComplete $percentComplete
}

$complianceReport | Export-Csv -Path $IntuneUpdatesReport -NoTypeInformation
$totalCount = $compliantCount + $manualCheckCount + $nonCompliantCount
$compliancePercentage = "{0:N2}" -f ($compliantCount / $totalCount * 100)

# Display summary
Write-Host ""
Write-Host "Summary"
Write-Host "-Total Device Count: $totalCount"
Write-Host "-Total Non-Compliant Device Count: $nonCompliantCount"
Write-Host "-Total Manually Check Required Patch Device Count: $manualCheckCount"
Write-Host "-Total Compliant Device Count: $compliantCount"
Write-Host "-Patching Compliance Percentage: $compliancePercentage%"
Write-Host ""
Write-Host "$LatestDate, Intune Patching compliance Report is available at this location: $IntuneUpdatesReport"

# Stop logging
Stop-Transcript

# Cleanup temporary files
if (Test-Path $OutFileMP) { Remove-Item $OutFileMP }
if (Test-Path $OutFileLP) { Remove-Item $OutFileLP }
if (Test-Path $MergeOverallFile) { Remove-Item $MergeOverallFile }

