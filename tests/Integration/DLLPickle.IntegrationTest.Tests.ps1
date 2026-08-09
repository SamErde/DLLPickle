BeforeAll {
    Set-Location -Path $PSScriptRoot
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $BuiltModuleManifestPath = Join-Path $ProjectRoot 'module\DLLPickle\DLLPickle.psd1'
    $RuntimePolicy = Get-Content -LiteralPath (Join-Path $ProjectRoot 'src\DLLPickle\SupportedRuntimeProfiles.json') -Raw | ConvertFrom-Json
    $RuntimeProfile = @($RuntimePolicy.profiles | Where-Object {
            $_.powerShellMajor -eq $PSVersionTable.PSVersion.Major -and $_.powerShellMinor -eq $PSVersionTable.PSVersion.Minor
        })
    if ($RuntimeProfile.Count -ne 1 -or $RuntimeProfile[0].dotnetMajor -ne [Environment]::Version.Major) {
        throw 'The integration-test process does not match exactly one supported runtime profile.'
    }
    $TargetFramework = [string]$RuntimeProfile[0].targetFramework
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

    It 'does not preload Azure.Core on the selected runtime profile (regression guard for the Az.Accounts load-context split)' {
        # Az.Accounts 5.x isolates its Azure SDK stack in a private AssemblyLoadContext.
        # Preloading Azure.Core into the default context splits Azure.Core.TokenRequestContext
        # across load contexts and breaks Connect-AzAccount. The net48-only Azure.Core preload
        # (#183) must not regress into any supported preload set.
        $BinPath = Join-Path (Split-Path -Path $BuiltModuleManifestPath -Parent) (Join-Path 'bin' $TargetFramework)

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

    It 'does not preload the Microsoft.Extensions.* BCL transitives (regression guard for #193 / Az.Resources)' {
        # These are incidental transitives of Microsoft.IdentityModel.Tokens, not part of DLLPickle's
        # identity-coordination purpose. PowerShell does not host-provide them, and preloading our own
        # copies into the default ALC collides with modules that bundle their own (Az.Resources 9.x ->
        # "Microsoft.Extensions.DependencyInjection.Abstractions ... assembly with same name is already
        # loaded"). They are excluded from the bundle via ExcludeAssets in DLLPickle.csproj.
        $BinPath = Join-Path (Split-Path -Path $BuiltModuleManifestPath -Parent) (Join-Path 'bin' $TargetFramework)

        # Packaging invariant: the Extensions BCL transitives must not be shipped.
        Join-Path $BinPath 'Microsoft.Extensions.DependencyInjection.Abstractions.dll' | Should -Not -Exist
        Join-Path $BinPath 'Microsoft.Extensions.Logging.Abstractions.dll' | Should -Not -Exist

        Remove-Module DLLPickle -Force -ErrorAction SilentlyContinue
        Import-Module $BuiltModuleManifestPath -Force

        # Behavioral invariant: Import-DPLibrary must not report them among preloaded assemblies,
        # and Microsoft.IdentityModel.Tokens must still load successfully without them bundled.
        $ImportResults = @(Import-DPLibrary -SuppressLogo)
        @($ImportResults | Where-Object DLLName -Like 'Microsoft.Extensions.*') | Should -BeNullOrEmpty
        $Tokens = $ImportResults | Where-Object DLLName -EQ 'Microsoft.IdentityModel.Tokens.dll'
        $Tokens.Status | Should -Not -Be 'Failed'
    }
}
