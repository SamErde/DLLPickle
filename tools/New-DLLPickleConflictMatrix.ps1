<#
.SYNOPSIS
    Builds a cross-module assembly conflict matrix from a DLLPickle upstream inventory.
.DESCRIPTION
    Consumes the inventory object produced by Get-DLLPickleUpstreamInventory.ps1 (or its JSON,
    via -InventoryPath) and computes, per tracked assembly: which modules ship it, the distinct
    versions, selected hashes, and runtime ALC owners. The ConflictSurface is the set of assemblies
    that diverge across modules. The profile fingerprint covers every selected tracked-assembly tuple
    so a content or ALC move cannot pass merely because the assembly version stayed unchanged.
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
$ProfileKey = if ($Inventory.PSObject.Properties.Name -contains 'ProfileKey') { [string]$Inventory.ProfileKey } else { $null }
$RequiresCompleteSelectionIdentity = -not [string]::IsNullOrWhiteSpace($ProfileKey)

# Group every tracked assembly across all modules by assembly name.
$ByAssembly = @{}
foreach ($Module in $Inventory.Modules) {
    foreach ($Assembly in $Module.TrackedAssemblies) {
        if (-not $ByAssembly.ContainsKey($Assembly.Name)) {
            $ByAssembly[$Assembly.Name] = [System.Collections.Generic.List[object]]::new()
        }
        $Sha256 = if ($Assembly.PSObject.Properties.Name -contains 'Sha256') {
            ([string]$Assembly.Sha256).ToLowerInvariant()
        } else {
            $null
        }
        $AlcOwner = if ($Assembly.PSObject.Properties.Name -contains 'Alc') {
            [string]$Assembly.Alc
        } elseif ($Assembly.PSObject.Properties.Name -contains 'AlcOwner') {
            [string]$Assembly.AlcOwner
        } else {
            $null
        }
        if ($RequiresCompleteSelectionIdentity -and $Sha256 -notmatch '^[a-f0-9]{64}$') {
            throw "Profile-keyed inventory '$ProfileKey' selection '$($Module.Name)/$($Assembly.Name)' requires a 64-character SHA-256."
        }
        if ($RequiresCompleteSelectionIdentity -and [string]::IsNullOrWhiteSpace($AlcOwner)) {
            throw "Profile-keyed inventory '$ProfileKey' selection '$($Module.Name)/$($Assembly.Name)' requires an ALC owner."
        }
        $ByAssembly[$Assembly.Name].Add([PSCustomObject]@{
                Module   = [string]$Module.Name
                Version  = [string]$Assembly.Version
                Sha256   = $Sha256
                AlcOwner = $AlcOwner
            })
    }
}

$AssemblyRows = foreach ($Name in ($ByAssembly.Keys | Sort-Object)) {
    $Entries = $ByAssembly[$Name]
    $DistinctVersions = @($Entries.Version | Sort-Object -Unique)
    $DistinctModules = @($Entries.Module | Sort-Object -Unique)
    $DistinctHashes = @($Entries.Sha256 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $DistinctAlcOwners = @($Entries.AlcOwner | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $Selections = @(
        $Entries |
            Sort-Object Module, Version, Sha256, AlcOwner |
            ForEach-Object {
                [PSCustomObject]@{
                    Module   = [string]$_.Module
                    Version  = [string]$_.Version
                    Sha256   = [string]$_.Sha256
                    AlcOwner = [string]$_.AlcOwner
                }
            }
    )
    [PSCustomObject]@{
        Name       = $Name
        ShippedBy  = $DistinctModules
        Versions   = $DistinctVersions
        Hashes     = $DistinctHashes
        AlcOwners  = $DistinctAlcOwners
        Selections = $Selections
        # Diverges only when >=2 DISTINCT modules ship >=2 distinct versions. Counting distinct
        # modules (not raw entries) avoids a false positive when one module ships the same
        # assembly more than once (e.g. nested folders / multiple RIDs) at differing versions.
        Diverges   = ($DistinctModules.Count -ge 2 -and $DistinctVersions.Count -ge 2)
        # Retain the legacy scalar for older comparison consumers when ownership is unambiguous.
        AlcOwner   = if ($DistinctAlcOwners.Count -eq 1) { $DistinctAlcOwners[0] } else { $null }
    }
}

# Profile-aware evidence fingerprint over every selected tracked assembly. Per-selection tuples keep
# module, version, content hash, and runtime ALC associated instead of hashing independent sets that
# could collide when two modules swap payloads or load contexts. Absolute selected-asset paths are not
# canonical input because runner roots differ; the selected file's SHA-256 is the stable content identity.
$EvidenceRows = @(
    $AssemblyRows | Sort-Object Name | ForEach-Object {
        $CanonicalSelections = @(
            $_.Selections | ForEach-Object {
                'module={0};version={1};sha256={2};alc={3}' -f $_.Module, $_.Version, $_.Sha256, $_.AlcOwner
            } | Sort-Object
        )
        '{0}|diverges={1}|{2}' -f $_.Name, ([string]$_.Diverges).ToLowerInvariant(), ($CanonicalSelections -join '|')
    }
)
$FingerprintInput = if ([string]::IsNullOrWhiteSpace($ProfileKey)) {
    $EvidenceRows -join '|'
} else {
    '{0}|{1}' -f $ProfileKey, ($EvidenceRows -join '|')
}
$FingerprintBytes = [System.Text.Encoding]::UTF8.GetBytes($FingerprintInput)
$Fingerprint = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($FingerprintBytes)).Replace('-', '').ToLowerInvariant()

$Matrix = [PSCustomObject]@{
    GeneratedAtUtc  = $null   # stamped by the caller; avoids non-deterministic test output
    ProfileKey      = $ProfileKey
    Profile         = if ($Inventory.PSObject.Properties.Name -contains 'Profile') { $Inventory.Profile } else { $null }
    ValidationTier  = if ($Inventory.PSObject.Properties.Name -contains 'ValidationTier') { $Inventory.ValidationTier } else { $null }
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
