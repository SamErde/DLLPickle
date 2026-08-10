<#
.SYNOPSIS
Collects resumable, sanitized interactive authentication evidence for the initial multi-target release.

.DESCRIPTION
Runs fixed scenarios under each prepared exact Windows PowerShell executable.
Every scenario is a fresh process. Existing passing scenario checkpoints are
reused only when the source commit, bundle fingerprint, and complete prepared
module-inventory fingerprint match. The final candidate remains pending until a
maintainer reviews and explicitly accepts it.

No token, tenant, account, mailbox, subscription, resource, or raw service
result is written to evidence.
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param (
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$WorkRoot = (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'artifacts/manual-authenticated'),

    [Parameter()]
    [string[]]$ProfileKey,

    [Parameter()]
    [string[]]$ScenarioId,

    [Parameter()]
    [switch]$RerunCompleted,

    [Parameter()]
    [string]$AzureSubscriptionId = $env:DLLPICKLE_MANUAL_AZURE_SUBSCRIPTION_ID,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'DLLPickle.ManualAuthenticatedEvidence.ps1')
$ResolvedWorkRoot = [System.IO.Path]::GetFullPath($WorkRoot)
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $ResolvedWorkRoot 'manual-authenticated-evidence.candidate.json'
}
$PreparationSummaryPath = Join-Path $ResolvedWorkRoot 'preparation-summary.json'
$SessionPath = Join-Path $ResolvedWorkRoot 'capture-session.json'
$ScenarioRoot = Join-Path $ResolvedWorkRoot 'scenarios'
$MatrixPath = Join-Path $RepositoryRoot 'build/powershell-test-matrix.json'
$PolicyPath = Join-Path $RepositoryRoot 'build/dependency-policy.json'
$DLLPickleManifestPath = Join-Path $RepositoryRoot 'module/DLLPickle/DLLPickle.psd1'
$ChildHarnessPath = Join-Path $PSScriptRoot 'Invoke-DLLPickleManualAuthenticatedScenario.ps1'
$ValidatorPath = Join-Path $PSScriptRoot 'Test-DLLPickleManualAuthenticatedEvidence.ps1'

foreach ($RequiredPath in @($PreparationSummaryPath, $MatrixPath, $PolicyPath, $DLLPickleManifestPath, $ChildHarnessPath, $ValidatorPath)) {
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) {
        throw "Manual authenticated compatibility preparation is incomplete: $RequiredPath"
    }
}
$Preparation = Get-Content -LiteralPath $PreparationSummaryPath -Raw | ConvertFrom-Json -ErrorAction Stop
$Matrix = Get-Content -LiteralPath $MatrixPath -Raw | ConvertFrom-Json -ErrorAction Stop
$AllProfileKeys = @(
    $Matrix.profiles | ForEach-Object {
        'ps{0}.{1}-{2}-windows-x64' -f $_.powerShellMajor, $_.powerShellMinor, $_.targetFramework
    }
)
$PreparedProfileKeys = @($Preparation.Profiles.ProfileKey)
if ($PreparedProfileKeys.Count -ne $AllProfileKeys.Count -or
    @(Compare-Object -ReferenceObject @(Get-DLLPickleOrdinalSequence -InputObject $AllProfileKeys) -DifferenceObject @(Get-DLLPickleOrdinalSequence -InputObject $PreparedProfileKeys)).Count -gt 0) {
    throw 'Preparation summary does not contain the exact required Windows runtime profile set.'
}
$Bundle = & (Join-Path $PSScriptRoot 'Get-DLLPickleBundleSourceFingerprint.ps1') -RepositoryRoot $RepositoryRoot
$SourceCommitSha = (git -C $RepositoryRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $SourceCommitSha -notmatch '^[a-f0-9]{40}$') {
    throw 'Could not resolve the source commit for manual authenticated evidence.'
}
if ([string]$Preparation.BundleSourceFingerprint -ne [string]$Bundle.fingerprint) {
    throw 'Prepared modules/runtimes belong to a different bundle fingerprint. Rerun Initialize-DLLPickleManualAuthenticatedCompatibility.ps1.'
}
$CurrentInventoryFingerprints = [ordered]@{}
foreach ($PreparedProfile in @($Preparation.Profiles)) {
    if (-not (Test-Path -LiteralPath ([string]$PreparedProfile.InventoryPath) -PathType Leaf)) {
        throw "Prepared inventory was not found for '$($PreparedProfile.ProfileKey)': $($PreparedProfile.InventoryPath)"
    }
    $PreparedInventory = Get-Content -LiteralPath ([string]$PreparedProfile.InventoryPath) -Raw | ConvertFrom-Json -ErrorAction Stop
    $CurrentInventoryFingerprint = Get-DLLPicklePreparedInventoryFingerprint -Inventory $PreparedInventory
    if ([string]$PreparedProfile.InventoryFingerprint -ne $CurrentInventoryFingerprint) {
        throw "Prepared module inventory changed for '$($PreparedProfile.ProfileKey)'. Rerun Initialize-DLLPickleManualAuthenticatedCompatibility.ps1."
    }
    $CurrentInventoryFingerprints[[string]$PreparedProfile.ProfileKey] = $CurrentInventoryFingerprint
}

if (Test-Path -LiteralPath $SessionPath -PathType Leaf) {
    $Session = Get-Content -LiteralPath $SessionPath -Raw | ConvertFrom-Json -ErrorAction Stop
    if ([string]$Session.sourceCommitSha -ne $SourceCommitSha -or [string]$Session.bundleSourceFingerprint -ne [string]$Bundle.fingerprint) {
        throw "The existing capture session belongs to another commit or bundle. Preserve it and choose a new -WorkRoot."
    }
    foreach ($PreparedProfile in @($Preparation.Profiles)) {
        $SessionFingerprintProperty = if ($null -ne $Session.inventoryFingerprints) {
            $Session.inventoryFingerprints.PSObject.Properties[[string]$PreparedProfile.ProfileKey]
        } else {
            $null
        }
        $SessionFingerprint = if ($null -ne $SessionFingerprintProperty) { $SessionFingerprintProperty.Value } else { $null }
        if ([string]$SessionFingerprint -ne [string]$CurrentInventoryFingerprints[[string]$PreparedProfile.ProfileKey]) {
            throw "The existing capture session belongs to another prepared module inventory for '$($PreparedProfile.ProfileKey)'. Preserve it and choose a new -WorkRoot."
        }
    }
} else {
    $Session = [pscustomobject][ordered]@{
        schemaVersion = 1
        sourceCommitSha = $SourceCommitSha
        bundleSourceFingerprint = [string]$Bundle.fingerprint
        inventoryFingerprints = $CurrentInventoryFingerprints
        captureStartedAtUtc = [System.DateTimeOffset]::UtcNow.ToString('o')
        credentialMode = 'delegated-interactive'
        credentialMaterialCaptured = $false
        writesPerformed = $false
    }
    $null = New-Item -Path $ResolvedWorkRoot -ItemType Directory -Force
    $Session | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $SessionPath -Encoding utf8NoBOM
}
$CaptureStartedAtUtc = ConvertTo-DLLPickleUtcDateTimeOffset -Value $Session.captureStartedAtUtc
$ExpiresAtUtc = $CaptureStartedAtUtc.AddDays(14)
if ([System.DateTimeOffset]::UtcNow -ge $ExpiresAtUtc) {
    throw "Manual authenticated evidence capture expired at $($ExpiresAtUtc.ToString('o')). Preserve it and start a new work root."
}

$AllScenarioIds = @(
    'graph-module-only', 'graph-dllpickle-first', 'graph-module-first',
    'exo-module-only', 'exo-dllpickle-first', 'exo-module-first',
    'az-module-only', 'az-dllpickle-first', 'az-module-first',
    'teams-module-only', 'teams-dllpickle-first', 'teams-module-first',
    'cross-import-order-1', 'cross-import-order-2'
)
$SelectedProfileKeys = if ($ProfileKey.Count -gt 0) { @($ProfileKey) } else { $AllProfileKeys }
$SelectedScenarioIds = if ($ScenarioId.Count -gt 0) { @($ScenarioId) } else { $AllScenarioIds }
$UnknownProfiles = @($SelectedProfileKeys | Where-Object { $_ -notin $AllProfileKeys })
$UnknownScenarios = @($SelectedScenarioIds | Where-Object { $_ -notin $AllScenarioIds })
if ($UnknownProfiles.Count -gt 0 -or $UnknownScenarios.Count -gt 0) {
    throw "Unsupported profile/scenario selection. Profiles: '$($UnknownProfiles -join ', ')'; scenarios: '$($UnknownScenarios -join ', ')'."
}

foreach ($CurrentProfileKey in $SelectedProfileKeys) {
    $PreparedProfiles = @($Preparation.Profiles | Where-Object ProfileKey -eq $CurrentProfileKey)
    if ($PreparedProfiles.Count -ne 1) { throw "Preparation summary has no unique '$CurrentProfileKey' profile." }
    $PreparedProfile = $PreparedProfiles[0]
    foreach ($CurrentScenarioId in $SelectedScenarioIds) {
        $ScenarioOutputPath = Join-Path $ScenarioRoot "$CurrentProfileKey/$CurrentScenarioId.json"
        if (-not $RerunCompleted.IsPresent -and (Test-Path -LiteralPath $ScenarioOutputPath -PathType Leaf)) {
            $ExistingScenario = Get-Content -LiteralPath $ScenarioOutputPath -Raw | ConvertFrom-Json -ErrorAction Stop
            if ([string]$ExistingScenario.status -eq 'passed' -and
                [string]$ExistingScenario.scenarioId -eq $CurrentScenarioId -and
                [string]$ExistingScenario.profileKey -eq $CurrentProfileKey -and
                [string]$ExistingScenario.powerShellVersion -eq [string]$PreparedProfile.PowerShellVersion -and
                [string]$ExistingScenario.targetFramework -eq [string]$PreparedProfile.TargetFramework -and
                [string]$ExistingScenario.platform -eq 'windows' -and
                [string]$ExistingScenario.architecture -eq 'x64' -and
                [string]$ExistingScenario.inventoryFingerprint -eq [string]$PreparedProfile.InventoryFingerprint) {
                Write-Information -MessageData "Reusing passing checkpoint: $CurrentProfileKey / $CurrentScenarioId" -InformationAction Continue
                continue
            }
        }

        Write-Information -MessageData '' -InformationAction Continue
        Write-Information -MessageData "Interactive scenario: $CurrentProfileKey / $CurrentScenarioId" -InformationAction Continue
        Write-Information -MessageData 'Complete only the provider sign-in prompts shown by the fixed child harness. No raw service output is retained.' -InformationAction Continue
        $ChildArguments = @(
            '-NoLogo', '-NoProfile', '-File', $ChildHarnessPath,
            '-ScenarioId', $CurrentScenarioId,
            '-InventoryPath', [string]$PreparedProfile.InventoryPath,
            '-PolicyPath', $PolicyPath,
            '-DLLPickleManifestPath', $DLLPickleManifestPath,
            '-OutputPath', $ScenarioOutputPath,
            '-ExpectedProfileKey', $CurrentProfileKey,
            '-ExpectedPowerShellVersion', [string]$PreparedProfile.PowerShellVersion,
            '-ExpectedTargetFramework', [string]$PreparedProfile.TargetFramework,
            '-ExpectedInventoryFingerprint', [string]$PreparedProfile.InventoryFingerprint
        )
        if (-not [string]::IsNullOrWhiteSpace($AzureSubscriptionId)) {
            $ChildArguments += @('-AzureSubscriptionId', $AzureSubscriptionId)
        }
        & ([string]$PreparedProfile.ExecutablePath) @ChildArguments
        if ($LASTEXITCODE -ne 0) {
            throw "Interactive scenario '$CurrentProfileKey/$CurrentScenarioId' failed. Correct the sign-in or authorization problem, then rerun; passing checkpoints will be reused."
        }
    }
}

$MissingScenarioPaths = @(
    foreach ($ExpectedProfileKey in $AllProfileKeys) {
        foreach ($ExpectedScenarioId in $AllScenarioIds) {
            $ExpectedPath = Join-Path $ScenarioRoot "$ExpectedProfileKey/$ExpectedScenarioId.json"
            if (-not (Test-Path -LiteralPath $ExpectedPath -PathType Leaf)) { $ExpectedPath }
        }
    }
)
if ($MissingScenarioPaths.Count -gt 0) {
    return [pscustomobject]@{
        Complete = $false
        MissingScenarioCount = $MissingScenarioPaths.Count
        CandidateEvidencePath = $null
        WritesPerformed = $false
    }
}

$Profiles = @(
    foreach ($RuntimeProfile in @($Matrix.profiles)) {
        $PowerShellLine = '{0}.{1}' -f $RuntimeProfile.powerShellMajor, $RuntimeProfile.powerShellMinor
        $CurrentProfileKey = 'ps{0}-{1}-windows-x64' -f $PowerShellLine, $RuntimeProfile.targetFramework
        $PreparedProfile = @($Preparation.Profiles | Where-Object ProfileKey -eq $CurrentProfileKey)[0]
        $Inventory = Get-Content -LiteralPath ([string]$PreparedProfile.InventoryPath) -Raw | ConvertFrom-Json -ErrorAction Stop
        $ScenarioRows = @(
            foreach ($ExpectedScenarioId in $AllScenarioIds) {
                $ScenarioPath = Join-Path $ScenarioRoot "$CurrentProfileKey/$ExpectedScenarioId.json"
                Get-Content -LiteralPath $ScenarioPath -Raw | ConvertFrom-Json -ErrorAction Stop
            }
        )
        [ordered]@{
            profileKey = $CurrentProfileKey
            powerShellVersion = [string]$RuntimeProfile.powerShellVersion
            powerShellLine = $PowerShellLine
            dotNetVersion = [string]$RuntimeProfile.dotnetRuntimeVersion
            dotNetMajor = [int]$RuntimeProfile.dotnetMajor
            targetFramework = [string]$RuntimeProfile.targetFramework
            platform = 'windows'
            architecture = 'x64'
            runtimeExecutable = 'runtime:{0}' -f [System.IO.Path]::GetFileName([string]$PreparedProfile.ExecutablePath)
            psHome = 'runtime:.'
            writesPerformed = $false
            inventoryFingerprint = [string]$PreparedProfile.InventoryFingerprint
            moduleVersions = @(
                foreach ($Module in @(Get-DLLPickleOrdinalSequence -InputObject @($Inventory.Modules) -KeySelector { param($Item) [string]$Item.Name } -Unique)) {
                    [ordered]@{
                        name = [string]$Module.Name
                        version = [string]$Module.Version
                        manifest = ConvertTo-DLLPickleUpstreamManifestIdentifier -ManifestPath ([string]$Module.ModuleManifestPath) -ModuleCachePath ([string]$Inventory.ModuleCachePath)
                    }
                }
            )
            scenarios = $ScenarioRows
        }
    }
)
$CaptureCompletedAtUtc = [System.DateTimeOffset]::UtcNow
if ($CaptureCompletedAtUtc -ge $ExpiresAtUtc) {
    throw "Manual authenticated evidence capture expired at $($ExpiresAtUtc.ToString('o')). Preserve it and start a new work root."
}
$Content = [ordered]@{
    bridge = [ordered]@{
        id = 'initial-powershell-7.4-7.6-multitargeting-major'
        allowedReleaseVersion = '3.0.0'
        expiresAtUtc = $ExpiresAtUtc.ToString('o')
    }
    bundleSourceFingerprint = [string]$Bundle.fingerprint
    credentialMode = 'delegated-interactive'
    credentialMaterialCaptured = $false
    authorizationBoundaryValidated = $false
    platformScope = 'windows-x64-only'
    writesPerformed = $false
    profiles = $Profiles
}
$Evidence = [ordered]@{
    schemaVersion = 1
    evidenceType = 'manual-interactive-transition'
    contentFingerprint = $null
    provenance = [ordered]@{
        sourceCommitSha = $SourceCommitSha
        captureStartedAtUtc = [string]$Session.captureStartedAtUtc
        captureCompletedAtUtc = $CaptureCompletedAtUtc.ToString('o')
    }
    acceptance = [ordered]@{
        status = 'pending'
        acceptedAtUtc = $null
        acceptedBy = $null
        confidence = $null
    }
    content = $Content
}
$Evidence.contentFingerprint = Get-DLLPickleNormalizedEvidenceFingerprint -Evidence ([pscustomobject]$Evidence)
$OutputDirectory = Split-Path -Path $OutputPath -Parent
if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
}
$Evidence | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
$Validation = & $ValidatorPath -EvidencePath $OutputPath -RepositoryRoot $RepositoryRoot -TestMatrixPath $MatrixPath -DependencyPolicyPath $PolicyPath -Mode Capture
[pscustomobject]@{
    Complete = $true
    CandidateEvidencePath = [System.IO.Path]::GetFullPath($OutputPath)
    EvidenceFingerprint = [string]$Validation.EvidenceFingerprint
    BundleSourceFingerprint = [string]$Validation.BundleSourceFingerprint
    AllowedReleaseVersion = [string]$Validation.AllowedReleaseVersion
    ExpiresAtUtc = [string]$Validation.ExpiresAtUtc
    AcceptanceStatus = 'pending'
    WritesPerformed = $false
}
