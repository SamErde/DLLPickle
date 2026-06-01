BeforeAll {
    Set-Location -Path $PSScriptRoot
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:InventoryScriptPath = Join-Path $ProjectRoot 'tools\Get-DLLPickleUpstreamInventory.ps1'
    $script:UpdateScriptPath = Join-Path $ProjectRoot 'tools\Update-DLLPickleDependencyPins.ps1'
}

Describe 'Dependency automation tooling' -Tag 'Unit' {
    It 'inventories tracked assemblies from an existing module cache' {
        $Assembly = [System.String].Assembly
        $AssemblyName = $Assembly.GetName().Name
        $ModuleCachePath = Join-Path -Path $TestDrive -ChildPath 'modules'
        $ModuleRoot = Join-Path -Path $ModuleCachePath -ChildPath ([System.IO.Path]::Combine('Synthetic.Graph', '1.0.0'))
        $null = New-Item -Path $ModuleRoot -ItemType Directory -Force
        Copy-Item -Path $Assembly.Location -Destination (Join-Path -Path $ModuleRoot -ChildPath "$AssemblyName.dll") -Force

        $PolicyPath = Join-Path -Path $TestDrive -ChildPath 'policy.json'
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

        $Result = & $script:InventoryScriptPath -PolicyPath $PolicyPath -ModuleCachePath $ModuleCachePath -SkipDownload -OutputPath (Join-Path $TestDrive 'inventory.json')

        $Result.Modules | Should -HaveCount 1
        $Result.Modules[0].Name | Should -Be 'Synthetic.Graph'
        @($Result.Modules[0].TrackedAssemblies).Name | Should -Contain $AssemblyName
    }

    It 'updates exact package pins from upstream inventory and reports blocked preload findings' {
        $ProjectPath = Join-Path -Path $TestDrive -ChildPath 'DLLPickle.csproj'
        @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
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
                    targetFramework = 'net8.0'
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
                    targetFramework = 'net8.0'
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
        $Report.Warnings | Should -Contain "PackageReference 'Contoso.CappedLibrary' candidate '1.53.0' exceeds maximum '1.50.0' for target framework 'net8.0'; using maximum version."
        Get-Content -LiteralPath $ProjectPath -Raw | Should -Match 'Include="Contoso\.CappedLibrary" Version="\[1\.50\.0\]"'
        Get-Content -LiteralPath $ProjectPath -Raw | Should -Match 'Include="Microsoft\.Identity\.Client" Version="4\.\*"'
        @($Report.BlockedFindings) | Should -HaveCount 1
        $Report.BlockedFindings[0].AssemblyName | Should -Be 'Microsoft.OData.Core'
    }
}
