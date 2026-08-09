<#
.SYNOPSIS
Builds a validated exact-patch matrix proposal from support-update discovery evidence.

.DESCRIPTION
Preparation mode writes a non-authoritative candidate matrix used only to provision
checksum-verified official archives. Finalization requires one runtime identity for
every declared operating-system lane of every patch update, proves the identities
agree on the bundled .NET runtime, and writes the reviewable matrix proposal.

This command only writes local files. It never commits, pushes, opens a pull request,
or modifies an issue.
#>

[CmdletBinding(DefaultParameterSetName = 'Finalize')]
[OutputType([pscustomobject])]
param (
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TestMatrixPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build/powershell-test-matrix.json'),

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$UpdateReportPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,

    [Parameter(Mandatory, ParameterSetName = 'Prepare')]
    [switch]$PrepareCandidate,

    [Parameter(Mandatory, ParameterSetName = 'Finalize')]
    [ValidateNotNullOrEmpty()]
    [string[]]$RuntimeIdentityPath,

    [Parameter(ParameterSetName = 'Finalize')]
    [datetime]$VerifiedAtUtc = [datetime]::UtcNow
)

$ErrorActionPreference = 'Stop'
$IsPreparation = $PrepareCandidate.IsPresent
foreach ($Path in @($TestMatrixPath, $UpdateReportPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required PowerShell matrix update input was not found: $Path"
    }
}

$Matrix = Get-Content -LiteralPath $TestMatrixPath -Raw | ConvertFrom-Json -ErrorAction Stop
$Report = Get-Content -LiteralPath $UpdateReportPath -Raw | ConvertFrom-Json -ErrorAction Stop
$PatchUpdates = @($Report.PatchUpdates)
if ($PatchUpdates.Count -eq 0) {
    throw 'The support-update report contains no servicing patch proposal.'
}
if (-not $Report.MatrixOnlyUpdateAvailable -or $Report.SupportContractReviewRequired) {
    throw 'A patch-only matrix proposal cannot include a new or retiring support line.'
}
if (@($PatchUpdates | Where-Object { -not $_.ChecksumsComplete }).Count -gt 0) {
    throw 'Every proposed official archive must have a complete SHA-256 digest.'
}

$IdentityRecords = @()
if (-not $IsPreparation) {
    $IdentityFiles = @(
        foreach ($IdentityPath in $RuntimeIdentityPath) {
            if (Test-Path -LiteralPath $IdentityPath -PathType Container) {
                Get-ChildItem -LiteralPath $IdentityPath -File -Filter '*.json' -Recurse
            } elseif (Test-Path -LiteralPath $IdentityPath -PathType Leaf) {
                Get-Item -LiteralPath $IdentityPath
            } else {
                throw "Runtime identity input was not found: $IdentityPath"
            }
        }
    )
    foreach ($IdentityFile in $IdentityFiles) {
        $Identity = Get-Content -LiteralPath $IdentityFile.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
        $RequiredIdentityProperties = @('PowerShellVersion', 'DotNetVersion', 'Platform', 'Architecture')
        $MissingIdentityProperties = @($RequiredIdentityProperties | Where-Object {
                $Identity.PSObject.Properties.Name -notcontains $_ -or
                [string]::IsNullOrWhiteSpace([string]$Identity.$_)
            })
        if ($MissingIdentityProperties.Count -gt 0) {
            Write-Warning "Runtime identity file '$($IdentityFile.FullName)' is missing required value(s): $($MissingIdentityProperties -join ', '); the file will not be used."
            continue
        }
        $IdentityRecords += $Identity
    }
}

$UpdatedLines = [System.Collections.Generic.List[object]]::new()
foreach ($PatchUpdate in $PatchUpdates) {
    $CurrentVersion = [string]$PatchUpdate.CurrentVersion
    $CandidateVersion = [string]$PatchUpdate.CandidateVersion
    $MatrixProfile = @($Matrix.profiles | Where-Object powerShellVersion -EQ $CurrentVersion)
    if ($MatrixProfile.Count -ne 1) {
        throw "The current matrix does not contain exactly one profile for PowerShell $CurrentVersion."
    }

    $CandidateArchives = @($PatchUpdate.Archives)
    if ($CandidateArchives.Count -ne @($Matrix.lanes).Count) {
        throw "PowerShell $CandidateVersion does not have one official archive for every declared lane."
    }
    foreach ($Lane in @($Matrix.lanes)) {
        $CandidateArchive = @($CandidateArchives | Where-Object {
                $_.Platform -eq $Lane.platform -and $_.Architecture -eq $Lane.architecture
            })
        if ($CandidateArchive.Count -ne 1 -or -not $CandidateArchive[0].Complete) {
            throw "PowerShell $CandidateVersion lacks one complete official archive for $($Lane.platform)/$($Lane.architecture)."
        }
        $ExistingArchive = @($Matrix.archiveAssets | Where-Object {
                $_.powerShellVersion -eq $CurrentVersion -and
                $_.platform -eq $Lane.platform -and
                $_.architecture -eq $Lane.architecture
            })
        if ($ExistingArchive.Count -ne 1) {
            throw "The current matrix lacks one archive row for PowerShell $CurrentVersion on $($Lane.platform)/$($Lane.architecture)."
        }
        $ExistingArchive[0].powerShellVersion = $CandidateVersion
        $ExistingArchive[0].fileName = [string]$CandidateArchive[0].FileName
        $ExistingArchive[0].sha256 = ([string]$CandidateArchive[0].Sha256).ToLowerInvariant()
        $ExistingArchive[0].downloadUrl = [string]$CandidateArchive[0].DownloadUrl
    }

    $DotNetRuntimeVersion = [string]$MatrixProfile[0].dotnetRuntimeVersion
    if (-not $IsPreparation) {
        $CandidateIdentities = @($IdentityRecords | Where-Object { [string]$_.PowerShellVersion -eq $CandidateVersion })
        if ($CandidateIdentities.Count -ne @($Matrix.lanes).Count) {
            throw "PowerShell $CandidateVersion requires $(@($Matrix.lanes).Count) runtime identities; found $($CandidateIdentities.Count)."
        }
        foreach ($Lane in @($Matrix.lanes)) {
            $LaneIdentity = @($CandidateIdentities | Where-Object {
                    [string]$_.Platform -eq [string]$Lane.platform -and
                    [string]$_.Architecture -eq [string]$Lane.architecture
                })
            if ($LaneIdentity.Count -ne 1) {
                throw "PowerShell $CandidateVersion requires one runtime identity for $($Lane.platform)/$($Lane.architecture)."
            }
            if ([version]$LaneIdentity[0].PowerShellVersion -ne [version]$CandidateVersion) {
                throw "A candidate runtime identity does not report the exact PowerShell patch $CandidateVersion."
            }
            if ([version]$LaneIdentity[0].DotNetVersion -lt [version]'1.0') {
                throw "PowerShell $CandidateVersion reported an invalid .NET runtime identity."
            }
        }
        $DotNetVersions = @($CandidateIdentities.DotNetVersion | ForEach-Object { ([version]$_).ToString() } | Sort-Object -Unique)
        if ($DotNetVersions.Count -ne 1) {
            throw "PowerShell $CandidateVersion archives disagree on the bundled .NET runtime: $($DotNetVersions -join ', ')."
        }
        $DotNetRuntimeVersion = [string]$DotNetVersions[0]
        if (([version]$DotNetRuntimeVersion).Major -ne [int]$MatrixProfile[0].dotnetMajor) {
            throw "PowerShell $CandidateVersion reports .NET $DotNetRuntimeVersion, outside declared CLR major $($MatrixProfile[0].dotnetMajor)."
        }
    }

    $MatrixProfile[0].powerShellVersion = $CandidateVersion
    $MatrixProfile[0].dotnetRuntimeVersion = $DotNetRuntimeVersion
    $UpdatedLines.Add([PSCustomObject]@{
            ReleaseLine = [string]$PatchUpdate.ReleaseLine
            CurrentVersion = $CurrentVersion
            CandidateVersion = $CandidateVersion
            DotNetRuntimeVersion = $DotNetRuntimeVersion
            RuntimeIdentityStatus = if ($IsPreparation) { 'pending-all-lanes' } else { 'verified-all-lanes' }
        })
}

if ($IsPreparation) {
    $Matrix | Add-Member -NotePropertyName candidateValidationPending -NotePropertyValue $true -Force
} else {
    $VerifiedTimestamp = $VerifiedAtUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
    $Matrix | Add-Member -NotePropertyName lastVerifiedUtc -NotePropertyValue $VerifiedTimestamp -Force
    if ($Matrix.PSObject.Properties.Name -contains 'candidateValidationPending') {
        $Matrix.PSObject.Properties.Remove('candidateValidationPending')
    }
}

$OutputDirectory = Split-Path -Path $OutputPath -Parent
if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
}
$Matrix | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

[PSCustomObject]@{
    Mode = if ($IsPreparation) { 'CandidatePreparation' } else { 'VerifiedProposal' }
    OutputPath = (Resolve-Path -LiteralPath $OutputPath).Path
    UpdatedLines = @($UpdatedLines)
}
