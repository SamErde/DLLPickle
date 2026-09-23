<#
.SYNOPSIS
Executes deterministic upstream import orders with and without DLLPickle.

.DESCRIPTION
Uses an exact stock PowerShell executable, exact saved module manifests, and an
isolated module path. Every configured import order runs twice in a fresh process:
without DLLPickle and after DLLPickle preloading. The report captures selected
assemblies and ALC ownership and emits a stable profile-keyed scenario fingerprint.
Known process-isolation limitations are observational in this no-auth tier: either
outcome is recorded, but a successful no-auth probe does not clear a limitation
whose re-adjudication requires authenticated runtime evidence.
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$InventoryPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PowerShellExecutable,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DLLPickleManifestPath,

    [Parameter()]
    [string]$KnownConflictsPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
foreach ($Path in @($PolicyPath, $InventoryPath, $PowerShellExecutable, $DLLPickleManifestPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required upstream scenario input was not found: $Path"
    }
}

$ResolvedPolicyPath = (Resolve-Path -LiteralPath $PolicyPath).Path
$ResolvedInventoryPath = (Resolve-Path -LiteralPath $InventoryPath).Path
$ResolvedPowerShellExecutable = (Resolve-Path -LiteralPath $PowerShellExecutable).Path
$ResolvedDLLPickleManifestPath = (Resolve-Path -LiteralPath $DLLPickleManifestPath).Path
$Policy = Get-Content -LiteralPath $ResolvedPolicyPath -Raw | ConvertFrom-Json -ErrorAction Stop
$Inventory = Get-Content -LiteralPath $ResolvedInventoryPath -Raw | ConvertFrom-Json -ErrorAction Stop
if (-not $Inventory.Profile -or [string]::IsNullOrWhiteSpace([string]$Inventory.ProfileKey)) {
    throw 'The upstream inventory is not keyed to an exact runtime profile.'
}
$ProfileKeyValues = @(
    [string]$Inventory.Profile.PowerShellLine
    [string]$Inventory.Profile.TargetFramework
    [string]$Inventory.Profile.Platform
    [string]$Inventory.Profile.Architecture
)
if (@($ProfileKeyValues | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
    throw "Upstream inventory '$($Inventory.ProfileKey)' lacks a complete PowerShell line, TFM, platform, and architecture profile."
}
$DerivedProfileKey = 'ps{0}-{1}-{2}-{3}' -f $ProfileKeyValues
if ([string]$Inventory.ProfileKey -ne $DerivedProfileKey) {
    throw "Upstream inventory profile key '$($Inventory.ProfileKey)' does not match derived profile key '$DerivedProfileKey'."
}

$ProfilePolicy = @($Policy.runtimeProfiles | Where-Object {
        $_.powerShellLine -eq $Inventory.Profile.PowerShellLine -and
        $_.targetFramework -eq $Inventory.Profile.TargetFramework
    })
if ($ProfilePolicy.Count -ne 1) {
    throw "No unique dependency-policy profile matches '$($Inventory.ProfileKey)'."
}
$ModulePolicyByName = @{}
foreach ($ModulePolicy in @($Policy.monitoredModules)) {
    $ModulePolicyByName[[string]$ModulePolicy.name] = $ModulePolicy
}
$InventoryModuleByName = @{}
foreach ($Module in @($Inventory.Modules)) {
    $InventoryModuleByName[[string]$Module.Name] = $Module
}
$ModuleSearchPath = @([string]$Inventory.ModuleCachePath, (Join-Path -Path ([string]$Inventory.Profile.PSHome) -ChildPath 'Modules'))
$SnapshotScriptPath = Join-Path $PSScriptRoot 'Get-DLLPickleRuntimeAssemblySnapshot.ps1'
$ScenarioDefinitions = [System.Collections.Generic.List[object]]::new()
$PolicyOrderIndex = 0
foreach ($ImportOrder in @($ProfilePolicy[0].importOrders)) {
    $PolicyOrderIndex++
    $ScenarioDefinitions.Add([PSCustomObject]@{
            ScenarioId = 'profile-target-scenario-{0:d2}' -f $PolicyOrderIndex
            ImportOrder = @($ImportOrder)
            ExpectedLimitation = $false
            ExpectedSuccess = $true
            OutcomePolicy = 'must-succeed'
        })
}
if (-not [string]::IsNullOrWhiteSpace($KnownConflictsPath)) {
    if (-not (Test-Path -LiteralPath $KnownConflictsPath -PathType Leaf)) {
        throw "Known-conflicts policy was not found: $KnownConflictsPath"
    }
    $KnownConflicts = @(Get-Content -LiteralPath $KnownConflictsPath -Raw | ConvertFrom-Json -ErrorAction Stop)
    foreach ($KnownConflict in @($KnownConflicts | Where-Object { [string]$_.id -in @($ProfilePolicy[0].knownConflictIds) })) {
        $ExpectedLimitation = [bool]$KnownConflict.requiresProcessIsolation
        foreach ($ImportOrder in @($KnownConflict.importOrders)) {
            $ScenarioDefinitions.Add([PSCustomObject]@{
                    ScenarioId = [string]$KnownConflict.id
                    ImportOrder = @($ImportOrder)
                    ExpectedLimitation = $ExpectedLimitation
                    ExpectedSuccess = if ($ExpectedLimitation) { $null } else { $true }
                    OutcomePolicy = if ($ExpectedLimitation) { 'observe-known-limitation' } else { 'must-succeed' }
                })
        }
    }
}

$ScenarioResults = [System.Collections.Generic.List[object]]::new()
$OrderIndex = 0
foreach ($ScenarioDefinition in $ScenarioDefinitions) {
    $OrderIndex++
    $ImportOrder = @($ScenarioDefinition.ImportOrder | ForEach-Object { [string]$_ })
    $ManifestPaths = @(
        foreach ($ModuleName in $ImportOrder) {
            if (-not $InventoryModuleByName.ContainsKey($ModuleName)) {
                throw "Upstream inventory '$($Inventory.ProfileKey)' does not contain module '$ModuleName'."
            }
            $ManifestPath = [string]$InventoryModuleByName[$ModuleName].ModuleManifestPath
            if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
                throw "Upstream inventory module '$ModuleName' has no exact manifest path."
            }
            $ManifestPath
        }
    )
    $ProbeCommands = @(
        foreach ($ModuleName in $ImportOrder) {
            if (-not $ModulePolicyByName.ContainsKey($ModuleName)) {
                throw "Dependency policy has no monitored-module row for '$ModuleName'."
            }
            [string]$ModulePolicyByName[$ModuleName].deterministicProbeCommand
        }
    )
    $CombinedProbeCommand = @($ProbeCommands | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join '; '

    foreach ($PreloadDllPickle in @($false, $true)) {
        $Scenario = [ordered]@{
            ScenarioId = [string]$ScenarioDefinition.ScenarioId
            OrderIndex = $OrderIndex
            ImportOrder = @($ImportOrder)
            DllPicklePreloaded = $PreloadDllPickle
            ExpectedLimitation = [bool]$ScenarioDefinition.ExpectedLimitation
            ExpectedSuccess = $ScenarioDefinition.ExpectedSuccess
            OutcomePolicy = [string]$ScenarioDefinition.OutcomePolicy
            ProbeCommands = @($ProbeCommands)
            Success = $false
            OutcomeMatchesExpectation = $false
            Assemblies = @()
            Error = $null
        }
        try {
            $SnapshotParameters = @{
                ModuleName = $ImportOrder
                ModuleManifestPath = $ManifestPaths
                ModuleSearchPath = $ModuleSearchPath
                ProbeCommand = $CombinedProbeCommand
                PolicyPath = $ResolvedPolicyPath
                PowerShellExecutable = $ResolvedPowerShellExecutable
                PowerShellVersion = [version]$Inventory.Profile.PowerShellVersion
                TargetFramework = [string]$Inventory.Profile.TargetFramework
                Strict = $true
            }
            if ($PreloadDllPickle) {
                $SnapshotParameters['PreloadDllPickleManifest'] = $ResolvedDLLPickleManifestPath
            }
            $Scenario.Assemblies = @(& $SnapshotScriptPath @SnapshotParameters)
            $Scenario.Success = $true
        } catch {
            $Scenario.Error = $_.Exception.Message
        }
        $Scenario.OutcomeMatchesExpectation =
            $Scenario.OutcomePolicy -eq 'observe-known-limitation' -or
            $Scenario.Success -eq $Scenario.ExpectedSuccess
        $ScenarioResults.Add([PSCustomObject]$Scenario)
    }
}

$ObservedAssemblies = @(
    foreach ($ScenarioResult in $ScenarioResults) {
        foreach ($Assembly in @($ScenarioResult.Assemblies)) {
            $Assembly
        }
    }
)
if ($ObservedAssemblies.Count -eq 0) {
    throw "Deterministic upstream scenarios for '$($Inventory.ProfileKey)' contain no observed tracked assemblies."
}
foreach ($ObservedAssembly in $ObservedAssemblies) {
    if ([string]$ObservedAssembly.Platform -ne [string]$Inventory.Profile.Platform -or
        [string]$ObservedAssembly.Architecture -ne [string]$Inventory.Profile.Architecture) {
        throw "Scenario assembly '$($ObservedAssembly.Name)' was observed on '$($ObservedAssembly.Platform)/$($ObservedAssembly.Architecture)', expected '$($Inventory.Profile.Platform)/$($Inventory.Profile.Architecture)' for '$($Inventory.ProfileKey)'."
    }
}

$CanonicalRows = @(
    "profile=$($Inventory.ProfileKey)"
    foreach ($Scenario in @($ScenarioResults | Sort-Object OrderIndex,DllPicklePreloaded)) {
        'scenario={0}|order={1}|preload={2}|expectedLimitation={3}|expectedSuccess={4}|outcomePolicy={5}|success={6}|outcomeMatches={7}|error={10}|modules={8}|assemblies={9}' -f (
            $Scenario.ScenarioId,
            $Scenario.OrderIndex,
            $Scenario.DllPicklePreloaded,
            $Scenario.ExpectedLimitation,
            $Scenario.ExpectedSuccess,
            $Scenario.OutcomePolicy,
            $Scenario.Success,
            $Scenario.OutcomeMatchesExpectation,
            (@($Scenario.ImportOrder) -join ','),
            (@($Scenario.Assemblies | Sort-Object Name,Path | ForEach-Object { '{0},{1},{2},{3},{4}' -f $_.Name, $_.Version, $_.Sha256, $_.Path, $_.Alc }) -join ';'),
            (([string]$Scenario.Error) -replace '(?i)dpp-snap-[0-9a-f]{32}\.(ps1|json)', 'dpp-snap-<id>.$1' -replace '\s+', ' ').Trim()
        )
    }
)
$FingerprintBytes = [System.Text.Encoding]::UTF8.GetBytes(($CanonicalRows -join [char]10))
$ScenarioFingerprint = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($FingerprintBytes)).Replace('-', '').ToLowerInvariant()
$Report = [PSCustomObject]@{
    SchemaVersion = 1
    GeneratedAtUtc = [System.DateTimeOffset]::UtcNow.ToString('o')
    ProfileKey = [string]$Inventory.ProfileKey
    Profile = $Inventory.Profile
    ValidationTier = 'deterministic-import-no-auth'
    WritesPerformed = $false
    ScenarioFingerprint = $ScenarioFingerprint
    Scenarios = @($ScenarioResults)
    Passed = @($ScenarioResults | Where-Object { -not $_.OutcomeMatchesExpectation }).Count -eq 0
}

$OutputDirectory = Split-Path -Path $OutputPath -Parent
if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
}
$Report | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

if ($Strict.IsPresent -and -not $Report.Passed) {
    $FailedLabels = @($ScenarioResults | Where-Object { -not $_.OutcomeMatchesExpectation } | ForEach-Object { "order $($_.OrderIndex), preload=$($_.DllPicklePreloaded), policy=$($_.OutcomePolicy), expectedSuccess=$($_.ExpectedSuccess), actualSuccess=$($_.Success)" })
    throw "Deterministic upstream scenarios failed for '$($Inventory.ProfileKey)': $($FailedLabels -join '; ')."
}
$Report
