BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ToolPath = Join-Path $script:RepositoryRoot 'tools\Test-DLLPickleManualAuthenticatedEvidence.ps1'
    $script:FingerprintToolPath = Join-Path $script:RepositoryRoot 'tools\Get-DLLPickleBundleSourceFingerprint.ps1'
    $script:TestMatrixPath = Join-Path $script:RepositoryRoot 'build\powershell-test-matrix.json'
    $script:DependencyPolicyPath = Join-Path $script:RepositoryRoot 'build\dependency-policy.json'

    function Get-ManualEvidenceContentFingerprint {
        param([Parameter(Mandatory)][object]$Evidence)

        $CanonicalContent = $Evidence.content | ConvertTo-Json -Depth 100 -Compress
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($CanonicalContent)
        [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($Bytes)).Replace('-', '').ToLowerInvariant()
    }

    function Get-ManualAuthenticatedEvidenceFixture {
        param(
            [Parameter(Mandatory)][string]$Path,
            [ValidateSet('pending', 'accepted')][string]$AcceptanceStatus = 'accepted'
        )

        $Matrix = Get-Content -LiteralPath $script:TestMatrixPath -Raw | ConvertFrom-Json
        $Policy = Get-Content -LiteralPath $script:DependencyPolicyPath -Raw | ConvertFrom-Json
        $Bundle = & $script:FingerprintToolPath -RepositoryRoot $script:RepositoryRoot
        $ProbeMap = [ordered]@{
            graph = @('graph-context', 'graph-me-read')
            exo = @('exo-mailbox-read')
            az = @('az-context', 'az-resource-read', 'az-storage-account-read')
            teams = @('teams-tenant-read')
            cross = @('graph-context', 'graph-me-read', 'exo-mailbox-read', 'az-context', 'teams-tenant-read')
        }
        $AudienceMap = [ordered]@{
            graph = @('https://graph.microsoft.com')
            exo = @('https://outlook.office365.com')
            az = @('https://management.azure.com')
            teams = @('https://api.spaces.skype.com')
            cross = @('https://api.spaces.skype.com', 'https://graph.microsoft.com', 'https://management.azure.com', 'https://outlook.office365.com')
        }
        $Profiles = @(
            foreach ($RuntimeProfile in @($Matrix.profiles)) {
                $PowerShellLine = '{0}.{1}' -f $RuntimeProfile.powerShellMajor, $RuntimeProfile.powerShellMinor
                $InventoryFingerprint = 'c' * 64
                $ProfilePolicy = @($Policy.runtimeProfiles | Where-Object powerShellLine -eq $PowerShellLine)[0]
                $ScenarioDefinitions = @(
                    [pscustomobject]@{ Id = 'graph-module-only'; Provider = 'graph'; Order = @('Microsoft.Graph.Authentication') }
                    [pscustomobject]@{ Id = 'graph-dllpickle-first'; Provider = 'graph'; Order = @('Microsoft.Graph.Authentication') }
                    [pscustomobject]@{ Id = 'graph-module-first'; Provider = 'graph'; Order = @('Microsoft.Graph.Authentication') }
                    [pscustomobject]@{ Id = 'exo-module-only'; Provider = 'exo'; Order = @('ExchangeOnlineManagement') }
                    [pscustomobject]@{ Id = 'exo-dllpickle-first'; Provider = 'exo'; Order = @('ExchangeOnlineManagement') }
                    [pscustomobject]@{ Id = 'exo-module-first'; Provider = 'exo'; Order = @('ExchangeOnlineManagement') }
                    [pscustomobject]@{ Id = 'az-module-only'; Provider = 'az'; Order = @('Az.Accounts', 'Az.Resources', 'Az.Storage') }
                    [pscustomobject]@{ Id = 'az-dllpickle-first'; Provider = 'az'; Order = @('Az.Accounts', 'Az.Resources', 'Az.Storage') }
                    [pscustomobject]@{ Id = 'az-module-first'; Provider = 'az'; Order = @('Az.Accounts', 'Az.Resources', 'Az.Storage') }
                    [pscustomobject]@{ Id = 'teams-module-only'; Provider = 'teams'; Order = @('MicrosoftTeams') }
                    [pscustomobject]@{ Id = 'teams-dllpickle-first'; Provider = 'teams'; Order = @('MicrosoftTeams') }
                    [pscustomobject]@{ Id = 'teams-module-first'; Provider = 'teams'; Order = @('MicrosoftTeams') }
                    [pscustomobject]@{ Id = 'cross-import-order-1'; Provider = 'cross'; Order = @($ProfilePolicy.importOrders[0]) }
                    [pscustomobject]@{ Id = 'cross-import-order-2'; Provider = 'cross'; Order = @($ProfilePolicy.importOrders[1]) }
                )
                $Scenarios = @(
                    foreach ($Definition in $ScenarioDefinitions) {
                        [ordered]@{
                            scenarioId = $Definition.Id
                            profileKey = 'ps{0}-{1}-windows-x64' -f $PowerShellLine, $RuntimeProfile.targetFramework
                            powerShellVersion = [string]$RuntimeProfile.powerShellVersion
                            targetFramework = [string]$RuntimeProfile.targetFramework
                            platform = 'windows'
                            architecture = 'x64'
                            inventoryFingerprint = $InventoryFingerprint
                            importOrder = @($Definition.Order)
                            dllPickleTiming = if ($Definition.Id -like 'cross-*' -or $Definition.Id -like '*-dllpickle-first') {
                                'dllpickle-first'
                            } elseif ($Definition.Id -like '*-module-first') {
                                'module-first'
                            } else {
                                'module-only'
                            }
                            expectedTokenAudiences = @($AudienceMap[$Definition.Provider])
                            status = 'passed'
                            writesPerformed = $false
                            errorType = $null
                            probes = @(
                                foreach ($ProbeId in @($ProbeMap[$Definition.Provider])) {
                                    [ordered]@{
                                        probeId = $ProbeId
                                        executed = $true
                                        status = 'passed'
                                        durationMilliseconds = 100
                                        writesPerformed = $false
                                        errorType = $null
                                    }
                                }
                            )
                            snapshots = @(
                                foreach ($Stage in @('before-authentication', 'after-connection', 'after-read-probe')) {
                                    [ordered]@{
                                        stage = $Stage
                                        assemblies = @(
                                            [ordered]@{
                                                name = 'Microsoft.Identity.Client'
                                                version = '4.82.1.0'
                                                sha256 = 'a' * 64
                                                selectedAsset = 'upstream:Synthetic/1.0/lib/Microsoft.Identity.Client.dll'
                                                assemblyLoadContext = 'Default'
                                                isCollectible = $false
                                            }
                                        )
                                    }
                                }
                            )
                        }
                    }
                )
                [ordered]@{
                    profileKey = 'ps{0}-{1}-windows-x64' -f $PowerShellLine, $RuntimeProfile.targetFramework
                    powerShellVersion = [string]$RuntimeProfile.powerShellVersion
                    powerShellLine = $PowerShellLine
                    dotNetVersion = [string]$RuntimeProfile.dotnetRuntimeVersion
                    dotNetMajor = [int]$RuntimeProfile.dotnetMajor
                    targetFramework = [string]$RuntimeProfile.targetFramework
                    platform = 'windows'
                    architecture = 'x64'
                    runtimeExecutable = 'runtime:pwsh.exe'
                    psHome = 'runtime:.'
                    writesPerformed = $false
                    inventoryFingerprint = $InventoryFingerprint
                    moduleVersions = @(
                        foreach ($ModuleName in @($Policy.monitoredModules.name | Sort-Object)) {
                            [ordered]@{
                                name = [string]$ModuleName
                                version = '1.0.0'
                                manifest = "upstream:$ModuleName/1.0.0/$ModuleName.psd1"
                            }
                        }
                    )
                    scenarios = $Scenarios
                }
            }
        )
        $Evidence = [pscustomobject][ordered]@{
            schemaVersion = 1
            evidenceType = 'manual-interactive-transition'
            contentFingerprint = $null
            provenance = [ordered]@{
                sourceCommitSha = 'b' * 40
                captureStartedAtUtc = '2026-08-09T12:00:00Z'
                captureCompletedAtUtc = '2026-08-09T13:00:00Z'
            }
            acceptance = [ordered]@{
                status = $AcceptanceStatus
                acceptedAtUtc = if ($AcceptanceStatus -eq 'accepted') { '2026-08-09T14:00:00Z' } else { $null }
                acceptedBy = if ($AcceptanceStatus -eq 'accepted') { 'maintainer' } else { $null }
                confidence = if ($AcceptanceStatus -eq 'accepted') { 'high' } else { $null }
            }
            content = [ordered]@{
                bridge = [ordered]@{
                    id = 'initial-powershell-7.4-7.6-multitargeting-major'
                    allowedReleaseVersion = '3.0.0'
                    expiresAtUtc = '2026-08-23T12:00:00Z'
                }
                bundleSourceFingerprint = [string]$Bundle.fingerprint
                credentialMode = 'delegated-interactive'
                credentialMaterialCaptured = $false
                authorizationBoundaryValidated = $false
                platformScope = 'windows-x64-only'
                writesPerformed = $false
                profiles = $Profiles
            }
        }
        $Evidence.contentFingerprint = Get-ManualEvidenceContentFingerprint -Evidence $Evidence
        $Evidence | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
        $Evidence
    }
}

Describe 'Time-bounded manual authenticated evidence' -Tag 'Unit' {
    It 'accepts only the complete exact Windows profile transition record' {
        $EvidencePath = Join-Path $TestDrive 'accepted.json'
        $null = Get-ManualAuthenticatedEvidenceFixture -Path $EvidencePath

        $Result = & $script:ToolPath -EvidencePath $EvidencePath -RepositoryRoot $script:RepositoryRoot -TestMatrixPath $script:TestMatrixPath -DependencyPolicyPath $script:DependencyPolicyPath -NowUtc '2026-08-10T00:00:00Z'

        $Result.AllowedReleaseVersion | Should -Be '3.0.0'
        @($Result.ProfileKeys) | Should -HaveCount 3
        $Result.WritesPerformed | Should -BeFalse
    }

    It 'validates a pending capture without allowing it as release evidence' {
        $EvidencePath = Join-Path $TestDrive 'pending.json'
        $null = Get-ManualAuthenticatedEvidenceFixture -Path $EvidencePath -AcceptanceStatus pending

        { & $script:ToolPath -EvidencePath $EvidencePath -RepositoryRoot $script:RepositoryRoot -TestMatrixPath $script:TestMatrixPath -DependencyPolicyPath $script:DependencyPolicyPath -Mode Capture -NowUtc '2026-08-10T00:00:00Z' } | Should -Not -Throw
        { & $script:ToolPath -EvidencePath $EvidencePath -RepositoryRoot $script:RepositoryRoot -TestMatrixPath $script:TestMatrixPath -DependencyPolicyPath $script:DependencyPolicyPath -Mode Release -NowUtc '2026-08-10T00:00:00Z' } | Should -Throw '*not been explicitly accepted*'
    }

    It 'rejects expired evidence' {
        $EvidencePath = Join-Path $TestDrive 'expired.json'
        $null = Get-ManualAuthenticatedEvidenceFixture -Path $EvidencePath

        $ExpiredAt = [System.DateTimeOffset]::Parse('2026-08-24T12:00:00Z')
        { & $script:ToolPath -EvidencePath $EvidencePath -RepositoryRoot $script:RepositoryRoot -TestMatrixPath $script:TestMatrixPath -DependencyPolicyPath $script:DependencyPolicyPath -NowUtc $ExpiredAt } |
            Should -Throw '*expired*'
    }

    It 'rejects a different bundle even when the evidence is re-fingerprinted' {
        $EvidencePath = Join-Path $TestDrive 'bundle-mismatch.json'
        $Evidence = Get-ManualAuthenticatedEvidenceFixture -Path $EvidencePath
        $Evidence.content.bundleSourceFingerprint = 'f' * 64
        $Evidence.contentFingerprint = Get-ManualEvidenceContentFingerprint -Evidence $Evidence
        $Evidence | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8

        { & $script:ToolPath -EvidencePath $EvidencePath -RepositoryRoot $script:RepositoryRoot -TestMatrixPath $script:TestMatrixPath -DependencyPolicyPath $script:DependencyPolicyPath -NowUtc '2026-08-10T00:00:00Z' } |
            Should -Throw '*bound to bundle*current bundle*'
    }

    It 'rejects missing authenticated read coverage' {
        $EvidencePath = Join-Path $TestDrive 'missing-probe.json'
        $Evidence = Get-ManualAuthenticatedEvidenceFixture -Path $EvidencePath
        $GraphScenario = $Evidence.content.profiles[0].scenarios | Where-Object scenarioId -eq 'graph-module-only'
        $GraphScenario.probes = @($GraphScenario.probes | Where-Object probeId -ne 'graph-me-read')
        $Evidence.contentFingerprint = Get-ManualEvidenceContentFingerprint -Evidence $Evidence
        $Evidence | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8

        { & $script:ToolPath -EvidencePath $EvidencePath -RepositoryRoot $script:RepositoryRoot -TestMatrixPath $script:TestMatrixPath -DependencyPolicyPath $script:DependencyPolicyPath -NowUtc '2026-08-10T00:00:00Z' } |
            Should -Throw '*Probe coverage*does not match the required set*'
    }

    It 'rejects any indication of a write' {
        $EvidencePath = Join-Path $TestDrive 'write.json'
        $Evidence = Get-ManualAuthenticatedEvidenceFixture -Path $EvidencePath
        $Evidence.content.writesPerformed = $true
        $Evidence.contentFingerprint = Get-ManualEvidenceContentFingerprint -Evidence $Evidence
        $Evidence | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8

        { & $script:ToolPath -EvidencePath $EvidencePath -RepositoryRoot $script:RepositoryRoot -TestMatrixPath $script:TestMatrixPath -DependencyPolicyPath $script:DependencyPolicyPath -NowUtc '2026-08-10T00:00:00Z' } |
            Should -Throw '*zero-write*'
    }

    It 'rejects a checkpoint copied from a different runtime profile' {
        $EvidencePath = Join-Path $TestDrive 'wrong-scenario-profile.json'
        $Evidence = Get-ManualAuthenticatedEvidenceFixture -Path $EvidencePath
        $Evidence.content.profiles[0].scenarios[0].profileKey = 'ps7.6-net10.0-windows-x64'
        $Evidence.contentFingerprint = Get-ManualEvidenceContentFingerprint -Evidence $Evidence
        $Evidence | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8

        { & $script:ToolPath -EvidencePath $EvidencePath -RepositoryRoot $script:RepositoryRoot -TestMatrixPath $script:TestMatrixPath -DependencyPolicyPath $script:DependencyPolicyPath -NowUtc '2026-08-10T00:00:00Z' } |
            Should -Throw '*not bound to exact profile*'
    }

    It 'rejects a scenario checkpoint from a different prepared inventory' {
        $EvidencePath = Join-Path $TestDrive 'wrong-scenario-inventory.json'
        $Evidence = Get-ManualAuthenticatedEvidenceFixture -Path $EvidencePath
        $Evidence.content.profiles[0].scenarios[0].inventoryFingerprint = 'd' * 64
        $Evidence.contentFingerprint = Get-ManualEvidenceContentFingerprint -Evidence $Evidence
        $Evidence | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8

        { & $script:ToolPath -EvidencePath $EvidencePath -RepositoryRoot $script:RepositoryRoot -TestMatrixPath $script:TestMatrixPath -DependencyPolicyPath $script:DependencyPolicyPath -NowUtc '2026-08-10T00:00:00Z' } |
            Should -Throw '*not bound to exact profile*'
    }

    It 'rejects an expiry window renewed from capture completion' {
        $EvidencePath = Join-Path $TestDrive 'renewed-expiry.json'
        $Evidence = Get-ManualAuthenticatedEvidenceFixture -Path $EvidencePath
        $Evidence.content.bridge.expiresAtUtc = '2026-08-23T13:00:00Z'
        $Evidence.contentFingerprint = Get-ManualEvidenceContentFingerprint -Evidence $Evidence
        $Evidence | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8

        { & $script:ToolPath -EvidencePath $EvidencePath -RepositoryRoot $script:RepositoryRoot -TestMatrixPath $script:TestMatrixPath -DependencyPolicyPath $script:DependencyPolicyPath -NowUtc '2026-08-10T00:00:00Z' } |
            Should -Throw '*exactly 14 days after capture starts*'
    }

    It 'rejects unknown fields that could carry unsanitized provider data' {
        $EvidencePath = Join-Path $TestDrive 'unknown-provider-data.json'
        $Evidence = Get-ManualAuthenticatedEvidenceFixture -Path $EvidencePath
        $Evidence.content.profiles[0].scenarios[0]['rawProviderResult'] = 'redacted-placeholder'
        $Evidence.contentFingerprint = Get-ManualEvidenceContentFingerprint -Evidence $Evidence
        $Evidence | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8

        { & $script:ToolPath -EvidencePath $EvidencePath -RepositoryRoot $script:RepositoryRoot -TestMatrixPath $script:TestMatrixPath -DependencyPolicyPath $script:DependencyPolicyPath -NowUtc '2026-08-10T00:00:00Z' } |
            Should -Throw '*Authenticated scenario*properties does not match the required set*'
    }

    It 'rejects content tampering before semantic checks' {
        $EvidencePath = Join-Path $TestDrive 'tampered.json'
        $Evidence = Get-ManualAuthenticatedEvidenceFixture -Path $EvidencePath
        $Evidence.content.bridge.allowedReleaseVersion = '3.0.1'
        $Evidence | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8

        { & $script:ToolPath -EvidencePath $EvidencePath -RepositoryRoot $script:RepositoryRoot -TestMatrixPath $script:TestMatrixPath -DependencyPolicyPath $script:DependencyPolicyPath -NowUtc '2026-08-10T00:00:00Z' } |
            Should -Throw '*does not recompute*'
    }

    It 'records explicit acceptance without changing fingerprinted evidence content' {
        $CandidatePath = Join-Path $TestDrive 'candidate.json'
        $AcceptedPath = Join-Path $TestDrive 'accepted-output.json'
        $Candidate = Get-ManualAuthenticatedEvidenceFixture -Path $CandidatePath -AcceptanceStatus pending
        $AcceptanceTool = Join-Path $script:RepositoryRoot 'tools\Set-DLLPickleManualAuthenticatedEvidenceAcceptance.ps1'

        $Result = & $AcceptanceTool -CandidateEvidencePath $CandidatePath -OutputPath $AcceptedPath -AcceptedBy 'maintainer' -Confidence high -AcceptedAtUtc ([System.DateTimeOffset]::Parse('2026-08-09T14:00:00Z')) -Confirm:$false
        $Accepted = Get-Content -LiteralPath $AcceptedPath -Raw | ConvertFrom-Json

        $Accepted.acceptance.status | Should -Be 'accepted'
        $Accepted.acceptance.confidence | Should -Be 'high'
        $Accepted.contentFingerprint | Should -BeExactly $Candidate.contentFingerprint
        $Result.AllowedReleaseVersion | Should -Be '3.0.0'
        $Result.WritesPerformed | Should -BeFalse
    }
}
