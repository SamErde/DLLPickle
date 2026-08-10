BeforeAll {
    $script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:GeneratorPath = Join-Path $script:ProjectRoot 'tools\New-DLLPickleSupportDocumentation.ps1'
    $script:ReadmePath = Join-Path $script:ProjectRoot 'README.md'
    $script:ArchitecturePath = Join-Path $script:ProjectRoot 'docs\Architecture.md'
    $script:DependencyDocPath = Join-Path $script:ProjectRoot 'docs\DEPENDENCIES.md'
}

Describe 'Generated support documentation' -Tag 'Unit' {
    It 'matches the canonical support and dependency policies' {
        { & $script:GeneratorPath -Check } | Should -Not -Throw
    }

    It 'renders repository-canonical CRLF endings on every host' {
        $OutputDirectory = Join-Path $TestDrive 'generated'

        $null = & $script:GeneratorPath -OutputDirectory $OutputDirectory

        foreach ($DocumentName in @('Support-Matrix.md', 'Compatibility-Evidence.md')) {
            $Document = [System.IO.File]::ReadAllText((Join-Path $OutputDirectory $DocumentName))
            $Document | Should -Match "`r`n"
            ($Document -replace "`r`n", '') | Should -Not -Match "`n"
        }
    }

    It 'renders accepted committed profile evidence instead of expiring artifact placeholders' {
        $FixtureRoot = Join-Path $TestDrive 'accepted-evidence-docs'
        $EvidenceDirectory = Join-Path $FixtureRoot 'profile-evidence'
        $null = New-Item -Path $EvidenceDirectory -ItemType Directory -Force
        $SupportPolicyPath = Join-Path $FixtureRoot 'support.json'
        $TestMatrixPath = Join-Path $FixtureRoot 'matrix.json'
        $DependencyPolicyPath = Join-Path $FixtureRoot 'dependency.json'
        $OutputDirectory = Join-Path $FixtureRoot 'generated'
        $EvidencePath = Join-Path $EvidenceDirectory 'ps7.6-net10.0-windows-x64.json'

        $EvidenceContent = [ordered]@{
            profile = [ordered]@{ profileKey = 'ps7.6-net10.0-windows-x64' }
            modules = @(
                [ordered]@{
                    name = 'Synthetic.One'
                    version = '1.10.0'
                    selectedAssets = @(
                        [ordered]@{
                            assemblyName = 'Microsoft.Identity.Client'
                            assemblyVersion = '4.82.1.0'
                            assemblyLoadContext = 'Default'
                            selectedAsset = 'upstream:Synthetic.One/1.10.0/lib/Microsoft.Identity.Client.dll'
                        }
                    )
                }
            )
        }
        $CanonicalContent = $EvidenceContent | ConvertTo-Json -Depth 100 -Compress
        $EvidenceBytes = [System.Text.Encoding]::UTF8.GetBytes($CanonicalContent)
        $EvidenceFingerprint = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($EvidenceBytes)).Replace('-', '').ToLowerInvariant()
        [ordered]@{
            schemaVersion = 1
            contentFingerprint = $EvidenceFingerprint
            provenance = [ordered]@{
                sourceRunId = '12345'
                sourceRunUrl = 'https://example.invalid/runs/12345'
                capturedAtUtc = '2026-08-09T12:00:00Z'
            }
            content = $EvidenceContent
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8

        [ordered]@{
            profiles = @(
                [ordered]@{
                    powerShellMajor = 7
                    powerShellMinor = 6
                    dotnetMajor = 10
                    targetFramework = 'net10.0'
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $SupportPolicyPath -Encoding UTF8
        [ordered]@{
            lastVerifiedUtc = '2026-08-09T12:00:00Z'
            profiles = @(
                [ordered]@{
                    powerShellMajor = 7
                    powerShellMinor = 6
                    powerShellVersion = '7.6.4'
                    dotnetMajor = 10
                    dotnetRuntimeVersion = '10.0.10'
                    targetFramework = 'net10.0'
                    lifecycleState = 'STS'
                    lifecycleEndDate = '2026-11-10'
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $TestMatrixPath -Encoding UTF8
        [ordered]@{
            monitoredModules = @(
                [ordered]@{
                    name = 'Synthetic.One'
                    authenticatedReadOnlyProbeCommand = 'Connect-Synthetic; Get-SyntheticReadOnly'
                }
            )
            runtimeProfiles = @(
                [ordered]@{
                    powerShellLine = '7.6'
                    targetFramework = 'net10.0'
                    platforms = @('windows')
                    baselines = [ordered]@{
                        windows = [ordered]@{
                            status = 'accepted'
                            evidencePath = 'profile-evidence/ps7.6-net10.0-windows-x64.json'
                            evidenceFingerprint = $EvidenceFingerprint
                        }
                    }
                }
            )
        } | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $DependencyPolicyPath -Encoding UTF8

        $null = & $script:GeneratorPath -SupportPolicyPath $SupportPolicyPath -TestMatrixPath $TestMatrixPath -DependencyPolicyPath $DependencyPolicyPath -OutputDirectory $OutputDirectory
        $Compatibility = Get-Content -LiteralPath (Join-Path $OutputDirectory 'Compatibility-Evidence.md') -Raw
        $Compatibility | Should -Match 'Synthetic\.One \| 1\.10\.0'
        $Compatibility | Should -Match 'upstream:Synthetic\.One/1\.10\.0/lib/Microsoft\.Identity\.Client\.dll'
        $Compatibility | Should -Match 'Microsoft\.Identity\.Client.*4\.82\.1\.0.*Default'
        $Compatibility | Should -Match '\[12345\]\(https://example\.invalid/runs/12345\)'
    }

    It 'keeps the primary documentation linked to the generated support contract' {
        Get-Content -LiteralPath $script:ReadmePath -Raw | Should -Match 'generated/Support-Matrix\.md'
        Get-Content -LiteralPath $script:ArchitecturePath -Raw | Should -Match 'generated/Support-Matrix\.md'
        Get-Content -LiteralPath $script:DependencyDocPath -Raw | Should -Match 'generated/Compatibility-Evidence\.md'
    }

    It 'separates Microsoft support, upstream evidence, and optional CI tooling claims' {
        $SupportMatrix = Get-Content -LiteralPath (Join-Path $script:ProjectRoot 'docs\generated\Support-Matrix.md') -Raw
        $Compatibility = Get-Content -LiteralPath (Join-Path $script:ProjectRoot 'docs\generated\Compatibility-Evidence.md') -Raw
        $SupportMatrix | Should -Match 'Microsoft-supported runtime contract'
        $SupportMatrix | Should -Match 'multi-pwsh.*optional'
        $Compatibility | Should -Match 'release-gating gaps'
        $Compatibility | Should -Match 'process-isolation requirement'
        $Compatibility | Should -Match 'Issue #34'
        $Compatibility | Should -Match 'PR #215'
        $Compatibility | Should -Match 'Issue #242'
        $Compatibility | Should -Match 'not executed without approved credentials'
    }
}
