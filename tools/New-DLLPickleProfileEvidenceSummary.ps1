<#
.SYNOPSIS
Aggregates exact-profile upstream baseline comparisons into one stable finding.

.DESCRIPTION
The summary is deterministic for the same comparison inputs. Its aggregate finding
fingerprint and HTML marker can be used to suppress repeated issue comments without
making this read-only command responsible for GitHub writes.
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$EvidenceRoot,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TestMatrixPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build/powershell-test-matrix.json'),

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $TestMatrixPath -PathType Leaf)) {
    throw "PowerShell test matrix was not found: $TestMatrixPath"
}
$Matrix = Get-Content -LiteralPath $TestMatrixPath -Raw | ConvertFrom-Json -ErrorAction Stop
$ExpectedProfileKeys = @(
    foreach ($RuntimeProfile in @($Matrix.profiles)) {
        foreach ($Lane in @($Matrix.lanes)) {
            'ps{0}.{1}-{2}-{3}-{4}' -f $RuntimeProfile.powerShellMajor, $RuntimeProfile.powerShellMinor, $RuntimeProfile.targetFramework, $Lane.platform, $Lane.architecture
        }
    }
)

$Comparisons = @(
    if (Test-Path -LiteralPath $EvidenceRoot -PathType Container) {
        foreach ($ComparisonFile in @(Get-ChildItem -LiteralPath $EvidenceRoot -File -Filter 'baseline-comparison.json' -Recurse | Sort-Object FullName)) {
            $Comparison = Get-Content -LiteralPath $ComparisonFile.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
            [PSCustomObject]@{
                ProfileKey = [string]$Comparison.ProfileKey
                Status = [string]$Comparison.Status
                BaselineStatus = [string]$Comparison.BaselineStatus
                BaselineFingerprint = [string]$Comparison.BaselineFingerprint
                CurrentFingerprint = [string]$Comparison.CurrentFingerprint
                BaselineScenarioFingerprint = [string]$Comparison.BaselineScenarioFingerprint
                CurrentScenarioFingerprint = [string]$Comparison.CurrentScenarioFingerprint
                BaselineEvidenceFingerprint = [string]$Comparison.BaselineEvidenceFingerprint
                CurrentEvidenceFingerprint = [string]$Comparison.CurrentEvidenceFingerprint
                BaselineEvidencePath = [string]$Comparison.BaselineEvidencePath
                FindingFingerprint = [string]$Comparison.FindingFingerprint
                SourcePath = [System.IO.Path]::GetRelativePath((Resolve-Path -LiteralPath $EvidenceRoot).Path, $ComparisonFile.FullName).Replace('\', '/')
            }
        }
    }
)
$DuplicateProfileKeys = @($Comparisons | Group-Object ProfileKey | Where-Object Count -GT 1 | ForEach-Object Name)
$MissingProfileKeys = @($ExpectedProfileKeys | Where-Object { $_ -notin $Comparisons.ProfileKey })
$UnexpectedProfileKeys = @($Comparisons.ProfileKey | Where-Object { $_ -notin $ExpectedProfileKeys })
$Findings = @($Comparisons | Where-Object Status -NE 'AcceptedUnchanged' | Sort-Object ProfileKey)
$CanonicalText = @(
    "missing=$($MissingProfileKeys -join ',')"
    "unexpected=$($UnexpectedProfileKeys -join ',')"
    "duplicates=$($DuplicateProfileKeys -join ',')"
    @($Comparisons | Sort-Object ProfileKey | ForEach-Object { '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}' -f $_.ProfileKey, $_.Status, $_.BaselineFingerprint, $_.CurrentFingerprint, $_.BaselineScenarioFingerprint, $_.CurrentScenarioFingerprint, $_.BaselineEvidenceFingerprint, $_.CurrentEvidenceFingerprint, $_.FindingFingerprint })
) -join [char]10
$FingerprintBytes = [System.Text.Encoding]::UTF8.GetBytes($CanonicalText)
$AggregateFingerprint = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($FingerprintBytes)).Replace('-', '').ToLowerInvariant()
$Complete = $Comparisons.Count -eq $ExpectedProfileKeys.Count -and $MissingProfileKeys.Count -eq 0 -and $UnexpectedProfileKeys.Count -eq 0 -and $DuplicateProfileKeys.Count -eq 0
$Ready = $Complete -and $Findings.Count -eq 0

$Summary = [PSCustomObject]@{
    SchemaVersion = 1
    GeneratedAtUtc = [System.DateTimeOffset]::UtcNow.ToString('o')
    ExpectedProfileKeys = @($ExpectedProfileKeys)
    Comparisons = @($Comparisons | Sort-Object ProfileKey)
    MissingProfileKeys = @($MissingProfileKeys)
    UnexpectedProfileKeys = @($UnexpectedProfileKeys)
    DuplicateProfileKeys = @($DuplicateProfileKeys)
    Findings = @($Findings)
    AggregateFindingFingerprint = $AggregateFingerprint
    FindingMarker = '<!-- dllpickle-finding-fingerprint:{0} -->' -f $AggregateFingerprint
    AllProfileEvidencePresent = $Complete
    ReadyForCandidateUpdate = $Ready
}

$OutputDirectory = Split-Path -Path $OutputPath -Parent
if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
}
$Summary | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

if ($Strict.IsPresent -and -not $Ready) {
    throw "Exact-profile upstream evidence is not ready: present=$Complete, findings=$($Findings.Count)."
}
$Summary
