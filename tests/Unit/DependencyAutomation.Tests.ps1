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
            exactPins = @()
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
    <TargetFrameworks>net48;net8.0</TargetFrameworks>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Azure.Core" Version="[1.51.1]" Condition="'$(TargetFramework)' == 'net48'" />
  </ItemGroup>
</Project>
'@ | Set-Content -LiteralPath $ProjectPath -Encoding UTF8

        $PolicyPath = Join-Path -Path $TestDrive -ChildPath 'policy.json'
        @{
            exactPins = @(
                @{
                    packageName = 'Azure.Core'
                    assemblyName = 'Azure.Core'
                    targetFramework = 'net48'
                    versionSyntax = 'exact'
                    sourceModules = @('Microsoft.Graph.Authentication', 'MicrosoftTeams')
                    updateMode = 'candidatePullRequest'
                    reason = 'Synthetic exact pin test.'
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
                            Name = 'Azure.Core'
                            Version = '1.52.0.0'
                            RelativePath = 'Dependencies\Azure.Core.dll'
                        }
                    )
                }
                @{
                    Name = 'MicrosoftTeams'
                    Version = '7.2.0'
                    TrackedAssemblies = @(
                        @{
                            Name = 'Azure.Core'
                            Version = '1.53.0.0'
                            RelativePath = 'Azure.Core.dll'
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

        $Report = & $script:UpdateScriptPath -InventoryPath $InventoryPath -PolicyPath $PolicyPath -ProjectPath $ProjectPath -OutputPath (Join-Path $TestDrive 'candidate-report.json')

        $Report.ProjectChanged | Should -BeTrue
        $Report.Changes[0].CandidateVersion | Should -Be '[1.53.0]'
        $Report.Changes[0].SourceModule | Should -Be 'MicrosoftTeams'
        Get-Content -LiteralPath $ProjectPath -Raw | Should -Match 'Version="\[1\.53\.0\]"'
        @($Report.BlockedFindings) | Should -HaveCount 1
        $Report.BlockedFindings[0].AssemblyName | Should -Be 'Microsoft.OData.Core'
    }
}
