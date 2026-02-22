<#
.SYNOPSIS
    Bootstraps the GitHub Actions environment with required dependencies.

.DESCRIPTION
    Installs required PowerShell modules and tools needed for the CI/CD pipeline.
    This includes build tools, testing frameworks, and code analysis modules.

.EXAMPLE
    ./.github/scripts/Actions_Bootstrap.ps1

.NOTES
    Run this script at the beginning of CI/CD workflows to ensure all dependencies are available.
#>

[CmdletBinding()]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]

param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Write-Host '🔨 Bootstrapping CI/CD Environment...'

# https://docs.microsoft.com/powershell/module/packagemanagement/get-packageprovider
Get-PackageProvider -Name Nuget -ForceBootstrap | Out-Null

# https://docs.microsoft.com/powershell/module/powershellget/set-psrepository
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# List of PowerShell Modules required for the build.
$ModulesToInstall = New-Object System.Collections.Generic.List[object]

# https://github.com/pester/Pester
$ModulesToInstall.Add(([PSCustomObject]@{
            ModuleName         = 'Pester'
            SkipPublisherCheck = $true # Skip publisher check for older Pester versions due to certificate mismatch.
            #ModuleVersion = '5.7.1'
        })) | Out-Null

# https://github.com/nightroman/Invoke-Build
$ModulesToInstall.Add(([PSCustomObject]@{
            ModuleName = 'InvokeBuild'
            #ModuleVersion = '5.12.1'
        })) | Out-Null

# https://github.com/PowerShell/PSScriptAnalyzer
$ModulesToInstall.Add(([PSCustomObject]@{
            ModuleName = 'PSScriptAnalyzer'
            #ModuleVersion = '1.23.0'
        })) | Out-Null

# https://github.com/PowerShell/Microsoft.PowerShell.PlatyPS
$ModulesToInstall.Add(([PSCustomObject]@{
            ModuleName = 'Microsoft.PowerShell.PlatyPS'
        })) | Out-Null
# https://github.com/PowerShell/platyPS
# Older version used due to: https://github.com/PowerShell/platyPS/issues/457
#$ModulesToInstall.Add(([PSCustomObject]@{
#    ModuleName    = 'platyPS'
#    #ModuleVersion = '0.12.0'
#})) | Out-Null

Write-Host '📦 Installing PowerShell Modules'
foreach ($Module in $ModulesToInstall) {
    $InstallSplat = @{
        Name        = $Module.ModuleName
        Repository  = 'PSGallery'
        Force       = $true
        ErrorAction = 'Stop'
    }
    if ($Module.ModuleVersion) {
        $InstallSplat['RequiredVersion'] = $Module.ModuleVersion
    }
    if ($Module.SkipPublisherCheck) {
        $InstallSplat['SkipPublisherCheck'] = $true
    }

    try {
        Install-Module @InstallSplat
        Import-Module -Name $Module.ModuleName -ErrorAction Stop
        Write-Host "  - Successfully installed $($Module.ModuleName)"
    } catch {
        $message = 'Failed to install {0}' -f $Module.ModuleName
        Write-Host "  - $message"
        throw
    }
}

# Ensure .NET tools are available
Write-Host "`n🧑‍💻 Verifying .NET environment..."
try {
    $dotnetVersion = dotnet --version
    Write-Host "  ✓ .NET SDK: $dotnetVersion"
} catch {
    Write-Error ".NET SDK is not installed: $_"
}

Write-Host "`n✅ Bootstrap complete!"
