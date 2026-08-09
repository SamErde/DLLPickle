BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:InventoryToolPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'tools/Get-DLLPickleUpstreamInventory.ps1'
    $script:TestMatrixPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'build/powershell-test-matrix.json'

    function Get-UpstreamInventoryFixture {
        $root = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('n'))
        $moduleCache = Join-Path -Path $root -ChildPath 'modules'
        $moduleVersionRoot = Join-Path -Path $moduleCache -ChildPath 'Contoso.ProfileProbe/1.0.0'
        $null = New-Item -Path $moduleVersionRoot -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path $moduleVersionRoot 'Contoso.ProfileProbe.psm1') -Value '# profile probe fixture' -Encoding utf8
        @'
@{
    RootModule = 'Contoso.ProfileProbe.psm1'
    ModuleVersion = '1.0.0'
    GUID = '471d52e5-d025-47f6-9706-f0f3b1bdb198'
    PowerShellVersion = '7.4'
    CompatiblePSEditions = @('Core')
}
'@ | Set-Content -LiteralPath (Join-Path $moduleVersionRoot 'Contoso.ProfileProbe.psd1') -Encoding utf8

        $policyPath = Join-Path -Path $root -ChildPath 'policy.json'
        [ordered]@{
            monitoredModules = @(
                [ordered]@{
                    name = 'Contoso.ProfileProbe'
                    umbrellaModule = 'Contoso.Umbrella'
                    repository = 'PSGallery'
                    purpose = 'Fixture'
                    deterministicProbeCommand = 'Get-Command Get-Item | Out-Null'
                }
            )
            trackedAssemblies = @('System.Management.Automation')
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $policyPath -Encoding utf8

        [pscustomobject]@{
            PolicyPath = $policyPath
            ModuleCachePath = $moduleCache
            OutputPath = Join-Path -Path $root -ChildPath 'inventory.json'
        }
    }
}

Describe 'Profile-aware upstream inventory' -Tag 'Unit' {
    It 'records exact runtime identity and only actually selected tracked assets' {
        $fixture = Get-UpstreamInventoryFixture
        $parameters = @{
            PolicyPath = $fixture.PolicyPath
            TestMatrixPath = $script:TestMatrixPath
            ModuleCachePath = $fixture.ModuleCachePath
            OutputPath = $fixture.OutputPath
            PowerShellExecutable = [Environment]::ProcessPath
            SkipDownload = $true
        }

        $report = & $script:InventoryToolPath @parameters

        $report.SchemaVersion | Should -Be 2
        $report.ValidationTier | Should -Be 'DeterministicImportNoAuth'
        $report.Profile.PowerShellVersion | Should -Be $PSVersionTable.PSVersion.ToString()
        $report.Profile.DotNetMajor | Should -Be ([Environment]::Version.Major)
        $report.Profile.TargetFramework | Should -Be ('net{0}.0' -f [Environment]::Version.Major)
        $report.Profile.ExecutablePath | Should -Not -BeNullOrEmpty
        $report.Profile.PSHome | Should -Not -BeNullOrEmpty
        $report.Profile.Platform | Should -Not -BeNullOrEmpty
        $report.Profile.Architecture | Should -Not -BeNullOrEmpty

        $module = $report.Modules[0]
        $module.UmbrellaModule | Should -Be 'Contoso.Umbrella'
        $module.ConstituentModule | Should -Be 'Contoso.ProfileProbe'
        $module.ManifestPowerShellVersion | Should -Be '7.4'
        @($module.CompatiblePSEditions) | Should -Contain 'Core'
        $row = $module.TrackedAssemblies | Where-Object Name -eq 'System.Management.Automation'
        $row.SelectedAssetPath | Should -Not -BeNullOrEmpty
        $row.Sha256 | Should -Match '^[a-f0-9]{64}$'
        $row.Alc | Should -Not -BeNullOrEmpty
        $row.TargetFramework | Should -Be $report.Profile.TargetFramework
    }

    It 'does not recursively mix every DLL asset in a saved module' {
        $source = Get-Content -LiteralPath $script:InventoryToolPath -Raw

        $source | Should -Not -Match "Get-ChildItem[^\r\n]+-Filter '\*\.dll'[^\r\n]+-Recurse"
        $source | Should -Match ([regex]::Escape('Get-DLLPickleRuntimeAssemblySnapshot.ps1'))
    }
}
