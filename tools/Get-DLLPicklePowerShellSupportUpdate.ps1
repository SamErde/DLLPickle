<#
.SYNOPSIS
    Discovers PowerShell servicing and support-contract update candidates.

.DESCRIPTION
    Compares the canonical exact test matrix with stable releases from the official
    PowerShell GitHub repository. Patch candidates include the required platform
    archives and GitHub-published SHA-256 digests when available. New GA minor lines,
    approaching retirement, and expired lines are reported separately. The tool is
    read-only; publishing a proposal is a distinct workflow action. Stable patch and
    support-contract fingerprints allow that workflow to suppress duplicate PRs,
    issues, and comments without using timestamps as publication identities.

.PARAMETER ReleaseDataPath
    Optional JSON fixture or captured GitHub releases response. When omitted, query
    the official PowerShell/PowerShell releases API.

.PARAMETER LifecycleDataPath
    Optional captured Microsoft Lifecycle HTML fixture. When omitted, query the
    official Microsoft PowerShell lifecycle page.

.PARAMETER RequireCurrent
    Throw if a newer patch, new GA line, expired line, or incomplete checksum set is found.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TestMatrixPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build/powershell-test-matrix.json'),

    [Parameter()]
    [string]$ReleaseDataPath,

    [Parameter()]
    [string]$LifecycleDataPath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts/lifecycle/powershell-support-update.json'),

    [Parameter()]
    [datetime]$AsOfUtc = [datetime]::UtcNow,

    [Parameter()]
    [switch]$RequireCurrent
)

$ErrorActionPreference = 'Stop'

function Get-DLLPickleStableFingerprint {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$CanonicalLine = @()
    )

    $CanonicalText = @($CanonicalLine | Sort-Object) -join [char]10
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($CanonicalText)
    return [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($Bytes)).Replace('-', '').ToLowerInvariant()
}

if (-not (Test-Path -LiteralPath $TestMatrixPath -PathType Leaf)) {
    throw "PowerShell test matrix was not found: $TestMatrixPath"
}

$TestMatrix = Get-Content -LiteralPath $TestMatrixPath -Raw | ConvertFrom-Json -ErrorAction Stop
$ReleaseData = if (-not [string]::IsNullOrWhiteSpace($ReleaseDataPath)) {
    if (-not (Test-Path -LiteralPath $ReleaseDataPath -PathType Leaf)) {
        throw "PowerShell release data was not found: $ReleaseDataPath"
    }
    @(Get-Content -LiteralPath $ReleaseDataPath -Raw | ConvertFrom-Json -ErrorAction Stop)
} else {
    $Headers = @{
        Accept               = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent'         = 'DLLPickle-support-policy'
    }
    @(Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases?per_page=100' -Headers $Headers -ErrorAction Stop)
}

$StableReleases = @(
    foreach ($Release in $ReleaseData) {
        $TagMatch = [regex]::Match([string]$Release.tag_name, '^v(?<version>7\.\d+\.\d+)$')
        if (-not $Release.draft -and -not $Release.prerelease -and $TagMatch.Success) {
            $ReleaseVersion = [version]$TagMatch.Groups['version'].Value
            $PublishedAt = if ($Release.published_at) { [datetime]$Release.published_at } else { [datetime]::MinValue }
            if ($PublishedAt -le $AsOfUtc.ToUniversalTime()) {
                [PSCustomObject]@{
                    Version     = $ReleaseVersion
                    ReleaseLine = '{0}.{1}' -f $ReleaseVersion.Major, $ReleaseVersion.Minor
                    PublishedAt = $PublishedAt.ToUniversalTime()
                    HtmlUrl     = [string]$Release.html_url
                    Assets      = @($Release.assets)
                }
            }
        }
    }
)
if ($StableReleases.Count -eq 0) {
    throw 'No stable PowerShell 7 release records were found in the official release data.'
}

$LifecycleContent = if (-not [string]::IsNullOrWhiteSpace($LifecycleDataPath)) {
    if (-not (Test-Path -LiteralPath $LifecycleDataPath -PathType Leaf)) {
        throw "PowerShell lifecycle data was not found: $LifecycleDataPath"
    }
    Get-Content -LiteralPath $LifecycleDataPath -Raw
} else {
    (Invoke-WebRequest -Uri ([string]$TestMatrix.lifecycleSourceUrl) -UseBasicParsing -ErrorAction Stop).Content
}
$PacificTimeZone = try {
    [System.TimeZoneInfo]::FindSystemTimeZoneById('America/Los_Angeles')
} catch {
    [System.TimeZoneInfo]::FindSystemTimeZoneById('Pacific Standard Time')
}
$LiveLifecycleRows = @(
    foreach ($TableRow in [regex]::Matches($LifecycleContent, '(?is)<tr[^>]*>(?<content>.*?)</tr>')) {
        $VersionMatch = [regex]::Match($TableRow.Groups['content'].Value, '(?is)<td[^>]*>\s*PowerShell\s+(?<line>7\.\d+)(?:\s*\(LTS\))?\s*</td>')
        $DateMatches = [regex]::Matches($TableRow.Groups['content'].Value, '(?is)<local-time[^>]*\sdatetime="(?<date>[^"]+)"')
        if (-not $VersionMatch.Success -or $DateMatches.Count -ne 2) {
            continue
        }
        $StartUtc = [datetime]::SpecifyKind([datetime]::Parse($DateMatches[0].Groups['date'].Value, [System.Globalization.CultureInfo]::InvariantCulture), [System.DateTimeKind]::Utc)
        $EndUtc = [datetime]::SpecifyKind([datetime]::Parse($DateMatches[1].Groups['date'].Value, [System.Globalization.CultureInfo]::InvariantCulture), [System.DateTimeKind]::Utc)
        [PSCustomObject]@{
            ReleaseLine = $VersionMatch.Groups['line'].Value
            StartDate = [System.TimeZoneInfo]::ConvertTimeFromUtc($StartUtc, $PacificTimeZone).ToString('yyyy-MM-dd')
            EndDate = [System.TimeZoneInfo]::ConvertTimeFromUtc($EndUtc, $PacificTimeZone).ToString('yyyy-MM-dd')
        }
    }
)
if ($LiveLifecycleRows.Count -eq 0) {
    throw 'No PowerShell 7 release rows were parsed from the official Microsoft lifecycle data.'
}
$DuplicateLifecycleLines = @($LiveLifecycleRows | Group-Object ReleaseLine | Where-Object Count -NE 1)
if ($DuplicateLifecycleLines.Count -gt 0) {
    throw "Microsoft lifecycle data contains duplicate PowerShell lines: $($DuplicateLifecycleLines.Name -join ', ')."
}
$AsOfPacificDate = [System.TimeZoneInfo]::ConvertTimeFromUtc($AsOfUtc.ToUniversalTime(), $PacificTimeZone).Date
$SupportedLifecycleLines = @($LiveLifecycleRows | Where-Object {
        $StartDate = [datetime]::ParseExact(
            [string]$_.StartDate,
            'yyyy-MM-dd',
            [System.Globalization.CultureInfo]::InvariantCulture
        )
        $EndDate = [datetime]::ParseExact(
            [string]$_.EndDate,
            'yyyy-MM-dd',
            [System.Globalization.CultureInfo]::InvariantCulture
        )
        $StartDate -le $AsOfPacificDate -and $EndDate -ge $AsOfPacificDate
    } | ForEach-Object ReleaseLine)

$DeclaredLines = @($TestMatrix.profiles | ForEach-Object { '{0}.{1}' -f $_.powerShellMajor, $_.powerShellMinor })
$PatchUpdates = @(
    foreach ($MatrixProfile in @($TestMatrix.profiles)) {
        $ReleaseLine = '{0}.{1}' -f $MatrixProfile.powerShellMajor, $MatrixProfile.powerShellMinor
        $NewestRelease = $StableReleases | Where-Object ReleaseLine -EQ $ReleaseLine | Sort-Object Version -Descending | Select-Object -First 1
        if (-not $NewestRelease -or $NewestRelease.Version -le [version]$MatrixProfile.powerShellVersion) {
            continue
        }

        $ArchiveCandidates = @(
            foreach ($CurrentArchive in @($TestMatrix.archiveAssets | Where-Object powerShellVersion -EQ $MatrixProfile.powerShellVersion)) {
                $ExpectedFileName = ([string]$CurrentArchive.fileName).Replace([string]$MatrixProfile.powerShellVersion, $NewestRelease.Version.ToString())
                $ReleaseAsset = @($NewestRelease.Assets | Where-Object name -EQ $ExpectedFileName | Select-Object -First 1)[0]
                $Digest = if ($ReleaseAsset -and [string]$ReleaseAsset.digest -match '^sha256:(?<hash>[a-fA-F0-9]{64})$') {
                    $Matches['hash'].ToLowerInvariant()
                } else {
                    $null
                }
                [PSCustomObject]@{
                    Platform     = [string]$CurrentArchive.platform
                    Architecture = [string]$CurrentArchive.architecture
                    FileName     = $ExpectedFileName
                    DownloadUrl  = if ($ReleaseAsset) { [string]$ReleaseAsset.browser_download_url } else { $null }
                    Sha256       = $Digest
                    Complete     = $null -ne $ReleaseAsset -and -not [string]::IsNullOrWhiteSpace($Digest)
                }
            }
        )
        [PSCustomObject]@{
            ReleaseLine       = $ReleaseLine
            CurrentVersion    = [string]$MatrixProfile.powerShellVersion
            CandidateVersion  = $NewestRelease.Version.ToString()
            ReleaseUrl        = $NewestRelease.HtmlUrl
            Archives          = @($ArchiveCandidates)
            ChecksumsComplete = @($ArchiveCandidates | Where-Object { -not $_.Complete }).Count -eq 0
        }
    }
)

$MaximumDeclaredMinor = @($TestMatrix.profiles.powerShellMinor | Measure-Object -Maximum)[0].Maximum
$NewLines = @(
    $StableReleases |
        Where-Object { $_.Version.Minor -gt $MaximumDeclaredMinor -and $_.ReleaseLine -notin $DeclaredLines -and $_.ReleaseLine -in $SupportedLifecycleLines } |
        Group-Object ReleaseLine |
        ForEach-Object { $_.Group | Sort-Object Version -Descending | Select-Object -First 1 } |
        Sort-Object Version |
        ForEach-Object {
            [PSCustomObject]@{
                ReleaseLine      = $_.ReleaseLine
                LatestVersion    = $_.Version.ToString()
                PublishedAtUtc   = $_.PublishedAt.ToString('o')
                ReleaseUrl       = $_.HtmlUrl
                LifecycleEndDate = [string]@($LiveLifecycleRows | Where-Object ReleaseLine -EQ $_.ReleaseLine)[0].EndDate
                ProposedMapping  = [PSCustomObject]@{
                    DotNetMajor = $null
                    TargetFramework = $null
                    Status = 'pending checksum-verified runtime identity and maintainer support-contract review'
                }
                PackageSizeEstimate = 'not-run-pending-reviewed-mapping'
                BuildResults = 'not-run-pending-reviewed-mapping'
                InitialUpstreamConflictEvidence = 'not-run-pending-reviewed-mapping'
                RequiredDecision = 'Map PowerShell line to CLR/TFM, estimate artifact size, and collect initial profile-aware conflict evidence.'
            }
        }
)

$LifecycleRows = @(
    foreach ($MatrixProfile in @($TestMatrix.profiles)) {
        $ReleaseLine = '{0}.{1}' -f $MatrixProfile.powerShellMajor, $MatrixProfile.powerShellMinor
        $LiveLifecycle = @($LiveLifecycleRows | Where-Object ReleaseLine -EQ $ReleaseLine)
        if ($LiveLifecycle.Count -ne 1) {
            continue
        }
        $EndDate = [datetime]::ParseExact([string]$LiveLifecycle[0].EndDate, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        $DaysRemaining = [math]::Floor(($EndDate.Date.AddDays(1) - $AsOfPacificDate).TotalDays)
        [PSCustomObject]@{
            ReleaseLine   = $ReleaseLine
            LifecycleEnd  = [string]$LiveLifecycle[0].EndDate
            MatrixLifecycleEnd = [string]$MatrixProfile.lifecycleEndDate
            DaysRemaining = $DaysRemaining
            Status        = if ($DaysRemaining -le 0) { 'Expired' } elseif ($DaysRemaining -le [int]$TestMatrix.retirementWarningDays) { 'RetiringSoon' } else { 'Supported' }
        }
    }
)

$IncompletePatchUpdates = @($PatchUpdates | Where-Object { -not $_.ChecksumsComplete })
$LifecycleMissingLines = @($DeclaredLines | Where-Object { $_ -notin $LiveLifecycleRows.ReleaseLine })
$LifecycleDateChanges = @($LifecycleRows | Where-Object { $_.LifecycleEnd -ne $_.MatrixLifecycleEnd })
$UndeclaredSupportedLines = @($SupportedLifecycleLines | Where-Object { $_ -notin $DeclaredLines })
$SupportContractReviewRequired =
    $NewLines.Count -gt 0 -or
    $UndeclaredSupportedLines.Count -gt 0 -or
    $LifecycleDateChanges.Count -gt 0 -or
    $LifecycleMissingLines.Count -gt 0 -or
    @($LifecycleRows | Where-Object Status -IN @('RetiringSoon', 'Expired')).Count -gt 0
$PatchCanonicalLines = @(
    foreach ($PatchUpdate in @($PatchUpdates | Sort-Object ReleaseLine)) {
        'patch|{0}|{1}|{2}' -f $PatchUpdate.ReleaseLine, $PatchUpdate.CurrentVersion, $PatchUpdate.CandidateVersion
        foreach ($Archive in @($PatchUpdate.Archives | Sort-Object Platform, Architecture)) {
            'archive|{0}|{1}|{2}|{3}|{4}' -f $PatchUpdate.CandidateVersion, $Archive.Platform, $Archive.Architecture, $Archive.FileName, $Archive.Sha256
        }
    }
)
$SupportContractCanonicalLines = @(
    foreach ($NewLine in @($NewLines | Sort-Object ReleaseLine)) {
        'new-line|{0}|{1}|{2}' -f $NewLine.ReleaseLine, $NewLine.LatestVersion, $NewLine.LifecycleEndDate
    }
    foreach ($LifecycleChange in @($LifecycleDateChanges | Sort-Object ReleaseLine)) {
        'lifecycle-date|{0}|{1}|{2}' -f $LifecycleChange.ReleaseLine, $LifecycleChange.MatrixLifecycleEnd, $LifecycleChange.LifecycleEnd
    }
    foreach ($MissingLine in @($LifecycleMissingLines | Sort-Object)) {
        'lifecycle-missing|{0}' -f $MissingLine
    }
    foreach ($UndeclaredLine in @($UndeclaredSupportedLines | Sort-Object)) {
        'undeclared-supported|{0}' -f $UndeclaredLine
    }
    foreach ($LifecycleState in @($LifecycleRows | Where-Object Status -IN @('RetiringSoon', 'Expired') | Sort-Object ReleaseLine)) {
        'lifecycle-state|{0}|{1}|{2}' -f $LifecycleState.ReleaseLine, $LifecycleState.Status, $LifecycleState.LifecycleEnd
    }
)
$PatchProposalFingerprint = Get-DLLPickleStableFingerprint -CanonicalLine $PatchCanonicalLines
$SupportContractFingerprint = Get-DLLPickleStableFingerprint -CanonicalLine $SupportContractCanonicalLines
$Report = [PSCustomObject]@{
    SchemaVersion                 = 1
    GeneratedAtUtc                = [System.DateTimeOffset]::UtcNow.ToString('o')
    ReleaseSource                 = 'https://api.github.com/repos/PowerShell/PowerShell/releases'
    LifecycleSource               = [string]$TestMatrix.lifecycleSourceUrl
    PatchUpdates                  = @($PatchUpdates)
    NewLines                      = @($NewLines)
    Lifecycle                     = @($LifecycleRows)
    LifecycleDateChanges          = @($LifecycleDateChanges)
    LifecycleMissingLines         = @($LifecycleMissingLines)
    UndeclaredSupportedLines      = @($UndeclaredSupportedLines)
    PatchProposalFingerprint      = $PatchProposalFingerprint
    PatchProposalMarker           = '<!-- dllpickle-finding-fingerprint:{0} -->' -f $PatchProposalFingerprint
    SupportContractFingerprint    = $SupportContractFingerprint
    SupportContractMarker         = '<!-- dllpickle-finding-fingerprint:{0} -->' -f $SupportContractFingerprint
    MatrixOnlyUpdateAvailable     = $PatchUpdates.Count -gt 0 -and $IncompletePatchUpdates.Count -eq 0 -and -not $SupportContractReviewRequired
    SupportContractReviewRequired = $SupportContractReviewRequired
    ProposalPublishingStatus      = 'pending-workflow-publication'
}

$OutputDirectory = Split-Path -Path $OutputPath -Parent
if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
}
$Report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

if ($RequireCurrent.IsPresent) {
    $Violations = [System.Collections.Generic.List[string]]::new()
    if ($PatchUpdates.Count -gt 0) { $Violations.Add("newer servicing patches: $($PatchUpdates.CandidateVersion -join ', ')") }
    if ($NewLines.Count -gt 0) { $Violations.Add("new GA PowerShell lines: $($NewLines.ReleaseLine -join ', ')") }
    if ($UndeclaredSupportedLines.Count -gt 0) { $Violations.Add("undeclared Microsoft-supported lines: $($UndeclaredSupportedLines -join ', ')") }
    if ($LifecycleDateChanges.Count -gt 0) { $Violations.Add("lifecycle date changes: $($LifecycleDateChanges.ReleaseLine -join ', ')") }
    if ($LifecycleMissingLines.Count -gt 0) { $Violations.Add("declared lines missing from lifecycle data: $($LifecycleMissingLines -join ', ')") }
    $ExpiredLines = @($LifecycleRows | Where-Object Status -EQ 'Expired')
    if ($ExpiredLines.Count -gt 0) { $Violations.Add("expired lines: $($ExpiredLines.ReleaseLine -join ', ')") }
    if ($IncompletePatchUpdates.Count -gt 0) { $Violations.Add('candidate patch assets lack a complete official checksum set') }
    if ($Violations.Count -gt 0) {
        throw "PowerShell support matrix is not release-current: $($Violations -join '; ')."
    }
}

$Report
