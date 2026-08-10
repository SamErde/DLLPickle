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
