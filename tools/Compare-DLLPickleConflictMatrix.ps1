<#
.SYNOPSIS
    Diffs two DLLPickle conflict matrices and reports material drift.
.DESCRIPTION
    Material drift includes new or removed tracked assemblies and conflicts, version-set changes,
    contributing-module-set changes, selected-hash changes, and ALC-ownership changes. This matches
    the profile evidence fingerprint emitted by New-DLLPickleConflictMatrix.ps1 and consumed by the
    required PR gate.
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

function Get-DLLPickleAssemblyEvidenceSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Assembly,

        [Parameter(Mandatory)]
        [string]$PropertyName,

        [Parameter()]
        [string]$LegacyPropertyName
    )

    if ($Assembly.PSObject.Properties.Name -contains $PropertyName) {
        return @(
            $Assembly.$PropertyName |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
    }
    if (
        -not [string]::IsNullOrWhiteSpace($LegacyPropertyName) -and
        $Assembly.PSObject.Properties.Name -contains $LegacyPropertyName -and
        -not [string]::IsNullOrWhiteSpace([string]$Assembly.$LegacyPropertyName)
    ) {
        return @([string]$Assembly.$LegacyPropertyName)
    }
    return @()
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

$BaseAssemblyNames = @($BaseByName.Keys | Sort-Object)
$CurrentAssemblyNames = @($CurrentByName.Keys | Sort-Object)
$NewTrackedAssemblies = @($CurrentAssemblyNames | Where-Object { $_ -notin $BaseAssemblyNames })
$RemovedTrackedAssemblies = @($BaseAssemblyNames | Where-Object { $_ -notin $CurrentAssemblyNames })
$CommonAssemblies = @($BaseAssemblyNames | Where-Object { $_ -in $CurrentAssemblyNames })
$VersionChanges = @(
    foreach ($Name in $CommonAssemblies) {
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
    foreach ($Name in $CommonAssemblies) {
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

$HashChanges = @(
    foreach ($Name in $CommonAssemblies) {
        $BaselineHashes = @(Get-DLLPickleAssemblyEvidenceSet -Assembly $BaseByName[$Name] -PropertyName 'Hashes')
        $CurrentHashes = @(Get-DLLPickleAssemblyEvidenceSet -Assembly $CurrentByName[$Name] -PropertyName 'Hashes')
        if (-not (Test-DLLPickleStringSetEqual -Left $BaselineHashes -Right $CurrentHashes)) {
            [PSCustomObject]@{
                Name     = $Name
                Baseline = $BaselineHashes
                Current  = $CurrentHashes
            }
        }
    }
)

$AlcChangeDetails = @(
    foreach ($Name in $CommonAssemblies) {
        $BaselineAlcOwners = @(
            Get-DLLPickleAssemblyEvidenceSet -Assembly $BaseByName[$Name] -PropertyName 'AlcOwners' -LegacyPropertyName 'AlcOwner'
        )
        $CurrentAlcOwners = @(
            Get-DLLPickleAssemblyEvidenceSet -Assembly $CurrentByName[$Name] -PropertyName 'AlcOwners' -LegacyPropertyName 'AlcOwner'
        )
        if (-not (Test-DLLPickleStringSetEqual -Left $BaselineAlcOwners -Right $CurrentAlcOwners)) {
            [PSCustomObject]@{
                Name     = $Name
                Baseline = $BaselineAlcOwners
                Current  = $CurrentAlcOwners
            }
        }
    }
)
$AlcChanges = @($AlcChangeDetails | ForEach-Object Name)

$Findings = [PSCustomObject]@{
    NewTrackedAssemblies      = $NewTrackedAssemblies
    RemovedTrackedAssemblies  = $RemovedTrackedAssemblies
    NewConflicts              = $NewConflicts
    RemovedConflicts          = $RemovedConflicts
    VersionChanges            = $VersionChanges
    ContributorChanges        = $ContributorChanges
    HashChanges               = $HashChanges
    AlcOwnershipChanges       = $AlcChanges
    AlcOwnershipChangeDetails = $AlcChangeDetails
}

$FindingCanonicalText = @(
    "profile=$CurrentProfileKey"
    "newTracked=$(@($NewTrackedAssemblies | Sort-Object) -join ',')"
    "removedTracked=$(@($RemovedTrackedAssemblies | Sort-Object) -join ',')"
    "new=$(@($NewConflicts | Sort-Object) -join ',')"
    "removed=$(@($RemovedConflicts | Sort-Object) -join ',')"
    "versions=$(@($VersionChanges | Sort-Object Name | ForEach-Object { '{0}:{1}>{2}' -f $_.Name, (@($_.Baseline) -join ','), (@($_.Current) -join ',') }) -join ';')"
    "contributors=$(@($ContributorChanges | Sort-Object Name | ForEach-Object { '{0}:{1}>{2}' -f $_.Name, (@($_.Baseline) -join ','), (@($_.Current) -join ',') }) -join ';')"
    "hashes=$(@($HashChanges | Sort-Object Name | ForEach-Object { '{0}:{1}>{2}' -f $_.Name, (@($_.Baseline) -join ','), (@($_.Current) -join ',') }) -join ';')"
    "alc=$(@($AlcChangeDetails | Sort-Object Name | ForEach-Object { '{0}:{1}>{2}' -f $_.Name, (@($_.Baseline) -join ','), (@($_.Current) -join ',') }) -join ';')"
) -join '|'
$FindingFingerprintBytes = [System.Text.Encoding]::UTF8.GetBytes($FindingCanonicalText)
$FindingFingerprint = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($FindingFingerprintBytes)).Replace('-', '').ToLowerInvariant()

[PSCustomObject]@{
    ProfileKey       = $CurrentProfileKey
    FindingFingerprint = $FindingFingerprint
    HasMaterialDrift = (
        $NewTrackedAssemblies.Count -gt 0 -or
        $RemovedTrackedAssemblies.Count -gt 0 -or
        $NewConflicts.Count -gt 0 -or
        $RemovedConflicts.Count -gt 0 -or
        $VersionChanges.Count -gt 0 -or
        $ContributorChanges.Count -gt 0 -or
        $HashChanges.Count -gt 0 -or
        $AlcChanges.Count -gt 0
    )
    Findings         = $Findings
}
