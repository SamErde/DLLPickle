BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    . (Join-Path $script:RepositoryRoot 'tools\DLLPickle.ManualAuthenticatedEvidence.ps1')
}

Describe 'Manual authenticated evidence helpers' -Tag 'Unit' {
    It 'collapses relative asset paths and rejects root escape' {
        ConvertTo-DLLPickleCollapsedAssetPath -Path 'module/./lib/../bin/file.dll' |
            Should -BeExactly 'module/bin/file.dll'
        { ConvertTo-DLLPickleCollapsedAssetPath -Path '../outside.dll' } |
            Should -Throw '*escapes its root*'
    }

    It 'normalizes direct roots, mixed separators, and rejects out-of-root paths' {
        $Parameters = @{
            ModuleCacheRoot = 'C:\cache\modules\'
            DLLPickleRoot = 'C:\repo\module\DLLPickle\'
            RuntimeRoot = 'C:\runtime\pwsh\'
        }

        ConvertTo-DLLPickleManualEvidencePath -Path 'C:/cache/modules' @Parameters |
            Should -BeExactly 'upstream:.'
        ConvertTo-DLLPickleManualEvidencePath -Path 'C:/repo/module/DLLPickle/bin\net8.0/file.dll' @Parameters |
            Should -BeExactly 'dllpickle:bin/net8.0/file.dll'
        { ConvertTo-DLLPickleManualEvidencePath -Path 'C:\cache\modules\..\secret.txt' @Parameters } |
            Should -Throw '*escapes its root*'
        { ConvertTo-DLLPickleManualEvidencePath -Path 'C:\unrelated\file.dll' @Parameters } |
            Should -Throw '*outside the upstream*'
    }

    It 'normalizes only manifests beneath the prepared cache root' {
        ConvertTo-DLLPickleUpstreamManifestIdentifier -ManifestPath 'C:/cache/Graph\2.0/Graph.psd1' -ModuleCachePath 'C:\cache\' |
            Should -BeExactly 'upstream:Graph/2.0/Graph.psd1'
        { ConvertTo-DLLPickleUpstreamManifestIdentifier -ManifestPath 'C:\cache' -ModuleCachePath 'C:\cache\' } |
            Should -Throw '*outside its prepared module cache*'
        { ConvertTo-DLLPickleUpstreamManifestIdentifier -ManifestPath 'C:\other\Graph.psd1' -ModuleCachePath 'C:\cache' } |
            Should -Throw '*outside its prepared module cache*'
    }

    It 'resolves exactly one command from the named prepared module' {
        $Command = Get-DLLPickleAuthenticatedCommand -Name 'Get-Item' -Module 'Microsoft.PowerShell.Management'

        $Command.Name | Should -BeExactly 'Get-Item'
        $Command.ModuleName | Should -BeExactly 'Microsoft.PowerShell.Management'
    }

    It 'returns a sanitized failing read-probe shape without retaining an error message' {
        Mock Get-DLLPickleAuthenticatedCommand {
            { throw [System.UnauthorizedAccessException]::new('sensitive provider detail') }
        } -ParameterFilter { $Name -eq 'Get-MgContext' -and $Module -eq 'Microsoft.Graph.Authentication' }

        $Result = Invoke-DLLPickleAuthenticatedReadProbe -ProbeId 'graph-context'

        @($Result.Keys) | Should -Be @('probeId', 'executed', 'status', 'durationMilliseconds', 'writesPerformed', 'errorType')
        $Result.probeId | Should -BeExactly 'graph-context'
        $Result.executed | Should -BeTrue
        $Result.status | Should -BeExactly 'failed'
        $Result.writesPerformed | Should -BeFalse
        $Result.errorType | Should -BeExactly 'System.UnauthorizedAccessException'
        ($Result | ConvertTo-Json -Compress) | Should -Not -Match 'sensitive provider detail'
    }

    It 'changes the prepared inventory fingerprint when selected module bytes change' {
        $CacheRoot = Join-Path $TestDrive 'module-cache'
        $ModuleRoot = Join-Path $CacheRoot 'Contoso.Module\1.0.0'
        $null = New-Item -Path $ModuleRoot -ItemType Directory -Force
        $ModuleFile = Join-Path $ModuleRoot 'Contoso.Module.psm1'
        Set-Content -LiteralPath $ModuleFile -Value 'function Get-Contoso { 1 }' -Encoding UTF8
        $Inventory = [pscustomobject]@{
            ProfileKey = 'ps7.4-net8.0-windows-x64'
            ModuleCachePath = $CacheRoot
            Profile = [pscustomobject]@{
                PowerShellVersion = '7.4.18'
                PowerShellLine = '7.4'
                TargetFramework = 'net8.0'
                Platform = 'windows'
                Architecture = 'x64'
            }
            Modules = @(
                [pscustomobject]@{
                    Name = 'Contoso.Module'
                    Version = '1.0.0'
                    LatestCompatibleVersion = '1.0.0'
                    ModulePath = $ModuleRoot
                    ModuleManifestPath = $ModuleFile
                }
            )
        }

        $Before = Get-DLLPicklePreparedInventoryFingerprint -Inventory $Inventory
        Set-Content -LiteralPath $ModuleFile -Value 'function Get-Contoso { 2 }' -Encoding UTF8
        $After = Get-DLLPicklePreparedInventoryFingerprint -Inventory $Inventory

        $Before | Should -Match '^[a-f0-9]{64}$'
        $After | Should -Match '^[a-f0-9]{64}$'
        $After | Should -Not -BeExactly $Before
    }
}
