<#
.SYNOPSIS
Validates the time-bounded manual authenticated-evidence transition record.

.DESCRIPTION
This validator is deliberately narrow. It accepts only the initial 3.0.0
PowerShell 7.4-7.6 multi-target release, exactly three Windows x64 profiles,
hard-coded read-only probes, and evidence bound to the current published-bundle
source fingerprint. It is not a generic authentication bypass and does not
replace the future protected credentialed workflow.

.PARAMETER EvidencePath
Path to the sanitized manual evidence JSON.

.PARAMETER RepositoryRoot
Repository root whose published inputs must match the evidence fingerprint.

.PARAMETER TestMatrixPath
Exact supported PowerShell runtime matrix.

.PARAMETER DependencyPolicyPath
Profile and monitored-module policy.

.PARAMETER Mode
Capture validates a pending candidate. Release additionally requires maintainer
acceptance and a currently valid expiry window.

.PARAMETER NowUtc
Clock injection for deterministic expiry tests.

.OUTPUTS
System.Management.Automation.PSCustomObject
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$EvidencePath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RepositoryRoot = (Split-Path -Path $PSScriptRoot -Parent),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TestMatrixPath = (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'build/powershell-test-matrix.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DependencyPolicyPath = (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'build/dependency-policy.json'),

    [Parameter()]
    [ValidateSet('Capture', 'Release')]
    [string]$Mode = 'Release',

    [Parameter()]
    [System.DateTimeOffset]$NowUtc = [System.DateTimeOffset]::UtcNow
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DLLPickle.ProfileEvidence.ps1')

function Assert-ExactStringSet {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Actual,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Expected,
        [Parameter(Mandatory)][string]$Label
    )

    $ExpectedSorted = @(Get-DLLPickleOrdinalSequence -InputObject @($Expected))
    $ActualSorted = @(Get-DLLPickleOrdinalSequence -InputObject @($Actual))
    $Difference = @(Compare-Object -ReferenceObject $ExpectedSorted -DifferenceObject $ActualSorted)
    if ($Difference.Count -gt 0 -or $Actual.Count -ne $Expected.Count) {
        throw "$Label does not match the required set. Expected '$($Expected -join ', ')'; actual '$($Actual -join ', ')'."
    }
}

function Assert-ExactPropertySet {
    param(
        [Parameter(Mandatory)][object]$InputObject,
        [Parameter(Mandatory)][string[]]$Expected,
        [Parameter(Mandatory)][string]$Label
    )

    Assert-ExactStringSet -Actual @($InputObject.PSObject.Properties.Name) -Expected $Expected -Label "$Label properties"
}

foreach ($RequiredPath in @($EvidencePath, $TestMatrixPath, $DependencyPolicyPath)) {
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) {
        throw "Required authenticated-evidence input was not found: $RequiredPath"
    }
}
$Evidence = Get-Content -LiteralPath $EvidencePath -Raw | ConvertFrom-Json -ErrorAction Stop
$TestMatrix = Get-Content -LiteralPath $TestMatrixPath -Raw | ConvertFrom-Json -ErrorAction Stop
$Policy = Get-Content -LiteralPath $DependencyPolicyPath -Raw | ConvertFrom-Json -ErrorAction Stop

Assert-ExactPropertySet -InputObject $Evidence -Expected @('schemaVersion', 'evidenceType', 'contentFingerprint', 'provenance', 'acceptance', 'content') -Label 'Evidence envelope'
Assert-ExactPropertySet -InputObject $Evidence.provenance -Expected @('sourceCommitSha', 'captureStartedAtUtc', 'captureCompletedAtUtc') -Label 'Evidence provenance'
Assert-ExactPropertySet -InputObject $Evidence.acceptance -Expected @('status', 'acceptedAtUtc', 'acceptedBy', 'confidence') -Label 'Evidence acceptance'
Assert-ExactPropertySet -InputObject $Evidence.content -Expected @('bridge', 'bundleSourceFingerprint', 'credentialMode', 'credentialMaterialCaptured', 'authorizationBoundaryValidated', 'platformScope', 'writesPerformed', 'profiles') -Label 'Evidence content'
Assert-ExactPropertySet -InputObject $Evidence.content.bridge -Expected @('id', 'allowedReleaseVersion', 'expiresAtUtc') -Label 'Evidence bridge'

if ([int]$Evidence.schemaVersion -ne 1 -or
    [string]$Evidence.evidenceType -ne 'manual-interactive-transition' -or
    -not $Evidence.content) {
    throw 'Manual authenticated evidence has an unsupported schema, type, or missing content.'
}
$RecomputedContentFingerprint = Get-DLLPickleNormalizedEvidenceFingerprint -Evidence $Evidence
if ([string]$Evidence.contentFingerprint -ne $RecomputedContentFingerprint) {
    throw "Manual authenticated evidence does not recompute to '$($Evidence.contentFingerprint)'."
}

$Bridge = $Evidence.content.bridge
if ([string]$Bridge.id -ne 'initial-powershell-7.4-7.6-multitargeting-major' -or
    [string]$Bridge.allowedReleaseVersion -ne '3.0.0') {
    throw 'Manual authenticated evidence is not scoped exclusively to the initial 3.0.0 multi-target release.'
}
$CaptureStartedAtUtc = ConvertTo-DLLPickleUtcDateTimeOffset -Value $Evidence.provenance.captureStartedAtUtc
$CapturedAtUtc = ConvertTo-DLLPickleUtcDateTimeOffset -Value $Evidence.provenance.captureCompletedAtUtc
$ExpiresAtUtc = ConvertTo-DLLPickleUtcDateTimeOffset -Value $Bridge.expiresAtUtc
if ([string]$Evidence.provenance.sourceCommitSha -notmatch '^[a-f0-9]{40}$' -or
    $CaptureStartedAtUtc -gt $CapturedAtUtc -or
    $CapturedAtUtc -gt $NowUtc.ToUniversalTime()) {
    throw 'Manual authenticated-evidence provenance has an invalid commit or capture window.'
}
if ($ExpiresAtUtc -ne $CaptureStartedAtUtc.AddDays(14) -or $CapturedAtUtc -ge $ExpiresAtUtc) {
    throw 'The manual authenticated-evidence bridge must expire exactly 14 days after capture starts, after capture completes.'
}
if ($NowUtc.ToUniversalTime() -ge $ExpiresAtUtc) {
    throw "Manual authenticated evidence expired at $($ExpiresAtUtc.ToString('o'))."
}
if ($Mode -eq 'Release') {
    if ([string]$Evidence.acceptance.status -ne 'accepted' -or
        [string]$Evidence.acceptance.acceptedBy -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$' -or
        [string]$Evidence.acceptance.confidence -notin @('low', 'medium', 'high')) {
        throw 'Manual authenticated evidence has not been explicitly accepted by a maintainer with a confidence level.'
    }
    $AcceptedAtUtc = ConvertTo-DLLPickleUtcDateTimeOffset -Value $Evidence.acceptance.acceptedAtUtc
    if ($AcceptedAtUtc -lt $CapturedAtUtc -or
        $AcceptedAtUtc -ge $ExpiresAtUtc -or
        $AcceptedAtUtc -gt $NowUtc.ToUniversalTime()) {
        throw "Manual authenticated evidence acceptance '$($AcceptedAtUtc.ToString('o'))' is outside its capture '$($CapturedAtUtc.ToString('o'))' to expiry '$($ExpiresAtUtc.ToString('o'))' window."
    }
}

if ([string]$Evidence.content.credentialMode -ne 'delegated-interactive' -or
    $Evidence.content.credentialMaterialCaptured -ne $false -or
    $Evidence.content.authorizationBoundaryValidated -ne $false -or
    [string]$Evidence.content.platformScope -ne 'windows-x64-only' -or
    $Evidence.content.writesPerformed -ne $false) {
    throw 'Manual transition evidence must remain delegated-interactive, credential-free, Windows-only, zero-write, and explicitly not least-privilege proof.'
}

$BundleFingerprintTool = Join-Path $PSScriptRoot 'Get-DLLPickleBundleSourceFingerprint.ps1'
$CurrentBundle = & $BundleFingerprintTool -RepositoryRoot $RepositoryRoot
if ([string]$Evidence.content.bundleSourceFingerprint -ne [string]$CurrentBundle.fingerprint) {
    throw "Manual authenticated evidence is bound to bundle '$($Evidence.content.bundleSourceFingerprint)', but the current bundle is '$($CurrentBundle.fingerprint)'."
}

$ExpectedProfiles = @(
    foreach ($RuntimeProfile in @($TestMatrix.profiles)) {
        [pscustomobject]@{
            ProfileKey = 'ps{0}.{1}-{2}-windows-x64' -f $RuntimeProfile.powerShellMajor, $RuntimeProfile.powerShellMinor, $RuntimeProfile.targetFramework
            PowerShellVersion = [string]$RuntimeProfile.powerShellVersion
            PowerShellLine = '{0}.{1}' -f $RuntimeProfile.powerShellMajor, $RuntimeProfile.powerShellMinor
            DotNetVersion = [string]$RuntimeProfile.dotnetRuntimeVersion
            DotNetMajor = [int]$RuntimeProfile.dotnetMajor
            TargetFramework = [string]$RuntimeProfile.targetFramework
        }
    }
)
Assert-ExactStringSet -Actual @($Evidence.content.profiles.profileKey) -Expected @($ExpectedProfiles.ProfileKey) -Label 'Authenticated profile coverage'

$ExpectedModuleNames = @(Get-DLLPickleOrdinalSequence -InputObject @($Policy.monitoredModules.name))
$ExpectedScenarioIds = @(
    'graph-module-only', 'graph-dllpickle-first', 'graph-module-first',
    'exo-module-only', 'exo-dllpickle-first', 'exo-module-first',
    'az-module-only', 'az-dllpickle-first', 'az-module-first',
    'teams-module-only', 'teams-dllpickle-first', 'teams-module-first',
    'cross-import-order-1', 'cross-import-order-2'
)
$ProviderProbes = [ordered]@{
    graph = @('graph-context', 'graph-me-read')
    exo = @('exo-mailbox-read')
    az = @('az-context', 'az-resource-read', 'az-storage-account-read')
    teams = @('teams-tenant-read')
    cross = @('graph-context', 'graph-me-read', 'exo-mailbox-read', 'az-context', 'teams-tenant-read')
}
$ProviderAudiences = [ordered]@{
    graph = @('https://graph.microsoft.com')
    exo = @('https://outlook.office365.com')
    az = @('https://management.azure.com')
    teams = @('https://api.spaces.skype.com')
    cross = @('https://api.spaces.skype.com', 'https://graph.microsoft.com', 'https://management.azure.com', 'https://outlook.office365.com')
}
$ProviderModuleOrders = [ordered]@{
    graph = @('Microsoft.Graph.Authentication')
    exo = @('ExchangeOnlineManagement')
    az = @('Az.Accounts', 'Az.Resources', 'Az.Storage')
    teams = @('MicrosoftTeams')
}

foreach ($ExpectedProfile in $ExpectedProfiles) {
    $ProfileRows = @($Evidence.content.profiles | Where-Object profileKey -eq $ExpectedProfile.ProfileKey)
    if ($ProfileRows.Count -ne 1) {
        throw "Expected exactly one authenticated profile '$($ExpectedProfile.ProfileKey)'."
    }
    $EvidenceProfile = $ProfileRows[0]
    Assert-ExactPropertySet -InputObject $EvidenceProfile -Expected @('profileKey', 'powerShellVersion', 'powerShellLine', 'dotNetVersion', 'dotNetMajor', 'targetFramework', 'platform', 'architecture', 'runtimeExecutable', 'psHome', 'writesPerformed', 'inventoryFingerprint', 'moduleVersions', 'scenarios') -Label "Authenticated profile '$($ExpectedProfile.ProfileKey)'"
    if ([string]$EvidenceProfile.powerShellVersion -ne $ExpectedProfile.PowerShellVersion -or
        [string]$EvidenceProfile.powerShellLine -ne $ExpectedProfile.PowerShellLine -or
        [string]$EvidenceProfile.dotNetVersion -ne $ExpectedProfile.DotNetVersion -or
        [int]$EvidenceProfile.dotNetMajor -ne $ExpectedProfile.DotNetMajor -or
        [string]$EvidenceProfile.targetFramework -ne $ExpectedProfile.TargetFramework -or
        [string]$EvidenceProfile.platform -ne 'windows' -or
        [string]$EvidenceProfile.architecture -ne 'x64' -or
        $EvidenceProfile.writesPerformed -ne $false) {
        throw "Authenticated profile '$($ExpectedProfile.ProfileKey)' does not match the exact zero-write Windows runtime contract."
    }
    if ([string]$EvidenceProfile.runtimeExecutable -notmatch '^runtime:' -or [string]$EvidenceProfile.psHome -notmatch '^runtime:') {
        throw "Authenticated profile '$($ExpectedProfile.ProfileKey)' contains an unnormalized runtime path."
    }
    if ([string]$EvidenceProfile.inventoryFingerprint -notmatch '^[a-f0-9]{64}$') {
        throw "Authenticated profile '$($ExpectedProfile.ProfileKey)' has no valid prepared module-inventory fingerprint."
    }
    Assert-ExactStringSet -Actual @($EvidenceProfile.moduleVersions.name) -Expected $ExpectedModuleNames -Label "Module versions for '$($ExpectedProfile.ProfileKey)'"
    foreach ($ModuleVersion in @($EvidenceProfile.moduleVersions)) {
        Assert-ExactPropertySet -InputObject $ModuleVersion -Expected @('name', 'version', 'manifest') -Label "Module-version row for '$($ExpectedProfile.ProfileKey)'"
        if ([string]::IsNullOrWhiteSpace([string]$ModuleVersion.version) -or
            [string]$ModuleVersion.manifest -notmatch '^upstream:') {
            throw "Authenticated profile '$($ExpectedProfile.ProfileKey)' has an incomplete or unnormalized module-version row."
        }
    }
    Assert-ExactStringSet -Actual @($EvidenceProfile.scenarios.scenarioId) -Expected $ExpectedScenarioIds -Label "Scenario coverage for '$($ExpectedProfile.ProfileKey)'"

    $ProfilePolicy = @($Policy.runtimeProfiles | Where-Object {
            $_.powerShellLine -eq $ExpectedProfile.PowerShellLine -and $_.targetFramework -eq $ExpectedProfile.TargetFramework
        })
    if ($ProfilePolicy.Count -ne 1) {
        throw "No unique dependency policy exists for '$($ExpectedProfile.ProfileKey)'."
    }
    foreach ($Scenario in @($EvidenceProfile.scenarios)) {
        Assert-ExactPropertySet -InputObject $Scenario -Expected @('scenarioId', 'profileKey', 'powerShellVersion', 'targetFramework', 'platform', 'architecture', 'inventoryFingerprint', 'importOrder', 'dllPickleTiming', 'expectedTokenAudiences', 'status', 'writesPerformed', 'probes', 'snapshots', 'errorType') -Label "Authenticated scenario '$($Scenario.scenarioId)'"
        if ([string]$Scenario.profileKey -ne $ExpectedProfile.ProfileKey -or
            [string]$Scenario.powerShellVersion -ne $ExpectedProfile.PowerShellVersion -or
            [string]$Scenario.targetFramework -ne $ExpectedProfile.TargetFramework -or
            [string]$Scenario.platform -ne 'windows' -or
            [string]$Scenario.architecture -ne 'x64' -or
            [string]$Scenario.inventoryFingerprint -ne [string]$EvidenceProfile.inventoryFingerprint) {
            throw "Authenticated scenario '$($Scenario.scenarioId)' is not bound to exact profile '$($ExpectedProfile.ProfileKey)'."
        }
        if ([string]$Scenario.status -ne 'passed' -or $Scenario.writesPerformed -ne $false -or
            -not [string]::IsNullOrWhiteSpace([string]$Scenario.errorType)) {
            throw "Authenticated scenario '$($Scenario.scenarioId)' for '$($ExpectedProfile.ProfileKey)' did not pass zero-write validation."
        }
        $Provider = if ([string]$Scenario.scenarioId -like 'cross-*') { 'cross' } else { ([string]$Scenario.scenarioId -split '-')[0] }
        $ExpectedTiming = if ($Provider -eq 'cross' -or [string]$Scenario.scenarioId -like '*-dllpickle-first') {
            'dllpickle-first'
        } elseif ([string]$Scenario.scenarioId -like '*-module-first') {
            'module-first'
        } else {
            'module-only'
        }
        if ([string]$Scenario.dllPickleTiming -ne $ExpectedTiming) {
            throw "Authenticated scenario '$($Scenario.scenarioId)' has DLLPickle timing '$($Scenario.dllPickleTiming)', expected '$ExpectedTiming'."
        }
        if ($Provider -ne 'cross' -and (@($Scenario.importOrder) -join '|') -ne (@($ProviderModuleOrders[$Provider]) -join '|')) {
            throw "Authenticated scenario '$($Scenario.scenarioId)' does not use the fixed provider module order."
        }
        Assert-ExactStringSet -Actual @($Scenario.probes.probeId) -Expected @($ProviderProbes[$Provider]) -Label "Probe coverage for '$($Scenario.scenarioId)'"
        Assert-ExactStringSet -Actual @($Scenario.expectedTokenAudiences) -Expected @($ProviderAudiences[$Provider]) -Label "Declared token audiences for '$($Scenario.scenarioId)'"
        foreach ($Probe in @($Scenario.probes)) {
            Assert-ExactPropertySet -InputObject $Probe -Expected @('probeId', 'executed', 'status', 'durationMilliseconds', 'writesPerformed', 'errorType') -Label "Authenticated probe '$($Probe.probeId)'"
            if ($Probe.executed -ne $true -or [string]$Probe.status -ne 'passed' -or $Probe.writesPerformed -ne $false -or
                -not [string]::IsNullOrWhiteSpace([string]$Probe.errorType) -or [long]$Probe.durationMilliseconds -lt 0) {
                throw "Authenticated probe '$($Probe.probeId)' in '$($Scenario.scenarioId)' is not an executed, passing, zero-write result."
            }
        }
        Assert-ExactStringSet -Actual @($Scenario.snapshots.stage) -Expected @('before-authentication', 'after-connection', 'after-read-probe') -Label "ALC snapshots for '$($Scenario.scenarioId)'"
        foreach ($Snapshot in @($Scenario.snapshots)) {
            Assert-ExactPropertySet -InputObject $Snapshot -Expected @('stage', 'assemblies') -Label "ALC snapshot '$($Scenario.scenarioId)/$($Snapshot.stage)'"
            foreach ($Assembly in @($Snapshot.assemblies)) {
                Assert-ExactPropertySet -InputObject $Assembly -Expected @('name', 'version', 'sha256', 'selectedAsset', 'assemblyLoadContext', 'isCollectible') -Label "Assembly row in '$($Scenario.scenarioId)/$($Snapshot.stage)'"
                if ([string]$Assembly.sha256 -notmatch '^[a-f0-9]{64}$' -or
                    [string]$Assembly.selectedAsset -notmatch '^(upstream|dllpickle|runtime):' -or
                    [string]$Assembly.name -notin @($Policy.trackedAssemblies) -or
                    [string]::IsNullOrWhiteSpace([string]$Assembly.name) -or
                    [string]::IsNullOrWhiteSpace([string]$Assembly.version) -or
                    [string]::IsNullOrWhiteSpace([string]$Assembly.assemblyLoadContext) -or
                    $Assembly.isCollectible -isnot [bool]) {
                    throw "ALC snapshot '$($Scenario.scenarioId)/$($Snapshot.stage)' contains an incomplete or unnormalized assembly row."
                }
            }
        }
    }

    $CrossScenarios = @(Get-DLLPickleOrdinalSequence -InputObject @($EvidenceProfile.scenarios | Where-Object scenarioId -like 'cross-*') -KeySelector { param($Scenario) [string]$Scenario.scenarioId })
    for ($OrderIndex = 0; $OrderIndex -lt 2; $OrderIndex++) {
        $ExpectedOrder = @($ProfilePolicy[0].importOrders[$OrderIndex])
        if ((@($CrossScenarios[$OrderIndex].importOrder) -join '|') -ne ($ExpectedOrder -join '|')) {
            throw "Authenticated cross-import scenario $($OrderIndex + 1) for '$($ExpectedProfile.ProfileKey)' does not match dependency policy."
        }
    }
}

[pscustomobject]@{
    Mode = $Mode
    EvidenceType = [string]$Evidence.evidenceType
    EvidenceFingerprint = $RecomputedContentFingerprint
    BundleSourceFingerprint = [string]$CurrentBundle.fingerprint
    AllowedReleaseVersion = [string]$Bridge.allowedReleaseVersion
    ExpiresAtUtc = $ExpiresAtUtc.ToString('o')
    ProfileKeys = @($ExpectedProfiles.ProfileKey)
    WritesPerformed = $false
}
