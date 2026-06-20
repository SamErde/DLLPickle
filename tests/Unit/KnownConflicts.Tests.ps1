BeforeAll {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $RepoRoot 'src\DLLPickle\Private\Test-DPModuleConflict.ps1')
    . (Join-Path $RepoRoot 'src\DLLPickle\Private\Get-DPKnownConflict.ps1')
    . (Join-Path $RepoRoot 'src\DLLPickle\Private\Format-DPConflictWarning.ps1')
    . (Join-Path $RepoRoot 'src\DLLPickle\Private\Invoke-DPConflictCheck.ps1')
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

Describe 'Shipped KnownConflicts.json source' -Tag 'Unit' {
    # The conflict data is a committed source file under src/DLLPickle (the single source of truth),
    # copied into the module verbatim by the build. No build-time extraction step to validate anymore.
    BeforeAll {
        $KnownConflictsPath = Join-Path $RepoRoot 'src\DLLPickle\KnownConflicts.json'
    }

    It 'exists as a committed source file under src/DLLPickle' {
        Test-Path -LiteralPath $KnownConflictsPath -PathType Leaf | Should -BeTrue
    }

    It 'is a non-empty JSON array of conflict entries' {
        $Parsed = Get-Content -LiteralPath $KnownConflictsPath -Raw | ConvertFrom-Json
        @($Parsed).Count | Should -BeGreaterThan 0
    }

    It 'contains the #174 Az.Storage + ExchangeOnlineManagement entry with the required fields' {
        $Conflicts = Get-DPKnownConflict -Path $KnownConflictsPath
        $Odata = $Conflicts | Where-Object id -EQ '174-odata-azstorage-exo'
        $Odata | Should -Not -BeNullOrEmpty
        @($Odata.modules) | Should -Contain 'Az.Storage'
        @($Odata.modules) | Should -Contain 'ExchangeOnlineManagement'
        $Odata.issue | Should -Be '174'
        $Odata.reason | Should -Not -BeNullOrEmpty
        $Odata.workaround | Should -Not -BeNullOrEmpty
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

Describe 'Invoke-DPConflictCheck' -Tag 'Unit' {
    BeforeEach {
        $script:DPConflictHandled = $null
        $LoadedPairPath = Join-Path $TestDrive 'invoke-loaded-pair.json'
        ConvertTo-Json -Depth 20 -InputObject @(
            [PSCustomObject]@{
                id         = 'invoke-loaded'
                modules    = @('Microsoft.PowerShell.Management', 'Microsoft.PowerShell.Utility')
                assembly   = 'x'
                issue      = '174'
                reason     = 'r'
                workaround = 'w'
            }
        ) | Set-Content -LiteralPath $LoadedPairPath -Encoding utf8
    }

    It 'warns only once for a conflict that is already loaded' {
        $Warnings = @()

        Invoke-DPConflictCheck -KnownConflictsPath $LoadedPairPath -WarningVariable +Warnings -WarningAction SilentlyContinue
        Invoke-DPConflictCheck -KnownConflictsPath $LoadedPairPath -WarningVariable +Warnings -WarningAction SilentlyContinue

        @($Warnings) | Should -HaveCount 1
        $Warnings[0].Message | Should -Match 'Microsoft.PowerShell.Management'
    }

    It 'does not mark an unloaded conflict as handled' {
        $UnloadedPairPath = Join-Path $TestDrive 'invoke-unloaded-pair.json'
        ConvertTo-Json -Depth 20 -InputObject @(
            [PSCustomObject]@{
                id         = 'invoke-unloaded'
                modules    = @('No.Such.ModuleA', 'No.Such.ModuleB')
                assembly   = 'x'
                issue      = '174'
                reason     = 'r'
                workaround = 'w'
            }
        ) | Set-Content -LiteralPath $UnloadedPairPath -Encoding utf8

        Invoke-DPConflictCheck -KnownConflictsPath $UnloadedPairPath -WarningAction SilentlyContinue

        $script:DPConflictHandled.Contains('invoke-unloaded') | Should -BeFalse
    }
}
