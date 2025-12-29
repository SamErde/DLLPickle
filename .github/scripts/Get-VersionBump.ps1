<#
.SYNOPSIS
    Analyzes commits since the last tag and determines the appropriate semantic version bump.

.DESCRIPTION
    Examines conventional commit messages to determine if a major, minor, or patch version bump
    is needed. Returns the bump type and the new version number.

.PARAMETER ManifestPath
    Path to the module manifest file. If not provided, uses "./src/DLLPickle/DLLPickle.psd1".

.OUTPUTS
    PSCustomObject with properties:
    - ShouldRelease: Boolean indicating if a release should proceed
    - NewVersionType: String indicating bump type ('major', 'minor', 'patch', 'none')
    - NewVersion: Version object with the calculated new version
    - CommitsSinceLastTag: Array of commit messages since last tag

.EXAMPLE
    $Result = & .\.github\scripts\Get-VersionBump.ps1
    if ($Result.ShouldRelease) {
        Write-Host "New version: $($Result.NewVersion)"
    }
#>

param(
    # Path to the module manifest. Defaults to "../../src/DLLPickle/DLLPickle.psd1"
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ManifestPath = [System.IO.Path]::Join( (Split-Path -Path (Split-Path -Path $PSScriptRoot)), 'src', 'DLLPickle', 'DLLPickle.psd1' )
)

$ErrorActionPreference = 'Stop'

# Get the current module version from the manifest.
Write-Host "Using manifest path: $ManifestPath" -ForegroundColor Cyan
try {
    $Manifest = Import-PowerShellDataFile -Path $ManifestPath
    $CurrentVersion = [version]($Manifest.ModuleVersion)
    Write-Host "Current version: $CurrentVersion" -ForegroundColor Cyan
} catch {
    Write-Error "Unable to read the current version from the module manifest. $_"
    exit 1
}

# Get the last tag. If no tag exists, use the initial commit.
$LastTag = git describe --tags --abbrev=0 2>$null
if (-not $LastTag) {
    Write-Host 'No previous tag found, using initial commit.' -ForegroundColor Yellow
    $LastTag = (git rev-list --max-parents=0 HEAD)
}
Write-Host "Last tag: $LastTag" -ForegroundColor Cyan

# Get commits since last tag.
$Commits = git log "$LastTag..HEAD" --pretty=format:"%s" 2>$null
# If no commits found, set "ShouldRelease" to false and exit.
if (-not $Commits) {
    Write-Host 'No new commits since last tag'
    $Result = @{
        ShouldRelease       = $false
        NewVersionType         = 'none'
        NewVersion          = $CurrentVersion
        CommitsSinceLastTag = @()
    }
    Write-Output ([PSCustomObject]$Result)
    exit 0
}

# Ensure commits is an array.
if ($Commits -is [string]) {
    $Commits = @($Commits)
}

Write-Host "`nCommits since last tag:"
$Commits | ForEach-Object { Write-Host "  $_" }

# Analyze conventional commit message prefix to determine version bump.
$HasMajor = $false
$HasMinor = $false
$HasPatch = $false

foreach ($Commit in $Commits) {
    # Check for breaking changes
    if ($Commit -match '^BREAKING CHANGE:|^breaking:|major-release') {
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
    # Other conventional commit types (chore, docs, style, refactor, perf).
    elseif ($Commit -match '^(chore|docs|style|refactor|perf)(\(.+\))?:') {
        $HasPatch = $true
    }
    # Ignore other commit types (test, ci, build, etc.)
    else {
        Write-Host "Ignoring commit (not a conventional type): $Commit" -ForegroundColor DarkGray
    }
}

# Determine version bump type and number.
$NewVersionType = 'none'
$NewVersion = $CurrentVersion

if ($HasMajor) {
    $NewVersion = [version]::new($CurrentVersion.Major + 1, 0, 0)
    $NewVersionType = 'major'
} elseif ($HasMinor) {
    $NewVersion = [version]::new($CurrentVersion.Major, $CurrentVersion.Minor + 1, 0)
    $NewVersionType = 'minor'
} elseif ($HasPatch) {
    $NewVersion = [version]::new($CurrentVersion.Major, $CurrentVersion.Minor, $CurrentVersion.Build + 1)
    $NewVersionType = 'patch'
} else {
    Write-Host 'No version bump needed (no relevant conventional commits found).' -ForegroundColor Yellow
    $Result = @{
        ShouldRelease       = $false
        NewVersionType         = 'none'
        NewVersion          = $CurrentVersion
        CommitsSinceLastTag = $Commits
    }
    Write-Output ([PSCustomObject]$Result)
    exit 0
}

Write-Host "`nNew version type: $NewVersionType"
Write-Host "New version: $NewVersion"

$Result = @{
    ShouldRelease       = $true
    NewVersionType         = $NewVersionType
    NewVersion          = $NewVersion
    CommitsSinceLastTag = $Commits
}

Write-Output ([PSCustomObject]$Result)
