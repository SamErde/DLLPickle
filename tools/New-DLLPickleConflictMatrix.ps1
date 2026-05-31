<#
.SYNOPSIS
    Builds a cross-module assembly conflict matrix from a DLLPickle upstream inventory.
.DESCRIPTION
    Consumes the inventory object produced by Get-DLLPickleUpstreamInventory.ps1 (or its JSON,
    via -InventoryPath) and computes, per tracked assembly: which modules ship it, the distinct
    versions, whether those versions diverge, and a placeholder AlcOwner field that the runtime
    probe fills in later. The ConflictSurface is the set of assemblies that diverge across modules.
.PARAMETER Inventory
    The inventory object (as returned by Get-DLLPickleUpstreamInventory.ps1).
.PARAMETER InventoryPath
    Path to an inventory JSON file (alternative to -Inventory).
.PARAMETER OutputPath
    Optional path to write the matrix as JSON.
.OUTPUTS
    PSCustomObject the conflict matrix.
#>
[CmdletBinding(DefaultParameterSetName = 'Object')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Object')]
    [PSCustomObject]$Inventory,

    [Parameter(Mandatory, ParameterSetName = 'Path')]
    [ValidateNotNullOrEmpty()]
    [string]$InventoryPath,

    [Parameter()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

if ($PSCmdlet.ParameterSetName -eq 'Path') {
    $Inventory = Get-Content -LiteralPath $InventoryPath -Raw | ConvertFrom-Json
}

# Group every tracked assembly across all modules by assembly name.
$ByAssembly = @{}
foreach ($Module in $Inventory.Modules) {
    foreach ($Assembly in $Module.TrackedAssemblies) {
        if (-not $ByAssembly.ContainsKey($Assembly.Name)) {
            $ByAssembly[$Assembly.Name] = [System.Collections.Generic.List[object]]::new()
        }
        $ByAssembly[$Assembly.Name].Add([PSCustomObject]@{
                Module  = $Module.Name
                Version = [string]$Assembly.Version
            })
    }
}

$AssemblyRows = foreach ($Name in ($ByAssembly.Keys | Sort-Object)) {
    $Entries = $ByAssembly[$Name]
    $DistinctVersions = @($Entries.Version | Sort-Object -Unique)
    $DistinctModules = @($Entries.Module | Sort-Object -Unique)
    [PSCustomObject]@{
        Name      = $Name
        ShippedBy = $DistinctModules
        Versions  = $DistinctVersions
        # Diverges only when >=2 DISTINCT modules ship >=2 distinct versions. Counting distinct
        # modules (not raw entries) avoids a false positive when one module ships the same
        # assembly more than once (e.g. nested folders / multiple RIDs) at differing versions.
        Diverges  = ($DistinctModules.Count -ge 2 -and $DistinctVersions.Count -ge 2)
        AlcOwner  = $null   # filled by the runtime probe / adjudication
    }
}

# Versions-aware fingerprint over the conflict surface. Each diverging assembly contributes its
# name AND its sorted distinct versions, so a material change where the same assemblies stay in
# conflict but their versions move (e.g. an upstream module bumps within-major) changes the hash.
# This is the single source of the drift fingerprint consumed by the Upstream-Compatibility workflow
# and the recorded baseline in build/dependency-policy.json. (ALC ownership is not included: it is
# null in the static inventory and is only known from the runtime probe / maintainer adjudication.)
$SurfaceRows = @(
    $AssemblyRows | Where-Object Diverges | Sort-Object Name | ForEach-Object {
        '{0}={1}' -f $_.Name, (@($_.Versions | Sort-Object) -join ',')
    }
)
$FingerprintBytes = [System.Text.Encoding]::UTF8.GetBytes(($SurfaceRows -join '|'))
$Fingerprint = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($FingerprintBytes)).Replace('-', '').ToLowerInvariant()

$Matrix = [PSCustomObject]@{
    GeneratedAtUtc  = $null   # stamped by the caller; avoids non-deterministic test output
    Assemblies      = @($AssemblyRows)
    ConflictSurface = @($AssemblyRows | Where-Object Diverges | ForEach-Object Name)
    Fingerprint     = $Fingerprint
}

if ($OutputPath) {
    $OutputDirectory = Split-Path -Path $OutputPath -Parent
    if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
    }
    $Matrix | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
}

$Matrix
