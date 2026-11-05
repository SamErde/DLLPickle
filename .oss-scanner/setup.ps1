<#
.SYNOPSIS
Installs the repository-pinned tools and Linux runtimes in the scanner image.
.DESCRIPTION
Runs during the network-enabled Docker build. Runtime archives are verified by
the existing provisioner; no tenant credentials or service modules are required.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $RepositoryRoot

$SdkPolicy = Get-Content -LiteralPath 'global.json' -Raw | ConvertFrom-Json
$InstalledSdk = & dotnet --version
if ($LASTEXITCODE -ne 0 -or $InstalledSdk -ne $SdkPolicy.sdk.version) {
    throw 'The scanner SDK image must match global.json exactly. Update its tag and digest together.'
}

$Matrix = Get-Content -LiteralPath 'build/powershell-test-matrix.json' -Raw | ConvertFrom-Json
if (@($Matrix.profiles).Count -eq 0) {
    throw 'The PowerShell runtime matrix is empty.'
}
$RuntimeIdentities = @(
    foreach ($RuntimeProfile in $Matrix.profiles) {
        $InstallParameters = @{
            Provider = 'DirectArchive'
            PowerShellVersion = $RuntimeProfile.powerShellVersion
            InstallRoot = '/opt/dllpickle/runtimes'
            Platform = 'linux'
            Architecture = 'x64'
            PassThru = $true
        }
        & ./tools/Install-DLLPickleTestPowerShell.ps1 @InstallParameters
    }
)
$RuntimeIdentities | ConvertTo-Json -Depth 10 -AsArray |
    Set-Content -LiteralPath '/opt/dllpickle/runtimes.json' -Encoding utf8NoBOM

# Save-Module avoids a tool dependency on the invoking user's home directory.
& ./.github/ci-scripts/Actions_Bootstrap.ps1 -ModuleInstallPath '/opt/dllpickle/modules'
