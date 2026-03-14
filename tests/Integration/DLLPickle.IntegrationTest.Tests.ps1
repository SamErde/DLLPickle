BeforeAll {
    Set-Location -Path $PSScriptRoot
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $BuiltModuleManifestPath = Join-Path $ProjectRoot 'module\DLLPickle\DLLPickle.psd1'
}

Describe 'Built module integration validation' -Tag 'Integration' {
    It 'imports DLL dependencies cleanly in Windows PowerShell 5.1' -Skip:(-not $IsWindows) {
        Test-Path $BuiltModuleManifestPath | Should -BeTrue

        $ValidationScriptPath = Join-Path $TestDrive 'Validate-BuiltModule.ps1'
        @"
Import-Module '$BuiltModuleManifestPath' -Force

`$Result = Import-DPLibrary -SuppressLogo -ShowLoaderExceptions -Verbose 4>&1
`$ImportResults = @(`$Result | Where-Object { `$_.PSObject.Properties.Name -contains 'Status' })
`$FailedResults = @(`$ImportResults | Where-Object Status -eq 'Failed')

if (`$FailedResults.Count -gt 0) {
	Write-Error ('Built module import reported failed assemblies: {0}' -f ((`$FailedResults | Select-Object -ExpandProperty DLLName) -join ', '))
	exit 1
}

if ((`$Result | Out-String) -match 'Failed to import') {
	Write-Error 'Built module import emitted transient loader failure output.'
	exit 1
}
"@ | Set-Content -Path $ValidationScriptPath -Encoding utf8

        $Output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ValidationScriptPath 2>&1

        $LASTEXITCODE | Should -Be 0
        ($Output -join [Environment]::NewLine) | Should -Not -Match 'Failed to import'
    }

    It 'imports DLL dependencies cleanly in PowerShell 7+' {
        Test-Path $BuiltModuleManifestPath | Should -BeTrue

        Remove-Module DLLPickle -Force -ErrorAction SilentlyContinue
        Import-Module $BuiltModuleManifestPath -Force

        $Result = Import-DPLibrary -SuppressLogo -ShowLoaderExceptions -Verbose 4>&1
        $ImportResults = @($Result | Where-Object { $_.PSObject.Properties.Name -contains 'Status' })

        @($ImportResults | Where-Object Status -EQ 'Failed') | Should -BeNullOrEmpty
        (($Result | Out-String) -match 'Failed to import') | Should -BeFalse
    }
}
