BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ToolPath = Join-Path $script:RepositoryRoot 'tools\Get-DLLPickleBundleSourceFingerprint.ps1'

    function Get-BundleFingerprintFixture {
        param([Parameter(Mandatory)][string]$Root)

        $ModuleRoot = Join-Path $Root 'src\DLLPickle\Private'
        $BuildRoot = Join-Path $Root 'src\DLLPickle.Build'
        $null = New-Item -Path $ModuleRoot -ItemType Directory -Force
        $null = New-Item -Path $BuildRoot -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path $Root 'src\DLLPickle\DLLPickle.psd1') -Value '@{ ModuleVersion = ''0.0.0'' }' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $ModuleRoot 'Get-Thing.ps1') -Value 'function Get-Thing { ''thing'' }' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $BuildRoot 'DLLPickle.csproj') -Value '<Project />' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $BuildRoot 'packages.lock.json') -Value '{ "version": 2 }' -Encoding UTF8
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
            'src/DLLPickle.Build/DLLPickle.csproj'
            'src/DLLPickle.Build/packages.lock.json'
            'src/DLLPickle/DLLPickle.psd1'
            'src/DLLPickle/Private/Get-Thing.ps1'
        )
    }

    It 'changes when a published source input changes' {
        $Root = Get-BundleFingerprintFixture -Root (Join-Path $TestDrive 'changed')
        $Before = & $script:ToolPath -RepositoryRoot $Root
        Set-Content -LiteralPath (Join-Path $Root 'src\DLLPickle\Private\Get-Thing.ps1') -Value 'function Get-Thing { ''changed'' }' -Encoding UTF8

        $After = & $script:ToolPath -RepositoryRoot $Root

        $After.fingerprint | Should -Not -Be $Before.fingerprint
    }

    It 'writes a self-contained file manifest when requested' {
        $Root = Get-BundleFingerprintFixture -Root (Join-Path $TestDrive 'report')
        $OutputPath = Join-Path $TestDrive 'bundle-source-fingerprint.json'

        $Expected = & $script:ToolPath -RepositoryRoot $Root -OutputPath $OutputPath
        $Actual = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json

        $Actual.fingerprint | Should -BeExactly $Expected.fingerprint
        @($Actual.files).Count | Should -Be 4
        Get-Content -LiteralPath $OutputPath -Raw | Should -Not -Match ([regex]::Escape($Root))
    }
}
