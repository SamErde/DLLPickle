<#
.SYNOPSIS
    Diffs two DLLPickle conflict matrices and reports material drift.
.DESCRIPTION
    Material drift = a newly diverging assembly entering the conflict surface, or an ALC-ownership
    change on a known assembly. Patch/minor moves with no new conflict and no ALC change are not
    material. Returns an object with HasMaterialDrift and a Findings breakdown.
.PARAMETER Baseline
    The baseline conflict matrix (as produced by New-DLLPickleConflictMatrix.ps1).
.PARAMETER Current
    The current conflict matrix to compare against the baseline.
.OUTPUTS
    PSCustomObject { HasMaterialDrift [bool]; Findings { NewConflicts; RemovedConflicts; AlcOwnershipChanges } }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [PSCustomObject]$Baseline,
    [Parameter(Mandatory)] [PSCustomObject]$Current
)

$ErrorActionPreference = 'Stop'

$BaseSurface = @($Baseline.Assemblies | Where-Object Diverges | ForEach-Object Name)
$CurrSurface = @($Current.Assemblies  | Where-Object Diverges | ForEach-Object Name)

$NewConflicts     = @($CurrSurface | Where-Object { $_ -notin $BaseSurface })
$RemovedConflicts = @($BaseSurface | Where-Object { $_ -notin $CurrSurface })

$BaseAlc = @{}
foreach ($Assembly in $Baseline.Assemblies) {
    $BaseAlc[$Assembly.Name] = [string]$Assembly.AlcOwner
}
$AlcChanges = @($Current.Assemblies | Where-Object {
        $BaseAlc.ContainsKey($_.Name) -and $BaseAlc[$_.Name] -ne [string]$_.AlcOwner
    } | ForEach-Object Name)

$Findings = [PSCustomObject]@{
    NewConflicts        = $NewConflicts
    RemovedConflicts    = $RemovedConflicts
    AlcOwnershipChanges = $AlcChanges
}

[PSCustomObject]@{
    HasMaterialDrift = ($NewConflicts.Count -gt 0 -or $AlcChanges.Count -gt 0)
    Findings         = $Findings
}
