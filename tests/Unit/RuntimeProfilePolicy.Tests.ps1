BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:RuntimePolicyPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'src/DLLPickle/SupportedRuntimeProfiles.json'
    $script:TestMatrixPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'build/powershell-test-matrix.json'
    $script:PolicyTestScriptPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'tools/Test-DLLPickleRuntimeProfilePolicy.ps1'
}

Describe 'Runtime profile policy data' -Tag 'Unit' {
    It 'declares only runtime behavior in the shipped policy' {
        $script:RuntimePolicyPath | Should -Exist
        $rawPolicy = Get-Content -LiteralPath $script:RuntimePolicyPath -Raw
        $policy = $rawPolicy | ConvertFrom-Json

        $policy.schemaVersion | Should -Be 1
        @($policy.profiles) | Should -HaveCount 3
        $rawPolicy | Should -Not -Match '7\.4\.18|7\.5\.9|7\.6\.4|multi-pwsh|MultiPwsh|lifecycle|checksum|sha256'
    }

    It 'maps every supported PowerShell line to one CLR major and TFM' {
        $policy = Get-Content -LiteralPath $script:RuntimePolicyPath -Raw | ConvertFrom-Json
        $actual = @($policy.profiles | ForEach-Object {
                '{0}.{1}|{2}|{3}' -f $_.powerShellMajor, $_.powerShellMinor, $_.dotnetMajor, $_.targetFramework
            })

        $actual | Should -Be @(
            '7.4|8|net8.0'
            '7.5|9|net9.0'
            '7.6|10|net10.0'
        )
        @($actual | Sort-Object -Unique) | Should -HaveCount $actual.Count
    }

    It 'declares platform-provided assemblies for the universal module payload' {
        $policy = Get-Content -LiteralPath $script:RuntimePolicyPath -Raw | ConvertFrom-Json

        foreach ($RuntimeProfileRow in @($policy.profiles)) {
            @($RuntimeProfileRow.hostProvidedAssemblyNames.windows) | Should -Be @('System.Security.Cryptography.ProtectedData')
            @($RuntimeProfileRow.hostProvidedAssemblyNames.linux) | Should -BeNullOrEmpty
            @($RuntimeProfileRow.hostProvidedAssemblyNames.macos) | Should -BeNullOrEmpty
        }
    }

    It 'keeps exact patch, lifecycle, stock archive, and optional tool metadata outside the package' {
        $script:TestMatrixPath | Should -Exist
        $rawMatrix = Get-Content -LiteralPath $script:TestMatrixPath -Raw
        $matrix = $rawMatrix | ConvertFrom-Json

        $matrix.schemaVersion | Should -Be 1
        $rawMatrix | Should -Match '"lastVerifiedUtc":\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"'
        $matrix.evidenceFreshnessDays | Should -BeGreaterThan 0
        $matrix.retirementWarningDays | Should -BeGreaterThan 0
        @($matrix.profiles).powerShellVersion | Should -Be @('7.4.18', '7.5.9', '7.6.4')
        @($matrix.lanes).platform | Should -Be @('windows', 'linux', 'macos')
        @($matrix.archiveAssets) | Should -HaveCount 9
        $matrix.provisioning.optionalProvider.name | Should -Be 'MultiPwsh'
        $matrix.provisioning.optionalProvider.version | Should -Be '0.18.0'
    }

    It 'aligns the shipped and CI profile sets exactly' {
        $policy = Get-Content -LiteralPath $script:RuntimePolicyPath -Raw | ConvertFrom-Json
        $matrix = Get-Content -LiteralPath $script:TestMatrixPath -Raw | ConvertFrom-Json
        $shipped = @($policy.profiles | ForEach-Object {
                '{0}.{1}|{2}|{3}' -f $_.powerShellMajor, $_.powerShellMinor, $_.dotnetMajor, $_.targetFramework
            })
        $tested = @($matrix.profiles | ForEach-Object {
                '{0}.{1}|{2}|{3}' -f $_.powerShellMajor, $_.powerShellMinor, $_.dotnetMajor, $_.targetFramework
            })

        $tested | Should -Be $shipped
    }

    It 'pins one checksum-verified official stock archive for every profile and lane' {
        $matrix = Get-Content -LiteralPath $script:TestMatrixPath -Raw | ConvertFrom-Json
        foreach ($RuntimeProfile in @($matrix.profiles)) {
            foreach ($lane in @($matrix.lanes)) {
                $MatchingAssets = @($matrix.archiveAssets | Where-Object {
                        $_.powerShellVersion -eq $RuntimeProfile.powerShellVersion -and
                        $_.platform -eq $lane.platform -and
                        $_.architecture -eq $lane.architecture
                    })
                $MatchingAssets | Should -HaveCount 1
                $MatchingAssets[0].downloadUrl | Should -Match '^https://github\.com/PowerShell/PowerShell/releases/download/v'
                $MatchingAssets[0].sha256 | Should -Match '^[a-f0-9]{64}$'
            }
        }
    }

    It 'pins checksum-verified multi-pwsh assets only for the optional CI provider' {
        $matrix = Get-Content -LiteralPath $script:TestMatrixPath -Raw | ConvertFrom-Json
        $provider = $matrix.provisioning.optionalProvider

        $provider.releaseUrl | Should -Be 'https://github.com/Devolutions/multi-pwsh/releases/tag/v0.18.0'
        @($provider.assets) | Should -HaveCount 3
        foreach ($asset in @($provider.assets)) {
            $asset.sha256 | Should -Match '^[a-f0-9]{64}$'
            $asset.downloadUrl | Should -Match '/Devolutions/multi-pwsh/releases/download/v0\.18\.0/'
        }
    }
}

Describe 'Runtime profile lifecycle enforcement' -Tag 'Unit' {
    It 'passes a release check while policy evidence is fresh and every line is supported' {
        $script:PolicyTestScriptPath | Should -Exist

        $result = @(& $script:PolicyTestScriptPath -Mode Release -AsOfUtc ([datetime]'2026-08-09T01:11:47Z') -PassThru)

        $result | Should -HaveCount 3
        @($result.Status | Sort-Object -Unique) | Should -Be @('Supported')
    }

    It 'fails closed when a shipped support line is expired' {
        {
            & $script:PolicyTestScriptPath -Mode Release -AsOfUtc ([datetime]'2026-11-11T08:00:00Z')
        } | Should -Throw '*expired*7.4*7.5*'
    }

    It 'keeps a line supported through the end of its Pacific lifecycle day' {
        $result = @(& $script:PolicyTestScriptPath -Mode Scheduled -AsOfUtc ([datetime]'2026-11-11T07:59:59Z') -PassThru -WarningAction SilentlyContinue)

        @($result | Where-Object Status -EQ 'Expired') | Should -BeNullOrEmpty
    }

    It 'warns on schedule before an impending retirement' {
        $warnings = @()

        $result = @(& $script:PolicyTestScriptPath -Mode Scheduled -AsOfUtc ([datetime]'2026-08-15T00:00:00Z') -PassThru -WarningVariable warnings)

        $warnings | Should -Not -BeNullOrEmpty
        @($result | Where-Object Status -eq 'RetiringSoon') | Should -HaveCount 2
    }

    It 'fails a release check when lifecycle verification is stale' {
        {
            & $script:PolicyTestScriptPath -Mode Release -AsOfUtc ([datetime]'2026-09-15T00:00:00Z')
        } | Should -Throw '*stale*last verified*'
    }

    It 'uses a release-current live discovery report as fresh lifecycle evidence' {
        $EvidencePath = Join-Path $TestDrive 'live-lifecycle-evidence.json'
        @{
            schemaVersion = 1
            generatedAtUtc = '2026-09-15T00:00:00Z'
            patchUpdates = @()
            newLines = @()
            lifecycle = @(
                @{ releaseLine = '7.4'; status = 'Supported' }
                @{ releaseLine = '7.5'; status = 'Supported' }
                @{ releaseLine = '7.6'; status = 'Supported' }
            )
            lifecycleDateChanges = @()
            lifecycleMissingLines = @()
            undeclaredSupportedLines = @()
            supportContractReviewRequired = $false
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $EvidencePath -Encoding utf8

        $result = @(& $script:PolicyTestScriptPath -Mode Release -AsOfUtc ([datetime]'2026-09-15T00:01:00Z') -LifecycleEvidencePath $EvidencePath -PassThru)

        $result | Should -HaveCount 3
    }

    It 'rejects live discovery evidence with an outstanding support update' {
        $EvidencePath = Join-Path $TestDrive 'outdated-lifecycle-evidence.json'
        @{
            schemaVersion = 1
            generatedAtUtc = '2026-09-15T00:00:00Z'
            patchUpdates = @(@{ candidateVersion = '7.5.10' })
            newLines = @()
            lifecycle = @(
                @{ releaseLine = '7.4'; status = 'Supported' }
                @{ releaseLine = '7.5'; status = 'Supported' }
                @{ releaseLine = '7.6'; status = 'Supported' }
            )
            lifecycleDateChanges = @()
            lifecycleMissingLines = @()
            undeclaredSupportedLines = @()
            supportContractReviewRequired = $false
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $EvidencePath -Encoding utf8

        { & $script:PolicyTestScriptPath -Mode Release -AsOfUtc ([datetime]'2026-09-15T00:01:00Z') -LifecycleEvidencePath $EvidencePath } |
            Should -Throw '*not release-current*newer servicing patches*'
    }
}
