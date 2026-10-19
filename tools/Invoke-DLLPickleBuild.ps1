<#
.SYNOPSIS
    Runs DLLPickle build tasks with the repository-pinned InvokeBuild version.

.DESCRIPTION
    Loads the exact InvokeBuild version declared in build/build-tool-versions.json
    and invokes the requested tasks. Run this script from a fresh, non-profile
    PowerShell process so previously loaded build-tool assemblies cannot affect it.

.PARAMETER Task
    One or more InvokeBuild task names. The default runs the build file's default task.

.PARAMETER BuildFile
    Path to the InvokeBuild build file.

.PARAMETER ToolPolicyPath
    Path to the exact build-tool version policy.

.EXAMPLE
    pwsh -NoProfile -NonInteractive -File ./tools/Invoke-DLLPickleBuild.ps1 -Task TestLocal

.OUTPUTS
    None.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Task = @('.'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$BuildFile = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'build/DLLPickle.Build.ps1'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ToolPolicyPath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'build/build-tool-versions.json')
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$ToolingScriptPath = Join-Path -Path $RepositoryRoot -ChildPath 'build/DLLPickle.Tooling.ps1'
. $ToolingScriptPath

$ToolPolicy = Get-DLLPickleBuildToolPolicy -Path $ToolPolicyPath
$InvokeBuildVersion = Get-DLLPickleBuildToolVersion -Policy $ToolPolicy -Name 'InvokeBuild'
$null = Import-DLLPickleBuildTool -Name 'InvokeBuild' -RequiredVersion $InvokeBuildVersion

$InvokeBuildCommand = Get-Command -Name 'Invoke-Build' -Module 'InvokeBuild' -ErrorAction Stop
& $InvokeBuildCommand -Task $Task -File $BuildFile
