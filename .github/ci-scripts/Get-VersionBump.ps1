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
    - CurrentVersion: Version object with the current version from the manifest
    - CommitsSinceLastTag: Integer count of commits since last tag
    - CommitMessages: Array of commit messages since last tag

    .EXAMPLE
    $Result = & .\.github\scripts\Get-VersionBump.ps1
    if ($Result.ShouldRelease) {
        Write-Host "New version: $($Result.NewVersion)"
    }
#>

[CmdletBinding()]
[OutputType([PSCustomObject])]
param(
    # Path to the module manifest. Defaults to "../../src/DLLPickle/DLLPickle.psd1"
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ManifestPath = [System.IO.Path]::Join( (Split-Path -Path (Split-Path -Path $PSScriptRoot)), 'src', 'DLLPickle', 'DLLPickle.psd1' )
)

$ErrorActionPreference = 'Stop'
# Verify git is available
if (-not (Get-Command -Name 'git' -ErrorAction SilentlyContinue)) {
    Write-Error 'Git is not installed or not available in the PATH.'
    exit 1
}

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

# Determine version bump type based on commits since last tag
[string]$VersionBump = 'none'
[bool]$ShouldRelease = $false

# Get commits since last tag.
[string[]]$Commits = @(git log "$LastTag..HEAD" --pretty=format:"%s" --no-merges 2>$null)
foreach ($Commit in $Commits) {
    # Analyze commit message for conventional commit types.
    if ($Commit -match '^BREAKING CHANGE:|^breaking:|major-release') {
        # Check for breaking changes. Set as major and stop checking further commits.
        $VersionBump = 'major'
        $ShouldRelease = $true
        break
    } elseif ($Commit -match '^(feat|minor)(\(.+\))?:') {
        # Check for features. Set as minor if not already major.
        if ($VersionBump -ne 'major') {
            $VersionBump = 'minor'
            $ShouldRelease = $true
        }
    } elseif ($Commit -match '^(fix|perf|refactor|security|chore)(\(.+\))?:') {
        # Check for fixes. Set as patch if not already major or minor.
        if ($VersionBump -ne 'major' -and $VersionBump -ne 'minor') {
            $VersionBump = 'patch'
            $ShouldRelease = $true
        }
    } else {
        # Ignore other commit types (docs, style, etc.) for version bumping.
        Write-Host "Ignoring commit (not a conventional type): $Commit" -ForegroundColor DarkGray
        continue
    }
}

# Calculate new version
$NewVersion = switch ($VersionBump) {
    'major' { [version]::new($CurrentVersion.Major + 1, 0, 0) }
    'minor' { [version]::new($CurrentVersion.Major, $CurrentVersion.Minor + 1, 0) }
    'patch' { [version]::new($CurrentVersion.Major, $CurrentVersion.Minor, $CurrentVersion.Build + 1) }
    'none' { $CurrentVersion }
}

# Create the result object.
[PSCustomObject]$Result = @{
    ShouldRelease       = $ShouldRelease
    NewVersionType      = $VersionBump
    NewVersion          = $NewVersion
    CurrentVersion      = $CurrentVersion
    CommitsSinceLastTag = $Commits.Count
    CommitMessages      = $Commits
}

$Result
