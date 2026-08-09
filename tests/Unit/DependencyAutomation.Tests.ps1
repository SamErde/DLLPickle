BeforeAll {
    Set-Location -Path $PSScriptRoot
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:InventoryScriptPath = Join-Path $ProjectRoot 'tools\Get-DLLPickleUpstreamInventory.ps1'
    $script:UpdateScriptPath = Join-Path $ProjectRoot 'tools\Update-DLLPickleDependencyPins.ps1'

    function Write-DependencyAutomationRuntimeMatrixFixture {
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        [ordered]@{
            schemaVersion = 1
            profiles      = @(
                [ordered]@{
                    powerShellVersion = $PSVersionTable.PSVersion.ToString()
                    powerShellMajor   = $PSVersionTable.PSVersion.Major
                    powerShellMinor   = $PSVersionTable.PSVersion.Minor
                    dotnetMajor       = [Environment]::Version.Major
                    targetFramework   = 'net{0}.0' -f [Environment]::Version.Major
                }
            )
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -Encoding UTF8

        return $Path
    }
}

Describe 'Dependency automation tooling' -Tag 'Unit' {
    It 'resolves every monitored module version before downloading any module' {
        $Assembly = [System.String].Assembly
        $AssemblyName = $Assembly.GetName().Name
        $ModuleCachePath = Join-Path -Path $TestDrive -ChildPath 'atomic-modules'
        $PolicyPath = Join-Path -Path $TestDrive -ChildPath 'atomic-policy.json'
        $TestMatrixPath = Write-DependencyAutomationRuntimeMatrixFixture -Path (Join-Path $TestDrive 'atomic-runtime-matrix.json')
        @{
            monitoredModules = @(
                @{ name = 'Synthetic.One'; repository = 'PSGallery'; purpose = 'First synthetic module.' }
                @{ name = 'Synthetic.Two'; repository = 'PSGallery'; purpose = 'Second synthetic module.' }
            )
            trackedAssemblies = @($AssemblyName)
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $PolicyPath -Encoding UTF8

        $InventoryTestStateKey = 'DLLPickle.DependencyAutomation.InventoryTestState'
        $InventoryTestState = [PSCustomObject]@{
            Events           = [System.Collections.Generic.List[string]]::new()
            AssemblyLocation = $Assembly.Location
            AssemblyName     = $AssemblyName
        }
        [System.AppDomain]::CurrentDomain.SetData($InventoryTestStateKey, $InventoryTestState)
        Mock Find-Module {
            $State = [System.AppDomain]::CurrentDomain.GetData('DLLPickle.DependencyAutomation.InventoryTestState')
            $State.Events.Add("find:$Name")
            [PSCustomObject]@{
                Name = $Name
                Version = if ($Name -eq 'Synthetic.One') { [version]'1.2.3' } else { [version]'4.5.6' }
            }
        }
        Mock Save-Module {
            $State = [System.AppDomain]::CurrentDomain.GetData('DLLPickle.DependencyAutomation.InventoryTestState')
            $State.Events.Add("save:$Name")
            $ModuleRoot = Join-Path -Path $Path -ChildPath ([System.IO.Path]::Combine($Name, [string]$RequiredVersion))
            $null = New-Item -Path $ModuleRoot -ItemType Directory -Force
            Copy-Item -LiteralPath $State.AssemblyLocation -Destination (Join-Path $ModuleRoot "$($State.AssemblyName).dll") -Force
            Set-Content -LiteralPath (Join-Path $ModuleRoot "$Name.psm1") -Value '# Synthetic importable module.' -Encoding UTF8
            New-ModuleManifest -Path (Join-Path $ModuleRoot "$Name.psd1") -RootModule "$Name.psm1" -ModuleVersion ([string]$RequiredVersion)
        }

        $null = & $script:InventoryScriptPath -PolicyPath $PolicyPath -TestMatrixPath $TestMatrixPath -ModuleCachePath $ModuleCachePath -OutputPath (Join-Path $TestDrive 'atomic-inventory.json')

        $InventoryEvents = @($InventoryTestState.Events)
        [System.AppDomain]::CurrentDomain.SetData($InventoryTestStateKey, $null)
        $InventoryEvents | Should -Be @('find:Synthetic.One', 'find:Synthetic.Two', 'save:Synthetic.One', 'save:Synthetic.Two')
    }

    It 'inventories tracked assemblies from an existing module cache' {
        $Assembly = [System.String].Assembly
        $AssemblyName = $Assembly.GetName().Name
        $ModuleCachePath = Join-Path -Path $TestDrive -ChildPath 'modules'
        $ModuleRoot = Join-Path -Path $ModuleCachePath -ChildPath ([System.IO.Path]::Combine('Synthetic.Graph', '1.0.0'))
        $null = New-Item -Path $ModuleRoot -ItemType Directory -Force
        Copy-Item -Path $Assembly.Location -Destination (Join-Path -Path $ModuleRoot -ChildPath "$AssemblyName.dll") -Force
        Set-Content -LiteralPath (Join-Path $ModuleRoot 'Synthetic.Graph.psm1') -Value '# Synthetic importable module.' -Encoding UTF8
        New-ModuleManifest -Path (Join-Path $ModuleRoot 'Synthetic.Graph.psd1') -RootModule 'Synthetic.Graph.psm1' -ModuleVersion '1.0.0'

        $PolicyPath = Join-Path -Path $TestDrive -ChildPath 'policy.json'
        $TestMatrixPath = Write-DependencyAutomationRuntimeMatrixFixture -Path (Join-Path $TestDrive 'inventory-runtime-matrix.json')
        @{
            monitoredModules = @(
                @{
                    name       = 'Synthetic.Graph'
                    repository = 'PSGallery'
                    purpose    = 'Synthetic inventory test module.'
                }
            )
            trackedAssemblies = @($AssemblyName)
            preload = @()
            blockedPreloadAssemblies = @()
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $PolicyPath -Encoding UTF8

        $Result = & $script:InventoryScriptPath -PolicyPath $PolicyPath -TestMatrixPath $TestMatrixPath -ModuleCachePath $ModuleCachePath -SkipDownload -OutputPath (Join-Path $TestDrive 'inventory.json')

        $Result.Modules | Should -HaveCount 1
        $Result.Modules[0].Name | Should -Be 'Synthetic.Graph'
        @($Result.Modules[0].TrackedAssemblies).Name | Should -Contain $AssemblyName
    }

    It 'reads gallery manifests that use allowed dynamic module-manifest expressions' {
        $Assembly = [System.String].Assembly
        $AssemblyName = $Assembly.GetName().Name
        $ModuleCachePath = Join-Path $TestDrive 'dynamic-modules'
        $ModuleRoot = Join-Path $ModuleCachePath 'Synthetic.Dynamic\1.0.0'
        $null = New-Item -Path $ModuleRoot -ItemType Directory -Force
        Copy-Item -LiteralPath $Assembly.Location -Destination (Join-Path $ModuleRoot "$AssemblyName.dll")
        Set-Content -LiteralPath (Join-Path $ModuleRoot 'Synthetic.Dynamic.psm1') -Value '# Synthetic dynamic-manifest module.' -Encoding UTF8
        @'
@{
    RootModule = if ($PSEdition -eq 'Core') { 'Synthetic.Dynamic.psm1' } else { 'Synthetic.Dynamic.psm1' }
    ModuleVersion = '1.0.0'
    GUID = '9be890c0-c2a2-47ea-aa9b-22b3395c35c4'
    PowerShellVersion = '7.0'
    FunctionsToExport = @()
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
'@ | Set-Content -LiteralPath (Join-Path $ModuleRoot 'Synthetic.Dynamic.psd1') -Encoding UTF8

        $PolicyPath = Join-Path $TestDrive 'dynamic-policy.json'
        $TestMatrixPath = Write-DependencyAutomationRuntimeMatrixFixture -Path (Join-Path $TestDrive 'dynamic-runtime-matrix.json')
        @{
            monitoredModules = @(@{ name = 'Synthetic.Dynamic'; repository = 'PSGallery'; purpose = 'Dynamic manifest regression.' })
            trackedAssemblies = @($AssemblyName)
            preload = @()
            blockedPreloadAssemblies = @()
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $PolicyPath -Encoding UTF8

        $Result = & $script:InventoryScriptPath -PolicyPath $PolicyPath -TestMatrixPath $TestMatrixPath -ModuleCachePath $ModuleCachePath -SkipDownload -OutputPath (Join-Path $TestDrive 'dynamic-inventory.json')

        $Result.Modules[0].ManifestPowerShellVersion | Should -Be '7.0'
    }

    It 'updates exact package pins from upstream inventory and reports blocked preload findings' {
        $ProjectPath = Join-Path -Path $TestDrive -ChildPath 'DLLPickle.csproj'
        @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFrameworks>net8.0;net9.0;net10.0</TargetFrameworks>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Contoso.CappedLibrary" Version="1.0.0" />
    <PackageReference Include="Microsoft.Identity.Client" Version="4.0.0" />
  </ItemGroup>
</Project>
'@ | Set-Content -LiteralPath $ProjectPath -Encoding UTF8

        $PolicyPath = Join-Path -Path $TestDrive -ChildPath 'policy.json'
        @{
            preload = @(
                @{
                    packageName = 'Contoso.CappedLibrary'
                    assemblyName = 'Contoso.CappedLibrary'
                    targetFrameworks = @('net8.0', 'net9.0', 'net10.0')
                    classification = 'preload'
                    versionPolicy = 'minorPatchFloat'
                    maximumPackageVersion = '1.50.0'
                    sourceModules = @('Microsoft.Graph.Authentication', 'MicrosoftTeams')
                    updateMode = 'candidatePullRequest'
                    reason = 'Synthetic capped preload test.'
                }
                @{
                    packageName = 'Microsoft.Identity.Client'
                    assemblyName = 'Microsoft.Identity.Client'
                    targetFrameworks = @('net8.0', 'net9.0', 'net10.0')
                    classification = 'preload'
                    versionPolicy = 'minorPatchFloat'
                    sourceModules = @('Az.Accounts', 'Microsoft.Graph.Authentication')
                    updateMode = 'candidatePullRequest'
                    reason = 'Synthetic floating preload test.'
                }
            )
            blockedPreloadAssemblies = @(
                @{
                    packageName = 'Microsoft.OData.Core'
                    assemblyName = 'Microsoft.OData.Core'
                    targetFrameworks = @('net8.0', 'net9.0', 'net10.0')
                    sourceModules = @('ExchangeOnlineManagement', 'Az.Storage')
                    updateMode = 'reportOnly'
                    reason = 'Synthetic blocked preload test.'
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $PolicyPath -Encoding UTF8

        $InventoryPath = Join-Path -Path $TestDrive -ChildPath 'inventory.json'
        @{
            Modules = @(
                @{
                    Name = 'Microsoft.Graph.Authentication'
                    Version = '2.37.0'
                    TrackedAssemblies = @(
                        @{
                            Name = 'Contoso.CappedLibrary'
                            Version = '1.52.0.0'
                            RelativePath = 'Dependencies\Contoso.CappedLibrary.dll'
                        }
                        @{
                            Name = 'Microsoft.Identity.Client'
                            Version = '4.82.1.0'
                            RelativePath = 'Dependencies\Microsoft.Identity.Client.dll'
                        }
                    )
                }
                @{
                    Name = 'Az.Accounts'
                    Version = '5.4.0'
                    TrackedAssemblies = @(
                        @{
                            Name = 'Microsoft.Identity.Client'
                            Version = '4.83.1.0'
                            RelativePath = 'Microsoft.Identity.Client.dll'
                        }
                    )
                }
                @{
                    Name = 'MicrosoftTeams'
                    Version = '7.2.0'
                    TrackedAssemblies = @(
                        @{
                            Name = 'Contoso.CappedLibrary'
                            Version = '1.53.0.0'
                            RelativePath = 'Contoso.CappedLibrary.dll'
                        }
                    )
                }
                @{
                    Name = 'ExchangeOnlineManagement'
                    Version = '3.10.0'
                    TrackedAssemblies = @(
                        @{
                            Name = 'Microsoft.OData.Core'
                            Version = '7.22.0.0'
                            RelativePath = 'Microsoft.OData.Core.dll'
                        }
                    )
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $InventoryPath -Encoding UTF8

        $Report = & $script:UpdateScriptPath -InventoryPath $InventoryPath -PolicyPath $PolicyPath -ProjectPath $ProjectPath -OutputPath (Join-Path $TestDrive 'candidate-report.json') -Confirm:$false -WhatIf:$false

        $Report.ProjectChanged | Should -BeTrue
        # Capped minorPatchFloat must NOT float (a floating 1.* would resolve above the 1.50.0 cap);
        # it is pinned exactly at the capped version. The uncapped MSAL entry floats as 4.*.
        $Report.Changes[0].CandidateVersion | Should -Be '[1.50.0]'
        $Report.Changes[0].SourceModule | Should -Be 'MicrosoftTeams'
        $Report.Changes[0].TargetFrameworks | Should -Be @('net8.0', 'net9.0', 'net10.0')
        @($Report.Changes[0].TfmResults) | Should -HaveCount 3
        $Report.Changes[0].UsesConditionalReferences | Should -BeFalse
        $Report.ReviewRequired | Should -BeFalse
        $Report.Warnings | Should -Contain "PackageReference 'Contoso.CappedLibrary' candidate '1.53.0' exceeds maximum '1.50.0' for target frameworks 'net8.0, net9.0, net10.0'; using maximum version."
        Get-Content -LiteralPath $ProjectPath -Raw | Should -Match 'Include="Contoso\.CappedLibrary" Version="\[1\.50\.0\]"'
        Get-Content -LiteralPath $ProjectPath -Raw | Should -Match 'Include="Microsoft\.Identity\.Client" Version="4\.\*"'
        @($Report.BlockedFindings) | Should -HaveCount 1
        $Report.BlockedFindings[0].AssemblyName | Should -Be 'Microsoft.OData.Core'
    }

    It 'flags existing per-TFM conditional pins for maintainer review' {
        $ProjectPath = Join-Path -Path $TestDrive -ChildPath 'conditional.csproj'
        @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFrameworks>net8.0;net9.0;net10.0</TargetFrameworks>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Contoso.Library" Version="1.0.0" Condition="'$(TargetFramework)' == 'net8.0'" />
    <PackageReference Include="Contoso.Library" Version="1.0.0" Condition="'$(TargetFramework)' == 'net9.0'" />
    <PackageReference Include="Contoso.Library" Version="1.0.0" Condition="'$(TargetFramework)' == 'net10.0'" />
  </ItemGroup>
</Project>
'@ | Set-Content -LiteralPath $ProjectPath -Encoding UTF8

        $PolicyPath = Join-Path -Path $TestDrive -ChildPath 'conditional-policy.json'
        @{
            preload = @(
                @{
                    packageName = 'Contoso.Library'
                    assemblyName = 'Contoso.Library'
                    targetFrameworks = @('net8.0', 'net9.0', 'net10.0')
                    versionPolicy = 'exact'
                    sourceModules = @('Contoso.Module')
                    reason = 'Synthetic conditional-pin test.'
                }
            )
            blockedPreloadAssemblies = @()
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $PolicyPath -Encoding UTF8

        $InventoryPath = Join-Path -Path $TestDrive -ChildPath 'conditional-inventory.json'
        @{
            Modules = @(
                @{
                    Name = 'Contoso.Module'
                    Version = '2.0.0'
                    TrackedAssemblies = @(
                        @{
                            Name = 'Contoso.Library'
                            Version = '2.0.0.0'
                            RelativePath = 'Contoso.Library.dll'
                        }
                    )
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $InventoryPath -Encoding UTF8

        $Report = & $script:UpdateScriptPath -InventoryPath $InventoryPath -PolicyPath $PolicyPath -ProjectPath $ProjectPath -OutputPath (Join-Path $TestDrive 'conditional-report.json') -Confirm:$false

        $Report.ProjectChanged | Should -BeTrue
        $Report.ReviewRequired | Should -BeTrue
        $Report.Changes[0].UsesConditionalReferences | Should -BeTrue
        $Report.Changes[0].ConditionalPinRequired | Should -BeFalse
        @($Report.Changes[0].TfmResults | Where-Object Applied) | Should -HaveCount 3
        ([regex]::Matches((Get-Content -LiteralPath $ProjectPath -Raw), 'Version="\[2\.0\.0\]"')).Count | Should -Be 3
    }

    It 'does not introduce conditional pins when profile inventories require different TFM versions' {
        $ProjectPath = Join-Path $TestDrive 'common-pin.csproj'
        @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFrameworks>net8.0;net9.0;net10.0</TargetFrameworks>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Contoso.Library" Version="1.0.0" />
  </ItemGroup>
</Project>
'@ | Set-Content -LiteralPath $ProjectPath -Encoding UTF8

        $PolicyPath = Join-Path $TestDrive 'multi-profile-policy.json'
        @{
            preload = @(
                @{
                    packageName = 'Contoso.Library'
                    assemblyName = 'Contoso.Library'
                    targetFrameworks = @('net8.0', 'net9.0', 'net10.0')
                    versionPolicy = 'exact'
                    sourceModules = @('Contoso.Module')
                    reason = 'Synthetic profile reconciliation test.'
                }
            )
            blockedPreloadAssemblies = @()
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $PolicyPath -Encoding UTF8

        $InventoryPaths = @(
            foreach ($TfmRow in @(
                    @{ Tfm = 'net8.0'; Version = '1.0.0.0' }
                    @{ Tfm = 'net9.0'; Version = '2.0.0.0' }
                    @{ Tfm = 'net10.0'; Version = '2.0.0.0' }
                )) {
                $Path = Join-Path $TestDrive "inventory-$($TfmRow.Tfm).json"
                @{
                    ProfileKey = "ps-test-$($TfmRow.Tfm)-windows-x64"
                    Profile = @{ TargetFramework = $TfmRow.Tfm }
                    Modules = @(
                        @{
                            Name = 'Contoso.Module'
                            Version = '3.0.0'
                            TrackedAssemblies = @(
                                @{
                                    Name = 'Contoso.Library'
                                    Version = $TfmRow.Version
                                    RelativePath = 'Contoso.Library.dll'
                                }
                            )
                        }
                    )
                } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
                $Path
            }
        )

        $Report = & $script:UpdateScriptPath -InventoryPath $InventoryPaths -PolicyPath $PolicyPath -ProjectPath $ProjectPath -OutputPath (Join-Path $TestDrive 'multi-profile-report.json') -Confirm:$false

        $Report.ProjectChanged | Should -BeFalse
        $Report.ReviewRequired | Should -BeTrue
        $Report.Changes[0].ConditionalPinRequired | Should -BeTrue
        $Report.Changes[0].CandidateVersions | Should -Be @('[1.0.0]', '[2.0.0]')
        @($Report.Changes[0].TfmResults | Where-Object Applied) | Should -HaveCount 0
        Get-Content -LiteralPath $ProjectPath -Raw | Should -Match 'Version="1\.0\.0"'
    }
}
