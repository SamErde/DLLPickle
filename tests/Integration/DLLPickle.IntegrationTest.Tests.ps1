BeforeAll {
    Set-Location -Path $PSScriptRoot
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $BuiltModuleManifestPath = Join-Path $ProjectRoot 'module\DLLPickle\DLLPickle.psd1'
}

Describe 'Built module integration validation' -Tag 'Integration' {
    It 'imports DLL dependencies cleanly in PowerShell 7+' {
        Test-Path $BuiltModuleManifestPath | Should -BeTrue

        Remove-Module DLLPickle -Force -ErrorAction SilentlyContinue
        Import-Module $BuiltModuleManifestPath -Force

        $Result = Import-DPLibrary -SuppressLogo -ShowLoaderExceptions -Verbose 4>&1
        $ImportResults = @($Result | Where-Object { $_.PSObject.Properties.Name -contains 'Status' })

        @($ImportResults | Where-Object Status -EQ 'Failed') | Should -BeNullOrEmpty
    }
}
