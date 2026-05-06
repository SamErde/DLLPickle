BeforeAll {
    Set-Location -Path $PSScriptRoot
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $BuiltModuleManifestPath = Join-Path $ProjectRoot 'module\DLLPickle\DLLPickle.psd1'
    $ScenarioOutputRoot = Join-Path -Path $ProjectRoot -ChildPath 'artifacts\testOutput\IssueRepro'
    $null = New-Item -Path $ScenarioOutputRoot -ItemType Directory -Force
    . (Join-Path $PSScriptRoot 'Invoke-DLLPickleScenario.ps1')

    function Initialize-Issue174SyntheticModule {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$RootPath,

            [Parameter(Mandatory)]
            [ValidateSet('Az.Storage', 'ExchangeOnlineManagement')]
            [string]$Name,

            [Parameter(Mandatory)]
            [string]$Version
        )

        $ModuleDirectory = Join-Path -Path $RootPath -ChildPath ([System.IO.Path]::Combine($Name, $Version))
        $null = New-Item -Path $ModuleDirectory -ItemType Directory -Force
        $ModuleFile = Join-Path -Path $ModuleDirectory -ChildPath "$Name.psm1"
        $ManifestFile = Join-Path -Path $ModuleDirectory -ChildPath "$Name.psd1"

        if ($Name -eq 'Az.Storage') {
            @'
$global:DllPickleSyntheticODataCore = [PSCustomObject]@{
    Name = 'Microsoft.OData.Core'
    Version = '7.6.4.0'
    Source = 'Az.Storage'
}
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

function Connect-ExchangeOnline {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$ManagedIdentity,

        [Parameter()]
        [string]$Organization
    )

    [PSCustomObject]@{
        Connected = $true
        ManagedIdentity = [bool]$ManagedIdentity
        Organization = $Organization
    }
}

function Get-EXOMailbox {
    [CmdletBinding()]
    param()

    if (-not (Test-DLLPickleSyntheticAssemblyVersion -Name 'Microsoft.OData.Core' -MinimumVersion ([version]'7.22.0.0'))) {
        throw [System.IO.FileNotFoundException]::new("Could not load file or assembly 'Microsoft.OData.Core, Version=7.22.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35'. Could not find or load a specific file. (0x80131621)")
    }

    [PSCustomObject]@{ DisplayName = 'Synthetic mailbox' }
}

Export-ModuleMember -Function Connect-ExchangeOnline, Get-EXOMailbox
'@ | Set-Content -LiteralPath $ModuleFile -Encoding UTF8
        }

        New-ModuleManifest -Path $ManifestFile -RootModule "$Name.psm1" -ModuleVersion $Version -FunctionsToExport '*' -ErrorAction Stop
    }
}

Describe 'Issue 174 Az.Storage and ExchangeOnlineManagement OData reproduction' -Tag 'Integration', 'Issue174' {
    BeforeEach {
        $SyntheticModuleRoot = Join-Path -Path $TestDrive -ChildPath 'Modules'
        Initialize-Issue174SyntheticModule -RootPath $SyntheticModuleRoot -Name 'Az.Storage' -Version '9.6.0'
        Initialize-Issue174SyntheticModule -RootPath $SyntheticModuleRoot -Name 'ExchangeOnlineManagement' -Version '3.9.2'
    }

    It 'captures an OData lazy-load failure after Az.Storage and ExchangeOnlineManagement imports without DLLPickle preloading' {
        $Result = Invoke-DLLPickleScenario -Name 'Issue174-AzStorageThenEXO-Synthetic' `
            -ModuleManifestPath $BuiltModuleManifestPath `
            -AdditionalModulePath $SyntheticModuleRoot `
            -OutputPath (Join-Path $ScenarioOutputRoot 'Issue174-AzStorageThenEXO-Synthetic.json') `
            -Step @(
                @{ Name = 'Import Az.Storage'; Script = 'Import-Module Az.Storage -Force' }
                @{ Name = 'Import ExchangeOnlineManagement'; Script = 'Import-Module ExchangeOnlineManagement -Force' }
                @{ Name = 'Connect ExchangeOnlineManagement'; Script = 'Connect-ExchangeOnline -ManagedIdentity -Organization synthetic.example' }
                @{ Name = 'Get EXO Mailbox'; Script = 'Get-EXOMailbox' }
            )

        $Result.Success | Should -BeFalse
        $MailboxStep = $Result.Steps | Where-Object Name -eq 'Get EXO Mailbox'
        $MailboxStep.Success | Should -BeFalse
        $MailboxStep.Error.Message | Should -Match 'Microsoft.OData.Core'
    }

    It 'keeps the OData lazy-load conflict visible when DLLPickle preloads supported libraries' {
        $Result = Invoke-DLLPickleScenario -Name 'Issue174-AzStorageThenEXO-DLLPickle-Synthetic' `
            -ModuleManifestPath $BuiltModuleManifestPath `
            -AdditionalModulePath $SyntheticModuleRoot `
            -OutputPath (Join-Path $ScenarioOutputRoot 'Issue174-AzStorageThenEXO-DLLPickle-Synthetic.json') `
            -Step @(
                @{ Name = 'Import DLLPickle'; Script = 'Import-Module $ScenarioModuleManifestPath -Force; Import-DPLibrary -SuppressLogo -ShowLoaderExceptions' }
                @{ Name = 'Import Az.Storage'; Script = 'Import-Module Az.Storage -Force' }
                @{ Name = 'Import ExchangeOnlineManagement'; Script = 'Import-Module ExchangeOnlineManagement -Force' }
                @{ Name = 'Connect ExchangeOnlineManagement'; Script = 'Connect-ExchangeOnline -ManagedIdentity -Organization synthetic.example' }
                @{ Name = 'Get EXO Mailbox'; Script = 'Get-EXOMailbox' }
            )

        $Result.Success | Should -BeFalse
        $ImportDPLibraryStep = $Result.Steps | Where-Object Name -eq 'Import DLLPickle'
        $LoadedODataCore = @($ImportDPLibraryStep.AssembliesAfter) | Where-Object Name -eq 'Microsoft.OData.Core'
        $LoadedODataCore | Should -BeNullOrEmpty
        $MailboxStep = $Result.Steps | Where-Object Name -eq 'Get EXO Mailbox'
        $MailboxStep.Success | Should -BeFalse
        $MailboxStep.Error.Message | Should -Match 'Microsoft.OData.Core'
    }

    It 'runs the live Az.Storage and ExchangeOnlineManagement import probe when explicitly enabled' -Tag 'LiveRepro' -Skip:($env:DLLPICKLE_RUN_LIVE_REPRO -ne '1') {
        $Result = Invoke-DLLPickleScenario -Name 'Issue174-Live-AzStorageThenEXO' `
            -ModuleManifestPath $BuiltModuleManifestPath `
            -OutputPath (Join-Path $ScenarioOutputRoot 'Issue174-Live-AzStorageThenEXO.json') `
            -Step @(
                @{ Name = 'Import DLLPickle'; Script = 'Import-Module $ScenarioModuleManifestPath -Force; Import-DPLibrary -SuppressLogo -ShowLoaderExceptions' }
                @{ Name = 'Import Az.Storage'; Script = 'Import-Module Az.Storage -Force' }
                @{ Name = 'Import ExchangeOnlineManagement'; Script = 'Import-Module ExchangeOnlineManagement -Force' }
            )

        $Result.Success | Should -BeTrue
    }
}

