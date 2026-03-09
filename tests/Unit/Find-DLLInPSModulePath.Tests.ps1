BeforeAll {
    #-------------------------------------------------------------------------
    Set-Location -Path $PSScriptRoot
    #-------------------------------------------------------------------------
    $ModuleName = 'DLLPickle'
    $PathToManifest = Resolve-Path ( [System.IO.Path]::Combine('..', '..', 'src', "$ModuleName", "$ModuleName.psd1") )
    #-------------------------------------------------------------------------
    if (Get-Module -Name $ModuleName -ErrorAction 'SilentlyContinue') {
        Remove-Module -Name $ModuleName -Force
    }
    Import-Module $PathToManifest -Force
    #-------------------------------------------------------------------------

    # Create test environment
    $TestModulePath = Join-Path -Path $TestDrive -ChildPath 'Modules'
    $null = New-Item -Path $TestModulePath -ItemType Directory -Force

    # Mock DLL content for testing
    $script:MockDLLPath1 = Join-Path -Path $TestModulePath -ChildPath 'TestModule1\Microsoft.Identity.Test.dll'
    $script:MockDLLPath2 = Join-Path -Path $TestModulePath -ChildPath 'TestModule2\Microsoft.Identity.Test.dll'
    $script:MockDLLPath3 = Join-Path -Path $TestModulePath -ChildPath 'TestModule3\OtherProduct.dll'
    $script:MockDLLPath4 = Join-Path -Path $TestModulePath -ChildPath 'TestModule1\en-US\Microsoft.Identity.Test.dll'

    # Create directory structure
    $null = New-Item -Path (Split-Path $script:MockDLLPath1) -ItemType Directory -Force
    $null = New-Item -Path (Split-Path $script:MockDLLPath2) -ItemType Directory -Force
    $null = New-Item -Path (Split-Path $script:MockDLLPath3) -ItemType Directory -Force
    $null = New-Item -Path (Split-Path $script:MockDLLPath4) -ItemType Directory -Force

    # Create mock DLL files
    $null = New-Item -Path $script:MockDLLPath1 -ItemType File -Force
    $null = New-Item -Path $script:MockDLLPath2 -ItemType File -Force
    $null = New-Item -Path $script:MockDLLPath3 -ItemType File -Force
    $null = New-Item -Path $script:MockDLLPath4 -ItemType File -Force

    # Create mock FileVersionInfo objects
    $script:MockVersionInfo1 = [PSCustomObject]@{
        PSTypeName       = 'System.Diagnostics.FileVersionInfo'
        OriginalFilename = 'Microsoft.Identity.Test.dll'
        InternalName     = 'Microsoft.Identity.Test.dll'
        ProductName      = 'Microsoft Identity Client'
        ProductVersion   = '4.56.0.0'
        FileVersion      = '4.56.0.0'
        FileName         = $script:MockDLLPath1
    }

    $script:MockVersionInfo2 = [PSCustomObject]@{
        PSTypeName       = 'System.Diagnostics.FileVersionInfo'
        OriginalFilename = 'Microsoft.Identity.Test.dll'
        InternalName     = 'Microsoft.Identity.Test.dll'
        ProductName      = 'Microsoft Identity Client'
        ProductVersion   = '4.57.0.0'
        FileVersion      = '4.57.0.0'
        FileName         = $script:MockDLLPath2
    }

    $script:MockVersionInfo3 = [PSCustomObject]@{
        PSTypeName       = 'System.Diagnostics.FileVersionInfo'
        OriginalFilename = 'OtherProduct.dll'
        InternalName     = 'OtherProduct.dll'
        ProductName      = 'Other Product Name'
        ProductVersion   = '1.0.0.0'
        FileVersion      = '1.0.0.0'
        FileName         = $script:MockDLLPath3
    }

    $script:MockVersionInfo4 = [PSCustomObject]@{
        PSTypeName       = 'System.Diagnostics.FileVersionInfo'
        OriginalFilename = 'Microsoft.Identity.Test.dll'
        InternalName     = 'Microsoft.Identity.Test.dll'
        ProductName      = 'Microsoft Identity Client'
        ProductVersion   = '4.56.0.0'
        FileVersion      = '4.56.0.0'
        FileName         = $script:MockDLLPath4
    }
}

Describe 'Find-DLLInPSModulePath' -Tag 'Unit' {
    Context 'Parameter Validation' {
        It 'Should have parameter <ParameterName>' -TestCases @(
            @{ ParameterName = 'ProductName' }
            @{ ParameterName = 'FileName' }
            @{ ParameterName = 'Path' }
            @{ ParameterName = 'ExcludeDirectories' }
            @{ ParameterName = 'Scope' }
            @{ ParameterName = 'NewestVersion' }
        ) {
            param($ParameterName)

            $Command = Get-Command -Name Find-DLLInPSModulePath
            $Command.Parameters.Keys | Should -Contain $ParameterName
        }

        It 'ProductName parameter should not be mandatory' {
            $Command = Get-Command -Name Find-DLLInPSModulePath
            $Command.Parameters['ProductName'].Attributes.Mandatory | Should -Not -Contain $true
        }

        It 'FileName parameter should not be mandatory' {
            $Command = Get-Command -Name Find-DLLInPSModulePath
            $Command.Parameters['FileName'].Attributes.Mandatory | Should -Not -Contain $true
        }

        It 'Scope should validate against CurrentUser, AllUsers, and Both' {
            $Command = Get-Command -Name Find-DLLInPSModulePath
            $ValidateSet = $Command.Parameters['Scope'].Attributes.Where{ $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $ValidateSet.ValidValues | Should -Be @('CurrentUser', 'AllUsers', 'Both')
        }

        It 'NewestVersion should be a switch parameter' {
            $Command = Get-Command -Name Find-DLLInPSModulePath
            $Command.Parameters['NewestVersion'].SwitchParameter | Should -BeTrue
        }

    }

    Context 'Basic Functionality' {
        BeforeEach {
            Mock -CommandName Get-ChildItem -ModuleName DLLPickle -MockWith {
                param($Path, $Filter, [switch]$File, [switch]$Recurse)
                [void]$Path, $Filter, $File, $Recurse
                $items = @(
                    [PSCustomObject]@{
                        FullName    = $script:MockDLLPath1
                        Directory   = [PSCustomObject]@{ Name = 'TestModule1' }
                        VersionInfo = $script:MockVersionInfo1
                    }
                    [PSCustomObject]@{
                        FullName    = $script:MockDLLPath2
                        Directory   = [PSCustomObject]@{ Name = 'TestModule2' }
                        VersionInfo = $script:MockVersionInfo2
                    }
                    [PSCustomObject]@{
                        FullName    = $script:MockDLLPath3
                        Directory   = [PSCustomObject]@{ Name = 'TestModule3' }
                        VersionInfo = $script:MockVersionInfo3
                    }
                )
                return $items
            }
        }

        It 'Should return DLLs matching the ProductName pattern' {
            $Result = Find-DLLInPSModulePath -Path $TestModulePath -ProductName 'Microsoft Identity'
            $Result | Should -Not -BeNullOrEmpty
            $Result.Count | Should -Be 2
        }

        It 'Should filter by FileName pattern' {
            Mock -CommandName Get-ChildItem -ModuleName DLLPickle -MockWith {
                param($Path, $Filter, [switch]$File, [switch]$Recurse)
                [void]$Path, $Filter, $File, $Recurse
                $items = @(
                    [PSCustomObject]@{
                        FullName    = $script:MockDLLPath1
                        Directory   = [PSCustomObject]@{ Name = 'TestModule1' }
                        VersionInfo = $script:MockVersionInfo1
                    }
                )
                return $items
            }

            $Result = Find-DLLInPSModulePath -Path $TestModulePath -FileName 'Microsoft.Identity*.dll'
            $Result | Should -Not -BeNullOrEmpty
        }

        It 'Should add custom type name to output objects' {
            $Result = Find-DLLInPSModulePath -Path $TestModulePath -ProductName 'Microsoft Identity'
            $Result[0].PSObject.TypeNames[0] | Should -Be 'DLLPickle.ModuleDllInfo'
        }

        It 'Should return rich module DLL objects' {
            $Result = Find-DLLInPSModulePath -Path $TestModulePath -ProductName 'Microsoft Identity'
            $Result | Should -Not -BeNullOrEmpty
            $Result[0].PSObject.TypeNames[0] | Should -Be 'DLLPickle.ModuleDllInfo'
            $Result[0].PSObject.Properties.Name | Should -Contain 'PathScope'
            $Result[0].PSObject.Properties.Name | Should -Contain 'VersionInfo'
        }
    }

    Context 'ExcludeDirectories Functionality' {
        BeforeEach {
            Mock -CommandName Get-ChildItem -ModuleName DLLPickle -MockWith {
                param($Path, $Filter, [switch]$File, [switch]$Recurse)
                [void]$Path, $Filter, $File, $Recurse
                $items = @(
                    [PSCustomObject]@{
                        FullName    = $script:MockDLLPath1
                        Directory   = [PSCustomObject]@{ Name = 'TestModule1' }
                        VersionInfo = $script:MockVersionInfo1
                    }
                    [PSCustomObject]@{
                        FullName    = $script:MockDLLPath4
                        Directory   = [PSCustomObject]@{ Name = 'en-US' }
                        VersionInfo = $script:MockVersionInfo4
                    }
                )
                return $items
            }
        }

        It 'Should exclude directories specified in ExcludeDirectories parameter' {
            $Result = Find-DLLInPSModulePath -Path $TestModulePath -ProductName 'Microsoft Identity' -ExcludeDirectories @('en-US')
            $Result.Count | Should -Be 1
            $Result[0].FileName | Should -Not -Match 'en-US'
        }
    }

    Context 'NewestVersion Functionality' {
        BeforeEach {
            Mock -CommandName Get-ChildItem -ModuleName DLLPickle -MockWith {
                param($Path, $Filter, [switch]$File, [switch]$Recurse)
                [void]$Path, $Filter, $File, $Recurse
                $items = @(
                    [PSCustomObject]@{
                        FullName    = $script:MockDLLPath1
                        Directory   = [PSCustomObject]@{ Name = 'TestModule1' }
                        VersionInfo = $script:MockVersionInfo1
                    }
                    [PSCustomObject]@{
                        FullName    = $script:MockDLLPath2
                        Directory   = [PSCustomObject]@{ Name = 'TestModule2' }
                        VersionInfo = $script:MockVersionInfo2
                    }
                )
                return $items
            }
        }

        It 'Should return only the newest version when NewestVersion is specified' {
            $Result = Find-DLLInPSModulePath -Path $TestModulePath -ProductName 'Microsoft Identity' -NewestVersion
            $Result.Count | Should -Be 1
            $Result[0].FileVersion | Should -Be '4.57.0.0'
        }

        It 'Should sort by semantic version instead of string order' {
            $MockVersionInfo10 = [PSCustomObject]@{
                PSTypeName       = 'System.Diagnostics.FileVersionInfo'
                OriginalFilename = 'Microsoft.Identity.Test.dll'
                InternalName     = 'Microsoft.Identity.Test.dll'
                ProductName      = 'Microsoft Identity Client'
                ProductVersion   = '10.0.0.0'
                FileVersion      = '10.0.0.0'
                FileName         = $script:MockDLLPath2
            }

            Mock -CommandName Get-ChildItem -ModuleName DLLPickle -MockWith {
                param($Path, $Filter, [switch]$File, [switch]$Recurse)
                [void]$Path, $Filter, $File, $Recurse
                @(
                    [PSCustomObject]@{
                        Name          = 'Microsoft.Identity.Test.dll'
                        FullName      = $script:MockDLLPath1
                        Directory     = [PSCustomObject]@{ Name = 'TestModule1'; Parent = [PSCustomObject]@{ FullName = $TestDrive } }
                        DirectoryName = (Split-Path -Path $script:MockDLLPath1 -Parent)
                        VersionInfo   = $script:MockVersionInfo1
                    }
                    [PSCustomObject]@{
                        Name          = 'Microsoft.Identity.Test.dll'
                        FullName      = $script:MockDLLPath2
                        Directory     = [PSCustomObject]@{ Name = 'TestModule2'; Parent = [PSCustomObject]@{ FullName = $TestDrive } }
                        DirectoryName = (Split-Path -Path $script:MockDLLPath2 -Parent)
                        VersionInfo   = $MockVersionInfo10
                    }
                )
            }

            $Result = Find-DLLInPSModulePath -Path $TestModulePath -ProductName 'Microsoft Identity' -NewestVersion
            $Result.Count | Should -Be 1
            $Result[0].FileVersion | Should -Be '10.0.0.0'
        }
    }

    Context 'Scope Functionality' {
        BeforeAll {
            $script:CurrentUserPath = Join-Path -Path (Join-Path -Path $HOME -ChildPath 'Documents\PowerShell\Modules') -ChildPath 'Contoso.Module'
            if ($env:ProgramFiles) {
                $script:AllUsersPath = Join-Path -Path (Join-Path -Path $env:ProgramFiles -ChildPath 'PowerShell\Modules') -ChildPath 'Contoso.Module'
            } else {
                $script:AllUsersPath = Join-Path -Path '/usr/local/share/powershell/Modules' -ChildPath 'Contoso.Module'
            }
        }

        BeforeEach {
            Mock -CommandName Get-ChildItem -ModuleName DLLPickle -MockWith {
                param($Path, $Filter, [switch]$File, [switch]$Recurse)
                [void]$Path, $Filter, $File, $Recurse
                return @()
            }
        }

        It 'Should filter paths when Scope is CurrentUser' {
            Mock -CommandName Test-Path -ModuleName DLLPickle -MockWith { $true }
            $Result = Find-DLLInPSModulePath -Path @($script:CurrentUserPath, $script:AllUsersPath) -Scope CurrentUser -ProductName 'Microsoft Identity' -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            # Should not throw an error
            $Result | Should -BeNullOrEmpty # Empty because no DLLs match
        }

        It 'Should filter paths when Scope is AllUsers' {
            Mock -CommandName Test-Path -ModuleName DLLPickle -MockWith { $true }
            $Result = Find-DLLInPSModulePath -Path @($script:CurrentUserPath, $script:AllUsersPath) -Scope AllUsers -ProductName 'Microsoft Identity' -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            # Should not throw an error
            $Result | Should -BeNullOrEmpty # Empty because no DLLs match
        }

        It 'Should classify paths as Unknown when roots do not match known scopes' {
            Mock -CommandName Test-Path -ModuleName DLLPickle -MockWith { $true }
            $UnknownPath = Join-Path -Path $TestDrive -ChildPath 'CustomModules'
            $Result = Find-DLLInPSModulePath -Path @($UnknownPath) -Scope Both -ProductName 'Microsoft Identity' -WarningAction SilentlyContinue
            $Result | Should -BeNullOrEmpty
        }

        It 'Should write error when Scope produces no valid paths' {
            Mock -CommandName Test-Path -ModuleName DLLPickle -MockWith { $true }
            $UnknownScopedPath = Join-Path -Path $TestDrive -ChildPath 'UnknownScopedPath'
            { Find-DLLInPSModulePath -Path @($UnknownScopedPath) -Scope CurrentUser -ProductName 'Microsoft Identity' -ErrorAction Stop } | Should -Throw -ErrorId 'ScopePathsNotFound*'
        }

        It 'Should write error when no valid paths are provided' {
            Mock -CommandName Test-Path -ModuleName DLLPickle -MockWith { $false }
            { Find-DLLInPSModulePath -Path @('C:\InvalidA', 'C:\InvalidB') -Scope Both -ProductName 'Microsoft Identity' -ErrorAction Stop } | Should -Throw -ErrorId 'NoValidModulePaths*'
        }
    }

    Context 'Warning and Error Handling' {
        BeforeEach {
            Mock -CommandName Get-ChildItem -ModuleName DLLPickle -MockWith {
                param($Path, $Filter, [switch]$File, [switch]$Recurse)
                [void]$Path, $Filter, $File, $Recurse
                return @()
            }
        }

        It 'Should write warning when path does not exist' {
            $NonExistentPath = Join-Path -Path $TestDrive -ChildPath 'NonExistent'
            Mock -CommandName Test-Path -ModuleName DLLPickle -MockWith {
                param($LiteralPath)
                return $LiteralPath -ne $NonExistentPath
            }

            $Result = Find-DLLInPSModulePath -Path @($NonExistentPath, $TestModulePath) -ProductName 'Test' -WarningVariable warnings -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            [void]$Result
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Out-String) | Should -Match 'Path does not exist or is not accessible'
        }

        It 'Should write warning when no DLLs are found' {
            Mock -CommandName Test-Path -ModuleName DLLPickle -MockWith { $true }
            $Result = Find-DLLInPSModulePath -Path $TestModulePath -ProductName 'NonExistentProduct' -WarningVariable warnings -WarningAction SilentlyContinue
            [void]$Result
            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Output Type' {
        BeforeEach {
            Mock -CommandName Get-ChildItem -ModuleName DLLPickle -MockWith {
                param($Path, $Filter, [switch]$File, [switch]$Recurse)
                [void]$Path, $Filter, $File, $Recurse
                $items = @(
                    [PSCustomObject]@{
                        Name          = 'Microsoft.Identity.Test.dll'
                        FullName      = $script:MockDLLPath1
                        Directory     = [PSCustomObject]@{ Name = 'TestModule1'; Parent = [PSCustomObject]@{ FullName = $TestDrive } }
                        DirectoryName = (Split-Path -Path $script:MockDLLPath1 -Parent)
                        VersionInfo   = $script:MockVersionInfo1
                    }
                )
                return $items
            }
        }

        It 'Should return objects with DLLPickle.ModuleDllInfo type' {
            $Result = Find-DLLInPSModulePath -Path $TestModulePath -ProductName 'Microsoft Identity'
            $Result[0].PSObject.TypeNames | Should -Contain 'DLLPickle.ModuleDllInfo'
            $Result[0].VersionInfo.PSObject.TypeNames | Should -Contain 'System.Diagnostics.FileVersionInfo'
        }

        It 'Should populate mapped properties for rich output objects' {
            $ScopedModuleRoot = Join-Path -Path (Join-Path -Path $HOME -ChildPath 'Documents\PowerShell\Modules') -ChildPath 'Contoso.Module'
            $ScopedDirectory = Join-Path -Path $ScopedModuleRoot -ChildPath 'lib'
            $ScopedFullName = Join-Path -Path $ScopedDirectory -ChildPath 'Microsoft.Identity.Test.dll'

            Mock -CommandName Test-Path -ModuleName DLLPickle -MockWith { $true }
            Mock -CommandName Get-ChildItem -ModuleName DLLPickle -MockWith {
                param($Path, $Filter, [switch]$File, [switch]$Recurse)
                [void]$Path, $Filter, $File, $Recurse
                @(
                    [PSCustomObject]@{
                        Name          = 'Microsoft.Identity.Test.dll'
                        FullName      = $ScopedFullName
                        Directory     = [PSCustomObject]@{ Name = 'lib'; Parent = [PSCustomObject]@{ FullName = $ScopedModuleRoot } }
                        DirectoryName = $ScopedDirectory
                        VersionInfo   = $script:MockVersionInfo1
                    }
                )
            }

            $Result = Find-DLLInPSModulePath -Path @($ScopedModuleRoot) -Scope CurrentUser -ProductName 'Microsoft Identity'

            $Result | Should -Not -BeNullOrEmpty
            $Result[0].FileName | Should -Be 'Microsoft.Identity.Test.dll'
            $Result[0].FullName | Should -Be $ScopedFullName
            $Result[0].Directory | Should -Be $ScopedDirectory
            $Result[0].ModuleRoot | Should -Be $ScopedModuleRoot
            $Result[0].PathScope | Should -Be 'CurrentUser'
            $Result[0].VersionInfo | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Pattern and Version Edge Cases' {
        It 'Should respect wildcard ProductName patterns directly' {
            Mock -CommandName Test-Path -ModuleName DLLPickle -MockWith { $true }
            Mock -CommandName Get-ChildItem -ModuleName DLLPickle -MockWith {
                param($Path, $Filter, [switch]$File, [switch]$Recurse)
                [void]$Path, $Filter, $File, $Recurse
                @(
                    [PSCustomObject]@{
                        Name          = 'Microsoft.Identity.Test.dll'
                        FullName      = $script:MockDLLPath1
                        Directory     = [PSCustomObject]@{ Name = 'TestModule1'; Parent = [PSCustomObject]@{ FullName = $TestDrive } }
                        DirectoryName = (Split-Path -Path $script:MockDLLPath1 -Parent)
                        VersionInfo   = $script:MockVersionInfo1
                    }
                )
            }

            $Result = Find-DLLInPSModulePath -Path $TestModulePath -ProductName 'Microsoft*Client'
            $Result | Should -Not -BeNullOrEmpty
            $Result.Count | Should -Be 1
        }

        It 'Should ignore entries with null VersionInfo and not throw' {
            Mock -CommandName Test-Path -ModuleName DLLPickle -MockWith { $true }
            Mock -CommandName Get-ChildItem -ModuleName DLLPickle -MockWith {
                param($Path, $Filter, [switch]$File, [switch]$Recurse)
                [void]$Path, $Filter, $File, $Recurse
                @(
                    [PSCustomObject]@{
                        Name          = 'Microsoft.Identity.Test.dll'
                        FullName      = $script:MockDLLPath1
                        Directory     = [PSCustomObject]@{ Name = 'TestModule1'; Parent = [PSCustomObject]@{ FullName = $TestDrive } }
                        DirectoryName = (Split-Path -Path $script:MockDLLPath1 -Parent)
                        VersionInfo   = $null
                    }
                )
            }

            { Find-DLLInPSModulePath -Path $TestModulePath -ProductName 'Microsoft Identity' -WarningAction SilentlyContinue } | Should -Not -Throw
            $Result = Find-DLLInPSModulePath -Path $TestModulePath -ProductName 'Microsoft Identity' -WarningAction SilentlyContinue
            $Result | Should -BeNullOrEmpty
        }

        It 'Should use fallback ordering when FileVersion cannot be parsed' {
            $InvalidVersionInfo = [PSCustomObject]@{
                PSTypeName       = 'System.Diagnostics.FileVersionInfo'
                OriginalFilename = 'Microsoft.Identity.Test.dll'
                InternalName     = 'Microsoft.Identity.Test.dll'
                ProductName      = 'Microsoft Identity Client'
                ProductVersion   = 'unknown'
                FileVersion      = 'not.a.version'
                FileName         = $script:MockDLLPath1
            }

            Mock -CommandName Test-Path -ModuleName DLLPickle -MockWith { $true }
            Mock -CommandName Get-ChildItem -ModuleName DLLPickle -MockWith {
                param($Path, $Filter, [switch]$File, [switch]$Recurse)
                [void]$Path, $Filter, $File, $Recurse
                @(
                    [PSCustomObject]@{
                        Name          = 'Microsoft.Identity.Test.dll'
                        FullName      = $script:MockDLLPath1
                        Directory     = [PSCustomObject]@{ Name = 'TestModule1'; Parent = [PSCustomObject]@{ FullName = $TestDrive } }
                        DirectoryName = (Split-Path -Path $script:MockDLLPath1 -Parent)
                        VersionInfo   = $InvalidVersionInfo
                    }
                    [PSCustomObject]@{
                        Name          = 'Microsoft.Identity.Test.dll'
                        FullName      = $script:MockDLLPath2
                        Directory     = [PSCustomObject]@{ Name = 'TestModule2'; Parent = [PSCustomObject]@{ FullName = $TestDrive } }
                        DirectoryName = (Split-Path -Path $script:MockDLLPath2 -Parent)
                        VersionInfo   = $script:MockVersionInfo2
                    }
                )
            }

            $Result = Find-DLLInPSModulePath -Path $TestModulePath -ProductName 'Microsoft Identity' -NewestVersion
            $Result | Should -Not -BeNullOrEmpty
            $Result.Count | Should -Be 1
            $Result[0].FileVersion | Should -Be '4.57.0.0'
        }
    }

    Context 'Help Metadata' {
        It 'Should include complete comment-based help sections' {
            $Help = Get-Help -Name Find-DLLInPSModulePath -Full

            $Help.Synopsis | Should -Not -BeNullOrEmpty
            $Help.Description.Text | Should -Not -BeNullOrEmpty
            $Help.Parameters.Parameter | Where-Object { $_.Name -eq 'Scope' } | Should -Not -BeNullOrEmpty
            $Help.Examples.Example | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Verbose Output' {
        BeforeEach {
            Mock -CommandName Get-ChildItem -ModuleName DLLPickle -MockWith {
                param($Path, $Filter, [switch]$File, [switch]$Recurse)
                [void]$Path, $Filter, $File, $Recurse
                return @()
            }
            Mock -CommandName Test-Path -ModuleName DLLPickle -MockWith { $true }
        }

        It 'Should write verbose messages when -Verbose is used' {
            $VerboseMessages = Find-DLLInPSModulePath -Path $TestModulePath -ProductName 'Test' -Verbose 4>&1
            $VerboseMessages | Where-Object { $_ -match 'Enumerating DLLs' } | Should -Not -BeNullOrEmpty
        }
    }
}
