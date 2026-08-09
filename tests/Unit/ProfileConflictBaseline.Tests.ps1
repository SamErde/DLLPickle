BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ToolPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'tools/Test-DLLPickleProfileConflictBaseline.ps1'

    function Get-ProfileBaselineFixture {
        param(
            [string]$Status = 'accepted',
            [string]$BaselineFingerprint = ('a' * 64),
            [string]$CurrentFingerprint = ('a' * 64),
            [string]$BaselineScenarioFingerprint = ('b' * 64),
            [string]$CurrentScenarioFingerprint = ('b' * 64)
        )

        $root = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('n'))
        $null = New-Item -Path $root -ItemType Directory -Force
        $policyPath = Join-Path $root 'policy.json'
        $matrixPath = Join-Path $root 'matrix.json'
        $scenarioPath = Join-Path $root 'scenario.json'
        [ordered]@{
            runtimeProfiles = @(
                [ordered]@{
                    powerShellLine = '7.6'
                    targetFramework = 'net10.0'
                    baselines = [ordered]@{
                        windows = [ordered]@{
                            status = $Status
                            conflictSurfaceFingerprint = $BaselineFingerprint
                            scenarioFingerprint = $BaselineScenarioFingerprint
                        }
                    }
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $policyPath -Encoding utf8
        [ordered]@{
            ProfileKey = 'ps7.6-net10.0-windows-x64'
            Profile = [ordered]@{
                PowerShellLine = '7.6'
                TargetFramework = 'net10.0'
                Platform = 'windows'
                Architecture = 'x64'
            }
            Fingerprint = $CurrentFingerprint
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $matrixPath -Encoding utf8

        [ordered]@{
            ProfileKey = 'ps7.6-net10.0-windows-x64'
            Profile = [ordered]@{
                PowerShellLine = '7.6'
                TargetFramework = 'net10.0'
                Platform = 'windows'
                Architecture = 'x64'
            }
            ValidationTier = 'deterministic-import-no-auth'
            WritesPerformed = $false
            Passed = $true
            ScenarioFingerprint = $CurrentScenarioFingerprint
            Scenarios = @(
                [ordered]@{
                    Assemblies = @(
                        [ordered]@{
                            Name = 'Microsoft.Identity.Client'
                            Platform = 'windows'
                            Architecture = 'x64'
                        }
                    )
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $scenarioPath -Encoding utf8

        [pscustomobject]@{ PolicyPath = $policyPath; MatrixPath = $matrixPath; ScenarioPath = $scenarioPath }
    }
}

Describe 'Profile-specific conflict baseline enforcement' -Tag 'Unit' {
    It 'passes only an accepted unchanged exact-profile baseline' {
        $fixture = Get-ProfileBaselineFixture

        $result = & $script:ToolPath -PolicyPath $fixture.PolicyPath -ConflictMatrixPath $fixture.MatrixPath -ScenarioEvidencePath $fixture.ScenarioPath -PassThru

        $result.Status | Should -Be 'AcceptedUnchanged'
        $result.ProfileKey | Should -Be 'ps7.6-net10.0-windows-x64'
    }

    It 'fails closed when profile evidence has not been accepted' {
        $fixture = Get-ProfileBaselineFixture -Status 'requires-profile-refresh' -BaselineFingerprint $null

        { & $script:ToolPath -PolicyPath $fixture.PolicyPath -ConflictMatrixPath $fixture.MatrixPath -ScenarioEvidencePath $fixture.ScenarioPath } |
            Should -Throw '*not accepted*requires-profile-refresh*'
    }

    It 'fails closed when the accepted profile fingerprint drifts' {
        $fixture = Get-ProfileBaselineFixture -CurrentFingerprint ('b' * 64)

        { & $script:ToolPath -PolicyPath $fixture.PolicyPath -ConflictMatrixPath $fixture.MatrixPath -ScenarioEvidencePath $fixture.ScenarioPath } |
            Should -Throw '*drift*baseline*current*'
    }

    It 'fails closed when deterministic import-order evidence drifts' {
        $fixture = Get-ProfileBaselineFixture -CurrentScenarioFingerprint ('c' * 64)

        { & $script:ToolPath -PolicyPath $fixture.PolicyPath -ConflictMatrixPath $fixture.MatrixPath -ScenarioEvidencePath $fixture.ScenarioPath } |
            Should -Throw '*scenario drift*'
    }

    It 'rejects a conflict matrix whose key does not match its profile fields' {
        $fixture = Get-ProfileBaselineFixture
        $Matrix = Get-Content -LiteralPath $fixture.MatrixPath -Raw | ConvertFrom-Json
        $Matrix.ProfileKey = 'ps7.6-net10.0-linux-x64'
        $Matrix | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $fixture.MatrixPath -Encoding UTF8

        { & $script:ToolPath -PolicyPath $fixture.PolicyPath -ConflictMatrixPath $fixture.MatrixPath -ScenarioEvidencePath $fixture.ScenarioPath } |
            Should -Throw '*does not match derived profile key*'
    }

    It 'rejects scenario metadata whose key does not match its profile fields' {
        $fixture = Get-ProfileBaselineFixture
        $Scenario = Get-Content -LiteralPath $fixture.ScenarioPath -Raw | ConvertFrom-Json
        $Scenario.Profile.Platform = 'linux'
        $Scenario | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $fixture.ScenarioPath -Encoding UTF8

        { & $script:ToolPath -PolicyPath $fixture.PolicyPath -ConflictMatrixPath $fixture.MatrixPath -ScenarioEvidencePath $fixture.ScenarioPath } |
            Should -Throw '*does not match derived profile key*'
    }

    It 'rejects scenario rows observed on a different platform or architecture' {
        $fixture = Get-ProfileBaselineFixture
        $Scenario = Get-Content -LiteralPath $fixture.ScenarioPath -Raw | ConvertFrom-Json
        $Scenario.Scenarios[0].Assemblies[0].Platform = 'linux'
        $Scenario.Scenarios[0].Assemblies[0].Architecture = 'arm64'
        $Scenario | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $fixture.ScenarioPath -Encoding UTF8

        { & $script:ToolPath -PolicyPath $fixture.PolicyPath -ConflictMatrixPath $fixture.MatrixPath -ScenarioEvidencePath $fixture.ScenarioPath } |
            Should -Throw '*observed on*linux/arm64*expected*windows/x64*'
    }

    It 'writes a stable finding before an unaccepted baseline fails closed' {
        $fixture = Get-ProfileBaselineFixture -Status 'requires-profile-refresh' -BaselineFingerprint $null
        $OutputPath = Join-Path $TestDrive 'baseline-comparison.json'

        $Parameters = @{
            PolicyPath = $fixture.PolicyPath
            ConflictMatrixPath = $fixture.MatrixPath
            ScenarioEvidencePath = $fixture.ScenarioPath
            OutputPath = $OutputPath
        }
        { & $script:ToolPath @Parameters } | Should -Throw '*not accepted*'
        $Result = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json
        $Result.Status | Should -Be 'RequiresAcceptance'
        $Result.FindingFingerprint | Should -Match '^[a-f0-9]{64}$'
    }
}

Describe 'Finding fingerprint report deduplication' -Tag 'Unit' {
    It 'matches only the exact stable marker' {
        $ScriptPath = Join-Path $script:RepositoryRoot 'tools\Test-DLLPickleFindingFingerprintReported.ps1'
        $Fingerprint = 'a' * 64
        & $ScriptPath -Fingerprint $Fingerprint -Text @('ordinary text', "<!-- dllpickle-finding-fingerprint:$Fingerprint -->") | Should -BeTrue
        & $ScriptPath -Fingerprint $Fingerprint -Text @('ordinary text', '<!-- dllpickle-finding-fingerprint:bbbb -->') | Should -BeFalse
    }

    It 'aggregates profile findings into one deterministic marker' {
        $SummaryScriptPath = Join-Path $script:RepositoryRoot 'tools\New-DLLPickleProfileEvidenceSummary.ps1'
        $MatrixPath = Join-Path $TestDrive 'summary-matrix.json'
        $EvidenceRoot = Join-Path $TestDrive 'summary-evidence'
        $null = New-Item -Path $EvidenceRoot -ItemType Directory
        @{
            profiles = @(@{ powerShellMajor = 7; powerShellMinor = 6; targetFramework = 'net10.0' })
            lanes = @(@{ platform = 'windows'; architecture = 'x64' })
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $MatrixPath -Encoding UTF8
        @{
            ProfileKey = 'ps7.6-net10.0-windows-x64'
            Status = 'RequiresAcceptance'
            BaselineStatus = 'requires-profile-refresh'
            BaselineFingerprint = $null
            CurrentFingerprint = 'b' * 64
            FindingFingerprint = 'c' * 64
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceRoot 'baseline-comparison.json') -Encoding UTF8

        $First = & $SummaryScriptPath -EvidenceRoot $EvidenceRoot -TestMatrixPath $MatrixPath -OutputPath (Join-Path $TestDrive 'first-summary.json')
        $Second = & $SummaryScriptPath -EvidenceRoot $EvidenceRoot -TestMatrixPath $MatrixPath -OutputPath (Join-Path $TestDrive 'second-summary.json')

        $First.AllProfileEvidencePresent | Should -BeTrue
        $First.ReadyForCandidateUpdate | Should -BeFalse
        $First.AggregateFindingFingerprint | Should -BeExactly $Second.AggregateFindingFingerprint
        $First.FindingMarker | Should -Be "<!-- dllpickle-finding-fingerprint:$($First.AggregateFindingFingerprint) -->"
    }
}
