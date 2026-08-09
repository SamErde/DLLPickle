<#
.SYNOPSIS
    Generates deterministic unpacked and compressed module-size evidence.

.DESCRIPTION
    Measures each shipped target-framework payload and the complete module. The
    committed baseline supplies material-growth thresholds. Compressed sizes use a
    sorted in-memory ZIP with fixed timestamps so reruns are stable.

.PARAMETER Strict
    Throw when a baseline entry is missing or a material unpacked-size increase occurs.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ModulePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'module\DLLPickle'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SupportPolicyPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\DLLPickle\SupportedRuntimeProfiles.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$BaselinePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\artifact-size-baseline.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\package\artifact-size.json'),

    [Parameter()]
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression

function Get-DLLPickleDeterministicCompressedSize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    $MemoryStream = [System.IO.MemoryStream]::new()
    try {
        $Archive = [System.IO.Compression.ZipArchive]::new($MemoryStream, [System.IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            $Files = @(Get-ChildItem -LiteralPath $RootPath -File -Recurse | Sort-Object FullName)
            foreach ($File in $Files) {
                $EntryName = [System.IO.Path]::GetRelativePath($RootPath, $File.FullName).Replace('\', '/')
                $Entry = $Archive.CreateEntry($EntryName, [System.IO.Compression.CompressionLevel]::Optimal)
                $Entry.LastWriteTime = [System.DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [System.TimeSpan]::Zero)
                $InputStream = $File.OpenRead()
                $OutputStream = $Entry.Open()
                try {
                    $InputStream.CopyTo($OutputStream)
                } finally {
                    $OutputStream.Dispose()
                    $InputStream.Dispose()
                }
            }
        } finally {
            $Archive.Dispose()
        }
        return $MemoryStream.Length
    } finally {
        $MemoryStream.Dispose()
    }
}

function Get-DLLPickleSizeMeasurement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [object]$Baseline,

        [Parameter(Mandatory)]
        [double]$MaximumIncreasePercent,

        [Parameter(Mandatory)]
        [long]$MaximumIncreaseBytes
    )

    $Files = @(Get-ChildItem -LiteralPath $Path -File -Recurse)
    $UnpackedBytes = [long](($Files | Measure-Object Length -Sum).Sum)
    $CompressedBytes = [long](Get-DLLPickleDeterministicCompressedSize -RootPath $Path)
    $HasBaseline = $null -ne $Baseline
    $BaselineUnpackedBytes = if ($HasBaseline) { [long]$Baseline.unpackedBytes } else { $null }
    $BaselineCompressedBytes = if ($HasBaseline) { [long]$Baseline.compressedBytes } else { $null }
    $UnpackedDeltaBytes = if ($HasBaseline) { $UnpackedBytes - $BaselineUnpackedBytes } else { $null }
    $CompressedDeltaBytes = if ($HasBaseline) { $CompressedBytes - $BaselineCompressedBytes } else { $null }
    $PercentThresholdBytes = if ($HasBaseline) { [long][Math]::Ceiling($BaselineUnpackedBytes * ($MaximumIncreasePercent / 100)) } else { $null }
    $AllowedIncreaseBytes = if ($HasBaseline) { [Math]::Max($MaximumIncreaseBytes, $PercentThresholdBytes) } else { $null }
    $ReviewRequired = -not $HasBaseline -or $UnpackedDeltaBytes -gt $AllowedIncreaseBytes

    [PSCustomObject]@{
        Name                         = $Name
        FileCount                    = $Files.Count
        UnpackedBytes                = $UnpackedBytes
        CompressedBytes              = $CompressedBytes
        BaselinePresent              = $HasBaseline
        BaselineUnpackedBytes        = $BaselineUnpackedBytes
        BaselineCompressedBytes      = $BaselineCompressedBytes
        UnpackedDeltaBytes           = $UnpackedDeltaBytes
        CompressedDeltaBytes         = $CompressedDeltaBytes
        AllowedUnpackedIncreaseBytes = $AllowedIncreaseBytes
        ReviewRequired               = $ReviewRequired
    }
}

foreach ($RequiredPath in @($ModulePath, $SupportPolicyPath, $BaselinePath)) {
    if (-not (Test-Path -LiteralPath $RequiredPath)) {
        throw "Required size-report path was not found: $RequiredPath"
    }
}

$ResolvedModulePath = (Resolve-Path -LiteralPath $ModulePath).Path
$SupportPolicy = Get-Content -LiteralPath $SupportPolicyPath -Raw | ConvertFrom-Json -ErrorAction Stop
$Baseline = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json -ErrorAction Stop
$BaselineApprovalStatus = [string]$Baseline.approvalStatus
$ApprovedAtUtc = [System.DateTimeOffset]::MinValue
$HasValidApprovalTimestamp = [System.DateTimeOffset]::TryParse(
    [string]$Baseline.approvedAtUtc,
    [System.Globalization.CultureInfo]::InvariantCulture,
    [System.Globalization.DateTimeStyles]::AssumeUniversal,
    [ref]$ApprovedAtUtc
)
$BaselineApproved = $BaselineApprovalStatus -ceq 'accepted' -and $HasValidApprovalTimestamp
$MaximumIncreasePercent = [double]$Baseline.thresholds.maximumIncreasePercent
$MaximumIncreaseBytes = [long]$Baseline.thresholds.maximumIncreaseBytes
$ExpectedTargetFrameworks = @($SupportPolicy.profiles.targetFramework | ForEach-Object { [string]$_ } | Sort-Object -Unique)

$Measurements = @(
    foreach ($TargetFramework in $ExpectedTargetFrameworks) {
        $TfmPath = Join-Path (Join-Path $ResolvedModulePath 'bin') $TargetFramework
        if (-not (Test-Path -LiteralPath $TfmPath -PathType Container)) {
            [PSCustomObject]@{
                Name            = $TargetFramework
                BaselinePresent = $false
                ReviewRequired  = $true
                Error           = "Target-framework directory was not found: $TfmPath"
            }
            continue
        }
        $BaselineEntry = @($Baseline.profiles | Where-Object name -EQ $TargetFramework | Select-Object -First 1)
        Get-DLLPickleSizeMeasurement -Name $TargetFramework -Path $TfmPath -Baseline $BaselineEntry[0] -MaximumIncreasePercent $MaximumIncreasePercent -MaximumIncreaseBytes $MaximumIncreaseBytes
    }
)
$FullBaseline = @($Baseline.fullArtifact | Select-Object -First 1)
$FullMeasurement = Get-DLLPickleSizeMeasurement -Name 'fullArtifact' -Path $ResolvedModulePath -Baseline $FullBaseline[0] -MaximumIncreasePercent $MaximumIncreasePercent -MaximumIncreaseBytes $MaximumIncreaseBytes
$SizeGrowthReviewRequired = @($Measurements | Where-Object ReviewRequired).Count -gt 0 -or $FullMeasurement.ReviewRequired
$ReviewRequired = -not $BaselineApproved -or $SizeGrowthReviewRequired

$Report = [PSCustomObject]@{
    SchemaVersion             = 1
    GeneratedAtUtc            = [System.DateTimeOffset]::UtcNow.ToString('o')
    ModulePath                = $ResolvedModulePath
    BaselineApprovalStatus    = $BaselineApprovalStatus
    BaselineApproved          = $BaselineApproved
    BaselineApprovedAtUtc     = if ($BaselineApproved) { $ApprovedAtUtc.ToUniversalTime().ToString('o') } else { $null }
    Thresholds                = $Baseline.thresholds
    Profiles                  = @($Measurements)
    FullArtifact              = $FullMeasurement
    SizeGrowthReviewRequired  = $SizeGrowthReviewRequired
    ReviewRequired            = $ReviewRequired
}

$OutputDirectory = Split-Path -Path $OutputPath -Parent
if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
}
$Report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

if ($Strict.IsPresent -and -not $BaselineApproved) {
    throw "DLLPickle artifact size baseline is not accepted by a maintainer (status '$BaselineApprovalStatus' or approval timestamp missing). Review build/artifact-size-baseline.json."
}
if ($Strict.IsPresent -and $SizeGrowthReviewRequired) {
    throw 'DLLPickle artifact size exceeds the approved material-growth policy or lacks a baseline. Review artifact-size.json.'
}

$Report
