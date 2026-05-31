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
    [PSCustomObject]@{
        Name      = $Name
        ShippedBy = @($Entries.Module | Sort-Object -Unique)
        Versions  = $DistinctVersions
        Diverges  = ($Entries.Module.Count -ge 2 -and $DistinctVersions.Count -ge 2)
        AlcOwner  = $null   # filled by the runtime probe / adjudication
    }
}

$Matrix = [PSCustomObject]@{
    GeneratedAtUtc  = $null   # stamped by the caller; avoids non-deterministic test output
    Assemblies      = @($AssemblyRows)
    ConflictSurface = @($AssemblyRows | Where-Object Diverges | ForEach-Object Name)
}

if ($OutputPath) {
    $OutputDirectory = Split-Path -Path $OutputPath -Parent
    if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
    }
    $Matrix | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
}

$Matrix
