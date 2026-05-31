BeforeAll {
    Set-Location -Path $PSScriptRoot
    . (Resolve-Path ([System.IO.Path]::Combine('..', '..', 'src', 'DLLPickle', 'Public', 'Import-DPBaseProfile.ps1')))
}

Describe 'Import-DPBaseProfile' -Tag 'Unit' {
    BeforeEach {
        Mock -CommandName Import-DPLibrary -MockWith {
            [PSCustomObject]@{
                DLLName = 'Microsoft.Identity.Client.dll'
                Status  = 'Imported'
            }
        }

        Mock -CommandName Import-Module -MockWith {
            [PSCustomObject]@{
                Name    = $Name
                Version = [version]'1.0.0'
            }
        }
    }

    It 'imports the validated base profile order after preloading libraries' {
        $Result = Import-DPBaseProfile -SuppressLogo

        Should -Invoke -CommandName Import-DPLibrary -Times 1 -Exactly
        Should -Invoke -CommandName Import-Module -Times 1 -Exactly -ParameterFilter { $Name -eq 'ExchangeOnlineManagement' }
        Should -Invoke -CommandName Import-Module -Times 1 -Exactly -ParameterFilter { $Name -eq 'MicrosoftTeams' }
        Should -Invoke -CommandName Import-Module -Times 1 -Exactly -ParameterFilter { $Name -eq 'Microsoft.Graph.Authentication' }
        Should -Invoke -CommandName Import-Module -Times 1 -Exactly -ParameterFilter { $Name -eq 'Az.Accounts' }

        @($Result) | Should -HaveCount 5
        $Result[0].Kind | Should -Be 'DependencyPreload'
        $Result[1..4].Name | Should -Be @(
            'ExchangeOnlineManagement'
            'MicrosoftTeams'
            'Microsoft.Graph.Authentication'
            'Az.Accounts'
        )
    }

    It 'supports a caller-provided module order' {
        $Result = Import-DPBaseProfile -ModuleName 'Microsoft.Graph.Authentication', 'Az.Accounts' -SuppressLogo

        Should -Invoke -CommandName Import-Module -Times 1 -Exactly -ParameterFilter { $Name -eq 'Microsoft.Graph.Authentication' }
        Should -Invoke -CommandName Import-Module -Times 1 -Exactly -ParameterFilter { $Name -eq 'Az.Accounts' }
        @($Result) | Should -HaveCount 3
        $Result[1].Name | Should -Be 'Microsoft.Graph.Authentication'
        $Result[2].Name | Should -Be 'Az.Accounts'
    }

    It 'surfaces failed preload details in the dependency preload result' {
        Mock -CommandName Import-DPLibrary -MockWith {
            [PSCustomObject]@{
                DLLName = 'Microsoft.Identity.Client.dll'
                Status  = 'Failed'
                Error   = 'Could not load Microsoft.Identity.Client.dll'
            }
        }

        $Result = Import-DPBaseProfile -ModuleName 'Microsoft.Graph.Authentication' -SuppressLogo

        $Result[0].Kind | Should -Be 'DependencyPreload'
        $Result[0].Status | Should -Be 'Failed'
        $Result[0].Error | Should -Be 'Microsoft.Identity.Client.dll: Could not load Microsoft.Identity.Client.dll'
    }
}
