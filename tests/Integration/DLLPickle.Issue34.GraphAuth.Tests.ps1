BeforeAll {
    Set-Location -Path $PSScriptRoot
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $BuiltModuleManifestPath = Join-Path $ProjectRoot 'module\DLLPickle\DLLPickle.psd1'
    $ScenarioOutputRoot = Join-Path -Path $ProjectRoot -ChildPath 'artifacts\testOutput\IssueRepro'
    $null = New-Item -Path $ScenarioOutputRoot -ItemType Directory -Force
    . (Join-Path $PSScriptRoot 'Invoke-DLLPickleScenario.ps1')

    function Initialize-Issue34SyntheticGraphModule {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$RootPath
        )

        $ModuleName = 'Microsoft.Graph.Authentication'
        $ModuleVersion = '2.38.0'
        $ModuleDirectory = Join-Path -Path $RootPath -ChildPath ([System.IO.Path]::Combine($ModuleName, $ModuleVersion))
        $null = New-Item -Path $ModuleDirectory -ItemType Directory -Force
        $ModuleFile = Join-Path -Path $ModuleDirectory -ChildPath "$ModuleName.psm1"
        $ManifestFile = Join-Path -Path $ModuleDirectory -ChildPath "$ModuleName.psd1"

        @'
function Connect-MgGraph {
    [CmdletBinding()]
    param()

    $MsalAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'Microsoft.Identity.Client' } |
        Select-Object -First 1
    $IdentityAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'Microsoft.IdentityModel.Abstractions' } |
        Select-Object -First 1

    $BuilderType = if ($MsalAssembly) {
        $MsalAssembly.GetType('Microsoft.Identity.Client.BaseAbstractApplicationBuilder`1')
    }
    $IdentityLoggerType = if ($IdentityAssembly) {
        $IdentityAssembly.GetType('Microsoft.IdentityModel.Abstractions.IIdentityLogger')
    }
    $WithIdentityLogger = if ($BuilderType -and $IdentityLoggerType) {
        $BuilderType.GetMethods() |
            Where-Object {
                $Parameters = @($_.GetParameters())
                $_.Name -eq 'WithLogging' -and
                $Parameters.Count -eq 2 -and
                $Parameters[0].ParameterType -eq $IdentityLoggerType -and
                $Parameters[1].ParameterType -eq [bool]
            } |
            Select-Object -First 1
    }

    if (-not $WithIdentityLogger) {
        throw [System.MissingMethodException]::new("Method not found: BaseAbstractApplicationBuilder.WithLogging(Microsoft.IdentityModel.Abstractions.IIdentityLogger, Boolean).")
    }

    [PSCustomObject]@{
        Connected = $true
        Method = 'WithLogging(IIdentityLogger, Boolean)'
    }
}

Export-ModuleMember -Function Connect-MgGraph
'@ | Set-Content -LiteralPath $ModuleFile -Encoding UTF8

        New-ModuleManifest -Path $ManifestFile -RootModule "$ModuleName.psm1" -ModuleVersion $ModuleVersion -FunctionsToExport 'Connect-MgGraph' -ErrorAction Stop
    }
}

Describe 'Issue 34 Microsoft Graph authentication API regression' -Tag 'Integration', 'Issue34' {
    BeforeEach {
        $SyntheticModuleRoot = Join-Path -Path $TestDrive -ChildPath 'Modules'
        Initialize-Issue34SyntheticGraphModule -RootPath $SyntheticModuleRoot
    }

    It 'reproduces the missing Graph authentication API without DLLPickle preloading' {
        $ScenarioParameters = @{
            Name = 'Issue34-GraphAuthentication-Unprotected-Synthetic'
            ModuleManifestPath = $BuiltModuleManifestPath
            AdditionalModulePath = $SyntheticModuleRoot
            OutputPath = Join-Path $ScenarioOutputRoot 'Issue34-GraphAuthentication-Unprotected-Synthetic.json'
            Step = @(
                @{ Name = 'Import Microsoft.Graph.Authentication'; Script = 'Import-Module Microsoft.Graph.Authentication -Force' }
                @{ Name = 'Connect Microsoft Graph'; Script = 'Connect-MgGraph' }
            )
        }
        $Result = Invoke-DLLPickleScenario @ScenarioParameters

        $Result.Success | Should -BeFalse
        $ConnectStep = $Result.Steps | Where-Object Name -EQ 'Connect Microsoft Graph'
        $ConnectStep.Success | Should -BeFalse
        $ConnectStep.Error.ExceptionType | Should -Be 'System.MissingMethodException'
        $ConnectStep.Error.Message | Should -Match 'WithLogging.*IIdentityLogger'
    }

    It 'preserves the Graph authentication API and one default ALC after DLLPickle preloading' {
        $ScenarioParameters = @{
            Name = 'Issue34-GraphAuthentication-Protected-Synthetic'
            ModuleManifestPath = $BuiltModuleManifestPath
            AdditionalModulePath = $SyntheticModuleRoot
            OutputPath = Join-Path $ScenarioOutputRoot 'Issue34-GraphAuthentication-Protected-Synthetic.json'
            Step = @(
                @{ Name = 'Import DLLPickle'; Script = 'Import-Module $ScenarioModuleManifestPath -Force; Import-DPLibrary -SuppressLogo -ShowLoaderExceptions' }
                @{ Name = 'Import Microsoft.Graph.Authentication'; Script = 'Import-Module Microsoft.Graph.Authentication -Force' }
                @{ Name = 'Connect Microsoft Graph'; Script = 'Connect-MgGraph' }
            )
        }
        $Result = Invoke-DLLPickleScenario @ScenarioParameters

        $Result.Success | Should -BeTrue
        $ConnectStep = $Result.Steps | Where-Object Name -EQ 'Connect Microsoft Graph'
        $ConnectStep.Success | Should -BeTrue
        ($ConnectStep.Output -join [Environment]::NewLine) | Should -Match 'WithLogging\(IIdentityLogger, Boolean\)'

        $FinalAssemblies = @($ConnectStep.AssembliesAfter)
        $MsalAssembly = $FinalAssemblies | Where-Object Name -EQ 'Microsoft.Identity.Client' | Select-Object -First 1
        $IdentityAssembly = $FinalAssemblies | Where-Object Name -EQ 'Microsoft.IdentityModel.Abstractions' | Select-Object -First 1
        $MsalAssembly | Should -Not -BeNullOrEmpty
        $IdentityAssembly | Should -Not -BeNullOrEmpty
        $MsalAssembly.LoadContext | Should -Be 'Default'
        $IdentityAssembly.LoadContext | Should -Be 'Default'
        $MsalAssembly.Location | Should -Match ([regex]::Escape($Result.Host.SelectedBundlePath))
        $IdentityAssembly.Location | Should -Match ([regex]::Escape($Result.Host.SelectedBundlePath))
    }
}
