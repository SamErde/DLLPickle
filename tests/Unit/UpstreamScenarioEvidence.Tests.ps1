BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ToolPath = Join-Path $script:RepositoryRoot 'tools\New-DLLPickleUpstreamScenarioEvidence.ps1'
}

Describe 'Deterministic upstream import-order evidence' -Tag 'Unit' {
    It 'runs every configured order with and without DLLPickle under exact manifests' {
        $ModuleCache = Join-Path $TestDrive 'modules'
        $ModuleRows = @(
            foreach ($Name in @('Synthetic.One', 'Synthetic.Two')) {
                $ModuleRoot = Join-Path $ModuleCache "$Name\1.0.0"
                $null = New-Item -Path $ModuleRoot -ItemType Directory -Force
                Set-Content -LiteralPath (Join-Path $ModuleRoot "$Name.psm1") -Value "function Get-$($Name.Replace('.', '')) { 'ok' }" -Encoding UTF8
                $ManifestPath = Join-Path $ModuleRoot "$Name.psd1"
                New-ModuleManifest -Path $ManifestPath -RootModule "$Name.psm1" -ModuleVersion '1.0.0' -FunctionsToExport @("Get-$($Name.Replace('.', ''))")
                [PSCustomObject]@{ Name = $Name; ModuleManifestPath = $ManifestPath }
            }
        )
        $DllPickleRoot = Join-Path $TestDrive 'dllpickle'
        $null = New-Item -Path $DllPickleRoot -ItemType Directory
        Set-Content -LiteralPath (Join-Path $DllPickleRoot 'DLLPickle.psm1') -Value 'function Import-DPLibrary { param([switch]$SuppressLogo) }' -Encoding UTF8
        $DllPickleManifest = Join-Path $DllPickleRoot 'DLLPickle.psd1'
        New-ModuleManifest -Path $DllPickleManifest -RootModule 'DLLPickle.psm1' -ModuleVersion '1.0.0' -FunctionsToExport @('Import-DPLibrary')

        $PowerShellLine = '{0}.{1}' -f $PSVersionTable.PSVersion.Major, $PSVersionTable.PSVersion.Minor
        $TargetFramework = 'net{0}.0' -f [Environment]::Version.Major
        $ProfileKey = "ps$PowerShellLine-$TargetFramework-windows-x64"
        $PolicyPath = Join-Path $TestDrive 'policy.json'
        @{
            trackedAssemblies = @('System.Management.Automation')
            monitoredModules = @(
                @{ name = 'Synthetic.One'; deterministicProbeCommand = 'Get-Command Get-SyntheticOne | Out-Null' }
                @{ name = 'Synthetic.Two'; deterministicProbeCommand = 'Get-Command Get-SyntheticTwo | Out-Null' }
            )
            runtimeProfiles = @(
                @{
                    powerShellLine = $PowerShellLine
                    targetFramework = $TargetFramework
                    importOrders = @(
                        , @('Synthetic.One', 'Synthetic.Two')
                        , @('Synthetic.Two', 'Synthetic.One')
                    )
                }
            )
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $PolicyPath -Encoding UTF8
        $InventoryPath = Join-Path $TestDrive 'inventory.json'
        @{
            ProfileKey = $ProfileKey
            ModuleCachePath = $ModuleCache
            Profile = @{
                PowerShellVersion = $PSVersionTable.PSVersion.ToString()
                PowerShellLine = $PowerShellLine
                TargetFramework = $TargetFramework
                PSHome = $PSHOME
                Platform = 'windows'
                Architecture = 'x64'
            }
            Modules = @($ModuleRows)
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $InventoryPath -Encoding UTF8

        $Parameters = @{
            PolicyPath = $PolicyPath
            InventoryPath = $InventoryPath
            PowerShellExecutable = [Environment]::ProcessPath
            DLLPickleManifestPath = $DllPickleManifest
            OutputPath = Join-Path $TestDrive 'scenario-evidence.json'
            Strict = $true
        }
        $First = & $script:ToolPath @Parameters
        $Parameters.OutputPath = Join-Path $TestDrive 'scenario-evidence-second.json'
        $Second = & $script:ToolPath @Parameters

        @($First.Scenarios) | Should -HaveCount 4
        @($First.Scenarios | Where-Object DllPicklePreloaded) | Should -HaveCount 2
        @($First.Scenarios | Where-Object { -not $_.DllPicklePreloaded }) | Should -HaveCount 2
        $First.Passed | Should -BeTrue
        $First.WritesPerformed | Should -BeFalse
        $First.ScenarioFingerprint | Should -BeExactly $Second.ScenarioFingerprint
    }
}
