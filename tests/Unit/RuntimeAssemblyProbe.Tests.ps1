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
        $Row.Platform | Should -BeIn @('windows', 'linux', 'macos')
        $Row.OS | Should -Not -BeNullOrEmpty
        if ($Row.Platform -eq 'macos') {
            $Row.OS | Should -Match '^macOS \d+\.\d+'
        }
    }

    It 'uses the stable macOS product version instead of the Darwin kernel description' {
        $Source = Get-Content -LiteralPath $LoadedScript -Raw

        $Source | Should -Match ([regex]::Escape('/usr/bin/sw_vers -productVersion'))
        $Source | Should -Match ([regex]::Escape('$OperatingSystemDescription = "macOS $MacOSProductVersion"'))
        Get-Content -LiteralPath (Join-Path $RepoRoot 'build\profile-evidence\ps7.4-net8.0-macos-x64.json') -Raw |
            Should -Not -Match 'Darwin Kernel Version'
        Get-Content -LiteralPath (Join-Path $RepoRoot 'build\profile-evidence\ps7.5-net9.0-macos-x64.json') -Raw |
            Should -Not -Match 'Darwin Kernel Version'
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
        $Result = & $SnapshotScript -ModuleName 'Microsoft.PowerShell.Management' -PolicyPath $Policy -PowerShellExecutable ([Environment]::ProcessPath) -PowerShellVersion $PSVersionTable.PSVersion -TargetFramework ('net{0}.0' -f [Environment]::Version.Major)
        ($Result | Where-Object Name -EQ 'System.Management.Automation') | Should -Not -BeNullOrEmpty
        $Result[0].PowerShellVersion | Should -Be $PSVersionTable.PSVersion.ToString()
        $Result[0].TargetFramework | Should -Be ('net{0}.0' -f [Environment]::Version.Major)
        $Result[0].ExecutablePath | Should -Not -BeNullOrEmpty
        $Result[0].Platform | Should -BeIn @('windows', 'linux', 'macos')
        $Result[0].Architecture | Should -Not -BeNullOrEmpty
    }

    It 'throws in strict mode when a module cannot be imported' {
        $Policy = Get-TempPolicyPath -TrackedAssemblies @('System.Management.Automation')

        { & $SnapshotScript -ModuleName 'DLLPickle.DefinitelyMissing' -PolicyPath $Policy -PowerShellExecutable ([Environment]::ProcessPath) -Strict } |
            Should -Throw '*runtime assembly snapshot failed*'
    }

    It 'throws in strict mode when the probe command fails' {
        $Policy = Get-TempPolicyPath -TrackedAssemblies @('System.Management.Automation')

        { & $SnapshotScript -ModuleName 'Microsoft.PowerShell.Management' -PolicyPath $Policy -PowerShellExecutable ([Environment]::ProcessPath) -ProbeCommand "throw 'probe failed'" -Strict } |
            Should -Throw '*runtime assembly snapshot failed*'
    }

    It 'imports an exact manifest under an explicitly isolated module path' {
        $Policy = Get-TempPolicyPath -TrackedAssemblies @('System.Management.Automation')
        $ModuleRoot = Join-Path $TestDrive 'isolated-module'
        $null = New-Item -Path $ModuleRoot -ItemType Directory
        Set-Content -LiteralPath (Join-Path $ModuleRoot 'Synthetic.Isolated.psm1') -Value '# isolated import target' -Encoding UTF8
        $ManifestPath = Join-Path $ModuleRoot 'Synthetic.Isolated.psd1'
        New-ModuleManifest -Path $ManifestPath -RootModule 'Synthetic.Isolated.psm1' -ModuleVersion '1.0.0'

        $Result = & $SnapshotScript -ModuleName 'Synthetic.Isolated' -ModuleManifestPath $ManifestPath -ModuleSearchPath @($ModuleRoot, (Join-Path $PSHOME 'Modules')) -PolicyPath $Policy -PowerShellExecutable ([Environment]::ProcessPath) -Strict

        $Result[0].ImportedModulePaths | Should -Contain $ManifestPath
        $Result[0].IsolatedModulePath | Should -Be (@($ModuleRoot, (Join-Path $PSHOME 'Modules')) -join [System.IO.Path]::PathSeparator)
    }

    It 'keeps module informational output separate from the JSON result' {
        $Policy = Get-TempPolicyPath -TrackedAssemblies @('System.Management.Automation')
        $ModuleRoot = Join-Path $TestDrive 'noisy-module'
        $null = New-Item -Path $ModuleRoot -ItemType Directory
        Set-Content -LiteralPath (Join-Path $ModuleRoot 'Synthetic.Noisy.psm1') -Value "Write-Host 'Get started with Synthetic.Noisy'" -Encoding UTF8
        $ManifestPath = Join-Path $ModuleRoot 'Synthetic.Noisy.psd1'
        New-ModuleManifest -Path $ManifestPath -RootModule 'Synthetic.Noisy.psm1' -ModuleVersion '1.0.0'

        $Result = & $SnapshotScript -ModuleName 'Synthetic.Noisy' -ModuleManifestPath $ManifestPath -ModuleSearchPath @($ModuleRoot, (Join-Path $PSHOME 'Modules')) -PolicyPath $Policy -PowerShellExecutable ([Environment]::ProcessPath) -Strict

        ($Result | Where-Object Name -EQ 'System.Management.Automation') | Should -Not -BeNullOrEmpty
    }

    It 'returns an empty snapshot when no tracked assemblies are loaded' {
        $Policy = Get-TempPolicyPath -TrackedAssemblies @('DLLPickle.NotLoaded')

        $Result = @(& $SnapshotScript -ModuleName 'Microsoft.PowerShell.Management' -PolicyPath $Policy -PowerShellExecutable ([Environment]::ProcessPath) -Strict)

        $Result | Should -HaveCount 0
    }

    It 'never launches a generic pwsh command from PATH' {
        $Source = Get-Content -LiteralPath $SnapshotScript -Raw

        $Source | Should -Match 'PowerShellExecutable'
        $Source | Should -Not -Match '(?m)&\s+pwsh\b'
    }
}
