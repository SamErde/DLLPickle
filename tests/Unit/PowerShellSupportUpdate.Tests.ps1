BeforeAll {
    Set-Location -Path $PSScriptRoot
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:DiscoveryPath = Join-Path $ProjectRoot 'tools\Get-DLLPicklePowerShellSupportUpdate.ps1'
    $script:MatrixUpdatePath = Join-Path $ProjectRoot 'tools\Update-DLLPicklePowerShellTestMatrix.ps1'

    function Get-SupportUpdateFixture {
        param(
            [string]$Root,
            [string[]]$ReleaseVersions
        )

        $MatrixPath = Join-Path $Root 'matrix.json'
        $ReleasePath = Join-Path $Root 'releases.json'
        $LifecyclePath = Join-Path $Root 'lifecycle.html'
        @{
            schemaVersion = 1
            lifecycleSourceUrl = 'https://learn.microsoft.com/en-us/lifecycle/products/powershell'
            retirementWarningDays = 90
            profiles = @(
                @{ powerShellVersion = '7.4.18'; powerShellMajor = 7; powerShellMinor = 4; dotnetMajor = 8; dotnetRuntimeVersion = '8.0.29'; targetFramework = 'net8.0'; lifecycleEndDate = '2026-11-10' }
                @{ powerShellVersion = '7.5.9'; powerShellMajor = 7; powerShellMinor = 5; dotnetMajor = 9; dotnetRuntimeVersion = '9.0.18'; targetFramework = 'net9.0'; lifecycleEndDate = '2026-11-10' }
                @{ powerShellVersion = '7.6.4'; powerShellMajor = 7; powerShellMinor = 6; dotnetMajor = 10; dotnetRuntimeVersion = '10.0.10'; targetFramework = 'net10.0'; lifecycleEndDate = '2028-11-14' }
            )
            lanes = @(
                @{ platform = 'windows'; architecture = 'x64' }
                @{ platform = 'linux'; architecture = 'x64' }
                @{ platform = 'macos'; architecture = 'x64' }
            )
            archiveAssets = @(
                foreach ($Version in @('7.4.18', '7.5.9', '7.6.4')) {
                    foreach ($Asset in @(
                            @{ platform = 'windows'; file = "PowerShell-$Version-win-x64.zip" }
                            @{ platform = 'linux'; file = "powershell-$Version-linux-x64.tar.gz" }
                            @{ platform = 'macos'; file = "powershell-$Version-osx-x64.tar.gz" }
                        )) {
                        @{ powerShellVersion = $Version; platform = $Asset.platform; architecture = 'x64'; fileName = $Asset.file; sha256 = ('b' * 64); downloadUrl = "https://example.invalid/$($Asset.file)" }
                    }
                }
            )
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $MatrixPath -Encoding UTF8

        @(
            foreach ($Version in $ReleaseVersions) {
                $Assets = foreach ($FileName in @("PowerShell-$Version-win-x64.zip", "powershell-$Version-linux-x64.tar.gz", "powershell-$Version-osx-x64.tar.gz")) {
                    @{ name = $FileName; browser_download_url = "https://example.invalid/$FileName"; digest = 'sha256:' + ('a' * 64) }
                }
                @{ tag_name = "v$Version"; draft = $false; prerelease = $false; published_at = '2026-08-01T00:00:00Z'; html_url = "https://example.invalid/v$Version"; assets = @($Assets) }
            }
        ) | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ReleasePath -Encoding UTF8

        $LifecycleRows = @(
            '<tr><td>PowerShell 7.4 (LTS)</td><td><local-time datetime="11/16/2023 8:00:00 AM"></local-time></td><td><local-time datetime="11/11/2026 6:59:59 AM"></local-time></td></tr>'
            '<tr><td>PowerShell 7.5</td><td><local-time datetime="1/23/2025 8:00:00 AM"></local-time></td><td><local-time datetime="11/11/2026 6:59:59 AM"></local-time></td></tr>'
            '<tr><td>PowerShell 7.6 (LTS)</td><td><local-time datetime="3/18/2026 8:00:00 AM"></local-time></td><td><local-time datetime="11/15/2028 6:59:59 AM"></local-time></td></tr>'
            if (@($ReleaseVersions | Where-Object { [version]$_ -ge [version]'7.7.0' }).Count -gt 0) {
                '<tr><td>PowerShell 7.7</td><td><local-time datetime="1/20/2027 8:00:00 AM"></local-time></td><td><local-time datetime="5/12/2028 6:59:59 AM"></local-time></td></tr>'
            }
        )
        "<table>$($LifecycleRows -join '')</table>" | Set-Content -LiteralPath $LifecyclePath -Encoding UTF8

        [PSCustomObject]@{ MatrixPath = $MatrixPath; ReleasePath = $ReleasePath; LifecyclePath = $LifecyclePath }
    }
}

Describe 'PowerShell support update discovery' -Tag 'Unit' {
    It 'passes release-current validation when exact pins are newest' {
        $Fixture = Get-SupportUpdateFixture -Root $TestDrive -ReleaseVersions @('7.4.18', '7.5.9', '7.6.4')
        $Report = & $script:DiscoveryPath -TestMatrixPath $Fixture.MatrixPath -ReleaseDataPath $Fixture.ReleasePath -LifecycleDataPath $Fixture.LifecyclePath -OutputPath (Join-Path $TestDrive 'current.json') -AsOfUtc '2026-08-08T00:00:00Z' -RequireCurrent

        @($Report.PatchUpdates) | Should -HaveCount 0
        @($Report.NewLines) | Should -HaveCount 0
        $Report.ProposalPublishingStatus | Should -Be 'pending-workflow-publication'
        $Report.PatchProposalFingerprint | Should -Match '^[a-f0-9]{64}$'
        $Report.SupportContractFingerprint | Should -Match '^[a-f0-9]{64}$'
    }

    It 'produces a checksum-complete matrix-only patch proposal' {
        $Fixture = Get-SupportUpdateFixture -Root $TestDrive -ReleaseVersions @('7.4.18', '7.5.10', '7.6.4')
        $Report = & $script:DiscoveryPath -TestMatrixPath $Fixture.MatrixPath -ReleaseDataPath $Fixture.ReleasePath -LifecycleDataPath $Fixture.LifecyclePath -OutputPath (Join-Path $TestDrive 'patch.json') -AsOfUtc '2026-08-08T00:00:00Z'

        @($Report.PatchUpdates) | Should -HaveCount 1
        $Report.PatchUpdates[0].CandidateVersion | Should -Be '7.5.10'
        @($Report.PatchUpdates[0].Archives) | Should -HaveCount 3
        $Report.PatchUpdates[0].ChecksumsComplete | Should -BeTrue
        $Report.MatrixOnlyUpdateAvailable | Should -BeTrue
        $Report.PatchProposalMarker | Should -Be "<!-- dllpickle-finding-fingerprint:$($Report.PatchProposalFingerprint) -->"
    }

    It 'finalizes a patch-only matrix proposal only after every lane reports one consistent runtime' {
        $Fixture = Get-SupportUpdateFixture -Root $TestDrive -ReleaseVersions @('7.4.18', '7.5.10', '7.6.4')
        $ReportPath = Join-Path $TestDrive 'patch-report.json'
        $null = & $script:DiscoveryPath -TestMatrixPath $Fixture.MatrixPath -ReleaseDataPath $Fixture.ReleasePath -LifecycleDataPath $Fixture.LifecyclePath -OutputPath $ReportPath -AsOfUtc '2026-08-08T00:00:00Z'
        $CandidatePath = Join-Path $TestDrive 'candidate-matrix.json'
        $Preparation = & $script:MatrixUpdatePath -TestMatrixPath $Fixture.MatrixPath -UpdateReportPath $ReportPath -OutputPath $CandidatePath -PrepareCandidate
        $Preparation.Mode | Should -Be 'CandidatePreparation'
        (Get-Content -LiteralPath $CandidatePath -Raw | ConvertFrom-Json).candidateValidationPending | Should -BeTrue

        $IdentityDirectory = Join-Path $TestDrive 'identities'
        $null = New-Item -Path $IdentityDirectory -ItemType Directory
        foreach ($Platform in @('windows', 'linux', 'macos')) {
            @{
                PowerShellVersion = '7.5.10'
                DotNetVersion = '9.0.19'
                Platform = $Platform
                Architecture = 'x64'
                TargetFramework = 'net9.0'
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $IdentityDirectory "$Platform.json") -Encoding UTF8
        }
        @{ PowerShellVersion = '7.5.10'; Platform = 'windows' } |
            ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $IdentityDirectory 'malformed.json') -Encoding UTF8
        $FinalPath = Join-Path $TestDrive 'final-matrix.json'
        $IdentityWarnings = @()
        $Final = & $script:MatrixUpdatePath -TestMatrixPath $Fixture.MatrixPath -UpdateReportPath $ReportPath -OutputPath $FinalPath -RuntimeIdentityPath $IdentityDirectory -VerifiedAtUtc '2026-08-08T12:34:56Z' -WarningVariable IdentityWarnings
        $Final.Mode | Should -Be 'VerifiedProposal'
        ($IdentityWarnings -join [Environment]::NewLine) | Should -Match 'malformed\.json.*DotNetVersion.*Architecture'
        $Updated = Get-Content -LiteralPath $FinalPath -Raw | ConvertFrom-Json
        @($Updated.profiles | Where-Object powerShellVersion -EQ '7.5.10') | Should -HaveCount 1
        @($Updated.profiles | Where-Object powerShellVersion -EQ '7.5.10')[0].dotnetRuntimeVersion | Should -Be '9.0.19'
        @($Updated.archiveAssets | Where-Object powerShellVersion -EQ '7.5.10') | Should -HaveCount 3
        ([datetime]$Updated.lastVerifiedUtc).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') | Should -Be '2026-08-08T12:34:56Z'
        $Updated.PSObject.Properties.Name | Should -Not -Contain 'candidateValidationPending'
    }

    It 'routes a new GA minor line to support-contract review and fails release-current validation' {
        $Fixture = Get-SupportUpdateFixture -Root $TestDrive -ReleaseVersions @('7.4.18', '7.5.9', '7.6.4', '7.7.0')
        $Parameters = @{
            TestMatrixPath = $Fixture.MatrixPath
            ReleaseDataPath = $Fixture.ReleasePath
            LifecycleDataPath = $Fixture.LifecyclePath
            OutputPath = Join-Path $TestDrive 'new-line.json'
            AsOfUtc = '2026-08-08T00:00:00Z'
            RequireCurrent = $true
        }

        { & $script:DiscoveryPath @Parameters } | Should -Throw '*new GA PowerShell lines: 7.7*'
        $Report = Get-Content -LiteralPath $Parameters.OutputPath -Raw | ConvertFrom-Json
        $Report.SupportContractReviewRequired | Should -BeTrue
        $Report.NewLines[0].RequiredDecision | Should -Match 'CLR/TFM'
        $Report.SupportContractMarker | Should -Be "<!-- dllpickle-finding-fingerprint:$($Report.SupportContractFingerprint) -->"
    }

    It 'keeps a retirement-warning fingerprint stable while the remaining day count changes' {
        $Fixture = Get-SupportUpdateFixture -Root $TestDrive -ReleaseVersions @('7.4.18', '7.5.9', '7.6.4')
        $First = & $script:DiscoveryPath -TestMatrixPath $Fixture.MatrixPath -ReleaseDataPath $Fixture.ReleasePath -LifecycleDataPath $Fixture.LifecyclePath -OutputPath (Join-Path $TestDrive 'retirement-first.json') -AsOfUtc '2026-08-15T00:00:00Z'
        $Second = & $script:DiscoveryPath -TestMatrixPath $Fixture.MatrixPath -ReleaseDataPath $Fixture.ReleasePath -LifecycleDataPath $Fixture.LifecyclePath -OutputPath (Join-Path $TestDrive 'retirement-second.json') -AsOfUtc '2026-08-16T00:00:00Z'

        $First.SupportContractReviewRequired | Should -BeTrue
        @($First.Lifecycle | Where-Object Status -EQ 'RetiringSoon') | Should -HaveCount 2
        $First.SupportContractFingerprint | Should -BeExactly $Second.SupportContractFingerprint
    }
}
