BeforeAll {
    Set-Location -Path $PSScriptRoot
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:ReportScriptPath = Join-Path $ProjectRoot 'tools\New-DLLPickleDependencyChangeReport.ps1'

    function Get-DependencyChangeReportFixture {
        param(
            [Parameter(Mandatory)]
            [string]$Root
        )

        $BaselineAssetsPath = Join-Path $Root 'baseline.assets.json'
        $CandidateAssetsPath = Join-Path $Root 'candidate.assets.json'
        $BaselineOutput = Join-Path $Root 'baseline-output'
        $CandidateOutput = Join-Path $Root 'candidate-output'
        $PolicyPath = Join-Path $Root 'support.json'
        $DependencyPolicyPath = Join-Path $Root 'dependency-policy.json'
        $null = New-Item -Path (Join-Path $BaselineOutput 'net8.0') -ItemType Directory -Force
        $null = New-Item -Path (Join-Path $CandidateOutput 'net8.0') -ItemType Directory -Force

        $Assets = @{
            targets = @{
                'net8.0' = @{
                    'Contoso.Library/1.0.0' = @{ compile = @{}; runtime = @{} }
                }
            }
        }
        $Assets | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $BaselineAssetsPath -Encoding UTF8
        $Assets | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $CandidateAssetsPath -Encoding UTF8
        @{ schemaVersion = 1; profiles = @(@{ targetFramework = 'net8.0' }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $PolicyPath -Encoding UTF8
        @{ preload = @(); blockedPreloadAssemblies = @() } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $DependencyPolicyPath -Encoding UTF8

        [PSCustomObject]@{
            BaselineAssetsPath = $BaselineAssetsPath
            Parameters = @{
                BaselineProjectAssetsPath = $BaselineAssetsPath
                CandidateProjectAssetsPath = $CandidateAssetsPath
                BaselineBuildOutputRoot = $BaselineOutput
                CandidateBuildOutputRoot = $CandidateOutput
                SupportPolicyPath = $PolicyPath
                DependencyPolicyPath = $DependencyPolicyPath
                OutputPath = Join-Path $Root 'report.json'
            }
        }
    }
}

Describe 'Per-TFM dependency change report' -Tag 'Unit' {
    It 'records resolved graph, selected assets, assembly deltas, size, and required conflict/scenario gates' {
        $BaselineAssetsPath = Join-Path $TestDrive 'baseline.assets.json'
        $CandidateAssetsPath = Join-Path $TestDrive 'candidate.assets.json'
        $BaselineOutput = Join-Path $TestDrive 'baseline-output'
        $CandidateOutput = Join-Path $TestDrive 'candidate-output'
        $PolicyPath = Join-Path $TestDrive 'support.json'
        $DependencyPolicyPath = Join-Path $TestDrive 'dependency-policy.json'
        $SizePath = Join-Path $TestDrive 'size.json'

        $BaselineAssets = @{
            targets = @{
                'net8.0' = @{
                    'Contoso.Library/1.0.0' = @{ compile = @{ 'lib/net8.0/Contoso.Library.dll' = @{} }; runtime = @{ 'lib/net8.0/Contoso.Library.dll' = @{} } }
                }
            }
        }
        $CandidateAssets = @{
            targets = @{
                'net8.0' = @{
                    'Contoso.Library/2.0.0' = @{ compile = @{ 'lib/net8.0/Contoso.Library.dll' = @{} }; runtime = @{ 'lib/net8.0/Contoso.Library.dll' = @{} } }
                    'Contoso.Added/1.0.0' = @{ compile = @{ 'lib/net8.0/Contoso.Added.dll' = @{} }; runtime = @{ 'lib/net8.0/Contoso.Added.dll' = @{} } }
                }
            }
        }
        $BaselineAssets | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $BaselineAssetsPath -Encoding UTF8
        $CandidateAssets | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $CandidateAssetsPath -Encoding UTF8
        $ConflictAssembly = [System.Text.Json.JsonDocument].Assembly
        @{ schemaVersion = 1; profiles = @(@{ targetFramework = 'net8.0' }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $PolicyPath -Encoding UTF8
        @{
            preload = @()
            blockedPreloadAssemblies = @(@{ assemblyName = $ConflictAssembly.GetName().Name })
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $DependencyPolicyPath -Encoding UTF8
        @{ Profiles = @(@{ Name = 'net8.0'; UnpackedDeltaBytes = 42; ReviewRequired = $false }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $SizePath -Encoding UTF8

        $null = New-Item -Path (Join-Path $BaselineOutput 'net8.0') -ItemType Directory -Force
        $null = New-Item -Path (Join-Path $CandidateOutput 'net8.0') -ItemType Directory -Force
        'baseline' | Set-Content -LiteralPath (Join-Path $BaselineOutput 'net8.0\Microsoft.Contoso.dll') -Encoding UTF8
        'candidate' | Set-Content -LiteralPath (Join-Path $CandidateOutput 'net8.0\Microsoft.Contoso.dll') -Encoding UTF8
        'added' | Set-Content -LiteralPath (Join-Path $CandidateOutput 'net8.0\System.Added.dll') -Encoding UTF8
        Copy-Item -LiteralPath $ConflictAssembly.Location -Destination (Join-Path $CandidateOutput "net8.0\$($ConflictAssembly.GetName().Name).dll")

        $Parameters = @{
            BaselineProjectAssetsPath = $BaselineAssetsPath
            CandidateProjectAssetsPath = $CandidateAssetsPath
            BaselineBuildOutputRoot = $BaselineOutput
            CandidateBuildOutputRoot = $CandidateOutput
            SupportPolicyPath = $PolicyPath
            DependencyPolicyPath = $DependencyPolicyPath
            SizeReportPath = $SizePath
            OutputPath = Join-Path $TestDrive 'report.json'
        }
        $Report = & $script:ReportScriptPath @Parameters
        $ProfileReport = $Report.Profiles[0]

        $ProfileReport.ResolvedGraphDelta.Changed[0].Baseline | Should -Be '1.0.0'
        $ProfileReport.ResolvedGraphDelta.Changed[0].Candidate | Should -Be '2.0.0'
        @($ProfileReport.ResolvedGraphDelta.Added).PackageName | Should -Contain 'Contoso.Added'
        @($ProfileReport.CandidateSelectedAssets) | Should -HaveCount 2
        @($ProfileReport.AssemblyDelta.Added).RelativePath | Should -Contain 'System.Added.dll'
        @($ProfileReport.AssemblyDelta.Changed).Key | Should -Contain 'Microsoft.Contoso.dll'
        $ProfileReport.Size.UnpackedDeltaBytes | Should -Be 42
        $ProfileReport.ConflictSurfaceDelta.RequiredCheck | Should -Be 'Validate upstream compatibility tooling'
        $ProfileReport.ConflictSurfaceDelta.HasChanges | Should -BeTrue
        @($ProfileReport.ConflictSurfaceDelta.Delta.Added).AssemblyName | Should -Contain $ConflictAssembly.GetName().Name
        $ProfileReport.ConflictSurfaceDelta.UpstreamAlcAdjudication | Should -Be 'required-profile-aware-gate'
        $Report.RequiredChecks | Should -Contain 'Build gate'
        $Report.ReviewRequired | Should -BeTrue
    }

    It 'fails closed when an assets file has no targets section' {
        $Fixture = Get-DependencyChangeReportFixture -Root (Join-Path $TestDrive 'missing-targets')
        @{ version = 3 } | ConvertTo-Json | Set-Content -LiteralPath $Fixture.BaselineAssetsPath -Encoding UTF8
        $Parameters = $Fixture.Parameters

        { & $script:ReportScriptPath @Parameters } | Should -Throw '*Baseline NuGet assets file has no targets section*'
    }

    It 'fails closed when a target graph contains duplicate package keys' {
        $Fixture = Get-DependencyChangeReportFixture -Root (Join-Path $TestDrive 'duplicate-package')
        @{
            targets = @{
                'net8.0' = @{
                    'Contoso.Library/1.0.0' = @{ compile = @{}; runtime = @{} }
                    'Contoso.Library/2.0.0' = @{ compile = @{}; runtime = @{} }
                }
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Fixture.BaselineAssetsPath -Encoding UTF8
        $Parameters = $Fixture.Parameters

        { & $script:ReportScriptPath @Parameters } | Should -Throw "*duplicate 'PackageName' value 'Contoso.Library'*"
    }
}
