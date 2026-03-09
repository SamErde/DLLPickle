BeforeAll {
    Set-Location -Path $PSScriptRoot
    . (Resolve-Path ([System.IO.Path]::Combine('..', '..', 'src', 'DLLPickle', 'Private', 'Test-DPVersion.ps1')))
}

Describe 'Test-DPVersion' -Tag 'Unit' {
    Context 'When DLLPickle is not installed locally' {
        BeforeEach {
            Mock -CommandName Get-Module -MockWith { $null }
        }

        It 'Writes an error and returns a failure object' {
            $Result = Test-DPVersion -ErrorAction SilentlyContinue -ErrorVariable VersionError

            $Result | Should -Not -BeNullOrEmpty
            $Result.IsSuccess | Should -BeFalse
            $Result.Source | Should -Be 'Local'
            $Result.CurrentVersion | Should -BeNullOrEmpty
            $VersionError | Should -Not -BeNullOrEmpty
            $VersionError[0].FullyQualifiedErrorId | Should -Be 'DPModuleNotFound,Test-DPVersion'
        }
    }

    Context 'When PowerShell Gallery returns a stable version' {
        BeforeEach {
            Mock -CommandName Get-Module -MockWith {
                [PSCustomObject]@{ Version = [Version]'1.0.0' }
            }

            Mock -CommandName Invoke-RestMethod -MockWith {
                [PSCustomObject]@{
                    properties = [PSCustomObject]@{
                        Version = '1.1.0'
                    }
                }
            } -ParameterFilter { $Uri -like '*powershellgallery*' }

            Mock -CommandName Invoke-RestMethod -MockWith {
                throw 'GitHub should not be called when gallery succeeds.'
            } -ParameterFilter { $Uri -like '*api.github.com*' }
        }

        It 'Returns successful result from PowerShell Gallery' {
            $Result = Test-DPVersion

            $Result.IsSuccess | Should -BeTrue
            $Result.Source | Should -Be 'PowerShellGallery'
            $Result.CurrentVersion.ToString() | Should -Be '1.0.0'
            $Result.LatestVersion.ToString() | Should -Be '1.1.0'
            $Result.LatestVersionString | Should -Be '1.1.0'
            $Result.IsUpdateAvailable | Should -BeTrue
            $Result.IncludePrerelease | Should -BeFalse
        }
    }

    Context 'When gallery returns prerelease and IncludePrerelease is not set' {
        BeforeEach {
            Mock -CommandName Get-Module -MockWith {
                [PSCustomObject]@{ Version = [Version]'1.0.0' }
            }

            Mock -CommandName Invoke-RestMethod -MockWith {
                [PSCustomObject]@{
                    properties = [PSCustomObject]@{
                        Version = '1.2.0-beta.1'
                    }
                }
            } -ParameterFilter { $Uri -like '*powershellgallery*' }

            Mock -CommandName Invoke-RestMethod -MockWith {
                [PSCustomObject]@{
                    tag_name = 'v1.1.0'
                }
            } -ParameterFilter { $Uri -like '*api.github.com*' }
        }

        It 'Ignores prerelease and falls back to GitHub stable version' {
            $Result = Test-DPVersion

            $Result.IsSuccess | Should -BeTrue
            $Result.Source | Should -Be 'GitHub'
            $Result.LatestVersionString | Should -Be '1.1.0'
            $Result.IsPrerelease | Should -BeFalse
            $Result.IncludePrerelease | Should -BeFalse
        }
    }

    Context 'When IncludePrerelease is set' {
        BeforeEach {
            Mock -CommandName Get-Module -MockWith {
                [PSCustomObject]@{ Version = [Version]'1.0.0' }
            }

            Mock -CommandName Invoke-RestMethod -MockWith {
                [PSCustomObject]@{
                    properties = [PSCustomObject]@{
                        Version = '1.2.0-beta.1'
                    }
                }
            } -ParameterFilter { $Uri -like '*powershellgallery*' }

            Mock -CommandName Invoke-RestMethod -MockWith {
                throw 'GitHub should not be called when prerelease is accepted from gallery.'
            } -ParameterFilter { $Uri -like '*api.github.com*' }
        }

        It 'Returns the prerelease version when explicitly requested' {
            $Result = Test-DPVersion -IncludePrerelease

            $Result.IsSuccess | Should -BeTrue
            $Result.Source | Should -Be 'PowerShellGallery'
            $Result.LatestVersion.ToString() | Should -Be '1.2.0'
            $Result.LatestVersionString | Should -Be '1.2.0-beta.1'
            $Result.IsPrerelease | Should -BeTrue
            $Result.IncludePrerelease | Should -BeTrue
        }
    }

    Context 'When both remote providers fail' {
        BeforeEach {
            Mock -CommandName Get-Module -MockWith {
                [PSCustomObject]@{ Version = [Version]'1.0.0' }
            }

            Mock -CommandName Invoke-RestMethod -MockWith {
                throw 'Remote failure'
            }
        }

        It 'Writes an error and returns a failure result object' {
            $Result = Test-DPVersion -ErrorAction SilentlyContinue -ErrorVariable VersionError
            $CapturedErrorIds = @(
                foreach ($ErrorItem in $VersionError) {
                    if ($null -ne $ErrorItem -and $null -ne $ErrorItem.PSObject.Properties['FullyQualifiedErrorId']) {
                        [string]$ErrorItem.FullyQualifiedErrorId
                    }
                }
            )

            $Result.IsSuccess | Should -BeFalse
            $Result.Source | Should -Be 'Unavailable'
            $Result.CurrentVersion.ToString() | Should -Be '1.0.0'
            $Result.LatestVersion | Should -BeNullOrEmpty
            $VersionError | Should -Not -BeNullOrEmpty
            $CapturedErrorIds | Should -Contain 'DPVersionLookupFailed,Test-DPVersion'
        }
    }

    Context 'Help metadata' {
        It 'Includes comment-based help sections' {
            $Help = Get-Help -Name Test-DPVersion -Full

            $Help.Synopsis | Should -Not -BeNullOrEmpty
            $Help.Description.Text | Should -Not -BeNullOrEmpty
            $Help.Examples.Example | Should -Not -BeNullOrEmpty
        }
    }
}
