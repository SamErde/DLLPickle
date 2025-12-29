<#
.SYNOPSIS
    Updates the PowerShell module manifest with a new version number.

.DESCRIPTION
    Updates the ModuleVersion in a PowerShell module manifest (.psd1) file and verifies the change was applied successfully.

.PARAMETER ManifestPath
    Path to the module manifest file.

.PARAMETER NewVersion
    The new version to set in the manifest.

.OUTPUTS
    PSCustomObject with properties:
    - Success: Boolean indicating if the update succeeded
    - OldVersion: The previous version
    - NewVersion: The updated version
    - ManifestPath: Path to the updated manifest

.EXAMPLE
    $Result = & .\.github\scripts\Update-ModuleManifest.ps1 -ManifestPath "./src/DLLPickle/DLLPickle.psd1" -NewVersion "1.3.0"
    if ($Result.Success) {
        Write-Host "Updated to version $($Result.NewVersion)"
    }
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ })]
    [string]$ManifestPath = [System.IO.Path]::Join( (Split-Path -Path (Split-Path -Path $PSScriptRoot)), 'src', 'DLLPickle', 'DLLPickle.psd1' ),

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    $NewVersion
)

$ErrorActionPreference = 'Stop'

# Read current version before update
try {
    $OldManifest = Import-PowerShellDataFile -Path $ManifestPath
    $OldVersion = $OldManifest.ModuleVersion
} catch {
    Write-Error "Unable to read the current version from the module manifest. $_"
    exit 1
}

Write-Host "Updating module manifest: $ManifestPath" -ForegroundColor Green
Write-Host "Current version: $OldVersion" -ForegroundColor White
Write-Host "New version: $NewVersion" -ForegroundColor White

try {
    # Update the manifest
    Update-ModuleManifest -Path $ManifestPath -ModuleVersion $NewVersion -ErrorAction Stop
    Write-Host '✓ Module manifest updated' -ForegroundColor Green

    # Verify the update
    $NewManifest = Import-PowerShellDataFile -Path $ManifestPath
    $ActualVersion = $NewManifest.ModuleVersion

    if ($ActualVersion -ne $NewVersion) {
        throw "Version mismatch after update. Expected: $NewVersion, Actual: $ActualVersion"
    }

    Write-Host "✓ Version verified: $ActualVersion" -ForegroundColor Green

    $Result = @{
        Success      = $true
        OldVersion   = $OldVersion
        NewVersion   = $ActualVersion
        ManifestPath = (Resolve-Path $ManifestPath).Path
    }
} catch {
    Write-Error "Failed to update module manifest: $_"
    $Result = @{
        Success      = $false
        OldVersion   = $OldVersion
        NewVersion   = $null
        ManifestPath = $ManifestPath
        ErrorMessage = $_.Exception.Message
    }
}

Write-Output ([PSCustomObject]$Result)
