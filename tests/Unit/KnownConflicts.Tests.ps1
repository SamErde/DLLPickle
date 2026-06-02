BeforeAll {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $ExportScript = Join-Path $RepoRoot 'build\Export-DLLPickleKnownConflicts.ps1'
    $PolicyPath = Join-Path $RepoRoot 'build\dependency-policy.json'
    . (Join-Path $RepoRoot 'src\DLLPickle\Private\Test-DPModuleConflict.ps1')
    . (Join-Path $RepoRoot 'src\DLLPickle\Private\Get-DPKnownConflict.ps1')
    . (Join-Path $RepoRoot 'src\DLLPickle\Private\Format-DPConflictWarning.ps1')
    . (Join-Path $RepoRoot 'src\DLLPickle\Public\Test-DPLibraryConflict.ps1')

    $SampleConflict = [PSCustomObject]@{
        id = 'sample'; modules = @('Alpha', 'Beta'); assembly = 'Some.Assembly'; issue = '999'
        reason = 'Alpha and Beta clash.'; workaround = 'Use separate sessions.'
    }
}

Describe 'Test-DPModuleConflict' -Tag 'Unit' {
    It 'returns a conflict when every module in the pair is loaded' {
        $Active = Test-DPModuleConflict -Conflict @($SampleConflict) -LoadedModule @('Alpha', 'Beta', 'Gamma')
        @($Active).Count | Should -Be 1
        $Active[0].id | Should -Be 'sample'
    }

    It 'returns nothing when only one module in the pair is loaded' {
        $Active = Test-DPModuleConflict -Conflict @($SampleConflict) -LoadedModule @('Alpha', 'Gamma')
        @($Active) | Should -BeNullOrEmpty
    }

    It 'returns nothing for an empty conflict list' {
        $Active = Test-DPModuleConflict -Conflict @() -LoadedModule @('Alpha', 'Beta')
        @($Active) | Should -BeNullOrEmpty
    }
}

Describe 'Format-DPConflictWarning' -Tag 'Unit' {
    It 'includes the modules, workaround, and issue link' {
        $Message = Format-DPConflictWarning -Conflict $SampleConflict
        $Message | Should -Match 'Alpha'
        $Message | Should -Match 'Beta'
        $Message | Should -Match 'separate sessions'
        $Message | Should -Match 'issues/999'
    }
}

Describe 'Get-DPKnownConflict' -Tag 'Unit' {
    It 'reads conflicts from an explicit path' {
        $Path = Join-Path $TestDrive 'kc.json'
        ConvertTo-Json -InputObject @($SampleConflict) -Depth 20 | Set-Content -LiteralPath $Path -Encoding utf8
        $Conflicts = Get-DPKnownConflict -Path $Path
        @($Conflicts).Count | Should -Be 1
        $Conflicts[0].id | Should -Be 'sample'
    }

    It 'returns an empty array when the file is missing' {
        $Conflicts = Get-DPKnownConflict -Path (Join-Path $TestDrive 'nope.json')
        @($Conflicts) | Should -BeNullOrEmpty
    }

    It 'returns an empty array (no throw) when the file is malformed' {
        $Path = Join-Path $TestDrive 'bad.json'
        Set-Content -LiteralPath $Path -Value '{ not json' -Encoding utf8
        { Get-DPKnownConflict -Path $Path } | Should -Not -Throw
        @(Get-DPKnownConflict -Path $Path) | Should -BeNullOrEmpty
    }
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

Describe 'Test-DPLibraryConflict' -Tag 'Unit' {
    BeforeAll {
        Import-Module Microsoft.PowerShell.Management -ErrorAction SilentlyContinue
        Import-Module Microsoft.PowerShell.Utility -ErrorAction SilentlyContinue
        $LoadedPairPath = Join-Path $TestDrive 'loaded-pair.json'
        ConvertTo-Json -Depth 20 -InputObject @(
            [PSCustomObject]@{ id = 'loaded'; modules = @('Microsoft.PowerShell.Management', 'Microsoft.PowerShell.Utility'); assembly = 'x'; issue = '174'; reason = 'r'; workaround = 'w' }
        ) | Set-Content -LiteralPath $LoadedPairPath -Encoding utf8
        $UnloadedPairPath = Join-Path $TestDrive 'unloaded-pair.json'
        ConvertTo-Json -Depth 20 -InputObject @(
            [PSCustomObject]@{ id = 'unloaded'; modules = @('No.Such.ModuleA', 'No.Such.ModuleB'); assembly = 'x'; issue = '174'; reason = 'r'; workaround = 'w' }
        ) | Set-Content -LiteralPath $UnloadedPairPath -Encoding utf8
    }

    It 'warns and returns the conflict when both modules are loaded' {
        $Active = Test-DPLibraryConflict -KnownConflictsPath $LoadedPairPath -WarningAction SilentlyContinue
        @($Active).Count | Should -Be 1
        $Active[0].id | Should -Be 'loaded'
    }

    It 'emits a Write-Warning when a conflict is active' {
        $Warnings = $null
        Test-DPLibraryConflict -KnownConflictsPath $LoadedPairPath -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null
        @($Warnings).Count | Should -BeGreaterThan 0
    }

    It 'is silent and returns nothing when no conflict pair is fully loaded' {
        $Warnings = $null
        $Active = Test-DPLibraryConflict -KnownConflictsPath $UnloadedPairPath -WarningVariable Warnings -WarningAction SilentlyContinue
        @($Active) | Should -BeNullOrEmpty
        @($Warnings) | Should -BeNullOrEmpty
    }
}
