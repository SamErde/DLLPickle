<#
.SYNOPSIS
    Analyzes commits since the last tag and determines the appropriate semantic version bump.

.DESCRIPTION
    Examines conventional commit messages to determine if a major, minor, or patch version bump
    is needed. Returns the bump type and the new version number.

.PARAMETER CheckVersion
    The current version string (e.g., "1.2.3").

.PARAMETER ManifestPath
    Path to the module manifest file. If not provided, uses "./src/DLLPickle/DLLPickle.psd1".

.OUTPUTS
    PSCustomObject with properties:
    - ShouldRelease: Boolean indicating if a release should proceed
    - VersionBump: String indicating bump type ('major', 'minor', 'patch', 'none')
    - NewVersion: Version object with the calculated new version
    - CommitsSinceLastTag: Array of commit messages since last tag

.EXAMPLE
    $Result = & .\.github\scripts\Get-VersionBump.ps1 -CheckVersion "1.2.3"
    if ($Result.ShouldRelease) {
        Write-Host "New version: $($Result.NewVersion)"
    }
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$CheckVersion,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ManifestPath = './src/DLLPickle/DLLPickle.psd1'
)

$ErrorActionPreference = 'Stop'

# If CheckVersion not provided, read from manifest
if ([string]::IsNullOrEmpty($CheckVersion)) {
    if (-not (Test-Path $ManifestPath)) {
        throw "Manifest file not found at $ManifestPath"
    }
    $Manifest = Import-PowerShellDataFile -Path $ManifestPath
    $CheckVersion = $Manifest.ModuleVersion
}

$CheckVersion = [version]$CheckVersion
Write-Host "Current version: $CheckVersion"

# Get the last tag
$LastTag = git describe --tags --abbrev=0 2>$null
if (-not $LastTag) {
    Write-Host 'No previous tag found, using initial commit'
    $LastTag = (git rev-list --max-parents=0 HEAD)
}
Write-Host "Last tag: $LastTag"

# Get commits since last tag
$Commits = git log "$LastTag..HEAD" --pretty=format:"%s" 2>$null
if (-not $Commits) {
    Write-Host 'No new commits since last tag'
    $Result = @{
        ShouldRelease       = $false
        VersionBump         = 'none'
        NewVersion          = $CheckVersion
        CommitsSinceLastTag = @()
    }
    Write-Output ([PSCustomObject]$Result)
    exit 0
}

# Ensure commits is an array
if ($Commits -is [string]) {
    $Commits = @($Commits)
}

Write-Host "`nCommits since last tag:"
$Commits | ForEach-Object { Write-Host "  $_" }

# Analyze conventional commits to determine version bump
$HasMajor = $false
$HasMinor = $false
$HasPatch = $false

foreach ($Commit in $Commits) {
    # Check for breaking changes
    if ($Commit -match 'BREAKING CHANGE:|!:|^breaking') {
        $HasMajor = $true
    }
    # Check for features
    elseif ($Commit -match '^feat(\(.+\))?:') {
        $HasMinor = $true
    }
    # Check for fixes
    elseif ($Commit -match '^fix(\(.+\))?:') {
        $HasPatch = $true
    }
    # Other conventional commit types (chore, docs, style, refactor, perf, test)
    elseif ($Commit -match '^(chore|docs|style|refactor|perf|test)(\(.+\))?:') {
        $HasPatch = $true
    }
}

# Determine version bump
$VersionBump = 'none'
$NewVersion = $CheckVersion

if ($HasMajor) {
    $NewVersion = [version]::new($CheckVersion.Major + 1, 0, 0)
    $VersionBump = 'major'
} elseif ($HasMinor) {
    $NewVersion = [version]::new($CheckVersion.Major, $CheckVersion.Minor + 1, 0)
    $VersionBump = 'minor'
} elseif ($HasPatch) {
    $NewVersion = [version]::new($CheckVersion.Major, $CheckVersion.Minor, $CheckVersion.Build + 1)
    $VersionBump = 'patch'
} else {
    Write-Host 'No version bump needed (no conventional commits found)'
    $Result = @{
        ShouldRelease       = $false
        VersionBump         = 'none'
        NewVersion          = $CheckVersion
        CommitsSinceLastTag = $Commits
    }
    Write-Output ([PSCustomObject]$Result)
    exit 0
}

Write-Host "`nVersion bump: $VersionBump"
Write-Host "New version: $NewVersion"

$Result = @{
    ShouldRelease       = $true
    VersionBump         = $VersionBump
    NewVersion          = $NewVersion
    CommitsSinceLastTag = $Commits
}

Write-Output ([PSCustomObject]$Result)
