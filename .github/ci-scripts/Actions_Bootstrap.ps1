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
[void]$ModulesToInstall.Add(([PSCustomObject]@{
            ModuleName = 'Pester'
            #ModuleVersion = '5.7.1'
        }))
# https://github.com/nightroman/Invoke-Build
[void]$ModulesToInstall.Add(([PSCustomObject]@{
            ModuleName = 'InvokeBuild'
            #ModuleVersion = '5.12.1'
        }))
# https://github.com/PowerShell/PSScriptAnalyzer
[void]$ModulesToInstall.Add(([PSCustomObject]@{
            ModuleName = 'PSScriptAnalyzer'
            #ModuleVersion = '1.23.0'
        }))
# https://github.com/PowerShell/Microsoft.PowerShell.PlatyPS
[void]$ModulesToInstall.Add(([PSCustomObject]@{
            ModuleName = 'Microsoft.PowerShell.PlatyPS'
        }))
# https://github.com/PowerShell/platyPS
# older version used due to: https://github.com/PowerShell/platyPS/issues/457
#[void]$ModulesToInstall.Add(([PSCustomObject]@{
#            ModuleName    = 'platyPS'
#            #ModuleVersion = '0.12.0'
#        }))

Write-Host '📦 Installing PowerShell Modules'
foreach ($Module in $ModulesToInstall) {
    $InstallSplat = @{
        Name               = $Module.ModuleName
        RequiredVersion    = $Module.ModuleVersion
        Repository         = 'PSGallery'
        SkipPublisherCheck = $true
        Force              = $true
        ErrorAction        = 'Stop'
    }
    try {
        if ($Module.ModuleName -eq 'Pester' -and ($IsWindows -or $PSVersionTable.PSVersion -le [version]'5.1')) {
            # special case for Pester certificate mismatch with older Pester versions - https://github.com/pester/Pester/issues/2389
            # this only affects windows builds
            Install-Module @InstallSplat -SkipPublisherCheck
        } else {
            Install-Module @InstallSplat
        }
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
