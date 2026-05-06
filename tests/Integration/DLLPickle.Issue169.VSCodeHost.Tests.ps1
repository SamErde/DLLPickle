BeforeAll {
    Set-Location -Path $PSScriptRoot
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $BuiltModuleManifestPath = Join-Path $ProjectRoot 'module\DLLPickle\DLLPickle.psd1'
    . (Join-Path $PSScriptRoot 'Invoke-DLLPickleScenario.ps1')

    function Initialize-Issue169SyntheticModule {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$RootPath,

            [Parameter(Mandatory)]
            [ValidateSet('PowerShellEditorServices.Commands', 'Microsoft.Graph.Authentication')]
            [string]$Name,

            [Parameter(Mandatory)]
            [string]$Version
        )

        $ModuleDirectory = Join-Path -Path $RootPath -ChildPath ([System.IO.Path]::Combine($Name, $Version))
        $null = New-Item -Path $ModuleDirectory -ItemType Directory -Force
        $ModuleFile = Join-Path -Path $ModuleDirectory -ChildPath "$Name.psm1"
        $ManifestFile = Join-Path -Path $ModuleDirectory -ChildPath "$Name.psd1"

        if ($Name -eq 'PowerShellEditorServices.Commands') {
            @'
$global:DllPickleSyntheticPreloadedAssembly = [PSCustomObject]@{
    Name = 'Microsoft.Identity.Client'
    Version = '4.60.0.0'
    Source = 'PowerShellEditorServices.Commands'
}
'@ | Set-Content -LiteralPath $ModuleFile -Encoding UTF8
        } else {
            @'
if ($global:DllPickleSyntheticPreloadedAssembly -and
    $global:DllPickleSyntheticPreloadedAssembly.Name -eq 'Microsoft.Identity.Client') {
    throw [System.IO.FileLoadException]::new("Assembly with same name is already loaded: Microsoft.Identity.Client from $($global:DllPickleSyntheticPreloadedAssembly.Source).")
}

function Connect-MgGraph {
    [CmdletBinding()]
    param()

    [PSCustomObject]@{ Connected = $true; Module = 'Microsoft.Graph.Authentication' }
}

Export-ModuleMember -Function Connect-MgGraph
'@ | Set-Content -LiteralPath $ModuleFile -Encoding UTF8
        }

        New-ModuleManifest -Path $ManifestFile -RootModule "$Name.psm1" -ModuleVersion $Version -FunctionsToExport '*' -ErrorAction Stop
    }
}

Describe 'Issue 169 VS Code host preload reproduction' -Tag 'Integration', 'Issue169' {
    BeforeEach {
        $SyntheticModuleRoot = Join-Path -Path $TestDrive -ChildPath 'Modules'
        Initialize-Issue169SyntheticModule -RootPath $SyntheticModuleRoot -Name 'PowerShellEditorServices.Commands' -Version '2025.4.0'
        Initialize-Issue169SyntheticModule -RootPath $SyntheticModuleRoot -Name 'Microsoft.Graph.Authentication' -Version '2.36.1'
    }

    It 'imports the synthetic Graph module in a normal pwsh host' {
        $Result = Invoke-DLLPickleScenario -Name 'Issue169-NormalHost-Synthetic' `
            -ModuleManifestPath $BuiltModuleManifestPath `
            -AdditionalModulePath $SyntheticModuleRoot `
            -Step @(
                @{ Name = 'Import Microsoft.Graph.Authentication'; Script = 'Import-Module Microsoft.Graph.Authentication -Force' }
            )

        $Result.Success | Should -BeTrue
    }

    It 'captures a VS Code-style preloaded assembly conflict before Graph import' {
        $Result = Invoke-DLLPickleScenario -Name 'Issue169-VSCodePreload-Synthetic' `
            -ModuleManifestPath $BuiltModuleManifestPath `
            -AdditionalModulePath $SyntheticModuleRoot `
            -Step @(
                @{ Name = 'Import PowerShellEditorServices.Commands'; Script = 'Import-Module PowerShellEditorServices.Commands -Force' }
                @{ Name = 'Import Microsoft.Graph.Authentication'; Script = 'Import-Module Microsoft.Graph.Authentication -Force' }
            )

        $Result.Success | Should -BeFalse
        $GraphStep = $Result.Steps | Where-Object Name -eq 'Import Microsoft.Graph.Authentication'
        $GraphStep.Success | Should -BeFalse
        $GraphStep.Error.Message | Should -Match 'same name is already loaded'
    }

    It 'runs the live VS Code host import probe when explicitly enabled' -Tag 'LiveRepro' -Skip:($env:DLLPICKLE_RUN_LIVE_REPRO -ne '1') {
        $Result = Invoke-DLLPickleScenario -Name 'Issue169-Live-PowerShellEditorServicesProbe' `
            -ModuleManifestPath $BuiltModuleManifestPath `
            -Step @(
                @{ Name = 'Import PowerShellEditorServices.Commands if present'; Script = '$Candidate = Get-Module PowerShellEditorServices.Commands -ListAvailable | Select-Object -First 1; if ($Candidate) { Import-Module $Candidate.Path -Force }' }
                @{ Name = 'Import DLLPickle'; Script = 'Import-Module $ScenarioModuleManifestPath -Force; Import-DPLibrary -SuppressLogo -ShowLoaderExceptions' }
                @{ Name = 'Import Microsoft.Graph.Authentication'; Script = 'Import-Module Microsoft.Graph.Authentication -Force' }
            )

        $Result.Success | Should -BeTrue
    }
}

