<#
.SYNOPSIS
    Reports the assemblies loaded in the CURRENT session whose simple name is tracked by the
    dependency policy, with version and AssemblyLoadContext (ALC).
.DESCRIPTION
    Enumerates [System.AppDomain]::CurrentDomain.GetAssemblies(), keeps those whose GetName().Name is
    in the policy's trackedAssemblies (optionally further filtered by -NameLike wildcards), and
    resolves each one's ALC name (or 'Default'). A private ALC name signals the owning module
    self-manages that assembly. Shared by the #174 live-probe runbook and by the child process of
    Get-DLLPickleRuntimeAssemblySnapshot.ps1, so the merge-gate filter logic lives in one place.

    Requires a session where direct .NET API access is permitted (Full Language Mode, or Constrained
    Language AUDIT mode); these reflection calls are blocked under enforced Constrained Language Mode.
.PARAMETER PolicyPath
    Path to dependency-policy.json. Defaults to build/dependency-policy.json relative to the repo root
    (the parent of this script's tools/ folder).
.PARAMETER NameLike
    Optional wildcard patterns; when supplied, an assembly must ALSO match one of them to be returned.
.OUTPUTS
    PSCustomObject[] with Name, Version, ALC, path, hash, OS, platform, and architecture. Sorted by Name.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$PolicyPath,

    [Parameter()]
    [string[]]$NameLike
)

$ErrorActionPreference = 'Stop'

if (-not $PolicyPath) {
    $PolicyPath = Join-Path -Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path -ChildPath 'build/dependency-policy.json'
}

$TrackedNames = @((Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json).trackedAssemblies)
$Platform = if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
    'windows'
} elseif ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) {
    'macos'
} elseif ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)) {
    'linux'
} else {
    'unknown'
}
$OperatingSystemDescription = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
if ($Platform -eq 'macos') {
    $MacOSProductVersion = (& /usr/bin/sw_vers -productVersion).Trim()
    if ($LASTEXITCODE -ne 0 -or $MacOSProductVersion -notmatch '^\d+\.\d+(?:\.\d+)?$') {
        throw "Could not normalize the macOS product version returned by sw_vers: '$MacOSProductVersion'."
    }
    $OperatingSystemDescription = "macOS $MacOSProductVersion"
}

[System.AppDomain]::CurrentDomain.GetAssemblies() |
    Where-Object { $TrackedNames -contains $_.GetName().Name } |
    Where-Object {
        if (-not $NameLike) { return $true }
        $AssemblyName = $_.GetName().Name
        foreach ($Pattern in $NameLike) {
            if ($AssemblyName -like $Pattern) { return $true }
        }
        return $false
    } |
    ForEach-Object {
        $Alc = [System.Runtime.Loader.AssemblyLoadContext]::GetLoadContext($_)
        $AssemblyPath = $_.Location
        [PSCustomObject]@{
            Name         = $_.GetName().Name
            Version      = $_.GetName().Version.ToString()
            FullName     = $_.FullName
            Alc          = if ($Alc -and $Alc.Name) { $Alc.Name } else { 'Default' }
            IsCollectible = if ($Alc) { $Alc.IsCollectible } else { $false }
            Path         = $AssemblyPath
            Sha256       = if (-not [string]::IsNullOrWhiteSpace($AssemblyPath) -and (Test-Path -LiteralPath $AssemblyPath -PathType Leaf)) {
                (Get-FileHash -LiteralPath $AssemblyPath -Algorithm SHA256).Hash.ToLowerInvariant()
            } else {
                $null
            }
            OS           = $OperatingSystemDescription
            Platform     = $Platform
            Architecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLowerInvariant()
        }
    } |
    Sort-Object Name
