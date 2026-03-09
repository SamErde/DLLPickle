BeforeAll {
    Set-Location -Path $PSScriptRoot
    . (Resolve-Path ([System.IO.Path]::Combine('..', '..', 'src', 'DLLPickle', 'Public', 'Get-DPConfig.ps1')))
    . (Resolve-Path ([System.IO.Path]::Combine('..', '..', 'src', 'DLLPickle', 'Public', 'Import-DPLibrary.ps1')))
}

Describe 'Import-DPLibrary' -Tag 'Unit' {
    Context 'Parameter metadata' {
        It 'Exposes expected switch parameters' {
            $Command = Get-Command -Name Import-DPLibrary

            $Command.Parameters.Keys | Should -Contain 'ShowLoaderExceptions'
            $Command.Parameters['ShowLoaderExceptions'].SwitchParameter | Should -BeTrue
        }
    }

    Context 'Validation failures' {
        BeforeEach {
            Mock -CommandName Get-DPConfig -MockWith {
                [PSCustomObject]@{
                    SkipLibraries = @()
                }
            }
        }

        It 'Throws when the target framework directory does not exist' {
            Mock -CommandName Test-Path -MockWith { $false }

            { Import-DPLibrary } | Should -Throw
        }

        It 'Throws when no DLL files are found' {
            Mock -CommandName Test-Path -MockWith { $true }
            Mock -CommandName Get-ChildItem -MockWith { @() }

            { Import-DPLibrary } | Should -Throw
        }
    }

    Context 'Result shape and filtering behavior' {
        BeforeEach {
            Mock -CommandName Test-Path -MockWith { $true }
        }

        It 'Returns rich objects and skips configured library names' {
            $LoadedAssemblyPath = [System.Text.StringBuilder].Assembly.Location
            $FirstCopyPath = Join-Path -Path $TestDrive -ChildPath 'FirstCopy.dll'
            $SecondCopyPath = Join-Path -Path $TestDrive -ChildPath 'SecondCopy.dll'

            Copy-Item -Path $LoadedAssemblyPath -Destination $FirstCopyPath -Force
            Copy-Item -Path $LoadedAssemblyPath -Destination $SecondCopyPath -Force

            Mock -CommandName Get-DPConfig -MockWith {
                [PSCustomObject]@{
                    SkipLibraries = @('FirstCopy.dll')
                }
            }
            Mock -CommandName Get-ChildItem -MockWith {
                @(
                    Get-Item -Path $FirstCopyPath
                    Get-Item -Path $SecondCopyPath
                )
            }

            $Result = Import-DPLibrary

            $Result | Should -Not -BeNullOrEmpty
            @($Result) | Should -HaveCount 1
            $Result[0].PSTypeNames | Should -Contain 'DLLPickle.ImportDPLibraryResult'
            $Result[0].DLLName | Should -Be 'SecondCopy.dll'
            $Result[0].AssemblyName | Should -Not -BeNullOrEmpty
            $Result[0].Status | Should -BeIn @('Already Loaded', 'Imported')
            $Result[0].Error | Should -BeNullOrEmpty
        }

        It 'Returns failed result object when assembly cannot be loaded' {
            $InvalidDllPath = Join-Path -Path $TestDrive -ChildPath 'InvalidLibrary.dll'
            Set-Content -Path $InvalidDllPath -Value 'not a .NET assembly' -Encoding UTF8

            Mock -CommandName Get-DPConfig -MockWith {
                [PSCustomObject]@{
                    SkipLibraries = @()
                }
            }
            Mock -CommandName Get-ChildItem -MockWith {
                @(Get-Item -Path $InvalidDllPath)
            }

            $Result = Import-DPLibrary

            $Result | Should -Not -BeNullOrEmpty
            @($Result) | Should -HaveCount 1
            $Result[0].PSTypeNames | Should -Contain 'DLLPickle.ImportDPLibraryResult'
            $Result[0].DLLName | Should -Be 'InvalidLibrary.dll'
            $Result[0].Status | Should -Be 'Failed'
            $Result[0].Error | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Help metadata' {
        It 'Includes comment-based help sections' {
            $Help = Get-Help -Name Import-DPLibrary -Full

            $Help.Synopsis | Should -Not -BeNullOrEmpty
            $Help.Description.Text | Should -Not -BeNullOrEmpty
            $Help.Parameters.Parameter | Where-Object { $_.Name -eq 'ShowLoaderExceptions' } | Should -Not -BeNullOrEmpty
            $Help.Examples.Example | Should -Not -BeNullOrEmpty
        }
    }
}
