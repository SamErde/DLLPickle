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

    It 'parses the canonical policy and resolves one exact tool version' {
        $Policy = Get-DLLPickleBuildToolPolicy -Path $script:ToolPolicyPath

        $Policy.schemaVersion | Should -Be 1
        Get-DLLPickleBuildToolVersion -Policy $Policy -Name 'Pester' | Should -Be ([version]'5.7.1')
        { Get-DLLPickleBuildToolVersion -Policy $Policy -Name 'Missing.Tool' } | Should -Throw '*exactly one*'
    }

    It 'rejects policy versions that are not Major.Minor.Patch' {
        $PolicyPath = Join-Path $TestDrive 'invalid-tool-policy.json'
        @{
            schemaVersion = 1
            modules = @(@{ name = 'Fixture.Tool'; version = '5.7' })
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $PolicyPath -Encoding utf8

        { Get-DLLPickleBuildToolPolicy -Path $PolicyPath } | Should -Throw '*Major.Minor.Patch*'
    }

    It 'compares tool versions by the requested precision' {
        Test-DLLPickleToolVersionMatch -ActualVersion ([version]'1.2.3.4') -RequiredVersion ([version]'1.2.3') |
            Should -BeTrue
        Test-DLLPickleToolVersionMatch -ActualVersion ([version]'1.2.4') -RequiredVersion ([version]'1.2.3') |
            Should -BeFalse
        Test-DLLPickleToolVersionMatch -ActualVersion ([version]'1.2.3.5') -RequiredVersion ([version]'1.2.3.4') |
            Should -BeFalse
    }

    It 'imports and reuses the exact requested module version' {
        $ModuleRoot = Join-Path $TestDrive 'modules/Fixture.Tool/1.2.3'
        $null = New-Item -Path $ModuleRoot -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path $ModuleRoot 'Fixture.Tool.psm1') -Value "function Get-FixtureTool { 'ok' }" -Encoding utf8
        New-ModuleManifest -Path (Join-Path $ModuleRoot 'Fixture.Tool.psd1') -RootModule 'Fixture.Tool.psm1' -ModuleVersion '1.2.3' -FunctionsToExport @('Get-FixtureTool')

        $OriginalModulePath = $env:PSModulePath
        try {
            $env:PSModulePath = (Split-Path -Path (Split-Path -Path $ModuleRoot -Parent) -Parent) + [System.IO.Path]::PathSeparator + $OriginalModulePath
            $First = Import-DLLPickleBuildTool -Name 'Fixture.Tool' -RequiredVersion ([version]'1.2.3')
            $Second = Import-DLLPickleBuildTool -Name 'Fixture.Tool' -RequiredVersion ([version]'1.2.3')

            $First.Version | Should -Be ([version]'1.2.3')
            $Second.Path | Should -BeExactly $First.Path
        } finally {
            Remove-Module -Name 'Fixture.Tool' -Force -ErrorAction SilentlyContinue
            $env:PSModulePath = $OriginalModulePath
        }
    }

    It 'does not change StrictMode in the caller process' {
        $tooling = Get-Content -LiteralPath $script:ToolingScriptPath -Raw

        $tooling | Should -Not -Match '(?m)^\s*Set-StrictMode\b'
    }
}
