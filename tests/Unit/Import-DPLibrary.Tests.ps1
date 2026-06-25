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
$DependencyPath = Join-Path -Path $TfmDirectory -ChildPath 'Z.Synthetic.Dependency.dll'
$ConsumerPath = Join-Path -Path $TfmDirectory -ChildPath 'A.Synthetic.Consumer.dll'
$CompilerRoot = Join-Path -Path $Payload.FixtureRoot -ChildPath 'compiler'
$DependencyProjectRoot = Join-Path -Path $CompilerRoot -ChildPath 'Dependency'
$ConsumerProjectRoot = Join-Path -Path $CompilerRoot -ChildPath 'Consumer'
$null = New-Item -Path $DependencyProjectRoot -ItemType Directory -Force
$null = New-Item -Path $ConsumerProjectRoot -ItemType Directory -Force

$DependencySourcePath = Join-Path -Path $DependencyProjectRoot -ChildPath 'Dependency.cs'
$DependencyProjectPath = Join-Path -Path $DependencyProjectRoot -ChildPath 'Z.Synthetic.Dependency.csproj'
$DependencySource = @"
namespace $($Payload.FixtureId) {
    public static class Dependency {
        public static string GetValue() { return "resolved"; }
    }
}
"@
Set-Content -LiteralPath $DependencySourcePath -Value $DependencySource -Encoding UTF8
Set-Content -LiteralPath $DependencyProjectPath -Value @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <AssemblyName>Z.Synthetic.Dependency</AssemblyName>
    <RootNamespace>$($Payload.FixtureId)</RootNamespace>
  </PropertyGroup>
</Project>
"@ -Encoding UTF8
$DependencyBuildOutput = @(& dotnet build $DependencyProjectPath -c Release -nologo -o $TfmDirectory 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Dependency project build failed: $($DependencyBuildOutput -join [Environment]::NewLine)"
}

$ConsumerSourcePath = Join-Path -Path $ConsumerProjectRoot -ChildPath 'Consumer.cs'
$ConsumerProjectPath = Join-Path -Path $ConsumerProjectRoot -ChildPath 'A.Synthetic.Consumer.csproj'
$ConsumerSource = @"
namespace $($Payload.FixtureId) {
    public static class Consumer {
        public static string GetValue() { return Dependency.GetValue(); }
    }
}
"@
Set-Content -LiteralPath $ConsumerSourcePath -Value $ConsumerSource -Encoding UTF8
Set-Content -LiteralPath $ConsumerProjectPath -Value @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <AssemblyName>A.Synthetic.Consumer</AssemblyName>
    <RootNamespace>$($Payload.FixtureId)</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <Reference Include="Z.Synthetic.Dependency">
      <HintPath>$DependencyPath</HintPath>
    </Reference>
  </ItemGroup>
</Project>
"@ -Encoding UTF8
$ConsumerBuildOutput = @(& dotnet build $ConsumerProjectPath -c Release -nologo -o $TfmDirectory 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Consumer project build failed: $($ConsumerBuildOutput -join [Environment]::NewLine)"
}

. (Join-Path $Payload.RepoRoot 'src\DLLPickle\Public\Get-DPConfig.ps1')
. (Join-Path $Payload.RepoRoot 'src\DLLPickle\Private\Resolve-DPDLLLoadOrder.ps1')
. (Join-Path $Payload.RepoRoot 'src\DLLPickle\Public\Import-DPLibrary.ps1')
function Get-DPConfig { [PSCustomObject]@{ SkipLibraries = @(); ShowLogo = $false } }
function Invoke-DPConflictCheck {}
$global:PSModuleRoot = $Payload.FixtureRoot

$LocalAssemblyNames = @('A.Synthetic.Consumer', 'Z.Synthetic.Dependency')
$DiscoveredReferences = @(Get-DPDLLReferenceName -Path $ConsumerPath -LocalAssemblyNames $LocalAssemblyNames)
if ($DiscoveredReferences -notcontains 'Z.Synthetic.Dependency') {
    throw "Synthetic consumer did not advertise its dependency edge: $($DiscoveredReferences -join ', ')"
}

$ProbeLoadedAssemblies = @(
    [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -in $LocalAssemblyNames } |
        Where-Object {
            $LoadContext = [System.Runtime.Loader.AssemblyLoadContext]::GetLoadContext($_)
            $LoadContext -and $LoadContext.IsCollectible
        }
)
if ($ProbeLoadedAssemblies.Count -gt 0) {
    throw "Reference discovery loaded synthetic assemblies into a collectible context: $($ProbeLoadedAssemblies.FullName -join ', ')"
}

$OrderedDlls = @(Resolve-DPDLLLoadOrder -DLLFiles @((Get-Item -LiteralPath $ConsumerPath), (Get-Item -LiteralPath $DependencyPath)))
if ($OrderedDlls[0].Name -ne 'Z.Synthetic.Dependency.dll' -or $OrderedDlls[1].Name -ne 'A.Synthetic.Consumer.dll') {
    throw "Synthetic dependency graph did not order dependency-first: $($OrderedDlls.Name -join ', ')"
}

$Result = @(Import-DPLibrary -SuppressLogo -WarningAction SilentlyContinue)
if ($Result.Count -ne 2 -or @($Result | Where-Object Status -eq 'Failed').Count -gt 0) {
    throw "Synthetic dependency import failed: $($Result | ConvertTo-Json -Compress)"
}
if (@($Result | Where-Object Status -ne 'Imported').Count -gt 0) {
    throw "Synthetic dependency import should not rely on preloaded probe contexts: $($Result | ConvertTo-Json -Compress)"
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
        It 'uses a metadata-only fallback instead of forcing per-assembly GC after collectible loads' {
            $ResolverSource = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\DLLPickle\Private\Resolve-DPDLLLoadOrder.ps1') -Raw

            $ResolverSource | Should -Match ([regex]::Escape('System.Reflection.PortableExecutable.PEReader'))
            $ResolverSource | Should -Not -Match ([regex]::Escape('[System.GC]::Collect()'))
            $ResolverSource | Should -Not -Match ([regex]::Escape('[System.GC]::WaitForPendingFinalizers()'))
        }

        It 'inspects dependency references without executing module initializers when MetadataLoadContext is unavailable' {
            $FixtureRoot = Join-Path -Path $TestDrive -ChildPath ('MetadataOnly' + [guid]::NewGuid().ToString('N'))
            $Payload = [ordered]@{
                RepoRoot    = $RepoRoot
                FixtureRoot = $FixtureRoot
                FixtureId   = 'MetadataOnly' + [guid]::NewGuid().ToString('N')
            }
            $PayloadBase64 = [Convert]::ToBase64String(
                [Text.Encoding]::UTF8.GetBytes(($Payload | ConvertTo-Json -Compress))
            )
            $ChildScript = @'
$ErrorActionPreference = 'Stop'
$Payload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__')) | ConvertFrom-Json
if ([type]::GetType('System.Reflection.MetadataLoadContext, System.Reflection.MetadataLoadContext', $false)) {
    'METADATA_ONLY_SKIPPED'
    exit 0
}

if (
    -not [type]::GetType('System.Reflection.PortableExecutable.PEReader, System.Reflection.Metadata', $false) -or
    -not [type]::GetType('System.Reflection.Metadata.MetadataReader, System.Reflection.Metadata', $false)
) {
    throw 'PEReader metadata inspection types are unavailable in the isolated child process.'
}

$TfmDirectory = Join-Path -Path $Payload.FixtureRoot -ChildPath ([IO.Path]::Combine('bin', 'net8.0'))
$CompilerRoot = Join-Path -Path $Payload.FixtureRoot -ChildPath 'compiler'
$DependencyProjectRoot = Join-Path -Path $CompilerRoot -ChildPath 'Dependency'
$ConsumerProjectRoot = Join-Path -Path $CompilerRoot -ChildPath 'Consumer'
$MarkerPath = Join-Path -Path $Payload.FixtureRoot -ChildPath 'module-initializer.txt'

$null = New-Item -Path $TfmDirectory -ItemType Directory -Force
$null = New-Item -Path $DependencyProjectRoot -ItemType Directory -Force
$null = New-Item -Path $ConsumerProjectRoot -ItemType Directory -Force

$DependencyPath = Join-Path -Path $TfmDirectory -ChildPath 'Z.MetadataOnly.Dependency.dll'
$ConsumerPath = Join-Path -Path $TfmDirectory -ChildPath 'A.MetadataOnly.Consumer.dll'

$DependencySource = @"
namespace $($Payload.FixtureId) {
    public static class Dependency {
        public static string GetValue() { return "resolved"; }
    }
}
"@
Set-Content -LiteralPath (Join-Path $DependencyProjectRoot 'Dependency.cs') -Value $DependencySource -Encoding UTF8
Set-Content -LiteralPath (Join-Path $DependencyProjectRoot 'Z.MetadataOnly.Dependency.csproj') -Value @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <AssemblyName>Z.MetadataOnly.Dependency</AssemblyName>
    <RootNamespace>$($Payload.FixtureId)</RootNamespace>
  </PropertyGroup>
</Project>
"@ -Encoding UTF8
$DependencyBuildOutput = @(& dotnet build (Join-Path $DependencyProjectRoot 'Z.MetadataOnly.Dependency.csproj') -c Release -nologo -o $TfmDirectory 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Dependency project build failed: $($DependencyBuildOutput -join [Environment]::NewLine)"
}

$EscapedMarkerPath = $MarkerPath.Replace('\', '\\')
$ConsumerSource = @"
using System.IO;
using System.Runtime.CompilerServices;

namespace $($Payload.FixtureId) {
    public static class ConsumerInitialization {
        [ModuleInitializer]
        public static void Initialize() {
            File.WriteAllText("$EscapedMarkerPath", "initialized");
        }
    }

    public static class Consumer {
        public static string GetValue() { return Dependency.GetValue(); }
    }
}
"@
Set-Content -LiteralPath (Join-Path $ConsumerProjectRoot 'Consumer.cs') -Value $ConsumerSource -Encoding UTF8
Set-Content -LiteralPath (Join-Path $ConsumerProjectRoot 'A.MetadataOnly.Consumer.csproj') -Value @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <AssemblyName>A.MetadataOnly.Consumer</AssemblyName>
    <RootNamespace>$($Payload.FixtureId)</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <Reference Include="Z.MetadataOnly.Dependency">
      <HintPath>$DependencyPath</HintPath>
    </Reference>
  </ItemGroup>
</Project>
"@ -Encoding UTF8
$ConsumerBuildOutput = @(& dotnet build (Join-Path $ConsumerProjectRoot 'A.MetadataOnly.Consumer.csproj') -c Release -nologo -o $TfmDirectory 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Consumer project build failed: $($ConsumerBuildOutput -join [Environment]::NewLine)"
}

. (Join-Path $Payload.RepoRoot 'src\DLLPickle\Private\Resolve-DPDLLLoadOrder.ps1')
$References = @(Get-DPDLLReferenceName -Path $ConsumerPath -LocalAssemblyNames @('A.MetadataOnly.Consumer', 'Z.MetadataOnly.Dependency'))
if ($References -notcontains 'Z.MetadataOnly.Dependency') {
    throw "Metadata-only dependency discovery missed the synthetic reference: $($References -join ', ')"
}

if (Test-Path -LiteralPath $MarkerPath) {
    throw 'Metadata-only dependency discovery executed the module initializer.'
}

$ProbeLoadedAssemblies = @(
    [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -in @('A.MetadataOnly.Consumer', 'Z.MetadataOnly.Dependency') } |
        Where-Object {
            $LoadContext = [System.Runtime.Loader.AssemblyLoadContext]::GetLoadContext($_)
            $LoadContext -and $LoadContext.IsCollectible
        }
)
if ($ProbeLoadedAssemblies.Count -gt 0) {
    throw "Metadata-only dependency discovery left synthetic assemblies in a collectible context: $($ProbeLoadedAssemblies.FullName -join ', ')"
}

'METADATA_ONLY_OK'
'@.Replace('__PAYLOAD__', $PayloadBase64)
            $ChildScriptPath = Join-Path -Path $TestDrive -ChildPath 'Invoke-MetadataOnlyDependencyTest.ps1'
            Set-Content -LiteralPath $ChildScriptPath -Value $ChildScript -Encoding UTF8

            $ProcessOutput = @(& pwsh -NoProfile -NonInteractive -File $ChildScriptPath 2>&1)
            $ProcessExitCode = $LASTEXITCODE
            $ProcessOutputText = $ProcessOutput -join [Environment]::NewLine

            if ($ProcessOutputText -match 'METADATA_ONLY_SKIPPED') {
                Set-ItResult -Skipped -Because 'MetadataLoadContext is available in the isolated child process, so the metadata-only fallback path is not exercised.'
                return
            }

            $ProcessExitCode | Should -Be 0 -Because $ProcessOutputText
            $ProcessOutputText | Should -Match 'METADATA_ONLY_OK'
        }

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
