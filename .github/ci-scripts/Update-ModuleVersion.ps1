<#
.SYNOPSIS
    Updates the PowerShell module manifest with a new version number.

.DESCRIPTION
    Updates the ModuleVersion in a PowerShell module manifest (.psd1) file and verifies the change was applied successfully.

.PARAMETER ManifestPath
    Path to the module manifest file.

.PARAMETER NewVersion
    The new version (as a SemVer string) to set in the manifest.

.OUTPUTS
    PSCustomObject with properties:
    - Success: Boolean indicating if the update succeeded
    - OldVersion: The previous version
    - NewVersion: The updated version
    - ManifestPath: Path to the updated manifest

.EXAMPLE
    $Result = & .\.github\ci-scripts\Update-ModuleVersion.ps1 -ManifestPath "./src/DLLPickle/DLLPickle.psd1" -NewVersion "1.3.0"
    if ($Result.Success) {
        Write-Host "Updated to version $($Result.NewVersion)"
    }
#>
[CmdletBinding()]
[OutputType([PSCustomObject])]
param(
    [Parameter()]
    [string]$ManifestPath = [System.IO.Path]::Join( (Split-Path -Path (Split-Path -Path $PSScriptRoot)), 'src', 'DLLPickle', 'DLLPickle.psd1' ),

    # Accept a string input and validate/convert to a version object in-script.
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$NewVersion
)

# Initialize result object for consistent return behavior.
$Result = [PSCustomObject]@{
    Success      = $false
    OldVersion   = $null
    NewVersion   = $null
    ManifestPath = $ManifestPath
    ErrorMessage = $null
}

# Read current version from the manifest before updating.
try {
    $OldManifest = Import-PowerShellDataFile -Path $ManifestPath -ErrorAction Stop
    $OldVersion = $OldManifest.ModuleVersion
    $Result.OldVersion = $OldVersion
} catch {
    $Result.ErrorMessage = "Unable to read the current version from the requested module manifest path. $_"
    Write-Error $Result.ErrorMessage
    return $Result
}

# Validate new version being re-cast from a string to a version object.
try {
    $NewVersion = [version]$NewVersion
} catch {
    $Result.ErrorMessage = "Invalid version format: '$NewVersion'. $_"
    Write-Error $Result.ErrorMessage
    return $Result
}

Write-Verbose "Updating module manifest: $ManifestPath"
Write-Verbose "Current version: $OldVersion"
Write-Verbose "New version: $NewVersion"

try {
    # Update the manifest
    Update-ModuleManifest -Path $ManifestPath -ModuleVersion $NewVersion -Confirm:$false -ErrorAction Stop
    Write-Verbose 'Module manifest updated'

    # Verify the update
    $NewManifest = Import-PowerShellDataFile -Path $ManifestPath -ErrorAction Stop
    $ActualVersion = $NewManifest.ModuleVersion

    if ($ActualVersion -ne $NewVersion) {
        throw "Version mismatch after update. Expected: $NewVersion, Actual: $ActualVersion"
    }

    Write-Verbose "Version verified: $ActualVersion"

    $Result.Success = $true
    $Result.NewVersion = $ActualVersion
    $Result.ManifestPath = (Resolve-Path $ManifestPath -ErrorAction Stop).Path
} catch {
    $Result.ErrorMessage = "Failed to update module manifest: $_"
    Write-Error $Result.ErrorMessage
    return $Result
}

$Result
