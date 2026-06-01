<#
.SYNOPSIS
    Snapshots which tracked assemblies a module loads, and into which AssemblyLoadContext.
.DESCRIPTION
    Spawns a fresh pwsh process, optionally preloads DLLPickle, imports the named module(s) in order,
    optionally runs a probe command, then reports each loaded assembly whose name is in the dependency
    policy's trackedAssemblies, with its version, path, and ALC name. The set of tracked names (and the
    ALC capture) is sourced from build/dependency-policy.json via Get-DLLPickleLoadedTrackedAssembly.ps1,
    so this tool and the live-probe runbook share one filter. A private ALC (name other than 'Default')
    indicates the module self-manages that assembly — a strong signal that DLLPickle must NOT preload it.
.PARAMETER ModuleName
    One or more modules to import, in order.
.PARAMETER PreloadDllPickleManifest
    Optional path to a DLLPickle manifest; when supplied, Import-DPLibrary runs before the imports.
.PARAMETER ProbeCommand
    Optional command string run after imports (e.g. 'Get-AzContext') to force lazy ALC init.
.PARAMETER PolicyPath
    Path to dependency-policy.json. Defaults to build/dependency-policy.json relative to the repo root.
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
    [string]$PolicyPath
)

$ErrorActionPreference = 'Stop'

$HelperScript = Join-Path -Path $PSScriptRoot -ChildPath 'Get-DLLPickleLoadedTrackedAssembly.ps1'
if (-not $PolicyPath) {
    $PolicyPath = Join-Path -Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path -ChildPath 'build/dependency-policy.json'
}

$ChildScript = @'
param($ModuleNames, $PreloadManifest, $ProbeCommand, $HelperScript, $PolicyPath)
$ModuleNames = $ModuleNames -split ','
$ErrorActionPreference = 'Continue'
if ($PreloadManifest) {
    Import-Module $PreloadManifest -Force
    Import-DPLibrary -SuppressLogo | Out-Null
}
foreach ($Name in $ModuleNames) { Import-Module $Name -Force -ErrorAction Continue }
if ($ProbeCommand) { try { Invoke-Expression $ProbeCommand | Out-Null } catch { } }
& $HelperScript -PolicyPath $PolicyPath | ConvertTo-Json -Depth 5
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
    if ($PreloadDllPickleManifest) { $ChildArguments += @('-PreloadManifest', $PreloadDllPickleManifest) }
    if ($ProbeCommand) { $ChildArguments += @('-ProbeCommand', $ProbeCommand) }
    $Raw = & pwsh @ChildArguments
    $Json = ($Raw | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($Json)) { return @() }
    @($Json | ConvertFrom-Json)
} finally {
    Remove-Item -LiteralPath $TempScript -Force -ErrorAction SilentlyContinue
}
