BeforeAll {
    Set-Location -Path $PSScriptRoot
    $script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:BuiltModuleManifestPath = Join-Path $script:ProjectRoot 'module\DLLPickle\DLLPickle.psd1'
    $script:ScenarioOutputRoot = Join-Path -Path $script:ProjectRoot -ChildPath 'artifacts\testOutput\IssueRepro'
    $null = New-Item -Path $script:ScenarioOutputRoot -ItemType Directory -Force
    . (Join-Path $PSScriptRoot 'Invoke-DLLPickleScenario.ps1')

    function Initialize-Issue242SyntheticModule {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$RootPath,

            [Parameter(Mandatory)]
            [string]$Name
        )

        $ModuleDirectory = Join-Path -Path $RootPath -ChildPath ([IO.Path]::Combine($Name, '1.0.0'))
        $null = New-Item -Path $ModuleDirectory -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path $ModuleDirectory "$Name.psm1") -Value '' -Encoding UTF8
        New-ModuleManifest `
            -Path (Join-Path $ModuleDirectory "$Name.psd1") `
            -RootModule "$Name.psm1" `
            -ModuleVersion '1.0.0' `
            -ErrorAction Stop
    }
}

Describe 'Issue 242 background assembly event regression' -Tag 'Integration', 'Issue242' {
    BeforeEach {
        $script:SyntheticModuleRoot = Join-Path -Path $TestDrive -ChildPath 'Modules'
        Initialize-Issue242SyntheticModule -RootPath $script:SyntheticModuleRoot -Name 'Az.Storage'
        Initialize-Issue242SyntheticModule -RootPath $script:SyntheticModuleRoot -Name 'ExchangeOnlineManagement'
    }

    It 'survives an assembly load raised from a thread without a PowerShell runspace' {
        $BackgroundLoadStep = @'
Add-Type -TypeDefinition @"
using System;
using System.Reflection;
using System.Reflection.Emit;
using System.Threading.Tasks;

public static class DLLPickleIssue242Probe {
    public static Task LoadOnWorkerThreadAsync() {
        return Task.Run(() => {
            var name = new AssemblyName("DLLPickle.Issue242." + Guid.NewGuid().ToString("N"));
            AssemblyBuilder.DefineDynamicAssembly(name, AssemblyBuilderAccess.Run);
        });
    }
}
"@
[DLLPickleIssue242Probe]::LoadOnWorkerThreadAsync().GetAwaiter().GetResult()
'BACKGROUND_ASSEMBLY_LOAD_OK'
'@

        $Result = Invoke-DLLPickleScenario `
            -Name 'Issue242-BackgroundAssemblyLoad' `
            -ModuleManifestPath $script:BuiltModuleManifestPath `
            -AdditionalModulePath $script:SyntheticModuleRoot `
            -OutputPath (Join-Path $script:ScenarioOutputRoot 'Issue242-BackgroundAssemblyLoad.json') `
            -TimeoutSeconds 30 `
            -Step @(
                @{
                    Name = 'Import DLLPickle'
                    Script = 'Import-Module $ScenarioModuleManifestPath -Force; Import-DPLibrary -SuppressLogo'
                }
                @{
                    Name = 'Load assembly on worker thread'
                    Script = $BackgroundLoadStep
                }
            )

        $Result.Success | Should -BeTrue
        $Result.ProcessExitCode | Should -Be 0
        ($Result.ProcessOutput -join [Environment]::NewLine) | Should -Not -Match 'PSInvalidOperationException|There is no Runspace available'
        $BackgroundStep = $Result.Steps | Where-Object Name -eq 'Load assembly on worker thread'
        $BackgroundStep.Success | Should -BeTrue
        ($BackgroundStep.Output -join [Environment]::NewLine) | Should -Match 'BACKGROUND_ASSEMBLY_LOAD_OK'
    }
}
