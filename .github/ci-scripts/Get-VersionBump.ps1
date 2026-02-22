<#
.SYNOPSIS
    Analyzes commits since the last tag and determines the appropriate semantic version bump.

.DESCRIPTION
    Examines conventional commit messages to determine if a major, minor, or patch version bump
    is needed. The base version is the higher of the module manifest version and the highest
    Git tag in the format "vX.Y.Z". Returns the bump type and the new version number.

.PARAMETER ManifestPath
    Path to the module manifest file. If not provided, uses "./src/DLLPickle/DLLPickle.psd1".

.PARAMETER ManualBump
    Optional parameter to manually specify the version bump type. Overrides automatic analysis.
    Valid values are 'major', 'minor', or 'patch'.

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
    [string]$ManifestPath = (Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot)) -ChildPath 'src\DLLPickle\DLLPickle.psd1'),

    # Optional manual version bump type to override automatic conventional commit analysis.
    [Parameter(Mandatory = $false)]
    [ValidateSet('major', 'minor', 'patch')]
    [string]$ManualBump
)

$ErrorActionPreference = 'Stop'
# Verify git is available
if (-not (Get-Command -Name 'git' -ErrorAction SilentlyContinue)) {
    throw 'Git is not installed or not available in the PATH.'
}

# Get the current module version from the manifest.
Write-Verbose "Using manifest path: $ManifestPath"
try {
    $Manifest = Import-PowerShellDataFile -Path $ManifestPath
    $ManifestVersion = [version]($Manifest.ModuleVersion)
    Write-Verbose "Manifest version: $ManifestVersion"
} catch {
    throw "Unable to read the current version from the module manifest. $_"
}

# Use the highest SemVer-like tag (vX.Y.Z) if present; otherwise use the manifest version.
$LastTag = $null
$TagVersion = $null
$Tags = @(git tag --list 'v*' --sort=-v:refname 2>$null)
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to list Git tags.'
}
foreach ($Tag in $Tags) {
    $ParsedVersion = $null
    if ([version]::TryParse($Tag.TrimStart('v', 'V'), [ref]$ParsedVersion)) {
        $LastTag = $Tag
        $TagVersion = $ParsedVersion
        break
    }
}

# Check for a valid SemVer tag and log the highest found. If none found, log that as well.
if ($TagVersion) {
    Write-Verbose "Highest SemVer tag: $LastTag ($TagVersion)"
} else {
    Write-Verbose 'No SemVer tags found in the format vX.Y.Z.'
}

# Determine the base version for bumping. Use the higher of the manifest version and the tag version.
$CurrentVersion = if ($TagVersion -and $TagVersion -gt $ManifestVersion) {
    $TagVersion
} else {
    $ManifestVersion
}
Write-Verbose "Base version for bumping: $CurrentVersion"

# Determine the version bump type. If a manual bump is specified, use that. Otherwise, analyze commits since the last tag.
if (-not [string]::IsNullOrEmpty($ManualBump)) {
    # Manually set the version bump type if specified. This overrides automatic analysis.
    Write-Verbose "Manual version bump specified: $ManualBump"
    $VersionBump = $ManualBump
    $ShouldRelease = $true
    $Commits = @()
} else {
    # Perform automatic version bump analysis based on commit messages since the last tag.
    # If no tag exists, use the initial commit.
    if (-not $LastTag) {
        Write-Verbose 'No previous tag found, using initial commit.'
        $LastTag = (git rev-list --max-parents=0 HEAD)
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to determine the initial commit.'
        }
    }
    Write-Verbose "Last tag: $LastTag"

    # Determine version bump type based on commits since last tag
    [string]$VersionBump = 'none'
    [bool]$ShouldRelease = $false

    # Get commits since last tag.
    [string[]]$Commits = @(git log "$LastTag..HEAD" --pretty=format:"%s" --no-merges 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to read Git commit history.'
    }
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
            Write-Verbose "Ignoring commit (not a conventional type): $Commit"
            continue
        }
    } # End of commit analysis loop
} # End of manual bump check

# Calculate new version based on the determined version bump type.
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

# Output the result object for use in subsequent steps.
$Result
