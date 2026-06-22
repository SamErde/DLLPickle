BeforeAll {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    # Join-Path (not Resolve-Path): the tool may not exist yet during the RED phase, and a missing
    # file should fail each test at invocation time rather than crashing discovery in BeforeAll.
    $script:ToolPath = Join-Path $RepoRoot 'tools\Test-DLLPickleTfmAlignment.ps1'

    # Named Get-* (not New-*): AnalyzeTests only excludes PSUseDeclaredVarsMoreThanAssignments, so a
    # state-changing verb would trip PSUseShouldProcessForStateChangingFunctions and fail the gate.
    function Get-FixturePackageDirectory {
        param(
            [Parameter()]
            [AllowEmptyCollection()]
            [string[]]$LibFramework = @(),

            [string]$PackageName = 'Contoso.Fixture',

            [switch]$NoLibFolder,

            [switch]$FlatLib,

            [Parameter()]
            [AllowEmptyCollection()]
            [string[]]$PlaceholderFramework = @()
        )

        $Root = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('n'))
        $PackageDirectory = Join-Path $Root $PackageName
        $null = New-Item -Path $PackageDirectory -ItemType Directory -Force

        if (-not $NoLibFolder) {
            $LibDirectory = Join-Path $PackageDirectory 'lib'
            $null = New-Item -Path $LibDirectory -ItemType Directory -Force
            if ($FlatLib) {
                Set-Content -LiteralPath (Join-Path $LibDirectory "$PackageName.dll") -Value 'fixture' -Encoding utf8
            } else {
                foreach ($Tfm in $LibFramework) {
                    $TfmDirectory = Join-Path $LibDirectory $Tfm
                    $null = New-Item -Path $TfmDirectory -ItemType Directory -Force
                    Set-Content -LiteralPath (Join-Path $TfmDirectory "$PackageName.dll") -Value 'fixture' -Encoding utf8
                }
                # A placeholder framework folder ships only a NuGet `_._` marker (no assembly).
                foreach ($Tfm in $PlaceholderFramework) {
                    $TfmDirectory = Join-Path $LibDirectory $Tfm
                    $null = New-Item -Path $TfmDirectory -ItemType Directory -Force
                    Set-Content -LiteralPath (Join-Path $TfmDirectory '_._') -Value '' -Encoding utf8
                }
            }
        }

        $PackageDirectory
    }

    # Builds a synthetic policy + lock file + NuGet-style packages root for the policy-driven mode.
    function Get-FixturePolicyContext {
        param(
            [Parameter(Mandatory)]
            [string[]]$AlignedLibFramework
        )

        $Context = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('n'))
        $PackagesRoot = Join-Path $Context 'packages'
        $null = New-Item -Path $PackagesRoot -ItemType Directory -Force

        $PolicyPath = Join-Path $Context 'policy.json'
        @{
            preload = @(
                @{ packageName = 'Contoso.Fixture'; assemblyName = 'Contoso.Fixture'; classification = 'preload' }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $PolicyPath -Encoding utf8

        $LockPath = Join-Path $Context 'packages.lock.json'
        @{
            version      = 1
            dependencies = @{
                'net8.0' = @{
                    'Contoso.Fixture' = @{ type = 'Direct'; resolved = '1.2.3' }
                }
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $LockPath -Encoding utf8

        # NuGet lowercases both the package id folder and the version folder under the global cache.
        $RestoredLib = Join-Path $PackagesRoot 'contoso.fixture\1.2.3\lib'
        foreach ($Tfm in $AlignedLibFramework) {
            $TfmDirectory = Join-Path $RestoredLib $Tfm
            $null = New-Item -Path $TfmDirectory -ItemType Directory -Force
            Set-Content -LiteralPath (Join-Path $TfmDirectory 'Contoso.Fixture.dll') -Value 'fixture' -Encoding utf8
        }

        [PSCustomObject]@{
            PolicyPath   = $PolicyPath
            LockPath     = $LockPath
            PackagesRoot = $PackagesRoot
        }
    }
}

Describe 'Test-DLLPickleTfmAlignment net8.0 compatibility decisions' -Tag 'Unit' {
    It 'treats <Tfm> as net8.0-aligned' -ForEach @(
        @{ Tfm = 'net8.0' }
        @{ Tfm = 'net6.0' }
        @{ Tfm = 'netstandard2.0' }
        @{ Tfm = 'netstandard2.1' }
        @{ Tfm = 'netcoreapp3.1' }
    ) {
        $Directory = Get-FixturePackageDirectory -LibFramework @($Tfm)
        $Result = & $script:ToolPath -PackageDirectory $Directory
        $Result.IsAligned | Should -BeTrue
        $Result.CompatibleAssets | Should -Contain $Tfm
    }

    It 'treats <Tfm> as NOT net8.0-aligned' -ForEach @(
        @{ Tfm = 'net48' }
        @{ Tfm = 'net472' }
        @{ Tfm = 'net40' }
        @{ Tfm = 'net9.0' }
        # OS-specific TFMs are not portable net8.0 assets (DLLPickle's bundle is portable net8.0).
        @{ Tfm = 'net8.0-windows' }
        @{ Tfm = 'net8.0-browser' }
        @{ Tfm = 'sl5-garbage' }
    ) {
        $Directory = Get-FixturePackageDirectory -LibFramework @($Tfm)
        $Result = & $script:ToolPath -PackageDirectory $Directory
        $Result.IsAligned | Should -BeFalse
    }
}

Describe 'Test-DLLPickleTfmAlignment package inspection' -Tag 'Unit' {
    It 'is aligned when a net8.0 asset is present alongside an incompatible one' {
        $Directory = Get-FixturePackageDirectory -LibFramework @('net48', 'net8.0')
        $Result = & $script:ToolPath -PackageDirectory $Directory
        $Result.IsAligned | Should -BeTrue
        $Result.CompatibleAssets | Should -Contain 'net8.0'
        $Result.CompatibleAssets | Should -Not -Contain 'net48'
    }

    It 'is aligned for a legacy flat lib folder (assemblies apply to any framework)' {
        $Directory = Get-FixturePackageDirectory -FlatLib
        $Result = & $script:ToolPath -PackageDirectory $Directory
        $Result.IsAligned | Should -BeTrue
    }

    It 'is not aligned when the package has no lib folder' {
        $Directory = Get-FixturePackageDirectory -NoLibFolder
        $Result = & $script:ToolPath -PackageDirectory $Directory
        $Result.IsAligned | Should -BeFalse
        $Result.Reason | Should -Match 'lib'
    }

    It 'is not aligned when the only compatible TFM folder ships no assembly (NuGet placeholder)' {
        $Directory = Get-FixturePackageDirectory -PlaceholderFramework @('net8.0')
        $Result = & $script:ToolPath -PackageDirectory $Directory
        $Result.IsAligned | Should -BeFalse
    }

    It 'ignores an empty compatible folder but stays aligned via a populated one' {
        $Directory = Get-FixturePackageDirectory -LibFramework @('net8.0') -PlaceholderFramework @('net6.0')
        $Result = & $script:ToolPath -PackageDirectory $Directory
        $Result.IsAligned | Should -BeTrue
        $Result.CompatibleAssets | Should -Contain 'net8.0'
        $Result.CompatibleAssets | Should -Not -Contain 'net6.0'
    }
}

Describe 'Test-DLLPickleTfmAlignment policy-driven inspection' -Tag 'Unit' {
    It 'reports an aggregate aligned result when every preload package is aligned' {
        $Fixture = Get-FixturePolicyContext -AlignedLibFramework @('net8.0', 'netstandard2.0')
        $OutputPath = Join-Path $TestDrive 'aligned-report.json'
        $Report = & $script:ToolPath -PolicyPath $Fixture.PolicyPath -LockFilePath $Fixture.LockPath -PackagesRoot $Fixture.PackagesRoot -OutputPath $OutputPath

        $Report.IsAligned | Should -BeTrue
        @($Report.Packages).Count | Should -Be 1
        $Report.Packages[0].PackageName | Should -Be 'Contoso.Fixture'
        $Report.Packages[0].ResolvedVersion | Should -Be '1.2.3'
        @($Report.Misaligned) | Should -BeNullOrEmpty
        Test-Path -LiteralPath $OutputPath | Should -BeTrue
    }

    It 'reports an aggregate misaligned result and names the offending package' {
        $Fixture = Get-FixturePolicyContext -AlignedLibFramework @('net48')
        $Report = & $script:ToolPath -PolicyPath $Fixture.PolicyPath -LockFilePath $Fixture.LockPath -PackagesRoot $Fixture.PackagesRoot

        $Report.IsAligned | Should -BeFalse
        @($Report.Misaligned) | Should -Contain 'Contoso.Fixture'
    }

    It 'throws in strict mode when a preload package is misaligned' {
        $Fixture = Get-FixturePolicyContext -AlignedLibFramework @('net48')
        { & $script:ToolPath -PolicyPath $Fixture.PolicyPath -LockFilePath $Fixture.LockPath -PackagesRoot $Fixture.PackagesRoot -Strict } |
            Should -Throw '*TFM*'
    }
}
