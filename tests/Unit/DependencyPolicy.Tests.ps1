BeforeAll {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:Policy = Get-Content -LiteralPath (Join-Path $ProjectRoot 'build\dependency-policy.json') -Raw | ConvertFrom-Json
}

Describe 'Dependency policy baseline' -Tag 'Unit' {
    It 'keys classifications and validation gates by every supported PowerShell/TFM profile' {
        @($script:Policy.runtimeProfiles) | Should -HaveCount 3
        @($script:Policy.runtimeProfiles.powerShellLine) | Should -Be @('7.4', '7.5', '7.6')
        @($script:Policy.runtimeProfiles.targetFramework) | Should -Be @('net8.0', 'net9.0', 'net10.0')

        foreach ($RuntimeProfile in @($script:Policy.runtimeProfiles)) {
            @($RuntimeProfile.platforms) | Should -Be @('windows', 'linux', 'macos')
            @($RuntimeProfile.monitoredModuleSet) | Should -Not -BeNullOrEmpty
            @($RuntimeProfile.importOrders) | Should -HaveCount 2
            @($RuntimeProfile.preloadAssemblyNames) | Should -Not -BeNullOrEmpty
            @($RuntimeProfile.blockedAssemblyNames) | Should -Not -BeNullOrEmpty
            $RuntimeProfile.validationTiers.deterministicImportNoAuth.required | Should -BeTrue
            $RuntimeProfile.validationTiers.authenticatedReadOnly.writesAllowed | Should -BeFalse
            foreach ($Platform in @('windows', 'linux', 'macos')) {
                $RuntimeProfile.baselines.$Platform.PSObject.Properties.Name | Should -Contain 'scenarioFingerprint'
            }
        }
    }

    It 'applies every preload and block decision to all three isolated TFMs' {
        foreach ($decision in @($script:Policy.preload + $script:Policy.blockedPreloadAssemblies)) {
            @($decision.targetFrameworks) | Should -Be @('net8.0', 'net9.0', 'net10.0')
        }
    }

    It 'records deterministic and authenticated read-only probes separately' {
        foreach ($module in @($script:Policy.monitoredModules)) {
            $module.umbrellaModule | Should -Not -BeNullOrEmpty
            $module.deterministicProbeCommand | Should -Not -BeNullOrEmpty
            $module.authenticatedReadOnlyProbeCommand | Should -Not -BeNullOrEmpty
        }
        ($script:Policy.monitoredModules | Where-Object name -eq 'ExchangeOnlineManagement').authenticatedReadOnlyProbeCommand | Should -Match 'Get-EXOMailbox'
        ($script:Policy.monitoredModules | Where-Object name -eq 'MicrosoftTeams').authenticatedReadOnlyProbeCommand | Should -Match 'Get-CsTenant'
    }

    It 'explicitly monitors Az.Resources as the #193 collision source' {
        $MonitoredNames = @($script:Policy.monitoredModules.name)
        $MonitoredNames | Should -Contain 'Az.Resources'

        # Az.Resources ships Microsoft.Extensions.DependencyInjection.Abstractions (a diverging
        # member of the conflict surface), so it must be recorded as a source module there and
        # carry the structured #193 collision linkage.
        $DiEntry = @(
            $script:Policy.blockedPreloadAssemblies |
                Where-Object { $_.assemblyName -eq 'Microsoft.Extensions.DependencyInjection.Abstractions' }
        )
        $DiEntry | Should -HaveCount 1
        @($DiEntry[0].sourceModules) | Should -Contain 'Az.Resources'
        $DiEntry[0].evidence.issue | Should -Be '193'

        # Az.Resources does NOT ship Microsoft.Extensions.Logging.Abstractions; the refreshed
        # inventory observes it only in MicrosoftTeams, so it must not be recorded there.
        $LoggingEntry = @(
            $script:Policy.blockedPreloadAssemblies |
                Where-Object { $_.assemblyName -eq 'Microsoft.Extensions.Logging.Abstractions' }
        )
        $LoggingEntry | Should -HaveCount 1
        @($LoggingEntry[0].sourceModules) | Should -Contain 'MicrosoftTeams'
        @($LoggingEntry[0].sourceModules) | Should -Not -Contain 'Az.Resources'
    }

    It 'records the complete structured conflict surface' {
        @($script:Policy.baseline.conflictSurface) | Should -HaveCount 18

        foreach ($Row in $script:Policy.baseline.conflictSurface) {
            $Row.name | Should -Not -BeNullOrEmpty
            @($Row.versions) | Should -Not -BeNullOrEmpty
            @($Row.shippedBy) | Should -Not -BeNullOrEmpty
        }
    }

    It 'has a fingerprint that matches the structured conflict surface' {
        $SurfaceRows = @(
            $script:Policy.baseline.conflictSurface |
                Sort-Object name |
                ForEach-Object {
                    '{0}={1};by={2}' -f $_.name, (@($_.versions | Sort-Object) -join ','), (@($_.shippedBy | Sort-Object) -join ',')
                }
        )
        $FingerprintBytes = [System.Text.Encoding]::UTF8.GetBytes(($SurfaceRows -join '|'))
        $Fingerprint = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($FingerprintBytes)).Replace('-', '').ToLowerInvariant()

        $script:Policy.baseline.conflictSurfaceFingerprint | Should -BeExactly $Fingerprint
    }

    It 'classifies every conflict row exactly once' {
        $ConflictNames = @($script:Policy.baseline.conflictSurface).name
        $ClassifiedNames = @(
            @($script:Policy.preload).assemblyName
            @($script:Policy.blockedPreloadAssemblies).assemblyName
        )

        $ConflictNames | Should -HaveCount 18
        foreach ($Name in $ConflictNames) {
            @($ClassifiedNames | Where-Object { $_ -eq $Name }) | Should -HaveCount 1
        }
    }

    It 'records the pull request 264 adjudication evidence' {
        $script:Policy.baseline.validation.pullRequest | Should -Be 264
        $script:Policy.baseline.validation.result | Should -BeExactly 'tracked-conflict-classified-and-excluded'
        $script:Policy.baseline.validation.validatedOn | Should -BeExactly '2026-06-25'
        @($script:Policy.baseline.validation.evidence) | Should -Not -BeNullOrEmpty
    }

    It 'records the ProtectedData conflict row and block classification' {
        $ConflictRow = @($script:Policy.baseline.conflictSurface | Where-Object name -EQ 'System.Security.Cryptography.ProtectedData')
        $BlockEntry = @($script:Policy.blockedPreloadAssemblies | Where-Object assemblyName -EQ 'System.Security.Cryptography.ProtectedData')

        $ConflictRow | Should -HaveCount 1
        @($ConflictRow[0].versions) | Should -Be @('4.0.3.0', '7.0.0.0', '9.0.0.0')
        @($ConflictRow[0].shippedBy) | Should -Be @('Az.Accounts', 'ExchangeOnlineManagement', 'Microsoft.Graph.Authentication', 'MicrosoftTeams')
        $BlockEntry | Should -HaveCount 1
    }

}
