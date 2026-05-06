BeforeAll {
    Set-Location -Path $PSScriptRoot
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $BuiltModuleManifestPath = Join-Path $ProjectRoot 'module\DLLPickle\DLLPickle.psd1'
    $ScenarioOutputRoot = Join-Path -Path $ProjectRoot -ChildPath 'artifacts\testOutput\IssueRepro'
    $null = New-Item -Path $ScenarioOutputRoot -ItemType Directory -Force
    . (Join-Path $PSScriptRoot 'Invoke-DLLPickleScenario.ps1')

    function Initialize-Issue156SyntheticModule {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$RootPath,

            [Parameter(Mandatory)]
            [ValidateSet('ExchangeOnlineManagement', 'Microsoft.Graph.Authentication')]
            [string]$Name,

            [Parameter(Mandatory)]
            [string]$Version
        )

        $ModuleDirectory = Join-Path -Path $RootPath -ChildPath ([System.IO.Path]::Combine($Name, $Version))
        $null = New-Item -Path $ModuleDirectory -ItemType Directory -Force
        $ModuleFile = Join-Path -Path $ModuleDirectory -ChildPath "$Name.psm1"
        $ManifestFile = Join-Path -Path $ModuleDirectory -ChildPath "$Name.psd1"

        if ($Name -eq 'ExchangeOnlineManagement') {
            @'
function Test-DLLPickleSyntheticAssemblyVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [version]$MinimumVersion
    )

    $LoadedAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq $Name } |
        Sort-Object -Property { $_.GetName().Version } -Descending |
        Select-Object -First 1

    return $LoadedAssembly -and $LoadedAssembly.GetName().Version -ge $MinimumVersion
}

if (-not $global:DllPickleSyntheticImportOrder) {
    $global:DllPickleSyntheticImportOrder = [System.Collections.Generic.List[string]]::new()
}

$global:DllPickleSyntheticImportOrder.Add('ExchangeOnlineManagement')

function Connect-ExchangeOnline {
    [CmdletBinding()]
    param()

    if (($global:DllPickleSyntheticImportOrder -contains 'Microsoft.Graph.Authentication') -and
        -not (Test-DLLPickleSyntheticAssemblyVersion -Name 'Microsoft.Identity.Client.Broker' -MinimumVersion ([version]'4.83.3.0'))) {
        throw [System.MissingMethodException]::new('Method not found: Microsoft.Identity.Client.Broker.BrokerExtension.WithBroker(Microsoft.Identity.Client.PublicClientApplicationBuilder, Microsoft.Identity.Client.BrokerOptions).')
    }

    [PSCustomObject]@{ Connected = $true; Module = 'ExchangeOnlineManagement' }
}

Export-ModuleMember -Function Connect-ExchangeOnline
'@ | Set-Content -LiteralPath $ModuleFile -Encoding UTF8
        } else {
            @'
function Test-DLLPickleSyntheticAssemblyVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [version]$MinimumVersion
    )

    $LoadedAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq $Name } |
        Sort-Object -Property { $_.GetName().Version } -Descending |
        Select-Object -First 1

    return $LoadedAssembly -and $LoadedAssembly.GetName().Version -ge $MinimumVersion
}

if (-not $global:DllPickleSyntheticImportOrder) {
    $global:DllPickleSyntheticImportOrder = [System.Collections.Generic.List[string]]::new()
}

if (($global:DllPickleSyntheticImportOrder -contains 'ExchangeOnlineManagement') -and
    -not (Test-DLLPickleSyntheticAssemblyVersion -Name 'Azure.Core' -MinimumVersion ([version]'1.51.1.0'))) {
    throw [System.TypeLoadException]::new("Method 'GetTokenAsync' in type 'Microsoft.Graph.PowerShell.Authentication.Core.Utilities.UserProvidedTokenCredential' from assembly 'Microsoft.Graph.Authentication.Core' does not have an implementation.")
}

$global:DllPickleSyntheticImportOrder.Add('Microsoft.Graph.Authentication')

function Connect-MgGraph {
    [CmdletBinding()]
    param()

    [PSCustomObject]@{ Connected = $true; Module = 'Microsoft.Graph.Authentication' }
}

Export-ModuleMember -Function Connect-MgGraph
'@ | Set-Content -LiteralPath $ModuleFile -Encoding UTF8
        }

        New-ModuleManifest -Path $ManifestFile -RootModule "$Name.psm1" -ModuleVersion $Version -FunctionsToExport '*' -ErrorAction Stop
    }
}

Describe 'Issue 156 Graph and ExchangeOnlineManagement reproduction' -Tag 'Integration', 'Issue156' {
    BeforeEach {
        $SyntheticModuleRoot = Join-Path -Path $TestDrive -ChildPath 'Modules'
        Initialize-Issue156SyntheticModule -RootPath $SyntheticModuleRoot -Name 'ExchangeOnlineManagement' -Version '3.9.2'
        Initialize-Issue156SyntheticModule -RootPath $SyntheticModuleRoot -Name 'Microsoft.Graph.Authentication' -Version '2.36.1'
    }

    It 'captures a Graph import failure after ExchangeOnlineManagement is loaded first without DLLPickle preloading' {
        $Result = Invoke-DLLPickleScenario -Name 'Issue156-ExchangeThenGraph-Synthetic' `
            -ModuleManifestPath $BuiltModuleManifestPath `
            -AdditionalModulePath $SyntheticModuleRoot `
            -OutputPath (Join-Path $ScenarioOutputRoot 'Issue156-ExchangeThenGraph-Synthetic.json') `
            -Step @(
                @{ Name = 'Import ExchangeOnlineManagement'; Script = 'Import-Module ExchangeOnlineManagement -Force' }
                @{ Name = 'Import Microsoft.Graph.Authentication'; Script = 'Import-Module Microsoft.Graph.Authentication -Force' }
            )

        $Result.Success | Should -BeFalse
        $GraphStep = $Result.Steps | Where-Object Name -eq 'Import Microsoft.Graph.Authentication'
        $GraphStep.Success | Should -BeFalse
        $GraphStep.Error.Message | Should -Match 'GetTokenAsync'
    }

    It 'prevents the Graph import failure after ExchangeOnlineManagement is loaded first' {
        $Result = Invoke-DLLPickleScenario -Name 'Issue156-ExchangeThenGraph-Protected-Synthetic' `
            -ModuleManifestPath $BuiltModuleManifestPath `
            -AdditionalModulePath $SyntheticModuleRoot `
            -OutputPath (Join-Path $ScenarioOutputRoot 'Issue156-ExchangeThenGraph-Protected-Synthetic.json') `
            -Step @(
                @{ Name = 'Import DLLPickle'; Script = 'Import-Module $ScenarioModuleManifestPath -Force; Import-DPLibrary -SuppressLogo -ShowLoaderExceptions' }
                @{ Name = 'Import ExchangeOnlineManagement'; Script = 'Import-Module ExchangeOnlineManagement -Force' }
                @{ Name = 'Import Microsoft.Graph.Authentication'; Script = 'Import-Module Microsoft.Graph.Authentication -Force' }
            )

        $Result.Success | Should -BeTrue
        $GraphStep = $Result.Steps | Where-Object Name -eq 'Import Microsoft.Graph.Authentication'
        $GraphStep.Success | Should -BeTrue
        $FinalAssemblies = @($Result.Steps | Select-Object -Last 1 -ExpandProperty AssembliesAfter)
        $AzureCore = $FinalAssemblies | Where-Object Name -eq 'Azure.Core' | Select-Object -First 1
        ([version]$AzureCore.Version) | Should -Be ([version]'1.51.1.0')
    }

    It 'captures a lazy ExchangeOnlineManagement broker failure after Graph is loaded first without DLLPickle preloading' {
        $Result = Invoke-DLLPickleScenario -Name 'Issue156-GraphThenExchangeConnect-Synthetic' `
            -ModuleManifestPath $BuiltModuleManifestPath `
            -AdditionalModulePath $SyntheticModuleRoot `
            -OutputPath (Join-Path $ScenarioOutputRoot 'Issue156-GraphThenExchangeConnect-Synthetic.json') `
            -Step @(
                @{ Name = 'Import Microsoft.Graph.Authentication'; Script = 'Import-Module Microsoft.Graph.Authentication -Force' }
                @{ Name = 'Import ExchangeOnlineManagement'; Script = 'Import-Module ExchangeOnlineManagement -Force' }
                @{ Name = 'Connect ExchangeOnlineManagement'; Script = 'Connect-ExchangeOnline' }
            )

        $Result.Success | Should -BeFalse
        $ConnectStep = $Result.Steps | Where-Object Name -eq 'Connect ExchangeOnlineManagement'
        $ConnectStep.Success | Should -BeFalse
        $ConnectStep.Error.Message | Should -Match 'WithBroker'
    }

    It 'prevents the lazy ExchangeOnlineManagement broker failure after Graph is loaded first' {
        $Result = Invoke-DLLPickleScenario -Name 'Issue156-GraphThenExchangeConnect-Protected-Synthetic' `
            -ModuleManifestPath $BuiltModuleManifestPath `
            -AdditionalModulePath $SyntheticModuleRoot `
            -OutputPath (Join-Path $ScenarioOutputRoot 'Issue156-GraphThenExchangeConnect-Protected-Synthetic.json') `
            -Step @(
                @{ Name = 'Import DLLPickle'; Script = 'Import-Module $ScenarioModuleManifestPath -Force; Import-DPLibrary -SuppressLogo -ShowLoaderExceptions' }
                @{ Name = 'Import Microsoft.Graph.Authentication'; Script = 'Import-Module Microsoft.Graph.Authentication -Force' }
                @{ Name = 'Import ExchangeOnlineManagement'; Script = 'Import-Module ExchangeOnlineManagement -Force' }
                @{ Name = 'Connect ExchangeOnlineManagement'; Script = 'Connect-ExchangeOnline' }
            )

        $Result.Success | Should -BeTrue
        $ConnectStep = $Result.Steps | Where-Object Name -eq 'Connect ExchangeOnlineManagement'
        $ConnectStep.Success | Should -BeTrue
        $FinalAssemblies = @($Result.Steps | Select-Object -Last 1 -ExpandProperty AssembliesAfter)
        $Broker = $FinalAssemblies | Where-Object Name -eq 'Microsoft.Identity.Client.Broker' | Select-Object -First 1
        ([version]$Broker.Version) | Should -BeGreaterOrEqual ([version]'4.83.3.0')
    }

    It 'runs the live Graph and ExchangeOnlineManagement import matrix when explicitly enabled' -Tag 'LiveRepro' -Skip:($env:DLLPICKLE_RUN_LIVE_REPRO -ne '1') {
        $Result = Invoke-DLLPickleScenario -Name 'Issue156-Live-ExchangeThenGraph' `
            -ModuleManifestPath $BuiltModuleManifestPath `
            -OutputPath (Join-Path $ScenarioOutputRoot 'Issue156-Live-ExchangeThenGraph.json') `
            -Step @(
                @{ Name = 'Import DLLPickle'; Script = 'Import-Module $ScenarioModuleManifestPath -Force; Import-DPLibrary -SuppressLogo -ShowLoaderExceptions' }
                @{ Name = 'Import ExchangeOnlineManagement'; Script = 'Import-Module ExchangeOnlineManagement -Force' }
                @{ Name = 'Import Microsoft.Graph.Authentication'; Script = 'Import-Module Microsoft.Graph.Authentication -Force' }
            )

        $Result.Success | Should -BeTrue
    }
}

