<#
.SYNOPSIS
    Snapshots which tracked assemblies a module loads, and into which AssemblyLoadContext.
.DESCRIPTION
    Spawns a fresh pwsh process, optionally preloads DLLPickle, imports the named module(s) in order,
    optionally runs a probe command, then reports each loaded assembly whose name is in the dependency
    policy's trackedAssemblies, with its version, path, and ALC name. The set of tracked names (and the
    ALC capture) is sourced from build/dependency-policy.json via Get-DLLPickleLoadedTrackedAssembly.ps1,
    so this tool and the live-probe runbook share one filter. A private ALC (name other than 'Default')
    indicates the module self-manages that assembly - a strong signal that DLLPickle must NOT preload it.
.PARAMETER ModuleName
    One or more modules to import, in order.
.PARAMETER PreloadDllPickleManifest
    Optional path to a DLLPickle manifest; when supplied, Import-DPLibrary runs before the imports.
.PARAMETER ProbeCommand
    Optional command string run after imports (e.g. 'Get-AzContext') to force lazy ALC init.
.PARAMETER PolicyPath
    Path to dependency-policy.json. Defaults to build/dependency-policy.json relative to the repo root.
.PARAMETER Strict
    Fails when a requested module cannot be imported or the probe command throws. Use this mode when
    collecting adjudication evidence so a partial snapshot cannot be mistaken for a successful probe.
.PARAMETER PowerShellExecutable
    Exact stock pwsh/pwsh.exe to launch. Defaults to the current process executable.
.PARAMETER PowerShellVersion
    Optional exact servicing patch expected from the child process.
.PARAMETER TargetFramework
    Expected TFM for the child CLR. The probe fails if it does not match.
.PARAMETER ModuleManifestPath
    Optional exact manifest path for each ModuleName, in the same order. This prevents
    a user- or machine-wide module of the same name from satisfying the evidence run.
.PARAMETER ModuleSearchPath
    Optional isolated module roots assigned inside the fresh child process before import.
.OUTPUTS
    PSCustomObject[] one row per loaded tracked assembly: Name, Version, Alc, Path.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$ModuleName,

    [Parameter()]
    [string]$PreloadDllPickleManifest,

    [Parameter()]
    [string]$ProbeCommand,

    [Parameter()]
    [string]$PolicyPath,

    [Parameter()]
    [string]$PowerShellExecutable = [Environment]::ProcessPath,

    [Parameter()]
    [version]$PowerShellVersion,

    [Parameter()]
    [ValidatePattern('^net\d+\.0$')]
    [string]$TargetFramework,

    [Parameter()]
    [string[]]$ModuleManifestPath,

    [Parameter()]
    [string[]]$ModuleSearchPath,

    [Parameter()]
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
$ResolvedModuleManifestPaths = @($ModuleManifestPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($ResolvedModuleManifestPaths.Count -gt 0 -and $ResolvedModuleManifestPaths.Count -ne $ModuleName.Count) {
    throw 'ModuleManifestPath must contain one exact path for every ModuleName.'
}
foreach ($ManifestPath in $ResolvedModuleManifestPaths) {
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Module manifest was not found: $ManifestPath"
    }
}

$ExecutableCommand = Get-Command -Name $PowerShellExecutable -ErrorAction Stop
$ResolvedPowerShellExecutable = if ($ExecutableCommand.CommandType -eq 'Application') {
    $ExecutableCommand.Source
} else {
    throw "PowerShellExecutable must resolve to an application, not $($ExecutableCommand.CommandType): $PowerShellExecutable"
}

$HelperScript = Join-Path -Path $PSScriptRoot -ChildPath 'Get-DLLPickleLoadedTrackedAssembly.ps1'
if (-not $PolicyPath) {
    $PolicyPath = Join-Path -Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path -ChildPath 'build/dependency-policy.json'
}

$ChildScript = @'
param($ModuleNames, $ModuleManifestPathsEncoded, $IsolatedModulePath, $PreloadManifest, $ProbeCommand, $HelperScript, $PolicyPath, $ExpectedPowerShellVersion, $ExpectedTargetFramework, [switch]$StrictMode)
$ModuleNames = $ModuleNames -split ','
$ModuleManifestPaths = if ($ModuleManifestPathsEncoded) {
    $ManifestJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ModuleManifestPathsEncoded))
    @($ManifestJson | ConvertFrom-Json)
} else {
    @()
}
$ModuleManifestPaths = @($ModuleManifestPaths)
$env:PSModulePath = if ($IsolatedModulePath) { $IsolatedModulePath } else { $env:PSModulePath }
$ErrorActionPreference = 'Continue'
$ActualTargetFramework = 'net{0}.0' -f [Environment]::Version.Major
if ($ExpectedPowerShellVersion -and $PSVersionTable.PSVersion.ToString() -ne $ExpectedPowerShellVersion) {
    throw "PowerShell version mismatch. Expected $ExpectedPowerShellVersion but detected $($PSVersionTable.PSVersion)."
}
if ($ExpectedTargetFramework -and $ActualTargetFramework -ne $ExpectedTargetFramework) {
    throw "Target framework mismatch. Expected $ExpectedTargetFramework but detected $ActualTargetFramework."
}
if ($PreloadManifest) {
    if ($StrictMode) {
        Import-Module $PreloadManifest -Force -ErrorAction Stop
        Import-DPLibrary -SuppressLogo -ErrorAction Stop | Out-Null
    } else {
        Import-Module $PreloadManifest -Force
        Import-DPLibrary -SuppressLogo | Out-Null
    }
}
$ImportedModulePaths = @()
for ($ModuleIndex = 0; $ModuleIndex -lt $ModuleNames.Count; $ModuleIndex++) {
    $Name = $ModuleNames[$ModuleIndex]
    $ImportTarget = if ($ModuleManifestPaths.Count -gt 0) { [string]$ModuleManifestPaths[$ModuleIndex] } else { $Name }
    if ($StrictMode) {
        Import-Module -Name $ImportTarget -Force -ErrorAction Stop
    } else {
        Import-Module -Name $ImportTarget -Force -ErrorAction Continue
    }
    $ImportedModulePaths += $ImportTarget
}
if ($ProbeCommand) {
    if ($StrictMode) {
        Invoke-Expression $ProbeCommand | Out-Null
    } else {
        try { Invoke-Expression $ProbeCommand | Out-Null } catch { }
    }
}
$Rows = @(& $HelperScript -PolicyPath $PolicyPath)
foreach ($Row in $Rows) {
    $Row | Add-Member -NotePropertyName PowerShellVersion -NotePropertyValue $PSVersionTable.PSVersion.ToString()
    $Row | Add-Member -NotePropertyName DotNetVersion -NotePropertyValue ([Environment]::Version.ToString())
    $Row | Add-Member -NotePropertyName TargetFramework -NotePropertyValue $ActualTargetFramework
    $Row | Add-Member -NotePropertyName ExecutablePath -NotePropertyValue ([Environment]::ProcessPath)
    $Row | Add-Member -NotePropertyName PSHome -NotePropertyValue $PSHOME
    $Row | Add-Member -NotePropertyName ModuleSet -NotePropertyValue @($ModuleNames)
    $Row | Add-Member -NotePropertyName ImportOrder -NotePropertyValue @($ModuleNames)
    $Row | Add-Member -NotePropertyName ImportedModulePaths -NotePropertyValue @($ImportedModulePaths)
    $Row | Add-Member -NotePropertyName IsolatedModulePath -NotePropertyValue $env:PSModulePath
    $Row | Add-Member -NotePropertyName DllPicklePreloaded -NotePropertyValue (-not [string]::IsNullOrWhiteSpace($PreloadManifest))
}
$Rows | ConvertTo-Json -Depth 8
'@

$TempScript = Join-Path ([System.IO.Path]::GetTempPath()) ("dpp-snap-{0}.ps1" -f ([System.Guid]::NewGuid().ToString('n')))
Set-Content -LiteralPath $TempScript -Value $ChildScript -Encoding utf8NoBOM
try {
    $ChildArguments = @(
        '-NoProfile', '-NonInteractive', '-File', $TempScript,
        '-ModuleNames', ($ModuleName -join ','),
        '-HelperScript', $HelperScript,
        '-PolicyPath', $PolicyPath
    )
    if ($PowerShellVersion) { $ChildArguments += @('-ExpectedPowerShellVersion', $PowerShellVersion.ToString()) }
    if ($TargetFramework) { $ChildArguments += @('-ExpectedTargetFramework', $TargetFramework) }
    if ($ResolvedModuleManifestPaths.Count -gt 0) {
        $ManifestJson = ConvertTo-Json -InputObject @($ResolvedModuleManifestPaths) -Compress
        $ManifestEncoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($ManifestJson))
        $ChildArguments += @('-ModuleManifestPathsEncoded', $ManifestEncoded)
    }
    if ($ModuleSearchPath.Count -gt 0) {
        $ChildArguments += @('-IsolatedModulePath', (@($ModuleSearchPath) -join [System.IO.Path]::PathSeparator))
    }
    if ($PreloadDllPickleManifest) { $ChildArguments += @('-PreloadManifest', $PreloadDllPickleManifest) }
    if ($ProbeCommand) { $ChildArguments += @('-ProbeCommand', $ProbeCommand) }
    if ($Strict.IsPresent) {
        $ChildArguments += '-StrictMode'
        $Raw = & $ResolvedPowerShellExecutable @ChildArguments 2>&1
        if ($LASTEXITCODE -ne 0) {
            $ChildError = ($Raw | Out-String).Trim()
            throw "DLLPickle runtime assembly snapshot failed in strict mode. $ChildError"
        }
    } else {
        $Raw = & $ResolvedPowerShellExecutable @ChildArguments
    }
    $Json = ($Raw | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($Json)) { return @() }
    @($Json | ConvertFrom-Json)
} finally {
    Remove-Item -LiteralPath $TempScript -Force -ErrorAction SilentlyContinue
}
