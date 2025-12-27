<#
.SYNOPSIS
    Downloads and extracts NuGet package updates, and updates the package tracking JSON.

.DESCRIPTION
    Retrieves the latest version of specified packages from NuGet, downloads them,
    extracts the DLLs, and updates the package tracking JSON file.

.PARAMETER PackageTrackingPath
    Path to the Packages.json file containing the list of packages to update.

.PARAMETER DestinationPath
    Directory where DLLs should be extracted.

.OUTPUTS
    PSCustomObject with properties:
    - Success: Boolean indicating if updates succeeded
    - UpdatedCount: Number of packages updated
    - FailedCount: Number of packages that failed to update
    - UpdateMessage: Summary of what was updated

.EXAMPLE
    $Result = & .\.github\scripts\Update-NuGetPackages.ps1 `
        -PackageTrackingPath "./src/DLLPickle/Lib/Packages.json" `
        -DestinationPath "./src/DLLPickle/Lib"

.NOTES
    Requires internet connectivity to access NuGet.org API.
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ })]
    [string]$PackageTrackingPath,

    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$DestinationPath
)

$ErrorActionPreference = 'Stop'

# Ensure destination exists
New-Item -ItemType Directory -Path $DestinationPath -ErrorAction SilentlyContinue | Out-Null

$PackageTracking = Get-Content $PackageTrackingPath -Raw | ConvertFrom-Json
$UpdatedCount = 0
$FailedCount = 0
$ChangedPackages = @()

# Create temp directory for downloads
$TempDir = Join-Path $env:TEMP "package_update_$(Get-Random)"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

try {
    foreach ($Package in $PackageTracking.packages) {
        Write-Host "`n=== Processing $($Package.name) ===" -ForegroundColor Cyan

        $CurrentVersion = $Package.version
        Write-Host "Current version: $CurrentVersion"

        # Get latest version from NuGet
        $NuGetUrl = "https://api.nuget.org/v3-registration5-semver1/$($Package.name.ToLower())/index.json"
        try {
            $Response = Invoke-RestMethod -Uri $NuGetUrl -ErrorAction Stop
            $LatestVersion = $Response.items[-1].upper

            if ([version]$LatestVersion -gt [version]$CurrentVersion) {
                Write-Host "Downloading version $LatestVersion..."

                # Download package
                $DownloadUrl = "https://www.nuget.org/api/v2/package/$($Package.name)/$LatestVersion"
                $NupkgPath = Join-Path $TempDir "$($Package.name).$LatestVersion.nupkg"
                Invoke-WebRequest -Uri $DownloadUrl -OutFile $NupkgPath -ErrorAction Stop

                # Extract (nupkg is just a zip file)
                $ExtractPath = Join-Path $TempDir "$($Package.name)_extracted"
                Expand-Archive -Path $NupkgPath -DestinationPath $ExtractPath -Force

                # Try multiple framework paths in order of preference
                $FrameworkPaths = @(
                    'lib\netstandard2.0\*.dll',
                    'lib\netstandard2.1\*.dll',
                    'lib\net6.0\*.dll',
                    'lib\net472\*.dll',
                    'runtimes\win\lib\netstandard2.0\*.dll',
                    'runtimes\win\lib\net6.0\*.dll'
                )

                $DllsCopied = $false
                foreach ($FwPath in $FrameworkPaths) {
                    $SourceDlls = Join-Path $ExtractPath $FwPath
                    $DllFiles = Get-Item $SourceDlls -ErrorAction SilentlyContinue
                    if ($DllFiles) {
                        Write-Host "Copying DLLs from $FwPath..."
                        Copy-Item -Path $SourceDlls -Destination $DestinationPath -Force
                        $DllsCopied = $true
                        break
                    }
                }

                if (-not $DllsCopied) {
                    Write-Warning "No compatible DLLs found for $($Package.name)"
                    $FailedCount++
                } else {
                    # Update version in tracking object
                    $Package.version = $LatestVersion
                    $UpdatedCount++
                    $ChangedPackages += "$($Package.name): $CurrentVersion → $LatestVersion"
                    Write-Host "✓ $($Package.name) $LatestVersion extracted successfully" -ForegroundColor Green
                }
            } else {
                Write-Host 'Already up to date' -ForegroundColor Gray
            }
        } catch {
            Write-Warning "Failed to process $($Package.name): $_"
            $FailedCount++
        }
    }

    # Save updated JSON if any packages were changed
    if ($UpdatedCount -gt 0) {
        $PackageTracking | ConvertTo-Json -Depth 10 | Set-Content -Path $PackageTrackingPath -NoNewline
        Write-Host "`n✓ Updated package tracking JSON" -ForegroundColor Green
    }

    $Result = @{
        Success         = $true
        UpdatedCount    = $UpdatedCount
        FailedCount     = $FailedCount
        ChangedPackages = $ChangedPackages
        UpdateMessage   = "Updated $UpdatedCount package(s), $FailedCount failed"
    }
} finally {
    # Cleanup temp directory
    if (Test-Path $TempDir) {
        Remove-Item $TempDir -Recurse -Force
    }
}

Write-Output ([PSCustomObject]$Result)
