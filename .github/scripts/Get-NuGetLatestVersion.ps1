<#
.SYNOPSIS
    Queries NuGet.org for the latest version of a package.

.DESCRIPTION
    Calls the NuGet.org v3 API to retrieve the latest version of a package and
    compares it against the present version to determine if an update is available.

.PARAMETER PackageName
    Name of the NuGet package to check.

.PARAMETER CheckVersion
    The presently embedded version of the package to check against the latest version.

.OUTPUTS
    PSCustomObject with properties:
    - PackageName: Name of the package
    - CheckVersion: The presently embedded version
    - LatestVersion: The latest version available on NuGet
    - UpdateAvailable: Boolean indicating if an update is available
    - UpdateMessage: Human-readable update status

.EXAMPLE
    $result = & .\.github\scripts\Get-NuGetLatestVersion.ps1 -PackageName "Microsoft.Identity.Client" -CheckVersion "4.48.0"
    if ($result.UpdateAvailable) {
        Write-Host "Update available: $($result.CheckVersion) → $($result.LatestVersion)"
    }

.NOTES
    Uses the public NuGet.org v3 API endpoint.
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PackageName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$CheckVersion
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Checking $PackageName ===" -ForegroundColor Cyan
Write-Host "Checking version: $CheckVersion"

$NugetUrl = "https://api.nuget.org/v3-registration5-semver1/$($PackageName.ToLower())/index.json"

try {
    $Response = Invoke-RestMethod -Uri $NugetUrl -ErrorAction Stop
    $LatestVersion = $Response.items[-1].upper

    Write-Host "Latest version: $LatestVersion"

    $UpdateAvailable = [version]$LatestVersion -gt [version]$CheckVersion

    if ($UpdateAvailable) {
        Write-Host '✓ Update available!' -ForegroundColor Green
        $message = "${PackageName}: $CheckVersion → $LatestVersion"
    } else {
        Write-Host 'Already up to date' -ForegroundColor Gray
        $Message = "$PackageName is up to date"
    }

    $Result = @{
        PackageName     = $PackageName
        CheckVersion    = $CheckVersion
        LatestVersion   = $LatestVersion
        UpdateAvailable = $UpdateAvailable
        UpdateMessage   = $Message
    }
} catch {
    Write-Warning "Failed to check $PackageName`: $_"
    $Result = @{
        PackageName     = $PackageName
        CheckVersion    = $CheckVersion
        LatestVersion   = $null
        UpdateAvailable = $false
        UpdateMessage   = 'Failed to check for updates'
        ErrorMessage    = $_.Exception.Message
    }
}

Write-Output ([PSCustomObject]$Result)
