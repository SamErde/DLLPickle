BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:RuntimePolicyPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'src/DLLPickle/SupportedRuntimeProfiles.json'
    $script:TestMatrixPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'build/powershell-test-matrix.json'
    $script:BuildProjectPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'src/DLLPickle.Build/DLLPickle.csproj'
    $script:PackageLockPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'src/DLLPickle.Build/packages.lock.json'
    $script:PolicyTestScriptPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'tools/Test-DLLPickleRuntimeProfilePolicy.ps1'

    function Get-TestMatrixFixturePath {
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter(Mandatory)]
            [string]$EvidenceVerifiedUtc,

            [Parameter(Mandatory)]
            [string]$LastVerifiedUtc
        )

        $Matrix = Get-Content -LiteralPath $script:TestMatrixPath -Raw | ConvertFrom-Json
        $HoldoverProfile = $Matrix.profiles | Where-Object powerShellMinor -EQ 4
        $HoldoverProfile.supportPolicy.evidenceVerifiedUtc = $EvidenceVerifiedUtc
        $FixtureDecisionDate = ([datetimeoffset]$LastVerifiedUtc).UtcDateTime.ToString('yyyy-MM-dd')
        foreach ($RuntimeProfile in @($Matrix.profiles | Where-Object { $null -ne $_.supportPolicy })) {
            $RuntimeProfile.supportPolicy.decisionDate = $FixtureDecisionDate
        }
        $Matrix.lastVerifiedUtc = $LastVerifiedUtc
        $FixturePath = Join-Path $TestDrive "$Name.json"
        $Matrix | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $FixturePath -Encoding UTF8
        $FixturePath
    }
}

Describe 'Runtime profile policy data' -Tag 'Unit' {
    It 'declares only runtime behavior in the shipped policy' {
        $script:RuntimePolicyPath | Should -Exist
        $rawPolicy = Get-Content -LiteralPath $script:RuntimePolicyPath -Raw
        $policy = $rawPolicy | ConvertFrom-Json

        $policy.schemaVersion | Should -Be 1
        @($policy.profiles) | Should -HaveCount 3
        $rawPolicy | Should -Not -Match '7\.4\.21|7\.5\.12|7\.6\.7|multi-pwsh|MultiPwsh|lifecycle|checksum|sha256'
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

    It 'locks the unconditional ProtectedData reference consistently for every shipped TFM' {
        [xml]$project = Get-Content -LiteralPath $script:BuildProjectPath -Raw
        $lock = Get-Content -LiteralPath $script:PackageLockPath -Raw | ConvertFrom-Json
        $policy = Get-Content -LiteralPath $script:RuntimePolicyPath -Raw | ConvertFrom-Json
        $references = @($project.Project.ItemGroup.PackageReference | Where-Object Include -EQ 'System.Security.Cryptography.ProtectedData')

        $references | Should -HaveCount 1
        [string]$references[0].Condition | Should -BeNullOrEmpty
        $version = [string]$references[0].Version
        foreach ($targetFramework in @($policy.profiles.targetFramework)) {
            $entry = $lock.dependencies.$targetFramework.'System.Security.Cryptography.ProtectedData'
            $entry.type | Should -BeExactly 'Direct'
            $entry.requested | Should -BeExactly "[$version, )"
            $entry.resolved | Should -BeExactly $version
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
        $matrix.PSObject.Properties.Name | Should -Not -Contain 'candidateValidationPending'
        @($matrix.profiles).powerShellVersion | Should -Be @('7.4.21', '7.5.12', '7.6.7')
        foreach ($RuntimeProfile in @($matrix.profiles)) {
            [string]$RuntimeProfile.dotnetRuntimeVersion | Should -Match '^\d+\.\d+\.\d+$'
            ([version]$RuntimeProfile.dotnetRuntimeVersion).Major | Should -Be ([int]$RuntimeProfile.dotnetMajor)
        }
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
    It 'rejects a temporary candidate marker in canonical policy validation' {
        $MatrixFixture = Get-TestMatrixFixturePath -Name 'matrix-pending-candidate' -EvidenceVerifiedUtc '2026-08-09T01:10:00Z' -LastVerifiedUtc '2026-08-09T01:10:00Z'
        $Matrix = Get-Content -LiteralPath $MatrixFixture -Raw | ConvertFrom-Json
        $Matrix | Add-Member -NotePropertyName candidateValidationPending -NotePropertyValue $true
        $Matrix | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $MatrixFixture -Encoding UTF8

        { & $script:PolicyTestScriptPath -TestMatrixPath $MatrixFixture -Mode Release -AsOfUtc ([datetime]'2026-08-09T01:11:47Z') } |
            Should -Throw '*temporary candidateValidationPending marker*'
    }

    It 'rejects a canonical profile without an exact .NET runtime patch' {
        $MatrixFixture = Get-TestMatrixFixturePath -Name 'matrix-missing-runtime-patch' -EvidenceVerifiedUtc '2026-08-09T01:10:00Z' -LastVerifiedUtc '2026-08-09T01:10:00Z'
        $Matrix = Get-Content -LiteralPath $MatrixFixture -Raw | ConvertFrom-Json
        $Matrix.profiles[0].dotnetRuntimeVersion = $null
        $Matrix | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $MatrixFixture -Encoding UTF8

        { & $script:PolicyTestScriptPath -TestMatrixPath $MatrixFixture -Mode Release -AsOfUtc ([datetime]'2026-08-09T01:11:47Z') } |
            Should -Throw '*must declare an exact .NET runtime patch version*'
    }

    It 'passes a release check while policy evidence is fresh and every line is supported' {
        $script:PolicyTestScriptPath | Should -Exist
        $MatrixFixture = Get-TestMatrixFixturePath -Name 'matrix-supported' -EvidenceVerifiedUtc '2026-08-09T01:10:00Z' -LastVerifiedUtc '2026-08-09T01:10:00Z'

        $result = @(& $script:PolicyTestScriptPath -TestMatrixPath $MatrixFixture -Mode Release -AsOfUtc ([datetime]'2026-08-09T01:11:47Z') -PassThru)

        $result | Should -HaveCount 3
        @($result.Status | Sort-Object -Unique) | Should -Be @('Supported')
    }

    It 'fails closed when a shipped support line expires without a holdover' {
        {
            & $script:PolicyTestScriptPath -Mode Release -AsOfUtc ([datetime]'2026-11-11T08:00:00Z')
        } | Should -Throw '*expired*7.5*'
    }

    It 'permits the bounded 7.4 hosted-service holdover while its evidence is fresh' {
        $RuntimePolicy = Get-Content -LiteralPath $script:RuntimePolicyPath -Raw | ConvertFrom-Json
        $Matrix = Get-Content -LiteralPath $script:TestMatrixPath -Raw | ConvertFrom-Json
        $RuntimePolicy.profiles = @($RuntimePolicy.profiles | Where-Object powerShellMinor -EQ 4)
        $Matrix.profiles = @($Matrix.profiles | Where-Object powerShellMinor -EQ 4)
        $Matrix.lastVerifiedUtc = '2026-11-11T08:00:00Z'
        $RuntimePolicyFixture = Join-Path $TestDrive 'runtime-policy-74.json'
        $MatrixFixture = Join-Path $TestDrive 'matrix-74.json'
        $RuntimePolicy | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $RuntimePolicyFixture -Encoding UTF8
        $Matrix | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $MatrixFixture -Encoding UTF8

        $Result = @(& $script:PolicyTestScriptPath -RuntimePolicyPath $RuntimePolicyFixture -TestMatrixPath $MatrixFixture -Mode Release -AsOfUtc ([datetime]'2026-11-11T08:01:00Z') -PassThru)

        $Result.Status | Should -Be 'CompatibilityHoldover'
        $Result.RetirementAction | Should -Be 'retain-for-hosted-service-compatibility'
    }

    It 'fails closed when hosted-service holdover evidence needs revalidation' {
        $RuntimePolicy = Get-Content -LiteralPath $script:RuntimePolicyPath -Raw | ConvertFrom-Json
        $Matrix = Get-Content -LiteralPath $script:TestMatrixPath -Raw | ConvertFrom-Json
        $RuntimePolicy.profiles = @($RuntimePolicy.profiles | Where-Object powerShellMinor -EQ 4)
        $Matrix.profiles = @($Matrix.profiles | Where-Object powerShellMinor -EQ 4)
        $Matrix.lastVerifiedUtc = '2027-02-01T00:00:00Z'
        $RuntimePolicyFixture = Join-Path $TestDrive 'runtime-policy-74-stale.json'
        $MatrixFixture = Join-Path $TestDrive 'matrix-74-stale.json'
        $RuntimePolicy | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $RuntimePolicyFixture -Encoding UTF8
        $Matrix | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $MatrixFixture -Encoding UTF8

        { & $script:PolicyTestScriptPath -RuntimePolicyPath $RuntimePolicyFixture -TestMatrixPath $MatrixFixture -Mode Release -AsOfUtc ([datetime]'2027-02-01T00:01:00Z') } |
            Should -Throw '*holdover review due*7.4*'
    }

    It 'rejects hosted-service holdover evidence dated after the evaluation time' {
        $RuntimePolicy = Get-Content -LiteralPath $script:RuntimePolicyPath -Raw | ConvertFrom-Json
        $Matrix = Get-Content -LiteralPath $script:TestMatrixPath -Raw | ConvertFrom-Json
        $RuntimePolicy.profiles = @($RuntimePolicy.profiles | Where-Object powerShellMinor -EQ 4)
        $Matrix.profiles = @($Matrix.profiles | Where-Object powerShellMinor -EQ 4)
        $Matrix.profiles[0].supportPolicy.evidenceVerifiedUtc = '2026-11-11T08:02:00Z'
        $Matrix.lastVerifiedUtc = '2026-11-11T08:00:00Z'
        $RuntimePolicyFixture = Join-Path $TestDrive 'runtime-policy-74-future-evidence.json'
        $MatrixFixture = Join-Path $TestDrive 'matrix-74-future-evidence.json'
        $RuntimePolicy | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $RuntimePolicyFixture -Encoding UTF8
        $Matrix | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $MatrixFixture -Encoding UTF8

        { & $script:PolicyTestScriptPath -RuntimePolicyPath $RuntimePolicyFixture -TestMatrixPath $MatrixFixture -Mode Release -AsOfUtc ([datetime]'2026-11-11T08:01:00Z') } |
            Should -Throw '*holdover evidence cannot be verified in the future*'
    }

    It 'keeps a line supported through the end of its Pacific lifecycle day' {
        $result = @(& $script:PolicyTestScriptPath -Mode Scheduled -AsOfUtc ([datetime]'2026-11-11T07:59:59Z') -PassThru -WarningAction SilentlyContinue)

        @($result | Where-Object Status -EQ 'Expired') | Should -BeNullOrEmpty
    }

    It 'warns on schedule before an impending retirement' {
        $warnings = @()
        $MatrixFixture = Get-TestMatrixFixturePath -Name 'matrix-retiring-warning' -EvidenceVerifiedUtc '2026-08-14T00:00:00Z' -LastVerifiedUtc '2026-08-14T00:00:00Z'

        $result = @(& $script:PolicyTestScriptPath -TestMatrixPath $MatrixFixture -Mode Scheduled -AsOfUtc ([datetime]'2026-08-15T00:00:00Z') -PassThru -WarningVariable warnings)

        $warnings | Should -Not -BeNullOrEmpty
        @($result | Where-Object Status -eq 'RetiringSoon') | Should -HaveCount 2
    }

    It 'fails a release check when lifecycle verification is stale' {
        $Matrix = Get-Content -LiteralPath $script:TestMatrixPath -Raw | ConvertFrom-Json
        $Matrix.lastVerifiedUtc = '2026-07-01T00:00:00Z'
        ($Matrix.profiles | Where-Object powerShellMinor -EQ 4).supportPolicy.evidenceVerifiedUtc = '2026-07-01T00:00:00Z'
        foreach ($RuntimeProfile in @($Matrix.profiles | Where-Object { $null -ne $_.supportPolicy })) {
            $RuntimeProfile.supportPolicy.decisionDate = '2026-07-01'
        }
        $MatrixFixture = Join-Path $TestDrive 'matrix-stale.json'
        $Matrix | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $MatrixFixture -Encoding UTF8

        {
            & $script:PolicyTestScriptPath -TestMatrixPath $MatrixFixture -Mode Release -AsOfUtc ([datetime]'2026-09-15T00:00:00Z')
        } | Should -Throw '*stale*last verified*'
    }

    It 'allows scheduled patch validation when only generic matrix verification is stale' {
        $Matrix = Get-Content -LiteralPath $script:TestMatrixPath -Raw | ConvertFrom-Json
        $Matrix.lastVerifiedUtc = '2026-07-01T00:00:00Z'
        ($Matrix.profiles | Where-Object powerShellMinor -EQ 4).supportPolicy.evidenceVerifiedUtc = '2026-07-01T00:00:00Z'
        foreach ($RuntimeProfile in @($Matrix.profiles | Where-Object { $null -ne $_.supportPolicy })) {
            $RuntimeProfile.supportPolicy.decisionDate = '2026-07-01'
        }
        $MatrixFixture = Join-Path $TestDrive 'matrix-scheduled-stale.json'
        $Matrix | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $MatrixFixture -Encoding UTF8
        $Warnings = @()

        $Result = @(& $script:PolicyTestScriptPath -TestMatrixPath $MatrixFixture -Mode Scheduled -AsOfUtc ([datetime]'2026-09-15T00:00:00Z') -PassThru -WarningVariable Warnings)

        $Result | Should -HaveCount 3
        @($Result | Where-Object Status -In @('Expired', 'HoldoverReviewDue')) | Should -BeNullOrEmpty
        ($Warnings -join [Environment]::NewLine) | Should -Match 'lifecycle evidence is stale'
    }

    It 'uses a release-current live discovery report as fresh lifecycle evidence' {
        $MatrixFixture = Get-TestMatrixFixturePath -Name 'matrix-live-evidence' -EvidenceVerifiedUtc '2026-09-15T00:00:00Z' -LastVerifiedUtc '2026-09-15T00:00:00Z'
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

        $result = @(& $script:PolicyTestScriptPath -TestMatrixPath $MatrixFixture -Mode Release -AsOfUtc ([datetime]'2026-09-15T00:01:00Z') -LifecycleEvidencePath $EvidencePath -PassThru)

        $result | Should -HaveCount 3
    }

    It 'rejects general lifecycle evidence dated after the evaluation time' {
        $MatrixFixture = Get-TestMatrixFixturePath -Name 'matrix-future-lifecycle-evidence' -EvidenceVerifiedUtc '2026-09-15T00:00:00Z' -LastVerifiedUtc '2026-09-15T00:02:00Z'

        { & $script:PolicyTestScriptPath -TestMatrixPath $MatrixFixture -Mode Release -AsOfUtc ([datetime]'2026-09-15T00:01:00Z') } |
            Should -Throw '*lifecycle evidence cannot be verified in the future*'
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

    It 'rejects live discovery evidence with unresolved support-contract review' {
        $EvidencePath = Join-Path $TestDrive 'support-contract-review-evidence.json'
        @{
            schemaVersion = 1
            generatedAtUtc = '2026-09-15T00:00:00Z'
            patchUpdates = @()
            newLines = @()
            lifecycle = @(
                @{ releaseLine = '7.4'; status = 'RetiringSoon' }
                @{ releaseLine = '7.5'; status = 'RetiringSoon' }
                @{ releaseLine = '7.6'; status = 'Supported' }
            )
            lifecycleDateChanges = @()
            lifecycleMissingLines = @()
            undeclaredSupportedLines = @()
            supportContractReviewRequired = $true
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $EvidencePath -Encoding utf8

        { & $script:PolicyTestScriptPath -Mode Release -AsOfUtc ([datetime]'2026-09-15T00:01:00Z') -LifecycleEvidencePath $EvidencePath } |
            Should -Throw '*not release-current*support-contract review required*'
    }
}
