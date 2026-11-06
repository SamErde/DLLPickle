[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Seeds', Justification = 'Consumed by Pester discovery in the Describe script block.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'CasesPerSeed', Justification = 'Consumed by Pester discovery in the Describe script block.')]
param(
    [int[]]$Seeds = @(11450, 322, 20261106),
    [ValidateRange(1, 128)]
    [int]$CasesPerSeed = 32
)

BeforeAll {
    . (Join-Path $PSScriptRoot '../../src/DLLPickle/Public/Get-DPConfig.ps1')
    $FixturePath = Join-Path $TestDrive 'config.json'
    # Redirect only file access. Parsing and validation execute the production code.
    Mock Test-Path { $true }
    Mock Get-Content { [System.IO.File]::ReadAllText($FixturePath) }
}

Describe 'Configuration contract regressions' -Tag 'Unit' {
    It 'rejects <Json> without applying any settings' -ForEach @(
        @{ Json = '[]' }
        @{ Json = '[{"ShowLogo":false}]' }
        @{ Json = 'null' }
        @{ Json = 'false' }
        @{ Json = '42' }
        @{ Json = '"text"' }
        @{ Json = '' }
        @{ Json = '{invalid}' }
        @{ Json = '{"ShowLogo":"false"}' }
        @{ Json = '{"CheckForUpdates":0}' }
        @{ Json = '{"ShowLogo":[]}' }
        @{ Json = '{"ShowLogo":{}}' }
        @{ Json = '{"SkipLibraries":"a.dll"}' }
        @{ Json = '{"SkipLibraries":[null]}' }
        @{ Json = '{"SkipLibraries":[1]}' }
        @{ Json = '{"SkipLibraries":[false]}' }
        @{ Json = '{"SkipLibraries":[{}]}' }
        @{ Json = '{"SkipLibraries":[[]]}' }
        @{ Json = '{"ShowLogo":false,"CheckForUpdates":false,"SkipLibraries":["a.dll",1]}' }
        @{ Json = '{"ShowLogo":true,"ShowLogo":false}' }
        @{ Json = '{"showlogo":null,"ShowLogo":false}' }
    ) {
        [System.IO.File]::WriteAllText($FixturePath, $Json)
        $ReadErrors = @()
        $Result = Get-DPConfig -ErrorAction SilentlyContinue -ErrorVariable ReadErrors
        $Result.CheckForUpdates | Should -BeTrue
        $Result.ShowLogo | Should -BeTrue
        @($Result.SkipLibraries) | Should -HaveCount 0
        @($ReadErrors | Where-Object FullyQualifiedErrorId -EQ 'DPConfigReadFailed,Get-DPConfig') | Should -HaveCount 1
    }

    It 'honors ErrorAction Stop on a schema error' {
        [System.IO.File]::WriteAllText($FixturePath, '{"ShowLogo":"false"}')
        { Get-DPConfig -ErrorAction Stop } | Should -Throw -ErrorId 'DPConfigReadFailed,Get-DPConfig'
    }

    It 'preserves date-like strings, case-insensitive keys, comments and trailing commas' {
        [System.IO.File]::WriteAllText($FixturePath, '{/* preferences */"showlogo":false,"SkipLibraries":["2026-11-06T00:00:00Z"],}')
        $Result = Get-DPConfig -ErrorAction Stop
        $Result.ShowLogo | Should -BeFalse
        $Result.SkipLibraries[0] | Should -BeExactly '2026-11-06T00:00:00Z'
        $Result.SkipLibraries[0] | Should -BeOfType [string]
    }

    It 'defaults missing and null fields and ignores unknown fields' -ForEach @(
        @{ Json = '{}' }
        @{ Json = '{"ShowLogo":null,"CheckForUpdates":null,"SkipLibraries":null}' }
        @{ Json = '{"FutureSetting":{"nested":[1,false,null]}}' }
    ) {
        [System.IO.File]::WriteAllText($FixturePath, $Json)
        $Result = Get-DPConfig -ErrorAction Stop
        $Result.CheckForUpdates | Should -BeTrue
        $Result.ShowLogo | Should -BeTrue
        @($Result.SkipLibraries) | Should -HaveCount 0
        @($Result.PSObject.Properties.Name) | Should -HaveCount 3
    }
}

Describe 'Seeded configuration properties' -Tag 'Unit', 'GeneratedInput' {
    It 'preserves typed values and rejects a wrong type (seed <Seed>)' -ForEach @(
        foreach ($Seed in $Seeds) { @{ Seed = $Seed; CaseCount = $CasesPerSeed } }
    ) {
        $Random = [System.Random]::new($Seed)
        $Clock = [System.Diagnostics.Stopwatch]::StartNew()
        # Include escaping, Unicode, whitespace, duplicates and path-like literal names.
        # These strings are data only: never invoked, loaded, or used as filesystem paths.
        $Names = @('a.dll', 'A.dll', '', ' ', '../a.dll', 'C:\a.dll', '*.dll', "`u{00E9}.dll", 'quote".dll', "line`nbreak.dll", '$(throw).dll', '2026-11-06T00:00:00Z')
        for ($Case = 0; $Case -lt $CaseCount; $Case++) {
            $Clock.Elapsed.TotalSeconds | Should -BeLessThan 60 -Because "seed=$Seed case=$Case exceeded the bounded pilot budget"
            $ExpectedCheck = $Random.Next(2) -eq 1
            $ExpectedLogo = $Random.Next(2) -eq 1
            $NameCount = $Random.Next(0, 9)
            $ExpectedNames = @(
                for ($Index = 0; $Index -lt $NameCount; $Index++) {
                    $Names[$Random.Next($Names.Count)]
                }
            )
            $InputObject = [ordered]@{
                CheckForUpdates = $ExpectedCheck
                ShowLogo = $ExpectedLogo
                SkipLibraries = $ExpectedNames
            }
            $Json = ConvertTo-Json -InputObject $InputObject -Compress -Depth 5
            $Diagnostic = "seed=$Seed case=$Case json=$Json"
            [System.IO.File]::WriteAllText($FixturePath, $Json)
            $Result = Get-DPConfig -ErrorAction Stop
            $Result.CheckForUpdates | Should -Be $ExpectedCheck -Because $Diagnostic
            $Result.ShowLogo | Should -Be $ExpectedLogo -Because $Diagnostic
            $Result.CheckForUpdates | Should -BeOfType [bool] -Because $Diagnostic
            $Result.ShowLogo | Should -BeOfType [bool] -Because $Diagnostic
            # Compare serialized lists to preserve case, order, empty strings and duplicates.
            (ConvertTo-Json -InputObject @($Result.SkipLibraries) -Compress) |
                Should -BeExactly (ConvertTo-Json -InputObject $ExpectedNames -Compress) -Because $Diagnostic

            switch ($Case % 3) {
                0 { $InputObject.ShowLogo = 'false' }
                1 { $InputObject.CheckForUpdates = $Random.Next(0, 100) }
                2 { $InputObject.SkipLibraries = @($ExpectedNames) + @(@{ invalid = $Case }) }
            }
            $Json = ConvertTo-Json -InputObject $InputObject -Compress -Depth 5
            $Diagnostic = "seed=$Seed case=$Case invalid-json=$Json"
            [System.IO.File]::WriteAllText($FixturePath, $Json)
            $ReadErrors = @()
            $Result = Get-DPConfig -ErrorAction SilentlyContinue -ErrorVariable ReadErrors
            $Result.CheckForUpdates | Should -BeTrue -Because $Diagnostic
            $Result.ShowLogo | Should -BeTrue -Because $Diagnostic
            @($Result.SkipLibraries) | Should -HaveCount 0 -Because $Diagnostic
            @($ReadErrors | Where-Object FullyQualifiedErrorId -EQ 'DPConfigReadFailed,Get-DPConfig') |
                Should -HaveCount 1 -Because $Diagnostic
        }
    }
}
