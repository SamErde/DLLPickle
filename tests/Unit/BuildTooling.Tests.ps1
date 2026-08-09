BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ToolPolicyPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'build/build-tool-versions.json'
    $script:ToolingScriptPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'build/DLLPickle.Tooling.ps1'
    $script:BuildWrapperPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'tools/Invoke-DLLPickleBuild.ps1'
    $script:BootstrapPath = Join-Path -Path $script:RepositoryRoot -ChildPath '.github/ci-scripts/Actions_Bootstrap.ps1'

    if (Test-Path -LiteralPath $script:ToolingScriptPath) {
        . $script:ToolingScriptPath
    }
}

Describe 'Deterministic build tooling' -Tag 'Unit' {
    It 'ships a non-runtime policy with exact versions for every build tool' {
        $script:ToolPolicyPath | Should -Exist

        $policy = Get-Content -LiteralPath $script:ToolPolicyPath -Raw | ConvertFrom-Json
        $policy.schemaVersion | Should -Be 1
        @($policy.modules).Name | Should -Be @(
            'Pester'
            'InvokeBuild'
            'PSScriptAnalyzer'
            'Microsoft.PowerShell.PlatyPS'
        )
        foreach ($module in @($policy.modules)) {
            $module.version | Should -Match '^\d+\.\d+\.\d+$'
        }
    }

    It 'rejects a mismatched already-loaded Pester assembly' {
        $loadedAssemblyName = [System.Reflection.AssemblyName]::new('Pester, Version=5.6.0.0, Culture=neutral, PublicKeyToken=null')

        {
            Assert-DLLPicklePesterAssemblyVersion -RequiredVersion ([version]'5.7.1') -LoadedAssemblyName $loadedAssemblyName
        } | Should -Throw '*Pester assembly mismatch*5.6.0.0*5.7.1* fresh*'
    }

    It 'accepts the exact Pester assembly when only the revision component differs' {
        $loadedAssemblyName = [System.Reflection.AssemblyName]::new('Pester, Version=5.7.1.0, Culture=neutral, PublicKeyToken=null')

        {
            Assert-DLLPicklePesterAssemblyVersion -RequiredVersion ([version]'5.7.1') -LoadedAssemblyName $loadedAssemblyName
        } | Should -Not -Throw
    }

    It 'uses exact required-version imports in the CI bootstrap and build wrapper' {
        $script:BuildWrapperPath | Should -Exist
        $bootstrap = Get-Content -LiteralPath $script:BootstrapPath -Raw
        $wrapper = Get-Content -LiteralPath $script:BuildWrapperPath -Raw

        $bootstrap | Should -Match 'build-tool-versions\.json'
        $bootstrap | Should -Match 'RequiredVersion'
        $bootstrap | Should -Match 'ModuleInstallPath'
        $bootstrap | Should -Match 'Save-Module'
        $wrapper | Should -Match 'Import-DLLPickleBuildTool'
        $wrapper | Should -Not -Match 'MinimumVersion|MaximumVersion'
    }

    It 'detects whether the active module command supports SkipPublisherCheck' {
        function Test-CommandWithPublisherCheck {
            param(
                [Parameter()]
                [switch]$SkipPublisherCheck
            )

            $null = $SkipPublisherCheck
        }

        function Test-CommandWithoutPublisherCheck {
            param(
                [Parameter()]
                [switch]$Force
            )

            $null = $Force
        }

        $WithPublisherCheck = Get-Command -Name Test-CommandWithPublisherCheck
        $WithoutPublisherCheck = Get-Command -Name Test-CommandWithoutPublisherCheck

        Test-DLLPickleCommandParameter -Command $WithPublisherCheck -ParameterName 'SkipPublisherCheck' |
            Should -BeTrue
        Test-DLLPickleCommandParameter -Command $WithoutPublisherCheck -ParameterName 'SkipPublisherCheck' |
            Should -BeFalse
    }

    It 'guards optional publisher-check parameters before invoking the module command' {
        $bootstrap = Get-Content -LiteralPath $script:BootstrapPath -Raw

        $bootstrap | Should -Match ([regex]::Escape(
                'Test-DLLPickleCommandParameter -Command $ModuleInstallCommand -ParameterName ''SkipPublisherCheck'''
            ))
        $bootstrap | Should -Match ([regex]::Escape('& $ModuleInstallCommand @ModuleCommandSplat'))
    }

    It 'does not change StrictMode in the caller process' {
        $tooling = Get-Content -LiteralPath $script:ToolingScriptPath -Raw

        $tooling | Should -Not -Match '(?m)^\s*Set-StrictMode\b'
    }
}
