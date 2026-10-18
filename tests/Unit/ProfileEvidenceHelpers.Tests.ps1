BeforeAll {
    $RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    . (Join-Path $RepositoryRoot 'tools\DLLPickle.ProfileEvidence.ps1')
}

Describe 'Profile evidence helpers' -Tag 'Unit' {
    It 'recomputes the canonical UTF-8 SHA-256 content fingerprint' {
        $Evidence = [pscustomobject]@{
            schemaVersion = 1
            content = [ordered]@{
                profile = 'ps7.6-net10.0-windows-x64'
                values = @('z', 'a')
            }
        }
        $CanonicalContent = $Evidence.content | ConvertTo-Json -Depth 100 -Compress
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($CanonicalContent)
        $Expected = [System.BitConverter]::ToString(
            [System.Security.Cryptography.SHA256]::HashData($Bytes)
        ).Replace('-', '').ToLowerInvariant()

        Get-DLLPickleNormalizedEvidenceFingerprint -Evidence $Evidence | Should -BeExactly $Expected
    }

    It 'rejects unsupported or content-free evidence envelopes' {
        { Get-DLLPickleNormalizedEvidenceFingerprint -Evidence ([pscustomobject]@{ schemaVersion = 2; content = @{} }) } |
            Should -Throw '*unsupported schema*'
        { Get-DLLPickleNormalizedEvidenceFingerprint -Evidence ([pscustomobject]@{ schemaVersion = 1 }) } |
            Should -Throw '*no fingerprinted content*'
    }

    It 'normalizes date/time inputs to UTC with invariant parsing' {
        (ConvertTo-DLLPickleUtcDateTimeOffset -Value '2026-08-09T08:00:00-04:00').ToString('o') |
            Should -BeExactly '2026-08-09T12:00:00.0000000+00:00'
        ConvertTo-DLLPickleCanonicalUtcTimestamp -Value ([System.DateTimeOffset]'2026-08-09T08:00:00-04:00') |
            Should -BeExactly '2026-08-09T12:00:00.0000000Z'
    }

    It 'keeps scenario fingerprints stable across machine-specific paths and error text' {
        function Get-ScenarioFingerprintFixture {
            param(
                [Parameter(Mandatory)][string]$AssemblyPath,
                [Parameter(Mandatory)][string]$ErrorText,
                [string]$Sha256 = ('a' * 64)
            )

            [pscustomobject]@{
                ScenarioId = 'synthetic-order'
                OrderIndex = 1
                ImportOrder = @('Synthetic.One')
                DllPicklePreloaded = $false
                ExpectedLimitation = $true
                ExpectedSuccess = $null
                OutcomePolicy = 'observe-known-limitation'
                Success = $false
                OutcomeMatchesExpectation = $true
                Error = $ErrorText
                Assemblies = @(
                    [pscustomobject]@{
                        Name = 'Microsoft.Identity.Client'
                        Version = '4.82.1.0'
                        Sha256 = $Sha256
                        Path = $AssemblyPath
                        Alc = 'Default'
                        IsCollectible = $false
                    }
                )
            }
        }

        $First = Get-ScenarioFingerprintFixture -AssemblyPath 'C:\cache-a\Microsoft.Identity.Client.dll' -ErrorText 'Failure under C:\cache-a'
        $Second = Get-ScenarioFingerprintFixture -AssemblyPath 'D:\cache-b\Microsoft.Identity.Client.dll' -ErrorText 'Failure under D:\cache-b'
        $ChangedAssembly = Get-ScenarioFingerprintFixture -AssemblyPath 'D:\cache-b\Microsoft.Identity.Client.dll' -ErrorText 'Failure under D:\cache-b' -Sha256 ('b' * 64)

        $FirstFingerprint = Get-DLLPickleScenarioFingerprint -ProfileKey 'ps7.6-net10.0-windows-x64' -Scenario @($First)
        $SecondFingerprint = Get-DLLPickleScenarioFingerprint -ProfileKey 'ps7.6-net10.0-windows-x64' -Scenario @($Second)
        $ChangedFingerprint = Get-DLLPickleScenarioFingerprint -ProfileKey 'ps7.6-net10.0-windows-x64' -Scenario @($ChangedAssembly)

        $FirstFingerprint | Should -BeExactly $SecondFingerprint
        $ChangedFingerprint | Should -Not -BeExactly $FirstFingerprint
    }

    It 'accepts only the declared deterministic-probe error outcome' {
        $ExpectedCommand = Get-DLLPickleStrictProbeCommand -Command "Write-Error 'expected authentication gate'" -ExpectedErrorSubstring 'expected authentication gate'
        $UnexpectedCommand = Get-DLLPickleStrictProbeCommand -Command "Write-Error 'unexpected probe failure'" -ExpectedErrorSubstring 'expected authentication gate'
        $ExpectedScript = [scriptblock]::Create($ExpectedCommand)
        $UnexpectedScript = [scriptblock]::Create($UnexpectedCommand)
        $OriginalErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Stop'
            { & $ExpectedScript } | Should -Not -Throw
            { & $UnexpectedScript } | Should -Throw '*unexpected probe failure*'
        } finally {
            $ErrorActionPreference = $OriginalErrorActionPreference
        }
    }

    It 'does not wrap probes without an expected error outcome' {
        Get-DLLPickleStrictProbeCommand -Command 'Get-Date | Out-Null' |
            Should -BeExactly 'Get-Date | Out-Null'
    }

    It 'uses ordinal ordering and uniqueness regardless of process culture' {
        $OriginalCulture = [System.Globalization.CultureInfo]::CurrentCulture
        try {
            [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('tr-TR')
            $Actual = @(Get-DLLPickleOrdinalSequence -InputObject @('z', $null, 'a', 'A', 'z') -Unique)
        } finally {
            [System.Globalization.CultureInfo]::CurrentCulture = $OriginalCulture
        }

        ($Actual -join ',') | Should -BeExactly 'A,a,z'
    }
}
