BeforeAll {
    Set-Location -Path $PSScriptRoot
    . (Resolve-Path ([System.IO.Path]::Combine('..', '..', 'src', 'DLLPickle', 'Public', 'Get-DPConfig.ps1')))
}

Describe 'Get-DPConfig' -Tag 'Unit' {
    Context 'When configuration file is missing' {
        BeforeEach {
            Mock -CommandName Test-Path -MockWith { $false }
        }

        It 'Returns default values' {
            $result = Get-DPConfig

            $result | Should -Not -BeNullOrEmpty
            $result.CheckForUpdates | Should -BeTrue
            $result.ShowLogo | Should -BeTrue
            $result.SkipLibraries | Should -BeOfType ([string[]])
            $result.SkipLibraries | Should -HaveCount 0
        }
    }

    Context 'When configuration file exists and is valid' {
        BeforeEach {
            Mock -CommandName Test-Path -MockWith { $true }
            Mock -CommandName Get-Content -MockWith {
                '{"CheckForUpdates":false,"ShowLogo":false,"SkipLibraries":["a.dll","b.dll"]}'
            }
        }

        It 'Returns normalized config values from JSON' {
            $result = Get-DPConfig

            $result.CheckForUpdates | Should -BeFalse
            $result.ShowLogo | Should -BeFalse
            $result.SkipLibraries | Should -BeOfType ([string[]])
            $result.SkipLibraries | Should -Be @('a.dll', 'b.dll')
        }
    }

    Context 'When configuration JSON is invalid' {
        BeforeEach {
            Mock -CommandName Test-Path -MockWith { $true }
            Mock -CommandName Get-Content -MockWith { '{invalid json}' }
            Mock -CommandName ConvertFrom-Json -MockWith { throw 'Invalid JSON' }
        }

        It 'Writes an error and returns defaults' {
            $result = Get-DPConfig -ErrorVariable readError

            $result.CheckForUpdates | Should -BeTrue
            $result.ShowLogo | Should -BeTrue
            $result.SkipLibraries | Should -BeOfType ([string[]])
            $readError | Should -Not -BeNullOrEmpty
            $readError[0].FullyQualifiedErrorId | Should -Be 'DPConfigReadFailed,Get-DPConfig'
        }
    }

    Context 'Help metadata' {
        It 'Includes comment-based help sections' {
            $help = Get-Help -Name Get-DPConfig -Full

            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description.Text | Should -Not -BeNullOrEmpty
            $help.Examples.Example | Should -Not -BeNullOrEmpty
        }
    }
}
