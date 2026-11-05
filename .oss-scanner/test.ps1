<#
.SYNOPSIS
Rebuilds DLL Pickle and tests every declared Linux runtime in fresh processes.
.DESCRIPTION
Run inside the scanner image after its network-enabled build has cached the
dependencies. For acceptance, run this command with docker --network none.
The image retains exact tools, runtime archives, reference packs and NuGet caches.
Results are written under artifacts/oss-scanner, separately for each runtime.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $RepositoryRoot
$PreviousSummary = Join-Path $RepositoryRoot 'artifacts/oss-scanner/summary.json'
if (Test-Path -LiteralPath $PreviousSummary) {
    Remove-Item -LiteralPath $PreviousSummary -Force
}
$Matrix = Get-Content -LiteralPath 'build/powershell-test-matrix.json' -Raw | ConvertFrom-Json
$InstalledRuntimes = @(Get-Content -LiteralPath '/opt/dllpickle/runtimes.json' -Raw | ConvertFrom-Json)
if (@($Matrix.profiles).Count -eq 0) {
    throw 'The PowerShell runtime matrix is empty.'
}

# Exclude real service/tenant probes even if the caller set the opt-in variable.
$env:DLLPICKLE_RUN_LIVE_REPRO = '0'
$OriginalPath = $env:PATH
$DefaultPowerShell = (Get-Process -Id $PID).Path
$env:PSModulePath = '/opt/dllpickle/modules' + [System.IO.Path]::PathSeparator + (Join-Path $PSHOME 'Modules')

. ./build/DLLPickle.Tooling.ps1
$ToolPolicy = Get-DLLPickleBuildToolPolicy -Path './build/build-tool-versions.json'
$AnalyzerVersion = Get-DLLPickleBuildToolVersion -Policy $ToolPolicy -Name 'PSScriptAnalyzer'
$null = Import-DLLPickleBuildTool -Name 'PSScriptAnalyzer' -RequiredVersion $AnalyzerVersion
$AnalyzerFindings = @(Invoke-ScriptAnalyzer -Path $PSScriptRoot -Recurse -Settings './build/PSScriptAnalyzerSettings.psd1')
if ($AnalyzerFindings.Count -gt 0) {
    $AnalyzerFindings | Format-Table
    throw 'Scanner script analysis failed.'
}

# Reuse the complete build. Its locked restore must also work from the image cache.
& $DefaultPowerShell -NoLogo -NoProfile -NonInteractive -File ./tools/Invoke-DLLPickleBuild.ps1 -Task BuildCrossPlatform
if ($LASTEXITCODE -ne 0) {
    throw 'The scanner rebuild failed.'
}

$ResultsRoot = Join-Path $RepositoryRoot 'artifacts/oss-scanner'
$null = New-Item -ItemType Directory -Path $ResultsRoot -Force
$SummaryPath = Join-Path $ResultsRoot 'summary.json'
@{ status = 'running'; profiles = @() } | ConvertTo-Json |
    Set-Content -LiteralPath $SummaryPath -Encoding utf8NoBOM
$VerifiedProfiles = @()

foreach ($RuntimeProfile in $Matrix.profiles) {
    $Runtime = @($InstalledRuntimes | Where-Object PowerShellVersion -EQ $RuntimeProfile.powerShellVersion)
    if ($Runtime.Count -ne 1) {
        throw "Expected exactly one installed runtime for PowerShell $($RuntimeProfile.powerShellVersion)."
    }
    $Executable = [string]$Runtime[0].ExecutablePath
    $IdentityParameters = @{
        PowerShellExecutable = $Executable
        PowerShellVersion = $RuntimeProfile.powerShellVersion
        PassThru = $true
    }
    $Identity = & ./tools/Install-DLLPickleTestPowerShell.ps1 @IdentityParameters
    $RuntimeRoot = Split-Path -Parent $Executable
    $env:PATH = $RuntimeRoot + [System.IO.Path]::PathSeparator + $OriginalPath
    $env:PSModulePath = '/opt/dllpickle/modules' + [System.IO.Path]::PathSeparator + (Join-Path $RuntimeRoot 'Modules')
    $env:DLLPICKLE_TEST_PWSH = $Executable
    $env:DLLPICKLE_TEST_TFM = $RuntimeProfile.targetFramework
    $env:DLLPICKLE_TEST_PSMODULEPATH = $env:PSModulePath

    $RuntimeProfileResults = Join-Path $ResultsRoot $RuntimeProfile.powerShellVersion
    $null = New-Item -ItemType Directory -Path $RuntimeProfileResults -Force
    $Identity | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath (Join-Path $RuntimeProfileResults 'runtime.json') -Encoding utf8NoBOM

    foreach ($Task in @('Test', 'IntegrationTest')) {
        & $Executable -NoLogo -NoProfile -NonInteractive -File ./tools/Invoke-DLLPickleBuild.ps1 -Task $Task
        $TestExitCode = $LASTEXITCODE
        $ResultPrefix = if ($Task -eq 'Test') { 'PesterTests' } else { 'PesterIntegrationTests' }
        Copy-Item -Path "artifacts/testOutput/$ResultPrefix.*" -Destination $RuntimeProfileResults -Force
        if ($TestExitCode -ne 0) {
            throw "$Task failed for PowerShell $($RuntimeProfile.powerShellVersion)."
        }
        [xml]$TestXml = Get-Content -LiteralPath (Join-Path $RuntimeProfileResults "$ResultPrefix.xml") -Raw
        if ([int]$TestXml.DocumentElement.GetAttribute('total') -le 0) {
            throw "$Task discovered no tests for PowerShell $($RuntimeProfile.powerShellVersion)."
        }
    }

    & $Executable -NoLogo -NoProfile -NonInteractive -File ./tools/Test-DLLPicklePackageArtifact.ps1 -Strict -OutputPath (Join-Path $RuntimeProfileResults 'artifact-composition.json')
    if ($LASTEXITCODE -ne 0) {
        throw "Package composition failed for PowerShell $($RuntimeProfile.powerShellVersion)."
    }
    & $Executable -NoLogo -NoProfile -NonInteractive -File ./tools/Test-DLLPickleTfmAlignment.ps1 -Strict -OutputPath (Join-Path $RuntimeProfileResults 'tfm-alignment.json')
    if ($LASTEXITCODE -ne 0) {
        throw "TFM alignment failed for PowerShell $($RuntimeProfile.powerShellVersion)."
    }
    $VerifiedProfiles += $Identity
}

@{
    status = 'passed'
    profiles = $VerifiedProfiles
    scope = 'Linux unit, synthetic integration, package composition and TFM alignment; no tenant authentication'
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $SummaryPath -Encoding utf8NoBOM
