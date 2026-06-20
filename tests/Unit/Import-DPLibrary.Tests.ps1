BeforeAll {
    Set-Location -Path $PSScriptRoot
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    . (Resolve-Path ([System.IO.Path]::Combine('..', '..', 'src', 'DLLPickle', 'Public', 'Get-DPConfig.ps1')))
    . (Resolve-Path ([System.IO.Path]::Combine('..', '..', 'src', 'DLLPickle', 'Private', 'Resolve-DPDLLLoadOrder.ps1')))
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

        It 'Applies dependency-graph ordering before import attempts' {
            $LoadedAssemblyPath = [System.Text.StringBuilder].Assembly.Location
            $UnsafePath = Join-Path -Path $TestDrive -ChildPath 'System.Runtime.CompilerServices.Unsafe.dll'
            $AbstractionsPath = Join-Path -Path $TestDrive -ChildPath 'Microsoft.IdentityModel.Abstractions.dll'
            $IdentityClientPath = Join-Path -Path $TestDrive -ChildPath 'Microsoft.Identity.Client.dll'

            Copy-Item -Path $LoadedAssemblyPath -Destination $UnsafePath -Force
            Copy-Item -Path $LoadedAssemblyPath -Destination $AbstractionsPath -Force
            Copy-Item -Path $LoadedAssemblyPath -Destination $IdentityClientPath -Force

            Mock -CommandName Get-DPConfig -MockWith {
                [PSCustomObject]@{
                    SkipLibraries = @()
                    ShowLogo      = $false
                }
            }
            Mock -CommandName Get-ChildItem -MockWith {
                @(
                    (Get-Item -Path $IdentityClientPath)
                    (Get-Item -Path $UnsafePath)
                    (Get-Item -Path $AbstractionsPath)
                )
            }

            Mock -CommandName Resolve-DPDLLLoadOrder -MockWith {
                param ([System.IO.FileInfo[]]$DLLFiles)

                $ByName = @{}
                foreach ($File in $DLLFiles) {
                    $ByName[$File.Name] = $File
                }

                @(
                    $ByName['System.Runtime.CompilerServices.Unsafe.dll']
                    $ByName['Microsoft.IdentityModel.Abstractions.dll']
                    $ByName['Microsoft.Identity.Client.dll']
                )
            }

            $Result = Import-DPLibrary -SuppressLogo

            Should -Invoke -CommandName Resolve-DPDLLLoadOrder -Times 1 -Exactly
            @($Result) | Should -HaveCount 3
            $Result[0].DLLName | Should -Be 'System.Runtime.CompilerServices.Unsafe.dll'
            $Result[1].DLLName | Should -Be 'Microsoft.IdentityModel.Abstractions.dll'
            $Result[2].DLLName | Should -Be 'Microsoft.Identity.Client.dll'
            ($Result | ForEach-Object { $_.Status } | Select-Object -Unique) | Should -Be 'Already Loaded'
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
            Mock -CommandName Resolve-DPDLLLoadOrder -MockWith {
                param(
                    [Parameter(Mandatory = $true)]
                    $DLLFiles
                )
                ,$DLLFiles
            }

            $Result = Import-DPLibrary -WarningAction SilentlyContinue

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

        It 'loads an ordered synthetic transitive dependency without relying on resolver callbacks' {
            $FixtureRoot = Join-Path -Path $TestDrive -ChildPath 'SyntheticDependencyModule'
            $Payload = [ordered]@{
                RepoRoot    = $RepoRoot
                FixtureRoot = $FixtureRoot
                FixtureId   = 'Fixture' + [guid]::NewGuid().ToString('N')
            }
            $PayloadBase64 = [Convert]::ToBase64String(
                [Text.Encoding]::UTF8.GetBytes(($Payload | ConvertTo-Json -Compress))
            )
            $ChildScript = @'
$ErrorActionPreference = 'Stop'
$Payload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__')) | ConvertFrom-Json
$TfmDirectory = Join-Path -Path $Payload.FixtureRoot -ChildPath ([IO.Path]::Combine('bin', 'net8.0'))
$null = New-Item -Path $TfmDirectory -ItemType Directory -Force
$DependencyPath = Join-Path -Path $TfmDirectory -ChildPath 'A.Synthetic.Dependency.dll'
$ConsumerPath = Join-Path -Path $TfmDirectory -ChildPath 'Z.Synthetic.Consumer.dll'

$DependencySource = @"
namespace $($Payload.FixtureId) {
    public static class Dependency {
        public static string GetValue() { return "resolved"; }
    }
}
"@
Add-Type -TypeDefinition $DependencySource -OutputAssembly $DependencyPath -ErrorAction Stop

$ConsumerSource = @"
namespace $($Payload.FixtureId) {
    public static class Consumer {
        public static string GetValue() { return Dependency.GetValue(); }
    }
}
"@
Add-Type -TypeDefinition $ConsumerSource -ReferencedAssemblies $DependencyPath -OutputAssembly $ConsumerPath -ErrorAction Stop

. (Join-Path $Payload.RepoRoot 'src\DLLPickle\Public\Get-DPConfig.ps1')
. (Join-Path $Payload.RepoRoot 'src\DLLPickle\Private\Resolve-DPDLLLoadOrder.ps1')
. (Join-Path $Payload.RepoRoot 'src\DLLPickle\Public\Import-DPLibrary.ps1')
function Get-DPConfig { [PSCustomObject]@{ SkipLibraries = @(); ShowLogo = $false } }
function Invoke-DPConflictCheck {}
$global:PSModuleRoot = $Payload.FixtureRoot

$Result = @(Import-DPLibrary -SuppressLogo -WarningAction SilentlyContinue)
if ($Result.Count -ne 2 -or @($Result | Where-Object Status -eq 'Failed').Count -gt 0) {
    throw "Synthetic dependency import failed: $($Result | ConvertTo-Json -Compress)"
}

$ConsumerAssemblyName = [Reflection.AssemblyName]::GetAssemblyName($ConsumerPath).Name
$ConsumerAssembly = [AppDomain]::CurrentDomain.GetAssemblies() |
    Where-Object { $_.GetName().Name -eq $ConsumerAssemblyName } |
    Select-Object -First 1
$ConsumerType = $ConsumerAssembly.GetType("$($Payload.FixtureId).Consumer", $true)
if ($ConsumerType.GetMethod('GetValue').Invoke($null, @()) -ne 'resolved') {
    throw 'Synthetic consumer did not resolve its dependency.'
}
'SYNTHETIC_DEPENDENCY_OK'
'@.Replace('__PAYLOAD__', $PayloadBase64)
            $ChildScriptPath = Join-Path -Path $TestDrive -ChildPath 'Invoke-SyntheticDependencyTest.ps1'
            Set-Content -LiteralPath $ChildScriptPath -Value $ChildScript -Encoding UTF8

            $ProcessOutput = @(& pwsh -NoProfile -NonInteractive -File $ChildScriptPath 2>&1)
            $ProcessExitCode = $LASTEXITCODE

            $ProcessExitCode | Should -Be 0 -Because ($ProcessOutput -join [Environment]::NewLine)
            ($ProcessOutput -join [Environment]::NewLine) | Should -Match 'SYNTHETIC_DEPENDENCY_OK'
        }
    }

    Context 'Dependency graph helper behavior' {
        It 'Orders dependencies before dependents and appends unresolved nodes deterministically' {
            $AlphaPath = Join-Path -Path $TestDrive -ChildPath 'Alpha.dll'
            $BetaPath = Join-Path -Path $TestDrive -ChildPath 'Beta.dll'
            $GammaPath = Join-Path -Path $TestDrive -ChildPath 'Gamma.dll'
            $DeltaPath = Join-Path -Path $TestDrive -ChildPath 'Delta.dll'

            Set-Content -Path $AlphaPath -Value 'invalid assembly content' -Encoding utf8
            Set-Content -Path $BetaPath -Value 'invalid assembly content' -Encoding utf8
            Set-Content -Path $GammaPath -Value 'invalid assembly content' -Encoding utf8
            Set-Content -Path $DeltaPath -Value 'invalid assembly content' -Encoding utf8

            Mock -CommandName Get-DPDLLReferenceName -MockWith {
                param (
                    [string]$Path,
                    [string[]]$LocalAssemblyNames
                )

                [void]$LocalAssemblyNames

                switch ([System.IO.Path]::GetFileNameWithoutExtension($Path)) {
                    'Beta' { @('Alpha') }
                    'Gamma' { @('Beta') }
                    default { @() }
                }
            }

            $Ordered = Resolve-DPDLLLoadOrder -DLLFiles @(
                (Get-Item -Path $GammaPath)
                (Get-Item -Path $DeltaPath)
                (Get-Item -Path $BetaPath)
                (Get-Item -Path $AlphaPath)
            )

            @($Ordered) | Should -HaveCount 4

            $Names = @($Ordered | ForEach-Object { $_.Name })
            $AlphaIndex = $Names.IndexOf('Alpha.dll')
            $BetaIndex = $Names.IndexOf('Beta.dll')
            $GammaIndex = $Names.IndexOf('Gamma.dll')
            $DeltaIndex = $Names.IndexOf('Delta.dll')

            $AlphaIndex | Should -BeLessThan $BetaIndex
            $BetaIndex | Should -BeLessThan $GammaIndex
            $DeltaIndex | Should -BeLessThan $GammaIndex
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
