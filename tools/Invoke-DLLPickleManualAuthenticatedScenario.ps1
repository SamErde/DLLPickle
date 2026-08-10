<#
.SYNOPSIS
Runs one fixed interactive authenticated compatibility scenario in the current process.

.DESCRIPTION
This child harness is invoked by Invoke-DLLPickleManualAuthenticatedCompatibility.ps1
under an exact stock PowerShell executable. Authentication commands and read probes
are hard-coded. It writes sanitized JSON only: no token, tenant, account, subscription,
mailbox, resource, or raw service result is retained.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ScenarioId,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$InventoryPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$PolicyPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$DLLPickleManifestPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OutputPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExpectedProfileKey,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExpectedPowerShellVersion,
    [Parameter(Mandatory)][ValidatePattern('^net\d+\.0$')][string]$ExpectedTargetFramework,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedInventoryFingerprint,
    [Parameter()][string]$AzureSubscriptionId = $env:DLLPICKLE_MANUAL_AZURE_SUBSCRIPTION_ID
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DLLPickle.ManualAuthenticatedEvidence.ps1')

function Get-SanitizedAssemblySnapshot {
    $Rows = @(& $SnapshotHelper -PolicyPath $ResolvedPolicyPath)
    @(
        foreach ($Row in $Rows) {
            [ordered]@{
                name = [string]$Row.Name
                version = [string]$Row.Version
                sha256 = ([string]$Row.Sha256).ToLowerInvariant()
                selectedAsset = ConvertTo-DLLPickleManualEvidencePath -Path ([string]$Row.Path) -ModuleCacheRoot $ModuleCacheRoot -DLLPickleRoot $DLLPickleRoot -RuntimeRoot $PSHOME
                assemblyLoadContext = [string]$Row.Alc
                isCollectible = [bool]$Row.IsCollectible
            }
        }
    )
}

function Import-ExactModuleSet {
    param([Parameter(Mandatory)][string[]]$Names)

    foreach ($Name in $Names) {
        $Rows = @($Inventory.Modules | Where-Object Name -eq $Name)
        if ($Rows.Count -ne 1) { throw "Inventory does not contain exactly one '$Name' module." }
        Import-Module -Name ([string]$Rows[0].ModuleManifestPath) -Force -ErrorAction Stop
    }
}

function Import-DLLPickleBundle {
    Import-Module -Name $ResolvedDLLPickleManifestPath -Force -ErrorAction Stop
    $ImportResults = @(Import-DPLibrary -SuppressLogo -ErrorAction Stop)
    $FailedImports = @($ImportResults | Where-Object { [string]$_.Status -eq 'Failed' })
    if ($FailedImports.Count -gt 0) {
        throw "DLLPickle preload reported $($FailedImports.Count) failed assembly load(s)."
    }
}

function Connect-Provider {
    param(
        [Parameter(Mandatory)][ValidateSet('graph', 'exo', 'az', 'teams')][string]$Provider,
        [Parameter()][string]$SubscriptionId
    )

    switch ($Provider) {
        'graph' {
            $Command = Get-DLLPickleAuthenticatedCommand -Name 'Connect-MgGraph' -Module 'Microsoft.Graph.Authentication'
            & $Command -Scopes 'User.Read' -ContextScope Process -NoWelcome -ErrorAction Stop | Out-Null
        }
        'exo' {
            $Command = Get-DLLPickleAuthenticatedCommand -Name 'Connect-ExchangeOnline' -Module 'ExchangeOnlineManagement'
            & $Command -ShowBanner:$false -ErrorAction Stop | Out-Null
        }
        'az' {
            $Command = Get-DLLPickleAuthenticatedCommand -Name 'Connect-AzAccount' -Module 'Az.Accounts'
            # WAM depends on the interactive host and can fail after account selection.
            # Device code remains delegated-interactive and avoids changing persisted Az config.
            & $Command -Scope Process -UseDeviceAuthentication -ErrorAction Stop | Out-Null
            if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
                $Command = Get-DLLPickleAuthenticatedCommand -Name 'Set-AzContext' -Module 'Az.Accounts'
                & $Command -SubscriptionId $SubscriptionId -Scope Process -ErrorAction Stop | Out-Null
            }
        }
        'teams' {
            $Command = Get-DLLPickleAuthenticatedCommand -Name 'Connect-MicrosoftTeams' -Module 'MicrosoftTeams'
            & $Command -ErrorAction Stop | Out-Null
        }
    }
}

function Disconnect-Provider {
    param([Parameter(Mandatory)][ValidateSet('graph', 'exo', 'az', 'teams')][string]$Provider)

    try {
        switch ($Provider) {
            'graph' {
                $Command = Get-DLLPickleAuthenticatedCommand -Name 'Disconnect-MgGraph' -Module 'Microsoft.Graph.Authentication'
                & $Command -ErrorAction SilentlyContinue | Out-Null
            }
            'exo' {
                $Command = Get-DLLPickleAuthenticatedCommand -Name 'Disconnect-ExchangeOnline' -Module 'ExchangeOnlineManagement'
                & $Command -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            }
            'az' {
                $Command = Get-DLLPickleAuthenticatedCommand -Name 'Clear-AzContext' -Module 'Az.Accounts'
                & $Command -Scope Process -Force -ErrorAction SilentlyContinue | Out-Null
            }
            'teams' {
                $Command = Get-DLLPickleAuthenticatedCommand -Name 'Disconnect-MicrosoftTeams' -Module 'MicrosoftTeams'
                & $Command -ErrorAction SilentlyContinue | Out-Null
            }
        }
    } catch {
        # Cleanup failures must not replace the sanitized scenario result.
        Write-Verbose "Provider cleanup for '$Provider' did not complete."
    }
}

foreach ($RequiredPath in @($InventoryPath, $PolicyPath, $DLLPickleManifestPath)) {
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) { throw "Required scenario input was not found: $RequiredPath" }
}
$ResolvedInventoryPath = (Resolve-Path -LiteralPath $InventoryPath).Path
$ResolvedPolicyPath = (Resolve-Path -LiteralPath $PolicyPath).Path
$ResolvedDLLPickleManifestPath = (Resolve-Path -LiteralPath $DLLPickleManifestPath).Path
$DLLPickleRoot = Split-Path -Path $ResolvedDLLPickleManifestPath -Parent
$SnapshotHelper = Join-Path $PSScriptRoot 'Get-DLLPickleLoadedTrackedAssembly.ps1'
$Inventory = Get-Content -LiteralPath $ResolvedInventoryPath -Raw | ConvertFrom-Json -ErrorAction Stop
$InventoryFingerprint = [string]$Inventory.InventoryFingerprint
if ($InventoryFingerprint -ne $ExpectedInventoryFingerprint) {
    throw "Prepared module inventory fingerprint '$InventoryFingerprint' does not match expected '$ExpectedInventoryFingerprint'."
}
$ModuleCacheRoot = [string]$Inventory.ModuleCachePath
$ActualTargetFramework = 'net{0}.0' -f [Environment]::Version.Major
$ActualProfileKey = 'ps{0}.{1}-{2}-windows-x64' -f $PSVersionTable.PSVersion.Major, $PSVersionTable.PSVersion.Minor, $ActualTargetFramework
if ($ActualProfileKey -ne $ExpectedProfileKey -or
    $PSVersionTable.PSVersion.ToString() -ne $ExpectedPowerShellVersion -or
    $ActualTargetFramework -ne $ExpectedTargetFramework) {
    throw "Scenario runtime mismatch: expected PowerShell $ExpectedPowerShellVersion/$ExpectedTargetFramework; observed $($PSVersionTable.PSVersion)/$ActualTargetFramework."
}
if ([string]$Inventory.Profile.Platform -ne 'windows' -or [string]$Inventory.Profile.Architecture -ne 'x64') {
    throw 'Manual authenticated transition evidence is restricted to Windows x64.'
}
$env:PSModulePath = @($ModuleCacheRoot, (Join-Path $PSHOME 'Modules')) -join [System.IO.Path]::PathSeparator

$Definitions = [ordered]@{
    'graph-module-only' = [ordered]@{ providers = @('graph'); modules = @('Microsoft.Graph.Authentication'); timing = 'module-only'; probes = @('graph-context', 'graph-me-read') }
    'graph-dllpickle-first' = [ordered]@{ providers = @('graph'); modules = @('Microsoft.Graph.Authentication'); timing = 'dllpickle-first'; probes = @('graph-context', 'graph-me-read') }
    'graph-module-first' = [ordered]@{ providers = @('graph'); modules = @('Microsoft.Graph.Authentication'); timing = 'module-first'; probes = @('graph-context', 'graph-me-read') }
    'exo-module-only' = [ordered]@{ providers = @('exo'); modules = @('ExchangeOnlineManagement'); timing = 'module-only'; probes = @('exo-mailbox-read') }
    'exo-dllpickle-first' = [ordered]@{ providers = @('exo'); modules = @('ExchangeOnlineManagement'); timing = 'dllpickle-first'; probes = @('exo-mailbox-read') }
    'exo-module-first' = [ordered]@{ providers = @('exo'); modules = @('ExchangeOnlineManagement'); timing = 'module-first'; probes = @('exo-mailbox-read') }
    'az-module-only' = [ordered]@{ providers = @('az'); modules = @('Az.Accounts', 'Az.Resources', 'Az.Storage'); timing = 'module-only'; probes = @('az-context', 'az-resource-read', 'az-storage-account-read') }
    'az-dllpickle-first' = [ordered]@{ providers = @('az'); modules = @('Az.Accounts', 'Az.Resources', 'Az.Storage'); timing = 'dllpickle-first'; probes = @('az-context', 'az-resource-read', 'az-storage-account-read') }
    'az-module-first' = [ordered]@{ providers = @('az'); modules = @('Az.Accounts', 'Az.Resources', 'Az.Storage'); timing = 'module-first'; probes = @('az-context', 'az-resource-read', 'az-storage-account-read') }
    'teams-module-only' = [ordered]@{ providers = @('teams'); modules = @('MicrosoftTeams'); timing = 'module-only'; probes = @('teams-tenant-read') }
    'teams-dllpickle-first' = [ordered]@{ providers = @('teams'); modules = @('MicrosoftTeams'); timing = 'dllpickle-first'; probes = @('teams-tenant-read') }
    'teams-module-first' = [ordered]@{ providers = @('teams'); modules = @('MicrosoftTeams'); timing = 'module-first'; probes = @('teams-tenant-read') }
}
$Policy = Get-Content -LiteralPath $ResolvedPolicyPath -Raw | ConvertFrom-Json
$ProfilePolicy = @($Policy.runtimeProfiles | Where-Object {
        $_.powerShellLine -eq [string]$Inventory.Profile.PowerShellLine -and $_.targetFramework -eq $ExpectedTargetFramework
    })
if ($ProfilePolicy.Count -ne 1) { throw 'No unique dependency policy matches the authenticated scenario runtime.' }
$Definitions['cross-import-order-1'] = [ordered]@{ providers = @('graph', 'exo', 'az', 'teams'); modules = @($ProfilePolicy[0].importOrders[0]); timing = 'dllpickle-first'; probes = @('graph-context', 'graph-me-read', 'exo-mailbox-read', 'az-context', 'teams-tenant-read') }
$Definitions['cross-import-order-2'] = [ordered]@{ providers = @('graph', 'exo', 'az', 'teams'); modules = @($ProfilePolicy[0].importOrders[1]); timing = 'dllpickle-first'; probes = @('graph-context', 'graph-me-read', 'exo-mailbox-read', 'az-context', 'teams-tenant-read') }
if (-not $Definitions.Contains($ScenarioId)) { throw "Unsupported authenticated scenario '$ScenarioId'." }
$Definition = $Definitions[$ScenarioId]

$Result = [ordered]@{
    scenarioId = $ScenarioId
    profileKey = $ActualProfileKey
    powerShellVersion = $PSVersionTable.PSVersion.ToString()
    targetFramework = $ActualTargetFramework
    platform = 'windows'
    architecture = 'x64'
    inventoryFingerprint = $InventoryFingerprint
    importOrder = @($Definition.modules)
    dllPickleTiming = [string]$Definition.timing
    expectedTokenAudiences = @(
        Get-DLLPickleOrdinalSequence -InputObject @(
            foreach ($Provider in @($Definition.providers)) {
                switch ($Provider) {
                    'graph' { 'https://graph.microsoft.com' }
                    'exo' { 'https://outlook.office365.com' }
                    'az' { 'https://management.azure.com' }
                    'teams' { 'https://api.spaces.skype.com' }
                }
            }
        ) -Unique
    )
    status = 'failed'
    writesPerformed = $false
    probes = @()
    snapshots = @()
    errorType = $null
}
$ConnectedProviders = [System.Collections.Generic.List[string]]::new()
try {
    if ($Definition.timing -eq 'dllpickle-first') { Import-DLLPickleBundle }
    Import-ExactModuleSet -Names @($Definition.modules)
    if ($Definition.timing -eq 'module-first') { Import-DLLPickleBundle }
    $Result.snapshots += [ordered]@{ stage = 'before-authentication'; assemblies = @(Get-SanitizedAssemblySnapshot) }
    foreach ($Provider in @($Definition.providers)) {
        Connect-Provider -Provider $Provider -SubscriptionId $AzureSubscriptionId
        $ConnectedProviders.Add($Provider)
    }
    $Result.snapshots += [ordered]@{ stage = 'after-connection'; assemblies = @(Get-SanitizedAssemblySnapshot) }
    $Result.probes = @(
        foreach ($ProbeId in @($Definition.probes)) { Invoke-DLLPickleAuthenticatedReadProbe -ProbeId $ProbeId }
    )
    $Result.snapshots += [ordered]@{ stage = 'after-read-probe'; assemblies = @(Get-SanitizedAssemblySnapshot) }
    if (@($Result.probes | Where-Object status -ne 'passed').Count -eq 0) {
        $Result.status = 'passed'
    }
} catch {
    $Result.errorType = $_.Exception.GetType().FullName
} finally {
    for ($ProviderIndex = $ConnectedProviders.Count - 1; $ProviderIndex -ge 0; $ProviderIndex--) {
        Disconnect-Provider -Provider $ConnectedProviders[$ProviderIndex]
    }
}

$OutputDirectory = Split-Path -Path $OutputPath -Parent
if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
}
[pscustomobject]$Result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
if ($Result.status -ne 'passed') {
    throw "Authenticated scenario '$ScenarioId' failed. Sanitized error type: '$($Result.errorType)'. See '$OutputPath'."
}
[pscustomobject]$Result
