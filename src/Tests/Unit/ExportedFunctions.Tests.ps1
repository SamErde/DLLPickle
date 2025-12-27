BeforeAll {
    Set-Location -Path $PSScriptRoot
    $ModuleName = 'DLLPickle'
    $PathToManifest = [System.IO.Path]::Combine('..', '..', $ModuleName, "$ModuleName.psd1")
    Get-Module $ModuleName -ErrorAction SilentlyContinue | Remove-Module -Force
    Import-Module $PathToManifest -Force
    $ManifestContent = Test-ModuleManifest -Path $PathToManifest
    $ModuleExported = Get-Command -Module $ModuleName | Select-Object -ExpandProperty Name
    $ManifestExported = ($ManifestContent.ExportedFunctions).Keys
}
BeforeDiscovery {
    Set-Location -Path $PSScriptRoot
    $ModuleName = 'DLLPickle'
    $PathToManifest = [System.IO.Path]::Combine('..', '..', $ModuleName, "$ModuleName.psd1")
    $ManifestContent = Test-ModuleManifest -Path $PathToManifest
    $ModuleExported = Get-Command -Module $ModuleName | Select-Object -ExpandProperty Name
    $ManifestExported = ($ManifestContent.ExportedFunctions).Keys
}
Describe $ModuleName {

    Context 'Exported Commands' -Fixture {

        Context 'Number of commands' -Fixture {

            It 'Exports the same number of public functions as what is listed in the Module Manifest' {
                $ManifestExported.Count | Should -BeExactly $ModuleExported.Count
            }

        }

        Context 'Explicitly exported commands' {

            It 'Includes <_> in the Module Manifest ExportedFunctions' -ForEach $ModuleExported {
                $ManifestExported -contains $_ | Should -BeTrue
            }

        }
    } #context_ExportedCommands

    Context 'Command Help' -Fixture {
        Context '<_>' -Foreach $moduleExported {

            BeforeEach {
                $Help = Get-Help -Name $_ -Full
            }

            It -Name 'Includes a Synopsis' -Test {
                $Help.Synopsis | Should -Not -BeNullOrEmpty
            }

            It -Name 'Includes a Description' -Test {
                $Help.Description.Text | Should -Not -BeNullOrEmpty
            }

            It -Name 'Includes an Example' -Test {
                $Help.Examples.Example | Should -Not -BeNullOrEmpty
            }
        }
    } #context_CommandHelp
}
