BeforeAll {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $ExportScript = Join-Path $RepoRoot 'build\Export-DLLPickleKnownConflicts.ps1'
    $PolicyPath = Join-Path $RepoRoot 'build\dependency-policy.json'
}

Describe 'Export-DLLPickleKnownConflicts' -Tag 'Unit' {
    It 'writes the policy knownConflicts array to the output file verbatim' {
        $Out = Join-Path $TestDrive 'KnownConflicts.json'
        & $ExportScript -PolicyPath $PolicyPath -OutputPath $Out
        Test-Path -LiteralPath $Out | Should -BeTrue
        $Written = Get-Content -LiteralPath $Out -Raw | ConvertFrom-Json
        $Policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
        @($Written).Count | Should -Be @($Policy.knownConflicts).Count
        ($Written | Where-Object id -EQ '174-odata-azstorage-exo') | Should -Not -BeNullOrEmpty
    }
}
