BeforeAll {
    Set-Location -Path $PSScriptRoot
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $BuiltModuleManifestPath = Join-Path $ProjectRoot 'module\DLLPickle\DLLPickle.psd1'
}

Describe 'Built module integration validation' -Tag 'Integration' {
    It 'imports DLL dependencies cleanly in PowerShell 7.4+' {
        Test-Path $BuiltModuleManifestPath | Should -BeTrue

        Remove-Module DLLPickle -Force -ErrorAction SilentlyContinue
        Import-Module $BuiltModuleManifestPath -Force

        $Result = Import-DPLibrary -SuppressLogo -ShowLoaderExceptions -Verbose 4>&1
        $ImportResults = @($Result | Where-Object { $_.PSObject.Properties.Name -contains 'Status' })

        @($ImportResults | Where-Object Status -EQ 'Failed') | Should -BeNullOrEmpty
    }

    It 'does not preload Azure.Core on the net8.0 profile (regression guard for the Az.Accounts load-context split)' {
        # Az.Accounts 5.x isolates its Azure SDK stack in a private AssemblyLoadContext.
        # Preloading Azure.Core into the default context splits Azure.Core.TokenRequestContext
        # across load contexts and breaks Connect-AzAccount. The net48-only Azure.Core preload
        # (#183) must not regress into the net8.0 preload set.
        $BinPath = Join-Path (Split-Path -Path $BuiltModuleManifestPath -Parent) 'bin\net8.0'

        # Packaging invariant: Azure.Core (and its isolated BCL subgraph) must not be shipped.
        Join-Path $BinPath 'Azure.Core.dll' | Should -Not -Exist
        Join-Path $BinPath 'System.ClientModel.dll' | Should -Not -Exist

        Remove-Module DLLPickle -Force -ErrorAction SilentlyContinue
        Import-Module $BuiltModuleManifestPath -Force

        # Behavioral invariant: Import-DPLibrary must not report Azure.Core among preloaded assemblies.
        $ImportResults = @(Import-DPLibrary -SuppressLogo)
        @($ImportResults | Where-Object AssemblyName -EQ 'Azure.Core') | Should -BeNullOrEmpty
        @($ImportResults | Where-Object DLLName -EQ 'Azure.Core.dll') | Should -BeNullOrEmpty
    }
}
