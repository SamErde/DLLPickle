<#
.SYNOPSIS
    Snapshots which identity-stack assemblies a module loads, and into which AssemblyLoadContext.
.DESCRIPTION
    Spawns a fresh pwsh process, optionally preloads DLLPickle, imports the named module(s) in
    order, optionally runs a probe command, and returns each loaded Azure.*/Microsoft.Identity*/
    Microsoft.IdentityModel*/System.ClientModel/System.Text.Json assembly with its version, path,
    and ALC name. A private ALC (name other than 'Default') indicates the module self-manages that
    assembly, which is a strong signal that DLLPickle must NOT preload it.
.PARAMETER ModuleName
    One or more modules to import, in order.
.PARAMETER PreloadDllPickleManifest
    Optional path to a DLLPickle manifest; when supplied, Import-DPLibrary runs before the imports.
.PARAMETER ProbeCommand
    Optional command string run after imports (e.g. 'Get-AzContext') to force lazy ALC init.
.OUTPUTS
    PSCustomObject[] one row per loaded assembly: Name, Version, Alc, Path.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$ModuleName,

    [Parameter()]
    [string]$PreloadDllPickleManifest,

    [Parameter()]
    [string]$ProbeCommand
)

$ErrorActionPreference = 'Stop'

$ChildScript = @'
param($ModuleNames, $PreloadManifest, $ProbeCommand)
$ModuleNames = $ModuleNames -split ','
$ErrorActionPreference = 'Continue'
if ($PreloadManifest) {
    Import-Module $PreloadManifest -Force
    Import-DPLibrary -SuppressLogo | Out-Null
}
foreach ($Name in $ModuleNames) { Import-Module $Name -Force -ErrorAction Continue }
if ($ProbeCommand) { try { Invoke-Expression $ProbeCommand | Out-Null } catch { } }

$Pattern = '^(Azure\.|Microsoft\.Identity|Microsoft\.IdentityModel|System\.ClientModel|System\.Text\.Json|System\.Memory\.Data|Microsoft\.Bcl\.AsyncInterfaces|Microsoft\.Extensions\.)'
[System.AppDomain]::CurrentDomain.GetAssemblies() |
    Where-Object { $_.GetName().Name -match $Pattern } |
    ForEach-Object {
        $Alc = [System.Runtime.Loader.AssemblyLoadContext]::GetLoadContext($_)
        [PSCustomObject]@{
            Name    = $_.GetName().Name
            Version = $_.GetName().Version.ToString()
            Alc     = if ($Alc -and $Alc.Name) { $Alc.Name } else { 'Default' }
            Path    = $_.Location
        }
    } | ConvertTo-Json -Depth 5
'@

$TempScript = Join-Path ([System.IO.Path]::GetTempPath()) ("dpp-snap-{0}.ps1" -f ([System.Guid]::NewGuid().ToString('n')))
Set-Content -LiteralPath $TempScript -Value $ChildScript -Encoding utf8NoBOM
try {
    $ChildArguments = @('-NoProfile', '-NonInteractive', '-File', $TempScript, '-ModuleNames', ($ModuleName -join ','))
    if ($PreloadDllPickleManifest) { $ChildArguments += @('-PreloadManifest', $PreloadDllPickleManifest) }
    if ($ProbeCommand) { $ChildArguments += @('-ProbeCommand', $ProbeCommand) }
    $Raw = & pwsh @ChildArguments
    $Json = ($Raw | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($Json)) { return @() }
    @($Json | ConvertFrom-Json)
} finally {
    Remove-Item -LiteralPath $TempScript -Force -ErrorAction SilentlyContinue
}
