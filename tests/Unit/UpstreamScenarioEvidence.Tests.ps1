BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ToolPath = Join-Path $script:RepositoryRoot 'tools\New-DLLPickleUpstreamScenarioEvidence.ps1'
}

Describe 'Deterministic upstream import-order evidence' -Tag 'Unit' {
    It 'runs every configured order with and without DLLPickle under exact manifests' {
        $ModuleCache = Join-Path $TestDrive 'modules'
        $ModuleRows = @(
            foreach ($Name in @('Synthetic.One', 'Synthetic.Two', 'Synthetic.Failure')) {
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
                @{ name = 'Synthetic.Failure'; deterministicProbeCommand = 'throw "expected synthetic failure"' }
            )
            runtimeProfiles = @(
                @{
                    powerShellLine = $PowerShellLine
                    targetFramework = $TargetFramework
                    importOrders = @(
                        , @('Synthetic.One', 'Synthetic.Two')
                        , @('Synthetic.Two', 'Synthetic.One')
                    )
                    knownConflictIds = @('synthetic-expected-failure')
                }
            )
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $PolicyPath -Encoding UTF8
        $KnownConflictsPath = Join-Path $TestDrive 'known-conflicts.json'
        @(
            @{
                id = 'synthetic-expected-failure'
                importOrders = @(
                    , @('Synthetic.Failure')
                    , @('Synthetic.One')
                )
                requiresProcessIsolation = $true
            }
        ) | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $KnownConflictsPath -Encoding UTF8
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
            KnownConflictsPath = $KnownConflictsPath
            OutputPath = Join-Path $TestDrive 'scenario-evidence.json'
            Strict = $true
        }
        $First = & $script:ToolPath @Parameters
        $Parameters.OutputPath = Join-Path $TestDrive 'scenario-evidence-second.json'
        $Second = & $script:ToolPath @Parameters

        @($First.Scenarios) | Should -HaveCount 8
        @($First.Scenarios | Where-Object DllPicklePreloaded) | Should -HaveCount 4
        @($First.Scenarios | Where-Object { -not $_.DllPicklePreloaded }) | Should -HaveCount 4
        $ExpectedOrders = @(
            'Synthetic.Failure'
            'Synthetic.One'
            'Synthetic.One,Synthetic.Two'
            'Synthetic.Two,Synthetic.One'
        )
        $ActualOrders = @($First.Scenarios | ForEach-Object { @($_.ImportOrder) -join ',' } | Sort-Object -Unique)
        $ActualOrders | Should -Be $ExpectedOrders
        foreach ($ExpectedOrder in $ExpectedOrders) {
            $OrderScenarios = @($First.Scenarios | Where-Object { (@($_.ImportOrder) -join ',') -eq $ExpectedOrder })
            $OrderScenarios | Should -HaveCount 2
            @($OrderScenarios.DllPicklePreloaded | Sort-Object -Unique) | Should -Be @($false, $true)
            @($OrderScenarios.OutcomeMatchesExpectation | Select-Object -Unique) | Should -Be @($true)
        }
        $First.Passed | Should -BeTrue
        $First.WritesPerformed | Should -BeFalse
        $KnownLimitationScenarios = @($First.Scenarios | Where-Object ScenarioId -EQ 'synthetic-expected-failure')
        @($KnownLimitationScenarios | Where-Object Success) | Should -HaveCount 2
        @($KnownLimitationScenarios | Where-Object { -not $_.Success }) | Should -HaveCount 2
        foreach ($KnownLimitationScenario in $KnownLimitationScenarios) {
            $KnownLimitationScenario.ExpectedLimitation | Should -BeTrue
            $KnownLimitationScenario.ExpectedSuccess | Should -BeNullOrEmpty
            $KnownLimitationScenario.OutcomePolicy | Should -Be 'observe-known-limitation'
            $KnownLimitationScenario.OutcomeMatchesExpectation | Should -BeTrue
        }
        $First.ScenarioFingerprint | Should -BeExactly $Second.ScenarioFingerprint
    }
}
