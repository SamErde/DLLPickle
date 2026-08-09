<#
.SYNOPSIS
Validates that a project-file update changes only existing package versions.

.DESCRIPTION
Compares trusted base and candidate project files after masking Version attribute
values on existing PackageReference elements. Package additions, removals,
conditions, metadata, properties, comments, and all other project content must
remain unchanged. At least one package version must change, and every new value
must use a numeric NuGet version or floating-version form.

.PARAMETER BaseProjectPath
Path to the trusted base-branch project file.

.PARAMETER CandidateProjectPath
Path to the candidate project file.

.OUTPUTS
System.Management.Automation.PSCustomObject
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$BaseProjectPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$CandidateProjectPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DLLPickleProjectSnapshot {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Project file was not found: $Path"
    }

    try {
        $Document = [System.Xml.Linq.XDocument]::Parse(
            (Get-Content -LiteralPath $Path -Raw),
            [System.Xml.Linq.LoadOptions]::PreserveWhitespace
        )
    } catch {
        throw "Project file '$Path' is not valid XML: $($_.Exception.Message)"
    }

    $PackageVersions = [ordered]@{}
    $PackageReferences = @($Document.Descendants() | Where-Object { $_.Name.LocalName -eq 'PackageReference' })
    if ($PackageReferences.Count -eq 0) {
        throw "Project file '$Path' contains no PackageReference elements."
    }

    foreach ($PackageReference in $PackageReferences) {
        $IdentityAttributes = @($PackageReference.Attributes() | Where-Object { $_.Name.LocalName -in @('Include', 'Update') })
        $VersionAttributes = @($PackageReference.Attributes() | Where-Object { $_.Name.LocalName -eq 'Version' })
        if ($IdentityAttributes.Count -ne 1 -or $VersionAttributes.Count -ne 1) {
            throw "Every PackageReference in '$Path' must have exactly one Include or Update attribute and one Version attribute."
        }

        $Identity = '{0}:{1}' -f $IdentityAttributes[0].Name.LocalName, $IdentityAttributes[0].Value
        if ($PackageVersions.Contains($Identity)) {
            throw "Project file '$Path' contains duplicate PackageReference identity '$Identity'."
        }
        if ([string]::IsNullOrWhiteSpace($VersionAttributes[0].Value)) {
            throw "PackageReference '$Identity' in '$Path' has no version value."
        }

        $PackageVersions[$Identity] = $VersionAttributes[0].Value
        $VersionAttributes[0].Value = '__DLLPICKLE_ALLOWED_VERSION__'
    }

    [pscustomobject]@{
        NormalizedProject = $Document.ToString([System.Xml.Linq.SaveOptions]::DisableFormatting)
        PackageVersions   = $PackageVersions
    }
}

$Base = Get-DLLPickleProjectSnapshot -Path $BaseProjectPath
$Candidate = Get-DLLPickleProjectSnapshot -Path $CandidateProjectPath
$BaseKeys = @($Base.PackageVersions.Keys)
$CandidateKeys = @($Candidate.PackageVersions.Keys)
if ($BaseKeys.Count -ne $CandidateKeys.Count -or
    @($BaseKeys | Where-Object { -not $Candidate.PackageVersions.Contains($_) }).Count -gt 0) {
    throw 'The candidate project adds, removes, or renames a PackageReference.'
}

$NuGetVersionExpressionPattern = '^(?:' +
    '\d+(?:\.\d+){0,3}(?:-[0-9A-Za-z](?:[0-9A-Za-z.-]*[0-9A-Za-z])?)?(?:\+[0-9A-Za-z](?:[0-9A-Za-z.-]*[0-9A-Za-z])?)?' +
    '|\d+(?:\.\d+){0,2}\.\*(?:-\*)?' +
    '|\d+(?:\.\d+){0,3}-(?:\*|[0-9A-Za-z](?:[0-9A-Za-z.-]*[0-9A-Za-z])?\.\*)' +
    '|\*|\*-\*' +
    ')$'
$ChangedPackages = @(
    foreach ($PackageKey in $BaseKeys) {
        $BaseVersion = [string]$Base.PackageVersions[$PackageKey]
        $CandidateVersion = [string]$Candidate.PackageVersions[$PackageKey]
        if ($BaseVersion -ne $CandidateVersion) {
            if ($CandidateVersion -notmatch $NuGetVersionExpressionPattern) {
                throw "PackageReference '$PackageKey' has unsupported candidate version '$CandidateVersion'."
            }
            $PackageKey
        }
    }
)
if ($ChangedPackages.Count -eq 0) {
    throw 'The candidate project does not change any PackageReference Version attribute.'
}

if (-not [string]::Equals($Base.NormalizedProject, $Candidate.NormalizedProject, [System.StringComparison]::Ordinal)) {
    throw 'The candidate project changes content other than PackageReference Version attribute values.'
}

[pscustomobject]@{
    IsVersionOnlyUpdate = $true
    ChangedPackages     = $ChangedPackages
}
