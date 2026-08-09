BeforeAll {
    Set-Location -Path $PSScriptRoot
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:ArtifactInspectionPath = Join-Path $ProjectRoot 'tools\Test-DLLPicklePackageArtifact.ps1'
    $script:ArtifactSizePath = Join-Path $ProjectRoot 'tools\New-DLLPickleArtifactSizeReport.ps1'
}

Describe 'DLLPickle package artifact policy' -Tag 'Unit' {
    BeforeEach {
        $script:FixtureRoot = Join-Path $TestDrive 'fixture'
        $script:ModulePath = Join-Path $script:FixtureRoot 'module\DLLPickle'
        $script:BuildOutputRoot = Join-Path $script:FixtureRoot 'build-output'
        $script:PolicyPath = Join-Path $script:FixtureRoot 'SupportedRuntimeProfiles.json'
        $script:ProjectPath = Join-Path $script:FixtureRoot 'DLLPickle.csproj'
        $script:LockPath = Join-Path $script:FixtureRoot 'packages.lock.json'
        $null = New-Item -Path $script:ModulePath -ItemType Directory -Force

        @{
            schemaVersion = 1
            profiles = @(
                @{ powerShell = '7.4'; clrMajor = 8; targetFramework = 'net8.0' }
                @{ powerShell = '7.5'; clrMajor = 9; targetFramework = 'net9.0' }
                @{ powerShell = '7.6'; clrMajor = 10; targetFramework = 'net10.0' }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:PolicyPath -Encoding UTF8
        '<Project Sdk="Microsoft.NET.Sdk"></Project>' | Set-Content -LiteralPath $script:ProjectPath -Encoding UTF8
        '{ "version": 1 }' | Set-Content -LiteralPath $script:LockPath -Encoding UTF8
        '@{ RootModule = ''DLLPickle.psm1''; RequiredModules = @() }' | Set-Content -LiteralPath (Join-Path $script:ModulePath 'DLLPickle.psd1') -Encoding UTF8

        foreach ($TargetFramework in @('net8.0', 'net9.0', 'net10.0')) {
            $ArtifactTfmPath = Join-Path (Join-Path $script:ModulePath 'bin') $TargetFramework
            $BuildTfmPath = Join-Path $script:BuildOutputRoot $TargetFramework
            $null = New-Item -Path $ArtifactTfmPath -ItemType Directory -Force
            $null = New-Item -Path $BuildTfmPath -ItemType Directory -Force
            "artifact-$TargetFramework" | Set-Content -LiteralPath (Join-Path $ArtifactTfmPath 'Microsoft.Fixture.dll') -Encoding UTF8
            "artifact-$TargetFramework" | Set-Content -LiteralPath (Join-Path $BuildTfmPath 'Microsoft.Fixture.dll') -Encoding UTF8
        }
    }

    It 'accepts exactly the three policy-derived TFM payloads with no test-tool references' {
        $Parameters = @{
            ModulePath        = $script:ModulePath
            BuildOutputRoot   = $script:BuildOutputRoot
            SupportPolicyPath = $script:PolicyPath
            ProjectPath       = $script:ProjectPath
            LockFilePath      = $script:LockPath
            OutputPath        = Join-Path $TestDrive 'artifact-report.json'
            Strict            = $true
        }
        $Report = & $script:ArtifactInspectionPath @Parameters

        $Report.Passed | Should -BeTrue
        $Report.ActualTargetFrameworks | Should -Be @('net10.0', 'net8.0', 'net9.0')
        @($Report.Profiles) | Should -HaveCount 3
        @($Report.ForbiddenHits) | Should -HaveCount 0
    }

    It 'fails closed on an unexpected target framework' {
        $null = New-Item -Path (Join-Path $script:ModulePath 'bin\net11.0') -ItemType Directory -Force
        {
            & $script:ArtifactInspectionPath -ModulePath $script:ModulePath -BuildOutputRoot $script:BuildOutputRoot -SupportPolicyPath $script:PolicyPath -ProjectPath $script:ProjectPath -LockFilePath $script:LockPath -OutputPath (Join-Path $TestDrive 'unexpected.json') -Strict
        } | Should -Throw '*Unexpected target-framework directory*'
    }

    It 'fails closed when optional multi-pwsh tooling leaks into artifact content' {
        'multi-pwsh must never ship here' | Set-Content -LiteralPath (Join-Path $script:ModulePath 'leak.txt') -Encoding UTF8
        {
            & $script:ArtifactInspectionPath -ModulePath $script:ModulePath -BuildOutputRoot $script:BuildOutputRoot -SupportPolicyPath $script:PolicyPath -ProjectPath $script:ProjectPath -LockFilePath $script:LockPath -OutputPath (Join-Path $TestDrive 'leak.json') -Strict
        } | Should -Throw '*Forbidden multi-pwsh reference*'
    }

    It 'reports deterministic per-TFM and full-artifact sizes against the approved threshold' {
        $BaselinePath = Join-Path $TestDrive 'size-baseline.json'
        @{
            schemaVersion = 1
            approvalStatus = 'accepted'
            approvedAtUtc = '2026-08-09T00:00:00Z'
            thresholds = @{ maximumIncreasePercent = 10; maximumIncreaseBytes = 2097152 }
            profiles = @(
                @{ name = 'net8.0'; unpackedBytes = 0; compressedBytes = 0 }
                @{ name = 'net9.0'; unpackedBytes = 0; compressedBytes = 0 }
                @{ name = 'net10.0'; unpackedBytes = 0; compressedBytes = 0 }
            )
            fullArtifact = @{ unpackedBytes = 0; compressedBytes = 0 }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $BaselinePath -Encoding UTF8

        $Report = & $script:ArtifactSizePath -ModulePath $script:ModulePath -SupportPolicyPath $script:PolicyPath -BaselinePath $BaselinePath -OutputPath (Join-Path $TestDrive 'size-report.json') -Strict

        $Report.ReviewRequired | Should -BeFalse
        $Report.BaselineApproved | Should -BeTrue
        @($Report.Profiles) | Should -HaveCount 3
        @($Report.Profiles | Where-Object { $_.CompressedBytes -le 0 }) | Should -HaveCount 0
        $Report.FullArtifact.UnpackedBytes | Should -BeGreaterThan 0
        $Report.FullArtifact.CompressedBytes | Should -BeGreaterThan 0
    }

    It 'routes material growth to review and fails in strict mode' {
        $BaselinePath = Join-Path $TestDrive 'strict-size-baseline.json'
        @{
            schemaVersion = 1
            approvalStatus = 'accepted'
            approvedAtUtc = '2026-08-09T00:00:00Z'
            thresholds = @{ maximumIncreasePercent = 0; maximumIncreaseBytes = 0 }
            profiles = @(
                @{ name = 'net8.0'; unpackedBytes = 1; compressedBytes = 1 }
                @{ name = 'net9.0'; unpackedBytes = 1; compressedBytes = 1 }
                @{ name = 'net10.0'; unpackedBytes = 1; compressedBytes = 1 }
            )
            fullArtifact = @{ unpackedBytes = 1; compressedBytes = 1 }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $BaselinePath -Encoding UTF8

        {
            & $script:ArtifactSizePath -ModulePath $script:ModulePath -SupportPolicyPath $script:PolicyPath -BaselinePath $BaselinePath -OutputPath (Join-Path $TestDrive 'strict-size-report.json') -Strict
        } | Should -Throw '*exceeds the approved material-growth policy*'
    }

    It 'fails closed until the captured size baseline is explicitly accepted' {
        $BaselinePath = Join-Path $TestDrive 'unapproved-size-baseline.json'
        @{
            schemaVersion = 1
            approvalStatus = 'requires-maintainer-approval'
            capturedAtUtc = '2026-08-09T00:00:00Z'
            approvedAtUtc = $null
            thresholds = @{ maximumIncreasePercent = 10; maximumIncreaseBytes = 2097152 }
            profiles = @(
                @{ name = 'net8.0'; unpackedBytes = 0; compressedBytes = 0 }
                @{ name = 'net9.0'; unpackedBytes = 0; compressedBytes = 0 }
                @{ name = 'net10.0'; unpackedBytes = 0; compressedBytes = 0 }
            )
            fullArtifact = @{ unpackedBytes = 0; compressedBytes = 0 }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $BaselinePath -Encoding UTF8

        $Parameters = @{
            ModulePath = $script:ModulePath
            SupportPolicyPath = $script:PolicyPath
            BaselinePath = $BaselinePath
            OutputPath = Join-Path $TestDrive 'unapproved-size-report.json'
        }
        $Report = & $script:ArtifactSizePath @Parameters

        $Report.BaselineApproved | Should -BeFalse
        $Report.ReviewRequired | Should -BeTrue
        { & $script:ArtifactSizePath @Parameters -Strict } | Should -Throw '*baseline is not accepted by a maintainer*'
    }
}
