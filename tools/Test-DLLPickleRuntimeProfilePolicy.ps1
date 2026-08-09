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

$VerifiedUtc = [datetime]::Parse(
    [string]$TestMatrix.lastVerifiedUtc,
    [System.Globalization.CultureInfo]::InvariantCulture,
    [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
)
$EvaluationUtc = $AsOfUtc.ToUniversalTime()
$EvidenceAgeDays = [math]::Max(0, ($EvaluationUtc - $VerifiedUtc).TotalDays)
$EvidenceIsStale = $EvidenceAgeDays -gt [double]$TestMatrix.evidenceFreshnessDays

$Results = [System.Collections.Generic.List[object]]::new()
$ExpiredLines = [System.Collections.Generic.List[string]]::new()
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
        [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    )
    $EndExclusiveUtc = $EndDate.AddDays(1)
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
    $Violations.Add("lifecycle evidence is stale; last verified $($TestMatrix.lastVerifiedUtc), $([math]::Floor($EvidenceAgeDays)) day(s) ago")
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
