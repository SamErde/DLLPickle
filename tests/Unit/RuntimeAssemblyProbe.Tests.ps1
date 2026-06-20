BeforeAll {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $LoadedScript = Join-Path $RepoRoot 'tools\Get-DLLPickleLoadedTrackedAssembly.ps1'
    $SnapshotScript = Join-Path $RepoRoot 'tools\Get-DLLPickleRuntimeAssemblySnapshot.ps1'

    # Named Get-* (not New-*): the AnalyzeTests task only excludes PSUseDeclaredVarsMoreThanAssignments,
    # so a New-*/Set-* helper would trip PSUseShouldProcessForStateChangingFunctions and fail the gate.
    function Get-TempPolicyPath {
        param([string[]]$TrackedAssemblies)
        $Path = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('n') + '.json')
        [PSCustomObject]@{ trackedAssemblies = $TrackedAssemblies } |
            ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding utf8
        $Path
    }
}

Describe 'Get-DLLPickleLoadedTrackedAssembly' -Tag 'Unit' {
    It 'returns a loaded assembly that is in trackedAssemblies, with version + ALC' {
        $Policy = Get-TempPolicyPath -TrackedAssemblies @('System.Management.Automation')
        $Result = & $LoadedScript -PolicyPath $Policy
        $Row = $Result | Where-Object Name -EQ 'System.Management.Automation'
        $Row | Should -Not -BeNullOrEmpty
        $Row.Alc | Should -Not -BeNullOrEmpty
        $Row.Version | Should -Not -BeNullOrEmpty
    }

    It 'excludes loaded assemblies that are not in trackedAssemblies' {
        $Policy = Get-TempPolicyPath -TrackedAssemblies @('System.Management.Automation')
        $Result = & $LoadedScript -PolicyPath $Policy
        ($Result | Where-Object Name -EQ 'System.Private.CoreLib') | Should -BeNullOrEmpty
    }

    It 'returns nothing when -NameLike matches no tracked+loaded assembly' {
        $Policy = Get-TempPolicyPath -TrackedAssemblies @('System.Management.Automation')
        $Result = & $LoadedScript -PolicyPath $Policy -NameLike 'Microsoft.OData*'
        @($Result) | Should -BeNullOrEmpty
    }

    It 'returns the row when -NameLike matches a tracked+loaded assembly' {
        $Policy = Get-TempPolicyPath -TrackedAssemblies @('System.Management.Automation')
        $Result = & $LoadedScript -PolicyPath $Policy -NameLike 'System.Management.*'
        ($Result | Where-Object Name -EQ 'System.Management.Automation') | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-DLLPickleRuntimeAssemblySnapshot' -Tag 'Unit' {
    It 'sources its filter from -PolicyPath and returns tracked assemblies loaded in the child session' {
        $Policy = Get-TempPolicyPath -TrackedAssemblies @('System.Management.Automation')
        # Microsoft.PowerShell.Management is always importable; the child always has SMA loaded.
        $Result = & $SnapshotScript -ModuleName 'Microsoft.PowerShell.Management' -PolicyPath $Policy
        ($Result | Where-Object Name -EQ 'System.Management.Automation') | Should -Not -BeNullOrEmpty
    }

    It 'throws in strict mode when a module cannot be imported' {
        $Policy = Get-TempPolicyPath -TrackedAssemblies @('System.Management.Automation')

        { & $SnapshotScript -ModuleName 'DLLPickle.DefinitelyMissing' -PolicyPath $Policy -Strict } |
            Should -Throw '*runtime assembly snapshot failed*'
    }

    It 'throws in strict mode when the probe command fails' {
        $Policy = Get-TempPolicyPath -TrackedAssemblies @('System.Management.Automation')

        { & $SnapshotScript -ModuleName 'Microsoft.PowerShell.Management' -PolicyPath $Policy -ProbeCommand "throw 'probe failed'" -Strict } |
            Should -Throw '*runtime assembly snapshot failed*'
    }
}
