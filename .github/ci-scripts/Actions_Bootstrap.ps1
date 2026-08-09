<#
.SYNOPSIS
    Bootstraps the GitHub Actions environment with required dependencies.

.DESCRIPTION
    Installs required PowerShell modules and tools needed for the CI/CD pipeline.
    This includes build tools, testing frameworks, and code analysis modules.

.EXAMPLE
    ./.github/scripts/Actions_Bootstrap.ps1

.PARAMETER ModuleInstallPath
    Optional isolated module root. Exact tool versions are saved here and the path is
    prepended only to this process's PSModulePath. No user-scope module path is mutated.

.NOTES
    Run this script at the beginning of CI/CD workflows to ensure all dependencies are available.
#>

[CmdletBinding()]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]

param(
    [Parameter()]
    [string]$ModuleInstallPath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Write-Host '🔨 Bootstrapping CI/CD Environment...'

$RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$ToolingScriptPath = Join-Path -Path $RepositoryRoot -ChildPath 'build/DLLPickle.Tooling.ps1'
$ToolPolicyPath = Join-Path -Path $RepositoryRoot -ChildPath 'build/build-tool-versions.json'
. $ToolingScriptPath
$ToolPolicy = Get-DLLPickleBuildToolPolicy -Path $ToolPolicyPath

if (-not [string]::IsNullOrWhiteSpace($ModuleInstallPath)) {
    $ModuleInstallPath = [System.IO.Path]::GetFullPath($ModuleInstallPath)
    if (-not (Test-Path -LiteralPath $ModuleInstallPath -PathType Container)) {
        $null = New-Item -Path $ModuleInstallPath -ItemType Directory -Force
    }
    $ExistingModulePathEntries = @($env:PSModulePath -split [System.IO.Path]::PathSeparator | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $env:PSModulePath = @($ModuleInstallPath) + $ExistingModulePathEntries -join [System.IO.Path]::PathSeparator
}

# https://docs.microsoft.com/powershell/module/packagemanagement/get-packageprovider
Get-PackageProvider -Name Nuget -ForceBootstrap | Out-Null

# https://docs.microsoft.com/powershell/module/powershellget/set-psrepository
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

Write-Host '📦 Installing exact PowerShell build-tool versions'
foreach ($Module in @($ToolPolicy.modules)) {
    $RequiredVersion = [version]$Module.version
    $InstalledModule = Get-Module -ListAvailable -Name $Module.name |
        Where-Object { Test-DLLPickleToolVersionMatch -ActualVersion $_.Version -RequiredVersion $RequiredVersion } |
        Select-Object -First 1

    if (-not $InstalledModule) {
        $ModuleCommandSplat = @{
            Name            = $Module.name
            RequiredVersion = $Module.version
            Repository      = 'PSGallery'
            Force           = $true
            ErrorAction     = 'Stop'
        }
        if ($Module.skipPublisherCheck) {
            $ModuleCommandSplat['SkipPublisherCheck'] = $true
        }

        try {
            if ([string]::IsNullOrWhiteSpace($ModuleInstallPath)) {
                $ModuleCommandSplat['Scope'] = 'CurrentUser'
                Install-Module @ModuleCommandSplat
            } else {
                $ModuleCommandSplat['Path'] = $ModuleInstallPath
                Save-Module @ModuleCommandSplat
            }
        } catch {
            Write-Host "  - Failed to install $($Module.name) $RequiredVersion"
            throw
        }
    }

    $ImportedModule = Import-DLLPickleBuildTool -Name $Module.name -RequiredVersion $RequiredVersion
    Write-Host "  - $($ImportedModule.Name) $($ImportedModule.Version) ready"
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
