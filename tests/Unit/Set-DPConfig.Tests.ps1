BeforeAll {
    Set-Location -Path $PSScriptRoot
    . (Resolve-Path ([System.IO.Path]::Combine('..', '..', 'src', 'DLLPickle', 'Public', 'Set-DPConfig.ps1')))
}

Describe 'Set-DPConfig' -Tag 'Unit' {
    Context 'Parameter metadata' {
        It 'Exposes expected parameters' {
            $Command = Get-Command -Name Set-DPConfig

            $Command.Parameters.Keys | Should -Contain 'CheckForUpdates'
            $Command.Parameters.Keys | Should -Contain 'ShowLogo'
            $Command.Parameters.Keys | Should -Contain 'SkipLibraries'
            $Command.Parameters.Keys | Should -Contain 'Reset'
            $Command.Parameters.Keys | Should -Contain 'PassThru'
        }

        It 'Uses switch parameters where expected' {
            $Command = Get-Command -Name Set-DPConfig

            $Command.Parameters['Reset'].SwitchParameter | Should -BeTrue
            $Command.Parameters['PassThru'].SwitchParameter | Should -BeTrue
        }
    }

    Context 'When no configuration file exists' {
        BeforeEach {
            Mock -CommandName Test-Path -MockWith { $false }
            Mock -CommandName New-Item -MockWith { [PSCustomObject]@{ FullName = 'mock' } }
            Mock -CommandName Set-Content -MockWith {}
            Mock -CommandName Write-Host -MockWith {}
        }

        It 'Creates defaults, applies updates, and writes configuration' {
            $Result = Set-DPConfig -ShowLogo $false -PassThru

            $Result | Should -Not -BeNullOrEmpty
            $Result.CheckForUpdates | Should -BeTrue
            $Result.ShowLogo | Should -BeFalse
            @($Result.SkipLibraries | Where-Object { $null -ne $_ }) | Should -HaveCount 0

            Assert-MockCalled -CommandName New-Item -Times 1 -Exactly
            Assert-MockCalled -CommandName Set-Content -Times 1 -Exactly
        }

        It 'Writes using a supported Set-Content encoding parameter' {
            $null = Set-DPConfig -ShowLogo $false -PassThru

            if ($PSEdition -eq 'Core') {
                Assert-MockCalled -CommandName Set-Content -ParameterFilter { $Encoding -eq 'utf8NoBOM' } -Times 1 -Exactly
            } else {
                Assert-MockCalled -CommandName Set-Content -ParameterFilter { $Encoding -eq 'utf8' } -Times 1 -Exactly
            }
        }
    }

    Context 'When configuration file exists and is valid' {
        BeforeEach {
            Mock -CommandName Test-Path -MockWith {
                param(
                    [string]$LiteralPath,
                    [Microsoft.PowerShell.Commands.TestPathType]$PathType
                )
                [void]$LiteralPath
                [void]$PathType
                $true
            }
            Mock -CommandName Get-Content -MockWith {
                '{"CheckForUpdates":false,"ShowLogo":false,"SkipLibraries":["a.dll","b.dll"]}'
            }
            Mock -CommandName Set-Content -MockWith {}
            Mock -CommandName Write-Host -MockWith {}
        }

        It 'Updates only provided values and preserves others' {
            $Result = Set-DPConfig -ShowLogo $true -PassThru

            $Result.CheckForUpdates | Should -BeFalse
            $Result.ShowLogo | Should -BeTrue
            $Result.SkipLibraries | Should -Be @('a.dll', 'b.dll')

            Assert-MockCalled -CommandName Get-Content -Times 1 -Exactly
            Assert-MockCalled -CommandName Set-Content -Times 1 -Exactly
        }
    }

    Context 'When existing configuration content is invalid' {
        BeforeEach {
            Mock -CommandName Test-Path -MockWith {
                param(
                    [string]$LiteralPath,
                    [Microsoft.PowerShell.Commands.TestPathType]$PathType
                )
                [void]$LiteralPath
                [void]$PathType
                $true
            }
            Mock -CommandName Get-Content -MockWith { '{invalid json}' }
            Mock -CommandName ConvertFrom-Json -MockWith { throw 'Invalid JSON' }
            Mock -CommandName Set-Content -MockWith {}
            Mock -CommandName Write-Host -MockWith {}
        }

        It 'Writes an error and continues with defaults' {
            $Result = Set-DPConfig -CheckForUpdates $false -PassThru -ErrorAction SilentlyContinue -ErrorVariable ConfigReadError

            $Result.CheckForUpdates | Should -BeFalse
            $Result.ShowLogo | Should -BeTrue
            @($Result.SkipLibraries | Where-Object { $null -ne $_ }) | Should -HaveCount 0
            $ConfigReadError | Should -Not -BeNullOrEmpty
            ($ConfigReadError | ForEach-Object { $_.FullyQualifiedErrorId }) | Should -Contain 'DPConfigReadFailed,Set-DPConfig'

            Assert-MockCalled -CommandName Set-Content -Times 1 -Exactly
        }
    }

    Context 'When reset is requested with WhatIf' {
        BeforeEach {
            Mock -CommandName Test-Path -MockWith { $true }
            Mock -CommandName Set-Content -MockWith {}
            Mock -CommandName Write-Host -MockWith {}
        }

        It 'Does not write configuration when ShouldProcess is declined' {
            $null = Set-DPConfig -Reset -WhatIf

            Assert-MockCalled -CommandName Set-Content -Times 0 -Exactly
        }
    }

    Context 'Help metadata' {
        It 'Includes comment-based help sections' {
            $Help = Get-Help -Name Set-DPConfig -Full

            $Help.Synopsis | Should -Not -BeNullOrEmpty
            $Help.Description.Text | Should -Not -BeNullOrEmpty
            $Help.Examples.Example | Should -Not -BeNullOrEmpty
        }
    }
}
