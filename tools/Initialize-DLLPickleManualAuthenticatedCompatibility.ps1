<#
.SYNOPSIS
Prepares exact runtimes, latest compatible modules, and DLLPickle output for manual authentication tests.

.DESCRIPTION
Performs no authentication and no service calls. It builds the local module,
installs the checksum-pinned Windows x64 PowerShell runtimes from the canonical
matrix, and resolves/downloads the latest compatible monitored modules into an
isolated gitignored work root.
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param (
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$WorkRoot = (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'artifacts/manual-authenticated'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TestMatrixPath = (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'build/powershell-test-matrix.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyPath = (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'build/dependency-policy.json')
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$ResolvedWorkRoot = [System.IO.Path]::GetFullPath($WorkRoot)
$RuntimeInstallRoot = Join-Path $ResolvedWorkRoot 'runtimes'
$ModuleCacheParent = Join-Path $ResolvedWorkRoot 'module-cache'
$InventoryRoot = Join-Path $ResolvedWorkRoot 'inventories'
$DLLPickleManifestPath = Join-Path $RepositoryRoot 'module/DLLPickle/DLLPickle.psd1'

& (Join-Path $RepositoryRoot 'tools/Invoke-DLLPickleBuild.ps1') -Task PrepareModuleOutput
if (-not (Test-Path -LiteralPath $DLLPickleManifestPath -PathType Leaf)) {
    throw "DLLPickle build output was not created: $DLLPickleManifestPath"
}
$Matrix = Get-Content -LiteralPath $TestMatrixPath -Raw | ConvertFrom-Json -ErrorAction Stop
$PreparedProfiles = @(
    foreach ($RuntimeProfile in @($Matrix.profiles)) {
        $PowerShellLine = '{0}.{1}' -f $RuntimeProfile.powerShellMajor, $RuntimeProfile.powerShellMinor
        $ProfileKey = 'ps{0}-{1}-windows-x64' -f $PowerShellLine, $RuntimeProfile.targetFramework
        Write-Information -MessageData "Preparing $ProfileKey with PowerShell $($RuntimeProfile.powerShellVersion)..." -InformationAction Continue
        $InstallParameters = @{
            Provider = 'DirectArchive'
            PowerShellVersion = [string]$RuntimeProfile.powerShellVersion
            Platform = 'windows'
            Architecture = 'x64'
            InstallRoot = $RuntimeInstallRoot
            PassThru = $true
        }
        $Identity = & (Join-Path $RepositoryRoot 'tools/Install-DLLPickleTestPowerShell.ps1') @InstallParameters
        $ProfileInventoryRoot = Join-Path $InventoryRoot $ProfileKey
        $InventoryPath = Join-Path $ProfileInventoryRoot 'upstream-inventory.json'
        $ModuleCachePath = Join-Path $ModuleCacheParent ([string]$RuntimeProfile.powerShellVersion)
        $InventoryParameters = @{
            PolicyPath = $PolicyPath
            TestMatrixPath = $TestMatrixPath
            ModuleCachePath = $ModuleCachePath
            OutputPath = $InventoryPath
            PowerShellExecutable = [string]$Identity.ExecutablePath
            Force = $true
        }
        $Inventory = & (Join-Path $RepositoryRoot 'tools/Get-DLLPickleUpstreamInventory.ps1') @InventoryParameters
        $StaleSelections = @($Inventory.Modules | Where-Object Version -ne LatestCompatibleVersion)
        if ($StaleSelections.Count -gt 0) {
            throw "The prepared inventory for '$ProfileKey' did not select every latest compatible module."
        }
        $PreparedProfile = [pscustomobject]@{
            ProfileKey = $ProfileKey
            PowerShellVersion = [string]$RuntimeProfile.powerShellVersion
            TargetFramework = [string]$RuntimeProfile.targetFramework
            ExecutablePath = [string]$Identity.ExecutablePath
            InventoryPath = $InventoryPath
            ModuleVersions = [ordered]@{}
        }
        foreach ($Module in @($Inventory.Modules | Sort-Object Name)) {
            $PreparedProfile.ModuleVersions[[string]$Module.Name] = [string]$Module.Version
        }
        $PreparedProfile
    }
)
$BundleFingerprint = & (Join-Path $RepositoryRoot 'tools/Get-DLLPickleBundleSourceFingerprint.ps1') -RepositoryRoot $RepositoryRoot -OutputPath (Join-Path $ResolvedWorkRoot 'bundle-source-fingerprint.json')
$Summary = [pscustomobject]@{
    WorkRoot = $ResolvedWorkRoot
    DLLPickleManifestPath = $DLLPickleManifestPath
    BundleSourceFingerprint = [string]$BundleFingerprint.fingerprint
    Profiles = $PreparedProfiles
    AuthenticationPerformed = $false
    WritesPerformed = $false
}
$Summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ResolvedWorkRoot 'preparation-summary.json') -Encoding utf8NoBOM
$Summary
