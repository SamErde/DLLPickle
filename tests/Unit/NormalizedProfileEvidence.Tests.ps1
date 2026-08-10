BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ToolPath = Join-Path $script:RepositoryRoot 'tools\New-DLLPickleNormalizedProfileEvidence.ps1'

    function Get-NormalizedEvidenceFixture {
        param([Parameter(Mandatory)][string]$Root)

        $null = New-Item -Path $Root -ItemType Directory -Force
        $ModuleCache = Join-Path $Root 'module-cache\7.6.4'
        $ModuleRoot = Join-Path $ModuleCache 'Synthetic.One\1.10.0'
        $ModuleManifestPath = Join-Path $ModuleRoot 'Synthetic.One.psd1'
        $UpstreamAssemblyPath = Join-Path $ModuleRoot 'lib\..\lib\Microsoft.Identity.Client.dll'
        $DLLPickleAssemblyPath = Join-Path $script:RepositoryRoot 'module\DLLPickle\bin\net10.0\Microsoft.IdentityModel.Tokens.dll'
        $RuntimeAssemblyPath = Join-Path $Root 'pwsh\System.Security.Cryptography.ProtectedData.dll'
        $RuntimeProfile = [ordered]@{
            PowerShellVersion = '7.6.4'
            PowerShellLine = '7.6'
            DotNetVersion = '10.0.10'
            DotNetMajor = 10
            TargetFramework = 'net10.0'
            ExecutablePath = Join-Path $Root 'pwsh\pwsh.exe'
            PSHome = Join-Path $Root 'pwsh'
            Platform = 'windows'
            Architecture = 'x64'
        }
        $ProfileKey = 'ps7.6-net10.0-windows-x64'
        $InventoryPath = Join-Path $Root 'upstream-inventory.json'
        $MatrixPath = Join-Path $Root 'conflict-matrix.json'
        $ScenarioPath = Join-Path $Root 'scenario-evidence.json'
        $GapsPath = Join-Path $Root 'validation-gaps.json'

        [ordered]@{
            SchemaVersion = 2
            GeneratedAtUtc = '2026-08-09T12:00:00Z'
            ModuleCachePath = $ModuleCache
            ProfileKey = $ProfileKey
            ValidationTier = 'deterministic-import-no-auth'
            Profile = $RuntimeProfile
            Modules = @(
                [ordered]@{
                    Name = 'Synthetic.One'
                    UmbrellaModule = 'Synthetic'
                    ConstituentModule = 'Synthetic.One'
                    Version = '1.10.0'
                    LatestCompatibleVersion = '1.10.0'
                    Repository = 'PSGallery'
                    ModulePath = $ModuleRoot
                    ModuleManifestPath = $ModuleManifestPath
                    ManifestPowerShellVersion = '7.4'
                    CompatiblePSEditions = @('Desktop', 'Core')
                    DeterministicProbeCommand = 'Get-Command Get-SyntheticOne | Out-Null'
                    TrackedAssemblies = @(
                        [ordered]@{
                            Name = 'Microsoft.Identity.Client'
                            Version = '4.82.1.0'
                            PackageVersionCandidate = '4.82.1'
                            FullName = 'Microsoft.Identity.Client, Version=4.82.1.0'
                            Path = $UpstreamAssemblyPath
                            SelectedAssetPath = $UpstreamAssemblyPath
                            Sha256 = 'a' * 64
                            Alc = 'Default'
                            IsCollectible = $false
                            ConstituentModule = 'Synthetic.One'
                            OS = 'Microsoft Windows 11'
                            Platform = 'windows'
                            Architecture = 'x64'
                        }
                    )
                }
            )
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $InventoryPath -Encoding UTF8

        [ordered]@{
            ProfileKey = $ProfileKey
            Profile = $RuntimeProfile
            ValidationTier = 'deterministic-import-no-auth'
            Assemblies = @(
                [ordered]@{
                    Name = 'Microsoft.Identity.Client'
                    ShippedBy = @('Synthetic.One')
                    Versions = @('4.82.1.0')
                    Hashes = @('a' * 64)
                    AlcOwners = @('Default')
                    Selections = @(
                        [ordered]@{
                            Module = 'Synthetic.One'
                            Version = '4.82.1.0'
                            Sha256 = 'a' * 64
                            AlcOwner = 'Default'
                        }
                    )
                    Diverges = $false
                }
            )
            ConflictSurface = @()
            Fingerprint = 'b' * 64
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $MatrixPath -Encoding UTF8

        [ordered]@{
            SchemaVersion = 1
            ProfileKey = $ProfileKey
            Profile = $RuntimeProfile
            ValidationTier = 'deterministic-import-no-auth'
            WritesPerformed = $false
            ScenarioFingerprint = 'c' * 64
            Scenarios = @(
                [ordered]@{
                    ScenarioId = 'synthetic-order'
                    OrderIndex = 1
                    ImportOrder = @('Synthetic.One')
                    DllPicklePreloaded = $true
                    ExpectedLimitation = $false
                    ExpectedSuccess = $true
                    OutcomePolicy = 'must-succeed'
                    ProbeCommands = @('Get-Command Get-SyntheticOne | Out-Null')
                    Success = $true
                    OutcomeMatchesExpectation = $true
                    Assemblies = @(
                        [ordered]@{
                            Name = 'Microsoft.Identity.Client'
                            Version = '4.82.1.0'
                            FullName = 'Microsoft.Identity.Client, Version=4.82.1.0'
                            Alc = 'Default'
                            IsCollectible = $false
                            Path = $UpstreamAssemblyPath
                            Sha256 = 'a' * 64
                            OS = 'Microsoft Windows 11'
                            Platform = 'windows'
                            Architecture = 'x64'
                            ImportedModulePaths = @($ModuleManifestPath)
                        }
                        [ordered]@{
                            Name = 'System.Security.Cryptography.ProtectedData'
                            Version = '10.0.0.0'
                            FullName = 'System.Security.Cryptography.ProtectedData, Version=10.0.0.0'
                            Alc = 'Default'
                            IsCollectible = $false
                            Path = $RuntimeAssemblyPath
                            Sha256 = 'e' * 64
                            OS = 'Microsoft Windows 11'
                            Platform = 'windows'
                            Architecture = 'x64'
                            ImportedModulePaths = @($ModuleManifestPath)
                        }
                        [ordered]@{
                            Name = 'Microsoft.IdentityModel.Tokens'
                            Version = '8.14.0.0'
                            FullName = 'Microsoft.IdentityModel.Tokens, Version=8.14.0.0'
                            Alc = 'Default'
                            IsCollectible = $false
                            Path = $DLLPickleAssemblyPath
                            Sha256 = 'd' * 64
                            OS = 'Microsoft Windows 11'
                            Platform = 'windows'
                            Architecture = 'x64'
                            ImportedModulePaths = @($ModuleManifestPath)
                        }
                    )
                    Error = $null
                }
            )
            Passed = $true
        } | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $ScenarioPath -Encoding UTF8

        [ordered]@{
            schemaVersion = 1
            profile = '7.6.4/net10.0/windows/x64'
            deterministicImportNoAuth = 'executed-two-orders-with-and-without-dllpickle'
            authenticatedReadOnly = 'not-run-no-approved-credentials'
            writesPerformed = $false
            unexecutedCommands = @('Connect-Synthetic -ReadOnly')
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $GapsPath -Encoding UTF8

        [pscustomobject]@{
            InventoryPath = $InventoryPath
            MatrixPath = $MatrixPath
            ScenarioPath = $ScenarioPath
            GapsPath = $GapsPath
            ModuleCache = $ModuleCache
        }
    }

    function Invoke-NormalizerFixture {
        param(
            [Parameter(Mandatory)][object]$Fixture,
            [Parameter(Mandatory)][string]$OutputPath,
            [string]$SourceRunId = '100',
            [string]$CapturedAtUtc = '2026-08-09T12:00:00Z'
        )

        $Parameters = @{
            InventoryPath = $Fixture.InventoryPath
            ConflictMatrixPath = $Fixture.MatrixPath
            ScenarioEvidencePath = $Fixture.ScenarioPath
            ValidationGapsPath = $Fixture.GapsPath
            OutputPath = $OutputPath
            SourceRunId = $SourceRunId
            SourceRunUrl = "https://example.invalid/runs/$SourceRunId"
            SourceCommitSha = 'e' * 40
            CapturedAtUtc = $CapturedAtUtc
        }
        & $script:ToolPath @Parameters
    }
}

Describe 'Normalized exact-profile upstream evidence' -Tag 'Unit' {
    It 'preserves reviewable selections without runner-specific absolute paths' {
        $Fixture = Get-NormalizedEvidenceFixture -Root (Join-Path $TestDrive 'first-root')
        $OutputPath = Join-Path $TestDrive 'normalized.json'

        $Evidence = Invoke-NormalizerFixture -Fixture $Fixture -OutputPath $OutputPath
        $RawEvidence = Get-Content -LiteralPath $OutputPath -Raw

        $Evidence.schemaVersion | Should -Be 1
        $Evidence.content.profile.profileKey | Should -Be 'ps7.6-net10.0-windows-x64'
        $Evidence.content.modules[0].version | Should -Be '1.10.0'
        $Evidence.content.modules[0].selectedAssets[0].selectedAsset | Should -Be 'upstream:Synthetic.One/1.10.0/lib/Microsoft.Identity.Client.dll'
        @($Evidence.content.scenarios[0].assemblies.selectedAsset) | Should -Contain 'dllpickle:bin/net10.0/Microsoft.IdentityModel.Tokens.dll'
        @($Evidence.content.scenarios[0].assemblies.selectedAsset) | Should -Contain 'runtime:System.Security.Cryptography.ProtectedData.dll'
        $RawEvidence | Should -Not -Match ([regex]::Escape($TestDrive))
        $RawEvidence | Should -Not -Match '/home/runner|[A-Za-z]:\\Users\\'
    }

    It 'produces the same content fingerprint across roots and provenance' {
        $FirstFixture = Get-NormalizedEvidenceFixture -Root (Join-Path $TestDrive 'root-a')
        $SecondFixture = Get-NormalizedEvidenceFixture -Root (Join-Path $TestDrive 'root-b')

        $First = Invoke-NormalizerFixture -Fixture $FirstFixture -OutputPath (Join-Path $TestDrive 'first.json') -SourceRunId '100' -CapturedAtUtc '2026-08-09T12:00:00Z'
        $Second = Invoke-NormalizerFixture -Fixture $SecondFixture -OutputPath (Join-Path $TestDrive 'second.json') -SourceRunId '200' -CapturedAtUtc '2026-08-10T12:00:00Z'

        $First.contentFingerprint | Should -BeExactly $Second.contentFingerprint
        $First.provenance.sourceRunId | Should -Not -Be $Second.provenance.sourceRunId
        $First.provenance.capturedAtUtc | Should -Not -Be $Second.provenance.capturedAtUtc
    }

    It 'records a fingerprint that recomputes from normalized content' {
        $Fixture = Get-NormalizedEvidenceFixture -Root (Join-Path $TestDrive 'fingerprint-root')
        $Evidence = Invoke-NormalizerFixture -Fixture $Fixture -OutputPath (Join-Path $TestDrive 'fingerprint.json')

        $CanonicalContent = $Evidence.content | ConvertTo-Json -Depth 100 -Compress
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($CanonicalContent)
        $Expected = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($Bytes)).Replace('-', '').ToLowerInvariant()
        $Evidence.contentFingerprint | Should -BeExactly $Expected
    }

    It 'fails closed for an asset outside approved normalization roots' {
        $Fixture = Get-NormalizedEvidenceFixture -Root (Join-Path $TestDrive 'outside-root')
        $Inventory = Get-Content -LiteralPath $Fixture.InventoryPath -Raw | ConvertFrom-Json
        $Inventory.Modules[0].TrackedAssemblies[0].SelectedAssetPath = 'Z:\unexpected\payload.dll'
        $Inventory | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Fixture.InventoryPath -Encoding UTF8

        { Invoke-NormalizerFixture -Fixture $Fixture -OutputPath (Join-Path $TestDrive 'outside.json') } |
            Should -Throw '*outside the upstream module cache, DLLPickle module root, and exact runtime root*'
    }
}
