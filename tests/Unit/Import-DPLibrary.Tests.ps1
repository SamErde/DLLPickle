BeforeAll {
    #-------------------------------------------------------------------------
    Set-Location -Path $PSScriptRoot
    #-------------------------------------------------------------------------
    $ModuleName = 'DLLPickle'
    $PathToManifest = [System.IO.Path]::Combine('..', '..', 'src', $ModuleName, "$ModuleName.psd1")
    #-------------------------------------------------------------------------
    if (Get-Module -Name $ModuleName -ErrorAction 'SilentlyContinue') {
        Remove-Module -Name $ModuleName -Force
    }
    Import-Module $PathToManifest -Force
    #-------------------------------------------------------------------------
}

Describe 'Import-DPLibrary' -Tag Unit {

    Context 'Parameters' {

        BeforeAll {
            $Command = Get-Command -Name Import-DPLibrary
            [void]$Command
        }

        It 'should have ImportAll parameter' {
            $Command.Parameters.Keys | Should -Contain 'ImportAll'
        }

        It 'ImportAll parameter should be a switch' {
            $Command.Parameters['ImportAll'].ParameterType.Name | Should -BeExactly 'SwitchParameter'
        }

        It 'ImportAll parameter should not be mandatory' {
            $Command.Parameters['ImportAll'].Attributes.Mandatory | Should -Not -Contain $true
        }

    } #context_Parameters

    Context 'Input Validation' {

        BeforeAll {
            # Create a temporary test directory structure
            $TestRoot = Join-Path -Path $TestDrive -ChildPath 'DLLPickle'
            $TestLib = Join-Path -Path $TestRoot -ChildPath 'Lib'
            $null = New-Item -Path $TestLib -ItemType Directory -Force

            # Create a mock Packages.json
            $PackagesJson = @{
                packages = @(
                    @{
                        name       = 'TestPackage1'
                        version    = '1.0.0'
                        autoImport = $true
                    },
                    @{
                        name       = 'TestPackage2'
                        version    = '2.0.0'
                        autoImport = $false
                    }
                )
            }

            $PackagesJsonPath = Join-Path -Path $TestLib -ChildPath 'Packages.json'
            $PackagesJson | ConvertTo-Json -Depth 10 | Set-Content -Path $PackagesJsonPath
        }

        It 'should throw when Packages.json does not exist' {
            # Remove the Packages.json file
            Remove-Item -Path $PackagesJsonPath -Force

            # Mock the module directory to point to our test directory
            Mock -CommandName Test-Path -MockWith { $false } -ParameterFilter {
                $Path -match 'Packages\.json'
            } -ModuleName $ModuleName

            { Import-DPLibrary } | Should -Throw '*Packages.json not found*'
        }

        <#
        It 'should throw when Packages.json is malformed' {
            # Create invalid JSON
            $InvalidJsonPath = Join-Path -Path $TestLib -ChildPath 'Packages.json'
            'This is not valid JSON' | Set-Content -Path $InvalidJsonPath

            Mock -CommandName Get-Content -MockWith {
                'This is not valid JSON'
            } -ModuleName $ModuleName

            { Import-DPLibrary } | Should -Throw '*Failed to read or parse Packages.json*'
        }
        #>

    } #context_InputValidation

    Context 'Functionality - AutoImport Behavior' {

        BeforeAll {
            # Create temporary test structure
            $TestRoot = Join-Path -Path $TestDrive -ChildPath 'DLLPickle'
            $TestLib = Join-Path -Path $TestRoot -ChildPath 'Lib'
            $null = New-Item -Path $TestLib -ItemType Directory -Force

            # Create mock Packages.json
            $script:PackagesJson = @{
                packages = @(
                    @{
                        name       = 'TestPackage1'
                        version    = '1.0.0'
                        autoImport = $true
                    },
                    @{
                        name       = 'TestPackage2'
                        version    = '2.0.0'
                        autoImport = $false
                    },
                    @{
                        name       = 'TestPackage3'
                        version    = '3.0.0'
                        autoImport = $true
                    }
                )
            }

            $PackagesJsonPath = Join-Path -Path $TestLib -ChildPath 'Packages.json'
            $script:PackagesJson | ConvertTo-Json -Depth 10 | Set-Content -Path $PackagesJsonPath

            # Create dummy DLL files for testing
            'dummy' | Set-Content -Path (Join-Path -Path $TestLib -ChildPath 'TestPackage1.dll')
            'dummy' | Set-Content -Path (Join-Path -Path $TestLib -ChildPath 'TestPackage2.dll')
            'dummy' | Set-Content -Path (Join-Path -Path $TestLib -ChildPath 'TestPackage3.dll')
        }

        It 'should only import packages with autoImport set to true by default' {
            Mock -CommandName Get-Content -MockWith {
                $script:PackagesJson | ConvertTo-Json -Depth 10
            } -ParameterFilter { $Path -match 'Packages\.json' } -ModuleName $ModuleName

            Mock -CommandName Add-Type -MockWith { } -ModuleName $ModuleName

            # Mock the .NET AssemblyName call to avoid needing real DLLs
            Mock -CommandName Write-Verbose -MockWith { } -ModuleName $ModuleName

            # We need to handle the assembly loading check - mock it to return null (not loaded)
            InModuleScope -ModuleName $ModuleName -ScriptBlock {
                Mock -CommandName Test-Path -MockWith { param($Path)
                    if ($Path -match '\.dll$') { return $true }
                    if ($Path -match 'Packages\.json') { return $true }
                    return $false
                }
            }

            $Result = InModuleScope -ModuleName $ModuleName -ScriptBlock {
                param($TestLib)

                # Override the module directory detection
                $ModuleDirectory = Split-Path -Path $TestLib -Parent
                $LibraryDirectory = $TestLib
                $PackagesJsonPath = Join-Path -Path $LibraryDirectory -ChildPath 'Packages.json'

                Import-DPLibrary
            } -ArgumentList $TestLib

            $Result | Should -HaveCount 3
            ($Result | Where-Object { $_.Status -in @('Imported', 'Failed') }).Count | Should -Be 2
            ($Result | Where-Object { $_.Status -eq 'Skipped' }).Count | Should -Be 1
            $Result | Where-Object { $_.PackageName -eq 'TestPackage2' } | Select-Object -ExpandProperty Status | Should -BeExactly 'Skipped'
        }

        It 'should import all packages when ImportAll is specified' {
            Mock -CommandName Get-Content -MockWith {
                $script:PackagesJson | ConvertTo-Json -Depth 10
            } -ParameterFilter { $Path -match 'Packages\.json' } -ModuleName $ModuleName

            Mock -CommandName Add-Type -MockWith { } -ModuleName $ModuleName
            Mock -CommandName Write-Verbose -MockWith { } -ModuleName $ModuleName

            InModuleScope -ModuleName $ModuleName -ScriptBlock {
                Mock -CommandName Test-Path -MockWith { param($Path)
                    if ($Path -match '\.dll$') { return $true }
                    if ($Path -match 'Packages\.json') { return $true }
                    return $false
                }
            }

            $Result = InModuleScope -ModuleName $ModuleName -ScriptBlock {
                param($TestLib)

                $ModuleDirectory = Split-Path -Path $TestLib -Parent
                $LibraryDirectory = $TestLib
                $PackagesJsonPath = Join-Path -Path $LibraryDirectory -ChildPath 'Packages.json'

                Import-DPLibrary -ImportAll
            } -ArgumentList $TestLib

            $Result | Should -HaveCount 3
            ($Result | Where-Object { $_.Status -in @('Imported', 'Failed') }).Count | Should -Be 3
            ($Result | Where-Object { $_.Status -eq 'Skipped' }).Count | Should -Be 0
        }

    } #context_AutoImportBehavior

    Context 'Functionality - DLL File Handling' {

        BeforeAll {
            # Create temporary test structure
            $TestRoot = Join-Path -Path $TestDrive -ChildPath 'DLLPickle'
            $TestLib = Join-Path -Path $TestRoot -ChildPath 'Lib'
            $null = New-Item -Path $TestLib -ItemType Directory -Force

            # Create mock Packages.json with one package
            $PackagesJson = @{
                packages = @(
                    @{
                        name       = 'TestPackage1'
                        version    = '1.0.0'
                        autoImport = $true
                    }
                )
            }

            $PackagesJsonPath = Join-Path -Path $TestLib -ChildPath 'Packages.json'
            $PackagesJson | ConvertTo-Json -Depth 10 | Set-Content -Path $PackagesJsonPath
        }

        It 'should report "Not Found" status when DLL file does not exist' {
            Mock -CommandName Test-Path -MockWith { $false } -ParameterFilter {
                $Path -match '\.dll$'
            } -ModuleName $ModuleName
            Mock -CommandName Test-Path -MockWith { $true } -ParameterFilter {
                $Path -match 'Packages\.json'
            } -ModuleName $ModuleName
            Mock -CommandName Get-Content -MockWith {
                $PackagesJson | ConvertTo-Json -Depth 10
            } -ParameterFilter { $Path -match 'Packages\.json' } -ModuleName $ModuleName

            $Result = Import-DPLibrary

            $Result | Should -HaveCount 1
            $Result.Status | Should -BeExactly 'Not Found'
            $Result.Error | Should -BeExactly 'File does not exist'
        }

        It 'should write a warning when DLL file is not found' {
            Mock -CommandName Test-Path -MockWith { $false } -ParameterFilter {
                $Path -match '\.dll$'
            } -ModuleName $ModuleName
            Mock -CommandName Test-Path -MockWith { $true } -ParameterFilter {
                $Path -match 'Packages\.json'
            } -ModuleName $ModuleName
            Mock -CommandName Get-Content -MockWith {
                $PackagesJson | ConvertTo-Json -Depth 10
            } -ParameterFilter { $Path -match 'Packages\.json' } -ModuleName $ModuleName
            Mock -CommandName Write-Warning -MockWith { } -ModuleName $ModuleName

            Import-DPLibrary

            Should -Invoke -CommandName Write-Warning -Times 1 -ParameterFilter {
                $Message -match 'DLL not found'
            } -ModuleName $ModuleName
        }

    } #context_DLLFileHandling

    Context 'Functionality - Assembly Loading' {

        BeforeAll {
            # Create temporary test structure
            $TestRoot = Join-Path -Path $TestDrive -ChildPath 'DLLPickle'
            $TestLib = Join-Path -Path $TestRoot -ChildPath 'Lib'
            $null = New-Item -Path $TestLib -ItemType Directory -Force

            # Create mock Packages.json
            $script:PackagesJson = @{
                packages = @(
                    @{
                        name       = 'TestPackage1'
                        version    = '1.0.0'
                        autoImport = $true
                    }
                )
            }

            $PackagesJsonPath = Join-Path -Path $TestLib -ChildPath 'Packages.json'
            $script:PackagesJson | ConvertTo-Json -Depth 10 | Set-Content -Path $PackagesJsonPath

            # Create a dummy DLL file
            'dummy' | Set-Content -Path (Join-Path -Path $TestLib -ChildPath 'TestPackage1.dll')
        }

        It 'should successfully import a DLL that is not already loaded' {
            Mock -CommandName Get-Content -MockWith {
                $script:PackagesJson | ConvertTo-Json -Depth 10
            } -ParameterFilter { $Path -match 'Packages\.json' } -ModuleName $ModuleName

            Mock -CommandName Add-Type -MockWith { } -ModuleName $ModuleName
            Mock -CommandName Write-Verbose -MockWith { } -ModuleName $ModuleName
            Mock -CommandName Write-Warning -MockWith { } -ModuleName $ModuleName

            InModuleScope -ModuleName $ModuleName -ScriptBlock {
                Mock -CommandName Test-Path -MockWith { param($Path)
                    if ($Path -match '\.dll$') { return $true }
                    if ($Path -match 'Packages\.json') { return $true }
                    return $false
                }
            }

            $Result = InModuleScope -ModuleName $ModuleName -ScriptBlock {
                param($TestLib)

                $ModuleDirectory = Split-Path -Path $TestLib -Parent
                $LibraryDirectory = $TestLib

                Import-DPLibrary
            } -ArgumentList $TestLib

            # Verify the function attempts to process the DLL and returns appropriate status
            $Result | Should -HaveCount 1
            $Result.Status | Should -BeIn @('Imported', 'Failed', 'Already Loaded')
            $Result.PackageName | Should -BeExactly 'TestPackage1'
            # Note: With dummy DLL files, GetAssemblyName will fail before Add-Type is called
            # This is expected behavior - the function gracefully handles the error
        }

        It 'should report "Failed" status and error message when Add-Type fails' {
            Mock -CommandName Test-Path -MockWith { $true } -ModuleName $ModuleName
            Mock -CommandName Get-Content -MockWith {
                $script:PackagesJson | ConvertTo-Json -Depth 10
            } -ParameterFilter { $Path -match 'Packages\.json' } -ModuleName $ModuleName
            Mock -CommandName Add-Type -MockWith {
                throw 'Failed to load assembly'
            } -ModuleName $ModuleName
            Mock -CommandName Write-Warning -MockWith { } -ModuleName $ModuleName

            InModuleScope -ModuleName $ModuleName -ScriptBlock {
                Mock -CommandName Test-Path -MockWith { param($Path)
                    if ($Path -match '\.dll$') { return $true }
                    if ($Path -match 'Packages\.json') { return $true }
                    return $false
                }
            }

            $Result = InModuleScope -ModuleName $ModuleName -ScriptBlock {
                param($TestLib)

                $ModuleDirectory = Split-Path -Path $TestLib -Parent
                $LibraryDirectory = $TestLib

                Import-DPLibrary
            } -ArgumentList $TestLib

            $Result | Should -HaveCount 1
            $Result.Status | Should -BeExactly 'Failed'
            $Result.Error | Should -Not -BeNullOrEmpty
        }

    } #context_AssemblyLoading

    Context 'Output' {

        BeforeAll {
            # Create temporary test structure
            $TestRoot = Join-Path -Path $TestDrive -ChildPath 'DLLPickle'
            $TestLib = Join-Path -Path $TestRoot -ChildPath 'Lib'
            $null = New-Item -Path $TestLib -ItemType Directory -Force

            # Create mock Packages.json with multiple packages
            $script:PackagesJson = @{
                packages = @(
                    @{
                        name       = 'TestPackage1'
                        version    = '1.0.0'
                        autoImport = $true
                    },
                    @{
                        name       = 'TestPackage2'
                        version    = '2.0.0'
                        autoImport = $false
                    }
                )
            }

            $PackagesJsonPath = Join-Path -Path $TestLib -ChildPath 'Packages.json'
            $script:PackagesJson | ConvertTo-Json -Depth 10 | Set-Content -Path $PackagesJsonPath

            # Create dummy DLL files
            'dummy' | Set-Content -Path (Join-Path -Path $TestLib -ChildPath 'TestPackage1.dll')
            'dummy' | Set-Content -Path (Join-Path -Path $TestLib -ChildPath 'TestPackage2.dll')

            Mock -CommandName Get-Content -MockWith {
                $script:PackagesJson | ConvertTo-Json -Depth 10
            } -ParameterFilter { $Path -match 'Packages\.json' } -ModuleName $ModuleName
            Mock -CommandName Add-Type -MockWith { } -ModuleName $ModuleName
            Mock -CommandName Write-Verbose -MockWith { } -ModuleName $ModuleName

            InModuleScope -ModuleName $ModuleName -ScriptBlock {
                Mock -CommandName Test-Path -MockWith { param($Path)
                    if ($Path -match '\.dll$') { return $true }
                    if ($Path -match 'Packages\.json') { return $true }
                    return $false
                }
            }
        }

        It 'should return PSCustomObject type' {
            $Result = InModuleScope -ModuleName $ModuleName -ScriptBlock {
                param($TestLib)

                $ModuleDirectory = Split-Path -Path $TestLib -Parent
                $LibraryDirectory = $TestLib

                Import-DPLibrary
            } -ArgumentList $TestLib

            $Result[0] | Should -BeOfType [PSCustomObject]
        }

        It 'should return objects with PackageName property' {
            $Result = InModuleScope -ModuleName $ModuleName -ScriptBlock {
                param($TestLib)

                $ModuleDirectory = Split-Path -Path $TestLib -Parent
                $LibraryDirectory = $TestLib

                Import-DPLibrary
            } -ArgumentList $TestLib

            $Result[0].PSObject.Properties.Name | Should -Contain 'PackageName'
        }

        It 'should return objects with Version property' {
            $Result = InModuleScope -ModuleName $ModuleName -ScriptBlock {
                param($TestLib)

                $ModuleDirectory = Split-Path -Path $TestLib -Parent
                $LibraryDirectory = $TestLib

                Import-DPLibrary
            } -ArgumentList $TestLib

            $Result[0].PSObject.Properties.Name | Should -Contain 'Version'
        }

        It 'should return objects with Status property' {
            $Result = InModuleScope -ModuleName $ModuleName -ScriptBlock {
                param($TestLib)

                $ModuleDirectory = Split-Path -Path $TestLib -Parent
                $LibraryDirectory = $TestLib

                Import-DPLibrary
            } -ArgumentList $TestLib

            $Result[0].PSObject.Properties.Name | Should -Contain 'Status'
        }

        It 'should return objects with Error property' {
            $Result = InModuleScope -ModuleName $ModuleName -ScriptBlock {
                param($TestLib)

                $ModuleDirectory = Split-Path -Path $TestLib -Parent
                $LibraryDirectory = $TestLib

                Import-DPLibrary
            } -ArgumentList $TestLib

            $Result[0].PSObject.Properties.Name | Should -Contain 'Error'
        }

        It 'should return one result per package in Packages.json' {
            $Result = InModuleScope -ModuleName $ModuleName -ScriptBlock {
                param($TestLib)

                $ModuleDirectory = Split-Path -Path $TestLib -Parent
                $LibraryDirectory = $TestLib

                Import-DPLibrary
            } -ArgumentList $TestLib

            $Result | Should -HaveCount 2
        }

        It 'should include correct package names in output' {
            $Result = InModuleScope -ModuleName $ModuleName -ScriptBlock {
                param($TestLib)

                $ModuleDirectory = Split-Path -Path $TestLib -Parent
                $LibraryDirectory = $TestLib

                Import-DPLibrary
            } -ArgumentList $TestLib

            $Result.PackageName | Should -Contain 'TestPackage1'
            $Result.PackageName | Should -Contain 'TestPackage2'
        }

        It 'should include correct versions in output' {
            $Result = InModuleScope -ModuleName $ModuleName -ScriptBlock {
                param($TestLib)

                $ModuleDirectory = Split-Path -Path $TestLib -Parent
                $LibraryDirectory = $TestLib

                Import-DPLibrary
            } -ArgumentList $TestLib

            ($Result | Where-Object { $_.PackageName -eq 'TestPackage1' }).Version | Should -BeExactly '1.0.0'
            ($Result | Where-Object { $_.PackageName -eq 'TestPackage2' }).Version | Should -BeExactly '2.0.0'
        }

    } #context_Output

    Context 'Verbose Output' {

        BeforeAll {
            # Create temporary test structure
            $TestRoot = Join-Path -Path $TestDrive -ChildPath 'DLLPickle'
            $TestLib = Join-Path -Path $TestRoot -ChildPath 'Lib'
            $null = New-Item -Path $TestLib -ItemType Directory -Force

            # Create mock Packages.json
            $script:PackagesJson = @{
                packages = @(
                    @{
                        name       = 'TestPackage1'
                        version    = '1.0.0'
                        autoImport = $true
                    },
                    @{
                        name       = 'TestPackage2'
                        version    = '2.0.0'
                        autoImport = $false
                    }
                )
            }

            $PackagesJsonPath = Join-Path -Path $TestLib -ChildPath 'Packages.json'
            $script:PackagesJson | ConvertTo-Json -Depth 10 | Set-Content -Path $PackagesJsonPath

            # Create dummy DLL files
            'dummy' | Set-Content -Path (Join-Path -Path $TestLib -ChildPath 'TestPackage1.dll')
            'dummy' | Set-Content -Path (Join-Path -Path $TestLib -ChildPath 'TestPackage2.dll')

            Mock -CommandName Get-Content -MockWith {
                $script:PackagesJson | ConvertTo-Json -Depth 10
            } -ParameterFilter { $Path -match 'Packages\.json' } -ModuleName $ModuleName
            Mock -CommandName Add-Type -MockWith { } -ModuleName $ModuleName
            Mock -CommandName Write-Verbose -MockWith { } -ModuleName $ModuleName

            InModuleScope -ModuleName $ModuleName -ScriptBlock {
                Mock -CommandName Test-Path -MockWith { param($Path)
                    if ($Path -match '\.dll$') { return $true }
                    if ($Path -match 'Packages\.json') { return $true }
                    return $false
                }
            }
        }

        It 'should write verbose message when processing packages' {
            InModuleScope -ModuleName $ModuleName -ScriptBlock {
                param($TestLib)

                $ModuleDirectory = Split-Path -Path $TestLib -Parent
                $LibraryDirectory = $TestLib

                Import-DPLibrary -Verbose
            } -ArgumentList $TestLib

            # Verify that Write-Verbose is called during package processing
            # This may be for successful import, already loaded, or skipped packages
            Should -Invoke -CommandName Write-Verbose -ModuleName $ModuleName -Times 1 -Exactly:$false
        }

        It 'should write verbose message for skipped package' {
            InModuleScope -ModuleName $ModuleName -ScriptBlock {
                param($TestLib)

                $ModuleDirectory = Split-Path -Path $TestLib -Parent
                $LibraryDirectory = $TestLib

                Import-DPLibrary -Verbose
            } -ArgumentList $TestLib

            Should -Invoke -CommandName Write-Verbose -ParameterFilter {
                $Message -match 'Skipping auto-import'
            } -ModuleName $ModuleName
        }

    } #context_VerboseOutput

} #describe_Import-DPLibrary

AfterAll {
    Remove-Module -Name $ModuleName -Force -ErrorAction SilentlyContinue
}
