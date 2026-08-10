<#
.SYNOPSIS
Fail closed when a profile-specific upstream conflict baseline is absent or has drifted.

.PARAMETER PolicyPath
Path to the profile-aware dependency policy.

.PARAMETER ConflictMatrixPath
Path to a current profile-keyed conflict matrix.

.PARAMETER ScenarioEvidencePath
Path to the deterministic two-order, with/without-DLLPickle scenario report for
the same exact profile.

.PARAMETER NormalizedEvidencePath
Path to the durable normalized candidate snapshot generated from the same run.

.PARAMETER PassThru
Return a structured comparison result after validation.

.PARAMETER OutputPath
Optional path for the structured result. The result is written before a missing,
unaccepted, or drifted baseline causes the command to fail closed.

.OUTPUTS
System.Management.Automation.PSCustomObject
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param (
    [Parameter(Mandatory)]
    [string]$PolicyPath,

    [Parameter(Mandatory)]
    [string]$ConflictMatrixPath,

    [Parameter(Mandatory)]
    [string]$ScenarioEvidencePath,

    [Parameter(Mandatory)]
    [string]$NormalizedEvidencePath,

    [Parameter()]
    [switch]$PassThru,

    [Parameter()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$Policy = Get-Content -LiteralPath $PolicyPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$Matrix = Get-Content -LiteralPath $ConflictMatrixPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$ScenarioEvidence = Get-Content -LiteralPath $ScenarioEvidencePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$NormalizedEvidence = Get-Content -LiteralPath $NormalizedEvidencePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

function Get-NormalizedContentFingerprint {
    param([Parameter(Mandatory)][object]$Evidence)

    if ([int]$Evidence.schemaVersion -ne 1 -or -not $Evidence.content) {
        throw 'Normalized profile evidence has an unsupported schema or no fingerprinted content.'
    }
    $CanonicalContent = $Evidence.content | ConvertTo-Json -Depth 100 -Compress
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($CanonicalContent)
    [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($Bytes)).Replace('-', '').ToLowerInvariant()
}

$CandidateEvidenceFingerprint = Get-NormalizedContentFingerprint -Evidence $NormalizedEvidence
if ([string]$NormalizedEvidence.contentFingerprint -ne $CandidateEvidenceFingerprint) {
    throw "Normalized profile evidence content does not recompute to '$($NormalizedEvidence.contentFingerprint)'."
}
if (-not $Matrix.Profile -or [string]::IsNullOrWhiteSpace([string]$Matrix.ProfileKey)) {
    throw 'The conflict matrix is not keyed to an exact runtime profile.'
}
$MatrixProfileKeyValues = @(
    [string]$Matrix.Profile.PowerShellLine
    [string]$Matrix.Profile.TargetFramework
    [string]$Matrix.Profile.Platform
    [string]$Matrix.Profile.Architecture
)
if (@($MatrixProfileKeyValues | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
    throw "Conflict matrix '$($Matrix.ProfileKey)' lacks a complete PowerShell line, TFM, platform, and architecture profile."
}
$DerivedMatrixProfileKey = 'ps{0}-{1}-{2}-{3}' -f $MatrixProfileKeyValues
if ([string]$Matrix.ProfileKey -ne $DerivedMatrixProfileKey) {
    throw "Conflict matrix profile key '$($Matrix.ProfileKey)' does not match derived profile key '$DerivedMatrixProfileKey'."
}
if (-not $ScenarioEvidence.Profile) {
    throw "Scenario evidence for '$($Matrix.ProfileKey)' has no observed runtime profile."
}
$ScenarioProfileKeyValues = @(
    [string]$ScenarioEvidence.Profile.PowerShellLine
    [string]$ScenarioEvidence.Profile.TargetFramework
    [string]$ScenarioEvidence.Profile.Platform
    [string]$ScenarioEvidence.Profile.Architecture
)
if (@($ScenarioProfileKeyValues | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
    throw "Scenario evidence '$($ScenarioEvidence.ProfileKey)' lacks a complete PowerShell line, TFM, platform, and architecture profile."
}
$DerivedScenarioProfileKey = 'ps{0}-{1}-{2}-{3}' -f $ScenarioProfileKeyValues
if ([string]$ScenarioEvidence.ProfileKey -ne $DerivedScenarioProfileKey) {
    throw "Scenario evidence profile key '$($ScenarioEvidence.ProfileKey)' does not match derived profile key '$DerivedScenarioProfileKey'."
}
if ($DerivedScenarioProfileKey -ne $DerivedMatrixProfileKey) {
    throw "Scenario evidence profile '$DerivedScenarioProfileKey' does not match conflict profile '$DerivedMatrixProfileKey'."
}
$ObservedScenarioAssemblies = @(
    foreach ($Scenario in @($ScenarioEvidence.Scenarios)) {
        foreach ($Assembly in @($Scenario.Assemblies)) {
            $Assembly
        }
    }
)
if ($ObservedScenarioAssemblies.Count -eq 0) {
    throw "Scenario evidence for '$($Matrix.ProfileKey)' contains no observed tracked assemblies."
}
foreach ($ObservedAssembly in $ObservedScenarioAssemblies) {
    if ([string]$ObservedAssembly.Platform -ne [string]$Matrix.Profile.Platform -or
        [string]$ObservedAssembly.Architecture -ne [string]$Matrix.Profile.Architecture) {
        throw "Scenario assembly '$($ObservedAssembly.Name)' was observed on '$($ObservedAssembly.Platform)/$($ObservedAssembly.Architecture)', expected '$($Matrix.Profile.Platform)/$($Matrix.Profile.Architecture)' for '$($Matrix.ProfileKey)'."
    }
}
if (-not $ScenarioEvidence.Passed -or $ScenarioEvidence.WritesPerformed -or $ScenarioEvidence.ValidationTier -ne 'deterministic-import-no-auth') {
    throw "Scenario evidence for '$($Matrix.ProfileKey)' is not a passing zero-write deterministic tier."
}
if ([string]$NormalizedEvidence.content.profile.profileKey -ne [string]$Matrix.ProfileKey) {
    throw "Normalized evidence profile '$($NormalizedEvidence.content.profile.profileKey)' does not match '$($Matrix.ProfileKey)'."
}
if ([string]$NormalizedEvidence.content.validation.deterministicImportNoAuth.conflictSurfaceFingerprint -ne [string]$Matrix.Fingerprint -or
    [string]$NormalizedEvidence.content.validation.deterministicImportNoAuth.scenarioFingerprint -ne [string]$ScenarioEvidence.ScenarioFingerprint) {
    throw "Normalized evidence for '$($Matrix.ProfileKey)' does not bind the current conflict and scenario fingerprints."
}
if ([string]$NormalizedEvidence.content.validation.deterministicImportNoAuth.status -ne 'passed' -or
    $NormalizedEvidence.content.validation.deterministicImportNoAuth.writesPerformed -or
    $NormalizedEvidence.content.validation.authenticatedReadOnly.writesPerformed) {
    throw "Normalized evidence for '$($Matrix.ProfileKey)' is not a passing zero-write deterministic snapshot."
}

$ProfilePolicy = @($Policy.runtimeProfiles | Where-Object {
        $_.powerShellLine -eq $Matrix.Profile.PowerShellLine -and
        $_.targetFramework -eq $Matrix.Profile.TargetFramework
    })
if ($ProfilePolicy.Count -ne 1) {
    throw "No unique dependency-policy profile matches '$($Matrix.ProfileKey)'."
}

$Platform = [string]$Matrix.Profile.Platform
$BaselineProperty = $ProfilePolicy[0].baselines.PSObject.Properties |
    Where-Object Name -eq $Platform |
    Select-Object -First 1
if (-not $BaselineProperty) {
    throw "No $Platform conflict baseline is declared for '$($Matrix.ProfileKey)'."
}

$Baseline = $BaselineProperty.Value
$BaselineFingerprint = [string]$Baseline.conflictSurfaceFingerprint
$CurrentFingerprint = [string]$Matrix.Fingerprint
$BaselineScenarioFingerprint = [string]$Baseline.scenarioFingerprint
$CurrentScenarioFingerprint = [string]$ScenarioEvidence.ScenarioFingerprint
$BaselineEvidencePath = [string]$Baseline.evidencePath
$BaselineEvidenceFingerprint = [string]$Baseline.evidenceFingerprint
$Status = if (
    $Baseline.status -ne 'accepted' -or
    [string]::IsNullOrWhiteSpace($BaselineFingerprint) -or
    [string]::IsNullOrWhiteSpace($BaselineScenarioFingerprint) -or
    [string]::IsNullOrWhiteSpace($BaselineEvidencePath) -or
    [string]::IsNullOrWhiteSpace($BaselineEvidenceFingerprint)
) {
    'RequiresAcceptance'
} elseif (
    $CurrentFingerprint -ne $BaselineFingerprint -or
    $CurrentScenarioFingerprint -ne $BaselineScenarioFingerprint -or
    $CandidateEvidenceFingerprint -ne $BaselineEvidenceFingerprint
) {
    'Drifted'
} else {
    'AcceptedUnchanged'
}

if ($Status -eq 'AcceptedUnchanged') {
    $ResolvedPolicyPath = (Resolve-Path -LiteralPath $PolicyPath).Path
    $CommittedEvidencePath = Join-Path -Path (Split-Path -Path $ResolvedPolicyPath -Parent) -ChildPath $BaselineEvidencePath
    if (-not (Test-Path -LiteralPath $CommittedEvidencePath -PathType Leaf)) {
        throw "Accepted evidence for '$($Matrix.ProfileKey)' was not found at '$CommittedEvidencePath'."
    }
    $CommittedEvidence = Get-Content -LiteralPath $CommittedEvidencePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $CommittedEvidenceFingerprint = Get-NormalizedContentFingerprint -Evidence $CommittedEvidence
    if ([string]$CommittedEvidence.contentFingerprint -ne $CommittedEvidenceFingerprint -or
        $CommittedEvidenceFingerprint -ne $BaselineEvidenceFingerprint) {
        throw "Accepted evidence for '$($Matrix.ProfileKey)' does not recompute to the policy fingerprint '$BaselineEvidenceFingerprint'."
    }
    if ([string]$CommittedEvidence.content.profile.profileKey -ne [string]$Matrix.ProfileKey -or
        [string]$CommittedEvidence.content.validation.deterministicImportNoAuth.conflictSurfaceFingerprint -ne $BaselineFingerprint -or
        [string]$CommittedEvidence.content.validation.deterministicImportNoAuth.scenarioFingerprint -ne $BaselineScenarioFingerprint) {
        throw "Accepted evidence for '$($Matrix.ProfileKey)' does not bind the policy profile, conflict, and scenario fingerprints."
    }
}

$FindingCanonicalText = '{0}|{1}|conflict:{2}>{3}|scenario:{4}>{5}|evidence:{6}>{7}' -f $Matrix.ProfileKey, $Status, $BaselineFingerprint, $CurrentFingerprint, $BaselineScenarioFingerprint, $CurrentScenarioFingerprint, $BaselineEvidenceFingerprint, $CandidateEvidenceFingerprint
$FindingBytes = [System.Text.Encoding]::UTF8.GetBytes($FindingCanonicalText)
$FindingFingerprint = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($FindingBytes)).Replace('-', '').ToLowerInvariant()
$Result = [pscustomobject]@{
    ProfileKey          = [string]$Matrix.ProfileKey
    BaselineStatus      = [string]$Baseline.status
    BaselineFingerprint = $BaselineFingerprint
    CurrentFingerprint  = $CurrentFingerprint
    BaselineScenarioFingerprint = $BaselineScenarioFingerprint
    CurrentScenarioFingerprint = $CurrentScenarioFingerprint
    BaselineEvidenceFingerprint = $BaselineEvidenceFingerprint
    CurrentEvidenceFingerprint = $CandidateEvidenceFingerprint
    BaselineEvidencePath = $BaselineEvidencePath
    FindingFingerprint  = $FindingFingerprint
    Status              = $Status
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputDirectory = Split-Path -Path $OutputPath -Parent
    if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
    }
    $Result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}

if ($Status -eq 'RequiresAcceptance') {
    throw "The conflict baseline for '$($Matrix.ProfileKey)' is not accepted. Current status: '$($Baseline.status)'. Review the profile evidence before release or merge."
}
if ($Status -eq 'Drifted') {
    throw "Upstream profile evidence drift detected for '$($Matrix.ProfileKey)': baseline conflict '$BaselineFingerprint', current conflict '$CurrentFingerprint'; baseline scenario '$BaselineScenarioFingerprint', current scenario '$CurrentScenarioFingerprint'; baseline evidence '$BaselineEvidenceFingerprint', current evidence '$CandidateEvidenceFingerprint'."
}
if ($PassThru) { $Result }
