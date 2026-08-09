BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:RuntimePolicyPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'src/DLLPickle/SupportedRuntimeProfiles.json'
    . (Join-Path -Path $script:RepositoryRoot -ChildPath 'src/DLLPickle/Private/Get-DPRuntimeProfile.ps1')
}

Describe 'Get-DPRuntimeProfile' -Tag 'Unit' {
    It 'selects <TargetFramework> for PowerShell <PowerShellVersion> on CLR <DotNetMajor>' -ForEach @(
        @{ PowerShellVersion = [version]'7.4.18'; DotNetMajor = 8; TargetFramework = 'net8.0' }
        @{ PowerShellVersion = [version]'7.5.9'; DotNetMajor = 9; TargetFramework = 'net9.0' }
        @{ PowerShellVersion = [version]'7.6.4'; DotNetMajor = 10; TargetFramework = 'net10.0' }
    ) {
        $result = Get-DPRuntimeProfile -PolicyPath $script:RuntimePolicyPath -PowerShellVersion $PowerShellVersion -DotNetMajor $DotNetMajor

        $result.targetFramework | Should -Be $TargetFramework
    }

    It 'fails closed for an unsupported PowerShell line' {
        {
            Get-DPRuntimeProfile -PolicyPath $script:RuntimePolicyPath -PowerShellVersion ([version]'7.7.0') -DotNetMajor 10
        } | Should -Throw '*Unsupported PowerShell runtime*7.4*7.5*7.6*'
    }

    It 'fails closed when the PowerShell line is hosted on the wrong CLR major' {
        {
            Get-DPRuntimeProfile -PolicyPath $script:RuntimePolicyPath -PowerShellVersion ([version]'7.5.9') -DotNetMajor 10
        } | Should -Throw '*CLR mismatch*PowerShell 7.5*expected CLR 9*detected CLR 10*'
    }

    It 'rejects malformed JSON policy data' {
        $policyPath = Join-Path -Path $TestDrive -ChildPath 'malformed.json'
        Set-Content -LiteralPath $policyPath -Value '{ invalid json' -Encoding utf8

        {
            Get-DPRuntimeProfile -PolicyPath $policyPath -PowerShellVersion ([version]'7.6.4') -DotNetMajor 10
        } | Should -Throw '*malformed*'
    }

    It 'rejects duplicate PowerShell mappings' {
        $policyPath = Join-Path -Path $TestDrive -ChildPath 'duplicate.json'
        $policy = Get-Content -LiteralPath $script:RuntimePolicyPath -Raw | ConvertFrom-Json
        $policy.profiles = @($policy.profiles) + @($policy.profiles[0])
        $policy | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $policyPath -Encoding utf8

        {
            Get-DPRuntimeProfile -PolicyPath $policyPath -PowerShellVersion ([version]'7.4.18') -DotNetMajor 8
        } | Should -Throw '*duplicate*PowerShell 7.4*'
    }

    It 'rejects a TFM that does not correspond to the declared CLR major' {
        $policyPath = Join-Path -Path $TestDrive -ChildPath 'invalid-tfm.json'
        $policy = Get-Content -LiteralPath $script:RuntimePolicyPath -Raw | ConvertFrom-Json
        $policy.profiles[2].targetFramework = 'net9.0'
        $policy | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $policyPath -Encoding utf8

        {
            Get-DPRuntimeProfile -PolicyPath $policyPath -PowerShellVersion ([version]'7.6.4') -DotNetMajor 10
        } | Should -Throw '*targetFramework*net10.0*'
    }
}
