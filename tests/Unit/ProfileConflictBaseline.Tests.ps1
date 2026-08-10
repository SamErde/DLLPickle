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
        $normalizedPath = Join-Path $root 'candidate-evidence.json'
        $committedEvidencePath = Join-Path $root 'accepted-evidence.json'

        $EvidenceContent = [ordered]@{
            profile = [ordered]@{ profileKey = 'ps7.6-net10.0-windows-x64' }
            validation = [ordered]@{
                deterministicImportNoAuth = [ordered]@{
                    status = 'passed'
                    writesPerformed = $false
                    conflictSurfaceFingerprint = $CurrentFingerprint
                    scenarioFingerprint = $CurrentScenarioFingerprint
                }
                authenticatedReadOnly = [ordered]@{
                    status = 'not-run-no-approved-credentials'
                    writesPerformed = $false
                }
            }
            marker = 'stable-evidence'
        }
        $CanonicalEvidence = $EvidenceContent | ConvertTo-Json -Depth 100 -Compress
        $EvidenceBytes = [System.Text.Encoding]::UTF8.GetBytes($CanonicalEvidence)
        $EvidenceFingerprint = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($EvidenceBytes)).Replace('-', '').ToLowerInvariant()
        $Evidence = [ordered]@{
            schemaVersion = 1
            contentFingerprint = $EvidenceFingerprint
            provenance = [ordered]@{ sourceRunId = 'fixture' }
            content = $EvidenceContent
        }
        $Evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $normalizedPath -Encoding utf8
        $Evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $committedEvidencePath -Encoding utf8

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
                            evidencePath = 'accepted-evidence.json'
                            evidenceFingerprint = $EvidenceFingerprint
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

        [pscustomobject]@{
            PolicyPath = $policyPath
            MatrixPath = $matrixPath
            ScenarioPath = $scenarioPath
            NormalizedPath = $normalizedPath
            CommittedEvidencePath = $committedEvidencePath
        }
    }
}

Describe 'Profile-specific conflict baseline enforcement' -Tag 'Unit' {
    It 'passes only an accepted unchanged exact-profile baseline' {
        $fixture = Get-ProfileBaselineFixture

        $result = & $script:ToolPath -PolicyPath $fixture.PolicyPath -ConflictMatrixPath $fixture.MatrixPath -ScenarioEvidencePath $fixture.ScenarioPath -NormalizedEvidencePath $fixture.NormalizedPath -PassThru

        $result.Status | Should -Be 'AcceptedUnchanged'
        $result.ProfileKey | Should -Be 'ps7.6-net10.0-windows-x64'
    }

    It 'fails closed when profile evidence has not been accepted' {
        $fixture = Get-ProfileBaselineFixture -Status 'requires-profile-refresh' -BaselineFingerprint $null

        { & $script:ToolPath -PolicyPath $fixture.PolicyPath -ConflictMatrixPath $fixture.MatrixPath -ScenarioEvidencePath $fixture.ScenarioPath -NormalizedEvidencePath $fixture.NormalizedPath } |
            Should -Throw '*not accepted*requires-profile-refresh*'
    }

    It 'fails closed when the accepted profile fingerprint drifts' {
        $fixture = Get-ProfileBaselineFixture -CurrentFingerprint ('b' * 64)

        { & $script:ToolPath -PolicyPath $fixture.PolicyPath -ConflictMatrixPath $fixture.MatrixPath -ScenarioEvidencePath $fixture.ScenarioPath -NormalizedEvidencePath $fixture.NormalizedPath } |
            Should -Throw '*drift*baseline*current*'
    }

    It 'fails closed when deterministic import-order evidence drifts' {
        $fixture = Get-ProfileBaselineFixture -CurrentScenarioFingerprint ('c' * 64)

        { & $script:ToolPath -PolicyPath $fixture.PolicyPath -ConflictMatrixPath $fixture.MatrixPath -ScenarioEvidencePath $fixture.ScenarioPath -NormalizedEvidencePath $fixture.NormalizedPath } |
            Should -Throw '*profile evidence drift*'
    }

    It 'fails closed when normalized evidence content drifts independently' {
        $fixture = Get-ProfileBaselineFixture
        $Candidate = Get-Content -LiteralPath $fixture.NormalizedPath -Raw | ConvertFrom-Json
        $Candidate.content.marker = 'changed-evidence'
        $CanonicalContent = $Candidate.content | ConvertTo-Json -Depth 100 -Compress
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($CanonicalContent)
        $Candidate.contentFingerprint = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($Bytes)).Replace('-', '').ToLowerInvariant()
        $Candidate | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $fixture.NormalizedPath -Encoding UTF8

        { & $script:ToolPath -PolicyPath $fixture.PolicyPath -ConflictMatrixPath $fixture.MatrixPath -ScenarioEvidencePath $fixture.ScenarioPath -NormalizedEvidencePath $fixture.NormalizedPath } |
            Should -Throw '*profile evidence drift*baseline evidence*current evidence*'
    }

    It 'rejects normalized candidate evidence whose content fingerprint was tampered' {
        $fixture = Get-ProfileBaselineFixture
        $Candidate = Get-Content -LiteralPath $fixture.NormalizedPath -Raw | ConvertFrom-Json
        $Candidate.content.marker = 'tampered-without-rehash'
        $Candidate | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $fixture.NormalizedPath -Encoding UTF8

        { & $script:ToolPath -PolicyPath $fixture.PolicyPath -ConflictMatrixPath $fixture.MatrixPath -ScenarioEvidencePath $fixture.ScenarioPath -NormalizedEvidencePath $fixture.NormalizedPath } |
            Should -Throw '*does not recompute*'
    }

    It 'rejects a tampered committed snapshot even when the candidate is unchanged' {
        $fixture = Get-ProfileBaselineFixture
        $Committed = Get-Content -LiteralPath $fixture.CommittedEvidencePath -Raw | ConvertFrom-Json
        $Committed.content.marker = 'tampered-committed-evidence'
        $Committed | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $fixture.CommittedEvidencePath -Encoding UTF8

        { & $script:ToolPath -PolicyPath $fixture.PolicyPath -ConflictMatrixPath $fixture.MatrixPath -ScenarioEvidencePath $fixture.ScenarioPath -NormalizedEvidencePath $fixture.NormalizedPath } |
            Should -Throw '*accepted evidence*does not recompute*policy fingerprint*'
    }

    It 'rejects a conflict matrix whose key does not match its profile fields' {
        $fixture = Get-ProfileBaselineFixture
        $Matrix = Get-Content -LiteralPath $fixture.MatrixPath -Raw | ConvertFrom-Json
        $Matrix.ProfileKey = 'ps7.6-net10.0-linux-x64'
        $Matrix | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $fixture.MatrixPath -Encoding UTF8

        { & $script:ToolPath -PolicyPath $fixture.PolicyPath -ConflictMatrixPath $fixture.MatrixPath -ScenarioEvidencePath $fixture.ScenarioPath -NormalizedEvidencePath $fixture.NormalizedPath } |
            Should -Throw '*does not match derived profile key*'
    }

    It 'rejects scenario metadata whose key does not match its profile fields' {
        $fixture = Get-ProfileBaselineFixture
        $Scenario = Get-Content -LiteralPath $fixture.ScenarioPath -Raw | ConvertFrom-Json
        $Scenario.Profile.Platform = 'linux'
        $Scenario | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $fixture.ScenarioPath -Encoding UTF8

        { & $script:ToolPath -PolicyPath $fixture.PolicyPath -ConflictMatrixPath $fixture.MatrixPath -ScenarioEvidencePath $fixture.ScenarioPath -NormalizedEvidencePath $fixture.NormalizedPath } |
            Should -Throw '*does not match derived profile key*'
    }

    It 'rejects scenario rows observed on a different platform or architecture' {
        $fixture = Get-ProfileBaselineFixture
        $Scenario = Get-Content -LiteralPath $fixture.ScenarioPath -Raw | ConvertFrom-Json
        $Scenario.Scenarios[0].Assemblies[0].Platform = 'linux'
        $Scenario.Scenarios[0].Assemblies[0].Architecture = 'arm64'
        $Scenario | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $fixture.ScenarioPath -Encoding UTF8

        { & $script:ToolPath -PolicyPath $fixture.PolicyPath -ConflictMatrixPath $fixture.MatrixPath -ScenarioEvidencePath $fixture.ScenarioPath -NormalizedEvidencePath $fixture.NormalizedPath } |
            Should -Throw '*observed on*linux/arm64*expected*windows/x64*'
    }

    It 'writes a stable finding before an unaccepted baseline fails closed' {
        $fixture = Get-ProfileBaselineFixture -Status 'requires-profile-refresh' -BaselineFingerprint $null
        $OutputPath = Join-Path $TestDrive 'baseline-comparison.json'

        $Parameters = @{
            PolicyPath = $fixture.PolicyPath
            ConflictMatrixPath = $fixture.MatrixPath
            ScenarioEvidencePath = $fixture.ScenarioPath
            NormalizedEvidencePath = $fixture.NormalizedPath
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
            BaselineEvidenceFingerprint = $null
            CurrentEvidenceFingerprint = 'd' * 64
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
