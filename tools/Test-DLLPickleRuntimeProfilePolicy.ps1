<#
.SYNOPSIS
    Validates DLLPickle runtime-profile and lifecycle policy data.

.DESCRIPTION
    Confirms that shipped runtime mappings and non-shipped CI mappings agree,
    then evaluates lifecycle expiration, retirement proximity, and evidence
    freshness. Release mode fails closed on expired support or stale evidence.

.PARAMETER RuntimePolicyPath
    Path to the shipped runtime profile policy.

.PARAMETER TestMatrixPath
    Path to the non-shipped exact test matrix.

.PARAMETER LifecycleEvidencePath
    Optional current support-update discovery report. When supplied, the report
    must describe a release-current support contract, and its generation time is
    used instead of the committed matrix timestamp for evidence freshness.

.PARAMETER Mode
    Release fails closed. Scheduled emits warnings before retirement and for stale evidence.

.PARAMETER AsOfUtc
    UTC timestamp used for deterministic lifecycle evaluation.

.PARAMETER PassThru
    Returns one structured result per supported profile.

.EXAMPLE
    ./tools/Test-DLLPickleRuntimeProfilePolicy.ps1 -Mode Release

.OUTPUTS
    PSCustomObject when PassThru is specified.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RuntimePolicyPath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/DLLPickle/SupportedRuntimeProfiles.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TestMatrixPath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'build/powershell-test-matrix.json'),

    [Parameter()]
    [string]$LifecycleEvidencePath,

    [Parameter()]
    [ValidateSet('Release', 'Scheduled')]
    [string]$Mode = 'Release',

    [Parameter()]
    [datetime]$AsOfUtc = [datetime]::UtcNow,

    [Parameter()]
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

foreach ($RequiredInput in @(
        [PSCustomObject]@{ Name = 'Runtime profile policy'; Path = $RuntimePolicyPath }
        [PSCustomObject]@{ Name = 'PowerShell test matrix'; Path = $TestMatrixPath }
    )) {
    if (-not (Test-Path -LiteralPath $RequiredInput.Path -PathType Leaf)) {
        throw "$($RequiredInput.Name) file not found: $($RequiredInput.Path)"
    }
}
if (-not [string]::IsNullOrWhiteSpace($LifecycleEvidencePath) -and -not (Test-Path -LiteralPath $LifecycleEvidencePath -PathType Leaf)) {
    throw "PowerShell support-update evidence file not found: $LifecycleEvidencePath"
}

$RuntimePolicy = Get-Content -LiteralPath $RuntimePolicyPath -Raw | ConvertFrom-Json -ErrorAction Stop
$TestMatrix = Get-Content -LiteralPath $TestMatrixPath -Raw | ConvertFrom-Json -ErrorAction Stop
if ($RuntimePolicy.schemaVersion -ne 1 -or $TestMatrix.schemaVersion -ne 1) {
    throw 'Unsupported runtime-profile policy schema version.'
}

$RuntimeProfiles = @($RuntimePolicy.profiles)
$TestProfiles = @($TestMatrix.profiles)
if ($RuntimeProfiles.Count -eq 0 -or $TestProfiles.Count -eq 0) {
    throw 'Runtime-profile policy must contain at least one profile.'
}

$RuntimeKeys = @($RuntimeProfiles | ForEach-Object {
        '{0}.{1}|{2}|{3}' -f $_.powerShellMajor, $_.powerShellMinor, $_.dotnetMajor, $_.targetFramework
    })
$TestKeys = @($TestProfiles | ForEach-Object {
        '{0}.{1}|{2}|{3}' -f $_.powerShellMajor, $_.powerShellMinor, $_.dotnetMajor, $_.targetFramework
    })
if (@($RuntimeKeys | Sort-Object -Unique).Count -ne $RuntimeKeys.Count) {
    throw 'Shipped runtime-profile policy contains duplicate profiles.'
}
if (@($TestKeys | Sort-Object -Unique).Count -ne $TestKeys.Count) {
    throw 'Test matrix contains duplicate profiles.'
}
if ((@($RuntimeKeys | Sort-Object) -join [char]0) -ne (@($TestKeys | Sort-Object) -join [char]0)) {
    throw 'Shipped runtime-profile policy and CI test-matrix profile sets do not align.'
}

$LifecycleEvidence = if (-not [string]::IsNullOrWhiteSpace($LifecycleEvidencePath)) {
    Get-Content -LiteralPath $LifecycleEvidencePath -Raw | ConvertFrom-Json -ErrorAction Stop
} else {
    $null
}
if ($LifecycleEvidence) {
    $RequiredEvidenceProperties = @(
        'generatedAtUtc',
        'patchUpdates',
        'newLines',
        'lifecycle',
        'lifecycleDateChanges',
        'lifecycleMissingLines',
        'undeclaredSupportedLines',
        'supportContractReviewRequired'
    )
    $MissingEvidenceProperties = @($RequiredEvidenceProperties | Where-Object { $LifecycleEvidence.PSObject.Properties.Name -notcontains $_ })
    if ($LifecycleEvidence.schemaVersion -ne 1 -or $MissingEvidenceProperties.Count -gt 0 -or [string]::IsNullOrWhiteSpace([string]$LifecycleEvidence.generatedAtUtc)) {
        throw 'PowerShell support-update evidence has an unsupported schema or no generation timestamp.'
    }
    $LiveEvidenceViolations = [System.Collections.Generic.List[string]]::new()
    if (@($LifecycleEvidence.patchUpdates).Count -gt 0) { $LiveEvidenceViolations.Add('newer servicing patches') }
    if (@($LifecycleEvidence.newLines).Count -gt 0) { $LiveEvidenceViolations.Add('new GA PowerShell lines') }
    if (@($LifecycleEvidence.lifecycleDateChanges).Count -gt 0) { $LiveEvidenceViolations.Add('lifecycle date changes') }
    if (@($LifecycleEvidence.lifecycleMissingLines).Count -gt 0) { $LiveEvidenceViolations.Add('declared lifecycle lines missing from live evidence') }
    if (@($LifecycleEvidence.undeclaredSupportedLines).Count -gt 0) { $LiveEvidenceViolations.Add('undeclared Microsoft-supported lines') }
    if (@($LifecycleEvidence.lifecycle | Where-Object Status -EQ 'Expired').Count -gt 0) { $LiveEvidenceViolations.Add('expired PowerShell lines') }
    $DeclaredReleaseLines = @($TestProfiles | ForEach-Object { '{0}.{1}' -f $_.powerShellMajor, $_.powerShellMinor } | Sort-Object -Unique)
    $EvidenceReleaseLines = @($LifecycleEvidence.lifecycle.ReleaseLine | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    if (($DeclaredReleaseLines -join [char]0) -ne ($EvidenceReleaseLines -join [char]0)) { $LiveEvidenceViolations.Add('live lifecycle rows do not align with declared PowerShell lines') }
    if ($LiveEvidenceViolations.Count -gt 0) {
        throw "PowerShell support-update evidence is not release-current: $($LiveEvidenceViolations -join '; ')."
    }
}

$VerifiedTimestamp = if ($LifecycleEvidence) { [string]$LifecycleEvidence.generatedAtUtc } else { [string]$TestMatrix.lastVerifiedUtc }
$VerifiedUtc = [datetime]::Parse(
    $VerifiedTimestamp,
    [System.Globalization.CultureInfo]::InvariantCulture,
    [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
)
$EvaluationUtc = $AsOfUtc.ToUniversalTime()
$EvidenceAgeDays = [math]::Max(0, ($EvaluationUtc - $VerifiedUtc).TotalDays)
$EvidenceIsStale = $EvidenceAgeDays -gt [double]$TestMatrix.evidenceFreshnessDays

$Results = [System.Collections.Generic.List[object]]::new()
$ExpiredLines = [System.Collections.Generic.List[string]]::new()
$PacificTimeZone = try {
    [System.TimeZoneInfo]::FindSystemTimeZoneById('America/Los_Angeles')
} catch {
    [System.TimeZoneInfo]::FindSystemTimeZoneById('Pacific Standard Time')
}
foreach ($TestProfile in $TestProfiles) {
    $Version = [version]$TestProfile.powerShellVersion
    if ($Version.Major -ne $TestProfile.powerShellMajor -or $Version.Minor -ne $TestProfile.powerShellMinor) {
        throw "Exact PowerShell patch '$($TestProfile.powerShellVersion)' does not match its declared release line."
    }
    if ($TestProfile.targetFramework -ne "net$($TestProfile.dotnetMajor).0") {
        throw "Target framework '$($TestProfile.targetFramework)' does not match CLR major '$($TestProfile.dotnetMajor)'."
    }

    $EndDate = [datetime]::ParseExact(
        [string]$TestProfile.lifecycleEndDate,
        'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None
    )
    $EndExclusivePacific = [datetime]::SpecifyKind($EndDate.AddDays(1), [System.DateTimeKind]::Unspecified)
    $EndExclusiveUtc = [System.TimeZoneInfo]::ConvertTimeToUtc($EndExclusivePacific, $PacificTimeZone)
    $DaysRemaining = [math]::Floor(($EndExclusiveUtc - $EvaluationUtc).TotalDays)
    $ReleaseLine = '{0}.{1}' -f $TestProfile.powerShellMajor, $TestProfile.powerShellMinor
    $Status = if ($EvaluationUtc -ge $EndExclusiveUtc) {
        $ExpiredLines.Add($ReleaseLine)
        'Expired'
    } elseif ($DaysRemaining -le [int]$TestMatrix.retirementWarningDays) {
        'RetiringSoon'
    } else {
        'Supported'
    }

    if ($Mode -eq 'Scheduled' -and $Status -eq 'RetiringSoon') {
        Write-Warning "PowerShell $ReleaseLine retires on $($TestProfile.lifecycleEndDate) ($DaysRemaining day(s) remaining)."
    }

    $Results.Add([PSCustomObject]@{
            PowerShellVersion = $TestProfile.powerShellVersion
            ReleaseLine       = $ReleaseLine
            DotnetMajor       = [int]$TestProfile.dotnetMajor
            TargetFramework   = $TestProfile.targetFramework
            LifecycleEndDate  = $TestProfile.lifecycleEndDate
            DaysRemaining     = $DaysRemaining
            EvidenceAgeDays   = [math]::Round($EvidenceAgeDays, 2)
            Status            = $Status
        })
}

$Violations = [System.Collections.Generic.List[string]]::new()
if ($ExpiredLines.Count -gt 0) {
    $Violations.Add("expired PowerShell lines: $($ExpiredLines -join ', ')")
}
if ($EvidenceIsStale) {
    $EvidenceDescription = if ($LifecycleEvidence) { "live evidence generated $VerifiedTimestamp" } else { "last verified $VerifiedTimestamp" }
    $Violations.Add("lifecycle evidence is stale; $EvidenceDescription, $([math]::Floor($EvidenceAgeDays)) day(s) ago")
    if ($Mode -eq 'Scheduled') {
        Write-Warning $Violations[$Violations.Count - 1]
    }
}

if ($Mode -eq 'Release' -and $Violations.Count -gt 0) {
    throw "Runtime profile policy release check failed: $($Violations -join '; ')."
}
if ($Mode -eq 'Scheduled' -and $ExpiredLines.Count -gt 0) {
    throw "Runtime profile policy contains expired PowerShell lines: $($ExpiredLines -join ', ')."
}

if ($PassThru) {
    $Results
}
