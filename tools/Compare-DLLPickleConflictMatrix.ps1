<#
.SYNOPSIS
    Diffs two DLLPickle conflict matrices and reports material drift.
.DESCRIPTION
    Material drift includes new or removed conflicts, version-set changes, contributing-module-set
    changes, and ALC-ownership changes. This matches the versions- and contributor-aware fingerprint
    emitted by New-DLLPickleConflictMatrix.ps1 and consumed by the required PR gate.
.PARAMETER Baseline
    The baseline conflict matrix (as produced by New-DLLPickleConflictMatrix.ps1).
.PARAMETER Current
    The current conflict matrix to compare against the baseline.
.OUTPUTS
    PSCustomObject with HasMaterialDrift and a structured Findings breakdown.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [PSCustomObject]$Baseline,
    [Parameter(Mandatory)] [PSCustomObject]$Current
)

$ErrorActionPreference = 'Stop'

$BaselineProfileKey = if ($Baseline.PSObject.Properties.Name -contains 'ProfileKey') { [string]$Baseline.ProfileKey } else { $null }
$CurrentProfileKey = if ($Current.PSObject.Properties.Name -contains 'ProfileKey') { [string]$Current.ProfileKey } else { $null }
if (
    -not [string]::IsNullOrWhiteSpace($BaselineProfileKey) -and
    -not [string]::IsNullOrWhiteSpace($CurrentProfileKey) -and
    $BaselineProfileKey -ne $CurrentProfileKey
) {
    throw "Cannot compare conflict matrices from different runtime profiles: '$BaselineProfileKey' and '$CurrentProfileKey'."
}

function Test-DLLPickleStringSetEqual {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$Left = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$Right = @()
    )

    $Difference = Compare-Object -ReferenceObject @($Left | Sort-Object -Unique) -DifferenceObject @($Right | Sort-Object -Unique)
    return @($Difference).Count -eq 0
}

$BaseSurface = @($Baseline.Assemblies | Where-Object Diverges | ForEach-Object Name)
$CurrSurface = @($Current.Assemblies  | Where-Object Diverges | ForEach-Object Name)

$NewConflicts     = @($CurrSurface | Where-Object { $_ -notin $BaseSurface })
$RemovedConflicts = @($BaseSurface | Where-Object { $_ -notin $CurrSurface })

$BaseByName = @{}
foreach ($Assembly in $Baseline.Assemblies) {
    $BaseByName[[string]$Assembly.Name] = $Assembly
}

$CurrentByName = @{}
foreach ($Assembly in $Current.Assemblies) {
    $CurrentByName[[string]$Assembly.Name] = $Assembly
}

$CommonConflicts = @($BaseSurface | Where-Object { $_ -in $CurrSurface })
$VersionChanges = @(
    foreach ($Name in $CommonConflicts) {
        $BaselineVersions = @($BaseByName[$Name].Versions | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        $CurrentVersions = @($CurrentByName[$Name].Versions | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        if (-not (Test-DLLPickleStringSetEqual -Left $BaselineVersions -Right $CurrentVersions)) {
            [PSCustomObject]@{
                Name     = $Name
                Baseline = $BaselineVersions
                Current  = $CurrentVersions
            }
        }
    }
)

$ContributorChanges = @(
    foreach ($Name in $CommonConflicts) {
        $BaselineContributors = @($BaseByName[$Name].ShippedBy | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        $CurrentContributors = @($CurrentByName[$Name].ShippedBy | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        if (-not (Test-DLLPickleStringSetEqual -Left $BaselineContributors -Right $CurrentContributors)) {
            [PSCustomObject]@{
                Name     = $Name
                Baseline = $BaselineContributors
                Current  = $CurrentContributors
            }
        }
    }
)

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
    VersionChanges      = $VersionChanges
    ContributorChanges  = $ContributorChanges
    AlcOwnershipChanges = $AlcChanges
}

$FindingCanonicalText = @(
    "profile=$CurrentProfileKey"
    "new=$(@($NewConflicts | Sort-Object) -join ',')"
    "removed=$(@($RemovedConflicts | Sort-Object) -join ',')"
    "versions=$(@($VersionChanges | Sort-Object Name | ForEach-Object { '{0}:{1}>{2}' -f $_.Name, (@($_.Baseline) -join ','), (@($_.Current) -join ',') }) -join ';')"
    "contributors=$(@($ContributorChanges | Sort-Object Name | ForEach-Object { '{0}:{1}>{2}' -f $_.Name, (@($_.Baseline) -join ','), (@($_.Current) -join ',') }) -join ';')"
    "alc=$(@($AlcChanges | Sort-Object) -join ',')"
) -join '|'
$FindingFingerprintBytes = [System.Text.Encoding]::UTF8.GetBytes($FindingCanonicalText)
$FindingFingerprint = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($FindingFingerprintBytes)).Replace('-', '').ToLowerInvariant()

[PSCustomObject]@{
    ProfileKey       = $CurrentProfileKey
    FindingFingerprint = $FindingFingerprint
    HasMaterialDrift = (
        $NewConflicts.Count -gt 0 -or
        $RemovedConflicts.Count -gt 0 -or
        $VersionChanges.Count -gt 0 -or
        $ContributorChanges.Count -gt 0 -or
        $AlcChanges.Count -gt 0
    )
    Findings         = $Findings
}
