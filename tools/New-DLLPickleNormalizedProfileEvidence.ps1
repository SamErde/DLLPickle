<#
.SYNOPSIS
Creates a durable, path-normalized upstream compatibility snapshot.

.DESCRIPTION
Combines the exact-profile inventory, conflict matrix, deterministic scenario
evidence, and validation-gap report into a stable document suitable for source
control. Volatile run provenance is kept outside the fingerprinted content.
Runner-specific absolute paths are converted to upstream: or dllpickle:
identifiers so equivalent evidence recomputes to the same content fingerprint.

.PARAMETER InventoryPath
Path to upstream-inventory.json.

.PARAMETER ConflictMatrixPath
Path to conflict-matrix.json.

.PARAMETER ScenarioEvidencePath
Path to scenario-evidence.json.

.PARAMETER ValidationGapsPath
Path to validation-gaps.json.

.PARAMETER OutputPath
Path to write the normalized evidence JSON.

.PARAMETER SourceRunId
Optional CI run identifier retained as non-fingerprinted provenance.

.PARAMETER SourceRunUrl
Optional CI run URL retained as non-fingerprinted provenance.

.PARAMETER SourceCommitSha
Optional source commit retained as non-fingerprinted provenance.

.PARAMETER CapturedAtUtc
Optional ISO-8601 capture time. Defaults to the inventory timestamp, then UTC now.

.OUTPUTS
System.Management.Automation.PSCustomObject
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$InventoryPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ConflictMatrixPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ScenarioEvidencePath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ValidationGapsPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,

    [Parameter()]
    [string]$SourceRunId = $env:GITHUB_RUN_ID,

    [Parameter()]
    [string]$SourceRunUrl,

    [Parameter()]
    [string]$SourceCommitSha = $env:GITHUB_SHA,

    [Parameter()]
    [string]$CapturedAtUtc
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DLLPickle.ProfileEvidence.ps1')

function ConvertTo-CollapsedRelativePath {
    param([Parameter(Mandatory)][string]$Path)

    $Segments = [System.Collections.Generic.List[string]]::new()
    foreach ($Segment in @($Path -split '/')) {
        if ([string]::IsNullOrWhiteSpace($Segment) -or $Segment -eq '.') {
            continue
        }
        if ($Segment -eq '..') {
            if ($Segments.Count -eq 0) {
                throw "Evidence path '$Path' escapes its normalized root."
            }
            $Segments.RemoveAt($Segments.Count - 1)
            continue
        }
        $Segments.Add($Segment)
    }
    $Segments -join '/'
}

function ConvertTo-NormalizedEvidencePath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ModuleCachePath,
        [Parameter(Mandatory)][string]$RuntimeRoot
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'An evidence asset path is empty.'
    }

    $NormalizedPath = $Path.Replace('\', '/').TrimEnd('/')
    $NormalizedCache = $ModuleCachePath.Replace('\', '/').TrimEnd('/')
    $NormalizedRuntimeRoot = $RuntimeRoot.Replace('\', '/').TrimEnd('/')
    $RelativePath = $null
    $Prefix = $null
    if ($NormalizedPath.StartsWith("$NormalizedCache/", [System.StringComparison]::OrdinalIgnoreCase)) {
        $RelativePath = $NormalizedPath.Substring($NormalizedCache.Length + 1)
        $Prefix = 'upstream'
    } elseif ($NormalizedPath -match '(?i)/dllpickle-upstream-modules/[^/]+/(?<relative>.+)$') {
        $RelativePath = $Matches.relative
        $Prefix = 'upstream'
    } elseif ($NormalizedPath -match '(?i)/module/DLLPickle/(?<relative>.+)$') {
        $RelativePath = $Matches.relative
        $Prefix = 'dllpickle'
    } elseif ($NormalizedPath.StartsWith("$NormalizedRuntimeRoot/", [System.StringComparison]::OrdinalIgnoreCase)) {
        $RelativePath = $NormalizedPath.Substring($NormalizedRuntimeRoot.Length + 1)
        $Prefix = 'runtime'
    } else {
        throw "Evidence path '$Path' is outside the upstream module cache, DLLPickle module root, and exact runtime root."
    }

    '{0}:{1}' -f $Prefix, (ConvertTo-CollapsedRelativePath -Path $RelativePath)
}

foreach ($RequiredPath in @($InventoryPath, $ConflictMatrixPath, $ScenarioEvidencePath, $ValidationGapsPath)) {
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) {
        throw "Required profile evidence input was not found: $RequiredPath"
    }
}

$Inventory = Get-Content -LiteralPath $InventoryPath -Raw | ConvertFrom-Json -ErrorAction Stop
$Matrix = Get-Content -LiteralPath $ConflictMatrixPath -Raw | ConvertFrom-Json -ErrorAction Stop
$ScenarioEvidence = Get-Content -LiteralPath $ScenarioEvidencePath -Raw | ConvertFrom-Json -ErrorAction Stop
$ValidationGaps = Get-Content -LiteralPath $ValidationGapsPath -Raw | ConvertFrom-Json -ErrorAction Stop

$ProfileKey = [string]$Inventory.ProfileKey
if ([string]::IsNullOrWhiteSpace($ProfileKey) -or -not $Inventory.Profile) {
    throw 'The upstream inventory is not keyed to an exact runtime profile.'
}
foreach ($Source in @($Matrix, $ScenarioEvidence)) {
    if ([string]$Source.ProfileKey -ne $ProfileKey) {
        throw "Profile evidence '$($Source.ProfileKey)' does not match inventory profile '$ProfileKey'."
    }
}
$DerivedProfileKey = 'ps{0}-{1}-{2}-{3}' -f @(
    [string]$Inventory.Profile.PowerShellLine
    [string]$Inventory.Profile.TargetFramework
    [string]$Inventory.Profile.Platform
    [string]$Inventory.Profile.Architecture
)
if ($ProfileKey -ne $DerivedProfileKey) {
    throw "Inventory profile key '$ProfileKey' does not match derived profile key '$DerivedProfileKey'."
}
if (-not $ScenarioEvidence.Passed -or $ScenarioEvidence.WritesPerformed -or
    [string]$ScenarioEvidence.ValidationTier -ne 'deterministic-import-no-auth') {
    throw "Scenario evidence for '$ProfileKey' is not a passing zero-write deterministic tier."
}
if ($ValidationGaps.writesPerformed -or
    [string]$ValidationGaps.authenticatedReadOnly -ne 'not-run-no-approved-credentials') {
    throw "Validation-gap evidence for '$ProfileKey' must record an unexecuted, zero-write authenticated tier."
}
if (@($Inventory.Modules).Count -eq 0 -or @($Matrix.Assemblies).Count -eq 0 -or @($ScenarioEvidence.Scenarios).Count -eq 0) {
    throw "Profile evidence for '$ProfileKey' is incomplete."
}

$ModuleCachePath = [string]$Inventory.ModuleCachePath
if ([string]::IsNullOrWhiteSpace($ModuleCachePath)) {
    throw "Inventory for '$ProfileKey' has no module cache root for path normalization."
}
$RuntimeRoot = [string]$Inventory.Profile.PSHome
if ([string]::IsNullOrWhiteSpace($RuntimeRoot)) {
    throw "Inventory for '$ProfileKey' has no exact runtime root for path normalization."
}

$NormalizedModules = @(
    foreach ($Module in @(Get-DLLPickleOrdinalSequence -InputObject @($Inventory.Modules) -KeySelector { param($Item) [string]$Item.Name })) {
        $UnsortedSelectedAssets = @(
            foreach ($Assembly in @($Module.TrackedAssemblies)) {
                [ordered]@{
                    assemblyName = [string]$Assembly.Name
                    assemblyVersion = [string]$Assembly.Version
                    packageVersionCandidate = [string]$Assembly.PackageVersionCandidate
                    fullName = [string]$Assembly.FullName
                    sha256 = ([string]$Assembly.Sha256).ToLowerInvariant()
                    assemblyLoadContext = [string]$Assembly.Alc
                    isCollectible = [bool]$Assembly.IsCollectible
                    contributor = [string]$Assembly.ConstituentModule
                    selectedAsset = ConvertTo-NormalizedEvidencePath -Path ([string]$Assembly.SelectedAssetPath) -ModuleCachePath $ModuleCachePath -RuntimeRoot $RuntimeRoot
                }
            }
        )
        $SelectedAssets = @(
            Get-DLLPickleOrdinalSequence -InputObject $UnsortedSelectedAssets -KeySelector {
                param($Item)
                '{0}{5}{1}{5}{2}{5}{3}{5}{4}' -f $Item.assemblyName, $Item.assemblyVersion, $Item.sha256, $Item.assemblyLoadContext, $Item.selectedAsset, [char]0
            }
        )
        [ordered]@{
            name = [string]$Module.Name
            umbrellaModule = [string]$Module.UmbrellaModule
            constituentModule = [string]$Module.ConstituentModule
            version = [string]$Module.Version
            latestCompatibleVersion = [string]$Module.LatestCompatibleVersion
            repository = [string]$Module.Repository
            manifestPowerShellVersion = [string]$Module.ManifestPowerShellVersion
            compatiblePSEditions = @(Get-DLLPickleOrdinalSequence -InputObject @($Module.CompatiblePSEditions))
            deterministicProbeCommand = [string]$Module.DeterministicProbeCommand
            selectedAssets = $SelectedAssets
        }
    }
)

$NormalizedMatrixRows = @(
    foreach ($Assembly in @(Get-DLLPickleOrdinalSequence -InputObject @($Matrix.Assemblies) -KeySelector { param($Item) [string]$Item.Name })) {
        [ordered]@{
            name = [string]$Assembly.Name
            shippedBy = @(Get-DLLPickleOrdinalSequence -InputObject @($Assembly.ShippedBy))
            versions = @(Get-DLLPickleOrdinalSequence -InputObject @($Assembly.Versions))
            hashes = @(Get-DLLPickleOrdinalSequence -InputObject @($Assembly.Hashes | ForEach-Object { ([string]$_).ToLowerInvariant() }))
            assemblyLoadContexts = @(Get-DLLPickleOrdinalSequence -InputObject @($Assembly.AlcOwners))
            diverges = [bool]$Assembly.Diverges
            selections = @(
                foreach ($Selection in @(Get-DLLPickleOrdinalSequence -InputObject @($Assembly.Selections) -KeySelector {
                            param($Item)
                            '{0}{4}{1}{4}{2}{4}{3}' -f $Item.Module, $Item.Version, $Item.Sha256, $Item.AlcOwner, [char]0
                        })) {
                    [ordered]@{
                        contributor = [string]$Selection.Module
                        version = [string]$Selection.Version
                        sha256 = ([string]$Selection.Sha256).ToLowerInvariant()
                        assemblyLoadContext = [string]$Selection.AlcOwner
                    }
                }
            )
        }
    }
)

$NormalizedScenarios = @(
    foreach ($Scenario in @(Get-DLLPickleOrdinalSequence -InputObject @($ScenarioEvidence.Scenarios) -KeySelector {
                param($Item)
                '{0}{3}{1:D10}{3}{2}' -f $Item.ScenarioId, [int]$Item.OrderIndex, [bool]$Item.DllPicklePreloaded, [char]0
            })) {
        $FirstAssembly = @($Scenario.Assemblies | Select-Object -First 1)
        $ImportedModuleAssets = if ($FirstAssembly.Count -eq 1) {
            @(
                foreach ($ImportedPath in @($FirstAssembly[0].ImportedModulePaths)) {
                    ConvertTo-NormalizedEvidencePath -Path ([string]$ImportedPath) -ModuleCachePath $ModuleCachePath -RuntimeRoot $RuntimeRoot
                }
            )
        } else {
            @()
        }
        [ordered]@{
            scenarioId = [string]$Scenario.ScenarioId
            orderIndex = [int]$Scenario.OrderIndex
            importOrder = @($Scenario.ImportOrder)
            importedModuleAssets = $ImportedModuleAssets
            dllPicklePreloaded = [bool]$Scenario.DllPicklePreloaded
            expectedLimitation = [bool]$Scenario.ExpectedLimitation
            expectedSuccess = $Scenario.ExpectedSuccess
            outcomePolicy = [string]$Scenario.OutcomePolicy
            probeCommands = @($Scenario.ProbeCommands)
            success = [bool]$Scenario.Success
            outcomeMatchesExpectation = [bool]$Scenario.OutcomeMatchesExpectation
            errorObserved = -not [string]::IsNullOrWhiteSpace([string]$Scenario.Error)
            assemblies = @(
                $UnsortedScenarioAssemblies = @(
                    foreach ($Assembly in @($Scenario.Assemblies)) {
                        [ordered]@{
                            name = [string]$Assembly.Name
                            version = [string]$Assembly.Version
                            fullName = [string]$Assembly.FullName
                            sha256 = ([string]$Assembly.Sha256).ToLowerInvariant()
                            assemblyLoadContext = [string]$Assembly.Alc
                            isCollectible = [bool]$Assembly.IsCollectible
                            selectedAsset = ConvertTo-NormalizedEvidencePath -Path ([string]$Assembly.Path) -ModuleCachePath $ModuleCachePath -RuntimeRoot $RuntimeRoot
                        }
                    }
                )
                Get-DLLPickleOrdinalSequence -InputObject $UnsortedScenarioAssemblies -KeySelector {
                    param($Item)
                    '{0}{5}{1}{5}{2}{5}{3}{5}{4}' -f $Item.name, $Item.version, $Item.sha256, $Item.assemblyLoadContext, $Item.selectedAsset, [char]0
                }
            )
        }
    }
)

$Content = [ordered]@{
    profile = [ordered]@{
        profileKey = $ProfileKey
        powerShellVersion = [string]$Inventory.Profile.PowerShellVersion
        powerShellLine = [string]$Inventory.Profile.PowerShellLine
        dotNetVersion = [string]$Inventory.Profile.DotNetVersion
        dotNetMajor = [int]$Inventory.Profile.DotNetMajor
        targetFramework = [string]$Inventory.Profile.TargetFramework
        platform = [string]$Inventory.Profile.Platform
        architecture = [string]$Inventory.Profile.Architecture
    }
    validation = [ordered]@{
        deterministicImportNoAuth = [ordered]@{
            status = 'passed'
            writesPerformed = $false
            conflictSurfaceFingerprint = ([string]$Matrix.Fingerprint).ToLowerInvariant()
            scenarioFingerprint = ([string]$ScenarioEvidence.ScenarioFingerprint).ToLowerInvariant()
        }
        authenticatedReadOnly = [ordered]@{
            status = [string]$ValidationGaps.authenticatedReadOnly
            writesPerformed = [bool]$ValidationGaps.writesPerformed
            unexecutedCommands = @($ValidationGaps.unexecutedCommands)
        }
    }
    modules = $NormalizedModules
    conflictMatrix = [ordered]@{
        conflictSurface = @(Get-DLLPickleOrdinalSequence -InputObject @($Matrix.ConflictSurface))
        assemblies = $NormalizedMatrixRows
    }
    scenarios = $NormalizedScenarios
}

$FingerprintEnvelope = [pscustomobject]@{ schemaVersion = 1; content = $Content }
$ContentFingerprint = Get-DLLPickleNormalizedEvidenceFingerprint -Evidence $FingerprintEnvelope
$ObservedOperatingSystemCandidates = @(
    @($Inventory.Modules.TrackedAssemblies.OS) + @($ScenarioEvidence.Scenarios.Assemblies.OS) |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
)
$ObservedOperatingSystems = @(
    Get-DLLPickleOrdinalSequence -InputObject $ObservedOperatingSystemCandidates -Unique
)
if ([string]::IsNullOrWhiteSpace($CapturedAtUtc)) {
    $CapturedAtUtc = if (-not [string]::IsNullOrWhiteSpace([string]$Inventory.GeneratedAtUtc)) {
        [string]$Inventory.GeneratedAtUtc
    } else {
        [System.DateTimeOffset]::UtcNow.ToString('o')
    }
}
$ParsedCaptureTime = [System.DateTimeOffset]::Parse($CapturedAtUtc).ToUniversalTime().ToString('o')

$Evidence = [ordered]@{
    schemaVersion = 1
    contentFingerprint = $ContentFingerprint
    provenance = [ordered]@{
        sourceRunId = if ([string]::IsNullOrWhiteSpace($SourceRunId)) { $null } else { $SourceRunId }
        sourceRunUrl = if ([string]::IsNullOrWhiteSpace($SourceRunUrl)) { $null } else { $SourceRunUrl }
        sourceCommitSha = if ([string]::IsNullOrWhiteSpace($SourceCommitSha)) { $null } else { $SourceCommitSha }
        capturedAtUtc = $ParsedCaptureTime
        observedOperatingSystems = $ObservedOperatingSystems
    }
    content = $Content
}

$OutputDirectory = Split-Path -Path $OutputPath -Parent
if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
}
$Evidence | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
[pscustomobject]$Evidence
