BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ToolPath = Join-Path $script:RepositoryRoot 'tools\Get-DLLPickleBundleSourceFingerprint.ps1'

    function Get-BundleFingerprintFixture {
        param([Parameter(Mandatory)][string]$Root)

        $ModuleRoot = Join-Path $Root 'src\DLLPickle\Private'
        $BuildRoot = Join-Path $Root 'src\DLLPickle.Build'
        $BuildScriptRoot = Join-Path $Root 'build'
        $ToolsRoot = Join-Path $Root 'tools'
        $null = New-Item -Path $ModuleRoot -ItemType Directory -Force
        $null = New-Item -Path $BuildRoot -ItemType Directory -Force
        $null = New-Item -Path $BuildScriptRoot -ItemType Directory -Force
        $null = New-Item -Path $ToolsRoot -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path $Root 'src\DLLPickle\DLLPickle.psd1') -Value '@{ ModuleVersion = ''0.0.0'' }' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $ModuleRoot 'Get-Thing.ps1') -Value 'function Get-Thing { ''thing'' }' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $BuildRoot 'DLLPickle.csproj') -Value '<Project />' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $BuildRoot 'packages.lock.json') -Value '{ "version": 2 }' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $BuildScriptRoot 'DLLPickle.Build.ps1') -Value 'Add-BuildTask PrepareModuleOutput' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $BuildScriptRoot 'DLLPickle.Settings.ps1') -Value '$ModuleName = ''DLLPickle''' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $BuildScriptRoot 'DLLPickle.Tooling.ps1') -Value 'function Import-Tool {}' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $BuildScriptRoot 'build-tool-versions.json') -Value '{ "schemaVersion": 1 }' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $Root 'global.json') -Value '{ "sdk": { "version": "10.0.100" } }' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $ToolsRoot 'Invoke-DLLPickleBuild.ps1') -Value 'param([string[]]$Task)' -Encoding UTF8
        $Root
    }
}

Describe 'Published bundle source fingerprint' -Tag 'Unit' {
    It 'is stable across repository roots and excludes non-bundle files' {
        $FirstRoot = Get-BundleFingerprintFixture -Root (Join-Path $TestDrive 'first')
        $SecondRoot = Get-BundleFingerprintFixture -Root (Join-Path $TestDrive 'second')
        $null = New-Item -Path (Join-Path $SecondRoot 'docs') -ItemType Directory
        Set-Content -LiteralPath (Join-Path $SecondRoot 'docs\note.md') -Value 'not published' -Encoding UTF8

        $First = & $script:ToolPath -RepositoryRoot $FirstRoot
        $Second = & $script:ToolPath -RepositoryRoot $SecondRoot

        $First.fingerprint | Should -BeExactly $Second.fingerprint
        @($First.files.path) | Should -Be @(
            'build/DLLPickle.Build.ps1'
            'build/DLLPickle.Settings.ps1'
            'build/DLLPickle.Tooling.ps1'
            'build/build-tool-versions.json'
            'global.json'
            'src/DLLPickle.Build/DLLPickle.csproj'
            'src/DLLPickle.Build/packages.lock.json'
            'src/DLLPickle/DLLPickle.psd1'
            'src/DLLPickle/Private/Get-Thing.ps1'
            'tools/Invoke-DLLPickleBuild.ps1'
        )
    }

    It 'changes when a published source input changes' {
        $Root = Get-BundleFingerprintFixture -Root (Join-Path $TestDrive 'changed')
        $Before = & $script:ToolPath -RepositoryRoot $Root
        Set-Content -LiteralPath (Join-Path $Root 'src\DLLPickle\Private\Get-Thing.ps1') -Value 'function Get-Thing { ''changed'' }' -Encoding UTF8

        $After = & $script:ToolPath -RepositoryRoot $Root

        $After.fingerprint | Should -Not -Be $Before.fingerprint
    }

    It 'changes when packaging logic changes' {
        $Root = Get-BundleFingerprintFixture -Root (Join-Path $TestDrive 'packaging-change')
        $Before = & $script:ToolPath -RepositoryRoot $Root
        Set-Content -LiteralPath (Join-Path $Root 'build\DLLPickle.Build.ps1') -Value 'Add-BuildTask PrepareModuleOutput,Archive' -Encoding UTF8

        $After = & $script:ToolPath -RepositoryRoot $Root

        $After.fingerprint | Should -Not -Be $Before.fingerprint
    }

    It 'uses ordinal path order under English and Turkish cultures' {
        $Root = Get-BundleFingerprintFixture -Root (Join-Path $TestDrive 'culture')
        $OriginalCulture = [System.Globalization.CultureInfo]::CurrentCulture
        try {
            [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')
            $English = & $script:ToolPath -RepositoryRoot $Root
            [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('tr-TR')
            $Turkish = & $script:ToolPath -RepositoryRoot $Root
        } finally {
            [System.Globalization.CultureInfo]::CurrentCulture = $OriginalCulture
        }

        $English.fingerprint | Should -BeExactly $Turkish.fingerprint
        @($English.files.path) | Should -BeExactly @($Turkish.files.path)
    }

    It 'writes a self-contained file manifest when requested' {
        $Root = Get-BundleFingerprintFixture -Root (Join-Path $TestDrive 'report')
        $OutputPath = Join-Path $TestDrive 'bundle-source-fingerprint.json'

        $Expected = & $script:ToolPath -RepositoryRoot $Root -OutputPath $OutputPath
        $Actual = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json

        $Actual.fingerprint | Should -BeExactly $Expected.fingerprint
        @($Actual.files).Count | Should -Be 10
        Get-Content -LiteralPath $OutputPath -Raw | Should -Not -Match ([regex]::Escape($Root))
    }
}
