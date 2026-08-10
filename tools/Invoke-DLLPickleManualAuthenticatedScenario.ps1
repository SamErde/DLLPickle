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
    [Parameter()][string]$AzureSubscriptionId = $env:DLLPICKLE_MANUAL_AZURE_SUBSCRIPTION_ID
)

$ErrorActionPreference = 'Stop'

function ConvertTo-CollapsedAssetPath {
    param([Parameter(Mandatory)][string]$Path)

    $Segments = [System.Collections.Generic.List[string]]::new()
    foreach ($Segment in @($Path -split '/')) {
        if ([string]::IsNullOrWhiteSpace($Segment) -or $Segment -eq '.') { continue }
        if ($Segment -eq '..') {
            if ($Segments.Count -eq 0) { throw "Asset path '$Path' escapes its root." }
            $Segments.RemoveAt($Segments.Count - 1)
            continue
        }
        $Segments.Add($Segment)
    }
    $Segments -join '/'
}

function ConvertTo-ManualEvidencePath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ModuleCacheRoot,
        [Parameter(Mandatory)][string]$DLLPickleRoot,
        [Parameter(Mandatory)][string]$RuntimeRoot
    )

    $NormalizedPath = $Path.Replace('\', '/').TrimEnd('/')
    $Roots = [ordered]@{
        upstream = $ModuleCacheRoot.Replace('\', '/').TrimEnd('/')
        dllpickle = $DLLPickleRoot.Replace('\', '/').TrimEnd('/')
        runtime = $RuntimeRoot.Replace('\', '/').TrimEnd('/')
    }
    foreach ($RootEntry in $Roots.GetEnumerator()) {
        if ($NormalizedPath -eq $RootEntry.Value) { return "$($RootEntry.Key):." }
        if ($NormalizedPath.StartsWith("$($RootEntry.Value)/", [System.StringComparison]::OrdinalIgnoreCase)) {
            $Relative = $NormalizedPath.Substring($RootEntry.Value.Length + 1)
            return '{0}:{1}' -f $RootEntry.Key, (ConvertTo-CollapsedAssetPath -Path $Relative)
        }
    }
    throw "Authenticated evidence path '$Path' is outside the upstream, DLLPickle, and exact runtime roots."
}

function Get-SanitizedAssemblySnapshot {
    $Rows = @(& $SnapshotHelper -PolicyPath $ResolvedPolicyPath)
    @(
        foreach ($Row in $Rows) {
            [ordered]@{
                name = [string]$Row.Name
                version = [string]$Row.Version
                sha256 = ([string]$Row.Sha256).ToLowerInvariant()
                selectedAsset = ConvertTo-ManualEvidencePath -Path ([string]$Row.Path) -ModuleCacheRoot $ModuleCacheRoot -DLLPickleRoot $DLLPickleRoot -RuntimeRoot $PSHOME
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
    Import-DPLibrary -SuppressLogo -ErrorAction Stop | Out-Null
}

function Connect-Provider {
    param(
        [Parameter(Mandatory)][ValidateSet('graph', 'exo', 'az', 'teams')][string]$Provider,
        [Parameter()][string]$SubscriptionId
    )

    switch ($Provider) {
        'graph' {
            Connect-MgGraph -Scopes 'User.Read' -ContextScope Process -NoWelcome -ErrorAction Stop | Out-Null
        }
        'exo' {
            Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop | Out-Null
        }
        'az' {
            Connect-AzAccount -Scope Process -ErrorAction Stop | Out-Null
            if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
                Set-AzContext -SubscriptionId $SubscriptionId -Scope Process -ErrorAction Stop | Out-Null
            }
        }
        'teams' {
            Connect-MicrosoftTeams -ErrorAction Stop | Out-Null
        }
    }
}

function Disconnect-Provider {
    param([Parameter(Mandatory)][ValidateSet('graph', 'exo', 'az', 'teams')][string]$Provider)

    try {
        switch ($Provider) {
            'graph' { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null }
            'exo' { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null }
            'az' { Clear-AzContext -Scope Process -Force -ErrorAction SilentlyContinue | Out-Null }
            'teams' { Disconnect-MicrosoftTeams -ErrorAction SilentlyContinue | Out-Null }
        }
    } catch {
        # Cleanup failures must not replace the sanitized scenario result.
        Write-Verbose "Provider cleanup for '$Provider' did not complete."
    }
}

function Invoke-ReadProbe {
    param([Parameter(Mandatory)][string]$ProbeId)

    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        switch ($ProbeId) {
            'graph-context' {
                if (-not (Get-MgContext -ErrorAction Stop)) { throw 'Graph context was not established.' }
            }
            'graph-me-read' {
                Invoke-MgGraphRequest -Method GET -Uri '/v1.0/me?$select=id' -ErrorAction Stop | Out-Null
            }
            'exo-mailbox-read' {
                if (@(Get-EXOMailbox -ResultSize 1 -ErrorAction Stop).Count -eq 0) { throw 'Exchange mailbox read returned no object.' }
            }
            'az-context' {
                if (-not (Get-AzContext -ErrorAction Stop)) { throw 'Azure context was not established.' }
            }
            'az-resource-read' {
                if (@(Get-AzResource -ErrorAction Stop | Select-Object -First 1).Count -eq 0) { throw 'Azure resource read returned no object.' }
            }
            'az-storage-account-read' {
                if (@(Get-AzStorageAccount -ErrorAction Stop | Select-Object -First 1).Count -eq 0) { throw 'Azure storage-account read returned no object.' }
            }
            'teams-tenant-read' {
                if (-not (Get-CsTenant -ErrorAction Stop)) { throw 'Teams tenant read returned no object.' }
            }
            default { throw "Unsupported authenticated probe identifier '$ProbeId'." }
        }
        $Stopwatch.Stop()
        [ordered]@{
            probeId = $ProbeId
            executed = $true
            status = 'passed'
            durationMilliseconds = [long]$Stopwatch.ElapsedMilliseconds
            writesPerformed = $false
            errorType = $null
        }
    } catch {
        $Stopwatch.Stop()
        [ordered]@{
            probeId = $ProbeId
            executed = $true
            status = 'failed'
            durationMilliseconds = [long]$Stopwatch.ElapsedMilliseconds
            writesPerformed = $false
            errorType = $_.Exception.GetType().FullName
        }
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
    importOrder = @($Definition.modules)
    dllPickleTiming = [string]$Definition.timing
    expectedTokenAudiences = @(
        foreach ($Provider in @($Definition.providers)) {
            switch ($Provider) {
                'graph' { 'https://graph.microsoft.com' }
                'exo' { 'https://outlook.office365.com' }
                'az' { 'https://management.azure.com' }
                'teams' { 'https://api.spaces.skype.com' }
            }
        }
    ) | Sort-Object -Unique
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
    $Result.snapshots += [ordered]@{ stage = 'before-authentication'; assemblies = @(Get-SanitizedAssemblySnapshot) }
    foreach ($Provider in @($Definition.providers)) {
        Connect-Provider -Provider $Provider -SubscriptionId $AzureSubscriptionId
        $ConnectedProviders.Add($Provider)
    }
    $Result.snapshots += [ordered]@{ stage = 'after-connection'; assemblies = @(Get-SanitizedAssemblySnapshot) }
    if ($Definition.timing -eq 'module-first') { Import-DLLPickleBundle }
    $Result.probes = @(
        foreach ($ProbeId in @($Definition.probes)) { Invoke-ReadProbe -ProbeId $ProbeId }
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
