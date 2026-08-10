<#
.SYNOPSIS
Records explicit maintainer acceptance of a validated manual evidence candidate.

.DESCRIPTION
Validates the pending candidate, adds only acceptance metadata, writes the
committable transition file, and immediately revalidates it in Release mode.
This command does not commit, push, release, or publish anything.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
[OutputType([pscustomobject])]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$CandidateEvidencePath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'build/authenticated-evidence/initial-multitarget-major.json'),

    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$')]
    [string]$AcceptedBy,

    [Parameter(Mandatory)]
    [ValidateSet('low', 'medium', 'high')]
    [string]$Confidence,

    [Parameter()]
    [System.DateTimeOffset]$AcceptedAtUtc = [System.DateTimeOffset]::UtcNow
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$ValidatorPath = Join-Path $PSScriptRoot 'Test-DLLPickleManualAuthenticatedEvidence.ps1'
$ValidationParameters = @{
    EvidencePath = $CandidateEvidencePath
    RepositoryRoot = $RepositoryRoot
    TestMatrixPath = (Join-Path $RepositoryRoot 'build/powershell-test-matrix.json')
    DependencyPolicyPath = (Join-Path $RepositoryRoot 'build/dependency-policy.json')
    Mode = 'Capture'
    NowUtc = $AcceptedAtUtc
}
$null = & $ValidatorPath @ValidationParameters
$Evidence = Get-Content -LiteralPath $CandidateEvidencePath -Raw | ConvertFrom-Json -ErrorAction Stop
$Evidence.acceptance.status = 'accepted'
$Evidence.acceptance.acceptedAtUtc = $AcceptedAtUtc.ToUniversalTime().ToString('o')
$Evidence.acceptance.acceptedBy = $AcceptedBy
$Evidence.acceptance.confidence = $Confidence

if (-not $PSCmdlet.ShouldProcess($OutputPath, "Record accepted manual authenticated evidence for version $($Evidence.content.bridge.allowedReleaseVersion)")) {
    return
}
$OutputDirectory = Split-Path -Path $OutputPath -Parent
if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
}
$Evidence | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
$ValidationParameters.EvidencePath = $OutputPath
$ValidationParameters.Mode = 'Release'
$Validated = & $ValidatorPath @ValidationParameters
[pscustomobject]@{
    OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    AcceptedBy = $AcceptedBy
    Confidence = $Confidence
    AcceptedAtUtc = $AcceptedAtUtc.ToUniversalTime().ToString('o')
    EvidenceFingerprint = [string]$Validated.EvidenceFingerprint
    BundleSourceFingerprint = [string]$Validated.BundleSourceFingerprint
    AllowedReleaseVersion = [string]$Validated.AllowedReleaseVersion
    ExpiresAtUtc = [string]$Validated.ExpiresAtUtc
    WritesPerformed = $false
}
