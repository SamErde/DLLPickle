BeforeAll {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:Policy = Get-Content -LiteralPath (Join-Path $ProjectRoot 'build\dependency-policy.json') -Raw | ConvertFrom-Json
}

Describe 'Dependency policy baseline' -Tag 'Unit' {
    It 'explicitly monitors Az.Resources as the #193 collision source' {
        $MonitoredNames = @($script:Policy.monitoredModules | ForEach-Object name)
        $MonitoredNames | Should -Contain 'Az.Resources'

        $TrackedBlocked = @(
            $script:Policy.blockedPreloadAssemblies |
                Where-Object { $_.assemblyName -in @('Microsoft.Extensions.DependencyInjection.Abstractions', 'Microsoft.Extensions.Logging.Abstractions') }
        )

        $TrackedBlocked | Should -HaveCount 2
        foreach ($Entry in $TrackedBlocked) {
            @($Entry.sourceModules) | Should -Contain 'Az.Resources'
            $Entry.evidence.trackingScope | Should -Match 'included in monitoredModules'
        }
    }

    It 'records the complete structured conflict surface' {
        @($script:Policy.baseline.conflictSurface) | Should -HaveCount 17

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

        $ConflictNames | Should -HaveCount 17
        foreach ($Name in $ConflictNames) {
            @($ClassifiedNames | Where-Object { $_ -eq $Name }) | Should -HaveCount 1
        }
    }

    It 'records the pull request 257 adjudication evidence' {
        $script:Policy.baseline.validation.pullRequest | Should -Be 257
        $script:Policy.baseline.validation.result | Should -BeExactly 'tracked-conflict-classified-and-excluded'
        $script:Policy.baseline.validation.validatedOn | Should -BeExactly '2026-06-23'
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
