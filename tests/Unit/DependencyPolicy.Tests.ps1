BeforeAll {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:Policy = Get-Content -LiteralPath (Join-Path $ProjectRoot 'build\dependency-policy.json') -Raw | ConvertFrom-Json
}

Describe 'Dependency policy baseline' -Tag 'Unit' {
    It 'records the complete structured conflict surface' {
        @($script:Policy.baseline.conflictSurface) | Should -HaveCount 16

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

        $ConflictNames | Should -HaveCount 16
        foreach ($Name in $ConflictNames) {
            @($ClassifiedNames | Where-Object { $_ -eq $Name }) | Should -HaveCount 1
        }
    }

    It 'records the issue 239 adjudication evidence' {
        $script:Policy.baseline.validation.issue | Should -Be 239
        $script:Policy.baseline.validation.result | Should -BeExactly 'classifications-unchanged'
        $script:Policy.baseline.validation.validatedOn | Should -BeExactly '2026-06-20'
        @($script:Policy.baseline.validation.evidence) | Should -Not -BeNullOrEmpty
    }
}
