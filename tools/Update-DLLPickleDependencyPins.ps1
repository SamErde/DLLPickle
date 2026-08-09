<#
.SYNOPSIS
    Applies safe candidate dependency pin updates from upstream inventory.

.DESCRIPTION
    Reads an upstream compatibility inventory and dependency policy, compares
    preload rules with src/DLLPickle.Build/DLLPickle.csproj, updates supported
    package references when upstream module assembly identities require it, and
    writes a JSON candidate report. A preload entry whose versionPolicy is
    'minorPatchFloat' is written as a floating 'N.*' reference; otherwise an exact
    '[x.y.z]' reference is written. Blocked preload families are reported but not
    applied.

.PARAMETER InventoryPath
    One or more JSON reports produced by Get-DLLPickleUpstreamInventory.ps1. When
    profile-aware reports are supplied, every target framework is reconciled across
    its operating-system inventories before a common pin is changed.

.PARAMETER PolicyPath
    Path to the dependency policy JSON file.

.PARAMETER ProjectPath
    Path to src/DLLPickle.Build/DLLPickle.csproj.

.PARAMETER OutputPath
    Path where the JSON candidate report is written.

.PARAMETER Restore
    Runs dotnet restore --force-evaluate when a project file change is applied.

.EXAMPLE
    ./tools/Update-DLLPickleDependencyPins.ps1 -InventoryPath ./artifacts/upstream/inventory.json -Restore

.OUTPUTS
    PSCustomObject. The candidate update report that is also written as JSON.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$InventoryPath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'build/dependency-policy.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'src/DLLPickle.Build/DLLPickle.csproj'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'artifacts/upstreamCompatibility/candidate-report.json'),

    [Parameter()]
    [switch]$Restore
)

$ErrorActionPreference = 'Stop'

function ConvertTo-DLLPickleNuGetVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AssemblyVersion
    )

    $Version = [version]$AssemblyVersion
    if ($Version.Revision -eq 0) {
        return '{0}.{1}.{2}' -f $Version.Major, $Version.Minor, $Version.Build
    }

    return $Version.ToString()
}

function Get-DLLPickleCurrentPackageReference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]]$ProjectContent,

        [Parameter(Mandatory)]
        [string]$PackageName,

        [Parameter(Mandatory)]
        [string]$TargetFramework
    )

    function Test-DLLPickleTargetFrameworkCondition {
        param(
            [Parameter()]
            [AllowEmptyString()]
            [string]$Condition,

            [Parameter(Mandatory)]
            [string]$Framework
        )

        if ([string]::IsNullOrWhiteSpace($Condition) -or $Condition -notmatch '\$\(TargetFramework\)') {
            return $true
        }

        $ConditionMatch = [regex]::Match(
            $Condition,
            "^\s*'?\$\(TargetFramework\)'?\s*(?<operator>==|!=)\s*'(?<framework>[^']+)'\s*$"
        )
        if (-not $ConditionMatch.Success) {
            throw "Unsupported TargetFramework condition in PackageReference automation: $Condition"
        }

        $ConditionFramework = $ConditionMatch.Groups['framework'].Value
        if ($ConditionMatch.Groups['operator'].Value -eq '==') {
            return $Framework -eq $ConditionFramework
        }
        return $Framework -ne $ConditionFramework
    }

    $ResolvedReferences = [System.Collections.Generic.List[object]]::new()
    $ItemGroupCondition = $null
    for ($Index = 0; $Index -lt $ProjectContent.Count; $Index++) {
        $Line = $ProjectContent[$Index]
        if ($Line -match '<ItemGroup\b') {
            if ($null -ne $ItemGroupCondition) {
                throw 'Nested ItemGroup elements are not supported by dependency pin automation.'
            }
            $ItemGroupConditionMatch = [regex]::Match($Line, 'Condition\s*=\s*"([^"]*)"')
            $ItemGroupCondition = if ($ItemGroupConditionMatch.Success) { $ItemGroupConditionMatch.Groups[1].Value } else { '' }
        }

        $MatchesPackage = $Line -match ('Include="{0}"' -f [regex]::Escape($PackageName))
        $ReferenceConditionMatch = [regex]::Match($Line, 'Condition\s*=\s*"([^"]*)"')
        $ReferenceCondition = if ($ReferenceConditionMatch.Success) { $ReferenceConditionMatch.Groups[1].Value } else { '' }
        $MatchesTargetFramework = if ([string]::IsNullOrWhiteSpace($TargetFramework) -or $TargetFramework -eq '*') {
            $true
        } else {
            (Test-DLLPickleTargetFrameworkCondition -Condition $ItemGroupCondition -Framework $TargetFramework) -and
                (Test-DLLPickleTargetFrameworkCondition -Condition $ReferenceCondition -Framework $TargetFramework)
        }

        if ($MatchesPackage -and $MatchesTargetFramework) {
            $VersionMatch = [regex]::Match($Line, 'Version="([^"]+)"')
            if ($VersionMatch.Success) {
                $ResolvedReferences.Add([PSCustomObject]@{
                    Index   = $Index
                    Line    = $Line
                    Version = $VersionMatch.Groups[1].Value
                    ItemGroupCondition = $ItemGroupCondition
                    ReferenceCondition = $ReferenceCondition
                })
            }
        }

        if ($Line -match '</ItemGroup>') {
            $ItemGroupCondition = $null
        }
    }

    if ($ResolvedReferences.Count -gt 1) {
        throw "PackageReference '$PackageName' resolves ambiguously for target framework '$TargetFramework' at project lines $(@($ResolvedReferences.Index | ForEach-Object { $_ + 1 }) -join ', ')."
    }

    return @($ResolvedReferences)[0]
}

function ConvertTo-DLLPickleUpdatedPackageReferenceContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]]$ProjectContent,

        [Parameter(Mandatory)]
        [int]$Index,

        [Parameter(Mandatory)]
        [string]$NewVersion
    )

    $UpdatedContent = @($ProjectContent)
    $UpdatedContent[$Index] = [regex]::Replace($UpdatedContent[$Index], 'Version="[^"]+"', ('Version="{0}"' -f $NewVersion))
    $UpdatedContent
}

function Get-DLLPicklePinTargetFramework {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Pin
    )

    $TargetFrameworks = @(
        if ($Pin.PSObject.Properties.Name -contains 'targetFrameworks') {
            @($Pin.targetFrameworks)
        } elseif ($Pin.PSObject.Properties.Name -contains 'targetFramework') {
            @($Pin.targetFramework)
        }
    ) |
        ForEach-Object { [string]$_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique

    if ($TargetFrameworks.Count -eq 0) {
        throw "Dependency pin '$($Pin.packageName)' does not declare targetFrameworks."
    }

    return @($TargetFrameworks)
}

$ResolvedInventoryPaths = @($InventoryPath | ForEach-Object { (Resolve-Path -LiteralPath $_).Path } | Sort-Object -Unique)
$ResolvedPolicyPath = (Resolve-Path -LiteralPath $PolicyPath).Path
$ResolvedProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path

$Inventories = @(
    foreach ($ResolvedInventoryPath in $ResolvedInventoryPaths) {
        $Inventory = Get-Content -LiteralPath $ResolvedInventoryPath -Raw | ConvertFrom-Json
        [PSCustomObject]@{
            Path = $ResolvedInventoryPath
            Data = $Inventory
            ProfileKey = if ($Inventory.PSObject.Properties.Name -contains 'ProfileKey') { [string]$Inventory.ProfileKey } else { $null }
            TargetFramework = if ($Inventory.Profile -and $Inventory.Profile.PSObject.Properties.Name -contains 'TargetFramework') { [string]$Inventory.Profile.TargetFramework } else { $null }
        }
    }
)
$Policy = Get-Content -LiteralPath $ResolvedPolicyPath -Raw | ConvertFrom-Json
$ProjectContent = @(Get-Content -LiteralPath $ResolvedProjectPath)
$ProjectChanged = $false

$Changes = New-Object System.Collections.Generic.List[object]
$Warnings = New-Object System.Collections.Generic.List[string]

foreach ($Pin in @($Policy.preload)) {
    $TargetFrameworks = @(Get-DLLPicklePinTargetFramework -Pin $Pin)
    $SourceModuleLookup = @{}
    foreach ($SourceModule in @($Pin.sourceModules)) {
        $SourceModuleLookup[[string]$SourceModule] = $true
    }

    $TfmCandidates = [System.Collections.Generic.List[object]]::new()
    $CandidateResolutionFailed = $false
    foreach ($TargetFramework in $TargetFrameworks) {
        $RelevantInventories = @($Inventories | Where-Object {
                [string]::IsNullOrWhiteSpace($_.TargetFramework) -or $_.TargetFramework -eq $TargetFramework
            })
        if ($RelevantInventories.Count -eq 0) {
            $Warnings.Add("No upstream inventory was supplied for target framework '$TargetFramework'.")
            $CandidateResolutionFailed = $true
            continue
        }

        $PerInventoryCandidates = @(
            foreach ($InventoryRecord in $RelevantInventories) {
                $Candidates = @(
                    foreach ($Module in @($InventoryRecord.Data.Modules)) {
                        if (-not $SourceModuleLookup[[string]$Module.Name]) {
                            continue
                        }

                        foreach ($Assembly in @($Module.TrackedAssemblies)) {
                            if ([string]$Assembly.Name -eq [string]$Pin.assemblyName) {
                                [PSCustomObject]@{
                                    InventoryPath   = [string]$InventoryRecord.Path
                                    ProfileKey      = [string]$InventoryRecord.ProfileKey
                                    TargetFramework = $TargetFramework
                                    ModuleName      = [string]$Module.Name
                                    ModuleVersion   = [string]$Module.Version
                                    AssemblyName    = [string]$Assembly.Name
                                    AssemblyVersion = [string]$Assembly.Version
                                    PackageVersion  = ConvertTo-DLLPickleNuGetVersion -AssemblyVersion ([string]$Assembly.Version)
                                    RelativePath    = [string]$Assembly.RelativePath
                                }
                            }
                        }
                    }
                )
                if ($Candidates.Count -eq 0) {
                    $Warnings.Add(("No upstream assembly '{0}' was found for target framework '{1}' in source modules: {2}" -f $Pin.assemblyName, $TargetFramework, (@($Pin.sourceModules) -join ', ')))
                    $CandidateResolutionFailed = $true
                    continue
                }
                $Candidates | Sort-Object -Property { [version]$_.AssemblyVersion } -Descending | Select-Object -First 1
            }
        )
        if ($PerInventoryCandidates.Count -ne $RelevantInventories.Count) {
            $CandidateResolutionFailed = $true
            continue
        }

        $DistinctVersions = @($PerInventoryCandidates.PackageVersion | Sort-Object -Unique)
        $TfmCandidates.Add([PSCustomObject]@{
                TargetFramework        = $TargetFramework
                PackageVersion         = [string]($PerInventoryCandidates | Sort-Object -Property { [version]$_.PackageVersion } -Descending | Select-Object -First 1).PackageVersion
                CrossPlatformConsistent = $DistinctVersions.Count -eq 1
                ProfileCandidates      = @($PerInventoryCandidates)
            })
        if ($DistinctVersions.Count -ne 1) {
            $Warnings.Add(("Upstream assembly '{0}' resolves to inconsistent package versions for target framework '{1}': {2}. No automatic update was applied." -f $Pin.assemblyName, $TargetFramework, ($DistinctVersions -join ', ')))
        }
    }

    if ($CandidateResolutionFailed -or $TfmCandidates.Count -ne $TargetFrameworks.Count) {
        continue
    }

    $IsCapped = -not [string]::IsNullOrWhiteSpace([string]$Pin.maximumPackageVersion)
    if ($IsCapped) {
        $MaximumPackageVersion = [string]$Pin.maximumPackageVersion
        $HighestCandidateVersion = @($TfmCandidates.PackageVersion | Sort-Object { [version]$_ } -Descending)[0]
        $CappedTargetFrameworks = @($TfmCandidates | Where-Object { [version]$_.PackageVersion -gt [version]$MaximumPackageVersion } | ForEach-Object TargetFramework)
        if ($CappedTargetFrameworks.Count -gt 0) {
            $Warnings.Add((
                    "PackageReference '{0}' candidate '{1}' exceeds maximum '{2}' for target frameworks '{3}'; using maximum version." -f
                    $Pin.packageName,
                    $HighestCandidateVersion,
                    $MaximumPackageVersion,
                    ($CappedTargetFrameworks -join ', ')
                ))
        }
    }

    $VersionPolicy = if ($Pin.versionPolicy) { [string]$Pin.versionPolicy } else { 'exact' }
    foreach ($TfmCandidate in $TfmCandidates) {
        $TargetVersion = [string]$TfmCandidate.PackageVersion
        if ($IsCapped -and [version]$TargetVersion -gt [version]$MaximumPackageVersion) {
            $TargetVersion = $MaximumPackageVersion
        }
        # A capped float must be exact; otherwise restore could resolve above the cap.
        $TfmCandidate | Add-Member -NotePropertyName FormattedVersion -NotePropertyValue $(if ($VersionPolicy -eq 'minorPatchFloat' -and -not $IsCapped) {
                '{0}.*' -f ([version]$TargetVersion).Major
            } else {
                '[{0}]' -f $TargetVersion
            })
    }

    $CurrentReferences = @(
        foreach ($TargetFramework in $TargetFrameworks) {
            $Reference = Get-DLLPickleCurrentPackageReference -ProjectContent $ProjectContent -PackageName ([string]$Pin.packageName) -TargetFramework $TargetFramework
            [PSCustomObject]@{
                TargetFramework = $TargetFramework
                Reference       = $Reference
            }
        }
    )
    $MissingTargetFrameworks = @($CurrentReferences | Where-Object { -not $_.Reference } | Select-Object -ExpandProperty TargetFramework)

    if ($MissingTargetFrameworks.Count -gt 0) {
        $Warnings.Add(("PackageReference '{0}' was not found for target frameworks '{1}'; no automatic insert or partial update was attempted." -f $Pin.packageName, ($MissingTargetFrameworks -join ', ')))
        continue
    }

    $UniqueReferenceIndices = @($CurrentReferences.Reference.Index | Select-Object -Unique)
    $UsesConditionalReferences = $UniqueReferenceIndices.Count -gt 1
    $DistinctCandidateVersions = @($TfmCandidates.FormattedVersion | Sort-Object -Unique)
    $ConditionalPinRequired = $DistinctCandidateVersions.Count -gt 1 -and -not $UsesConditionalReferences
    $CrossPlatformConsistent = @($TfmCandidates | Where-Object { -not $_.CrossPlatformConsistent }).Count -eq 0
    $TfmResults = @(
        foreach ($CurrentReference in $CurrentReferences) {
            $TfmCandidate = @($TfmCandidates | Where-Object TargetFramework -EQ $CurrentReference.TargetFramework)[0]
            [PSCustomObject]@{
                TargetFramework  = [string]$CurrentReference.TargetFramework
                CurrentVersion   = [string]$CurrentReference.Reference.Version
                CandidateVersion = [string]$TfmCandidate.FormattedVersion
                ReferenceIndex   = [int]$CurrentReference.Reference.Index
                CrossPlatformConsistent = [bool]$TfmCandidate.CrossPlatformConsistent
                Applied          = $false
            }
        }
    )

    $AllProfileCandidates = @($TfmCandidates.ProfileCandidates)
    $TargetAssembly = $AllProfileCandidates | Sort-Object -Property { [version]$_.AssemblyVersion } -Descending | Select-Object -First 1

    $Change = [PSCustomObject]@{
        PackageName           = [string]$Pin.packageName
        TargetFrameworks      = @($TargetFrameworks)
        CurrentVersions       = @($CurrentReferences.Reference.Version | Select-Object -Unique)
        CandidateVersion      = if ($DistinctCandidateVersions.Count -eq 1) { [string]$DistinctCandidateVersions[0] } else { $null }
        CandidateVersions     = @($DistinctCandidateVersions)
        SourceModule          = [string]$TargetAssembly.ModuleName
        SourceModuleVersion   = [string]$TargetAssembly.ModuleVersion
        SourceAssemblyVersion = [string]$TargetAssembly.AssemblyVersion
        UsesConditionalReferences = $UsesConditionalReferences
        ConditionalPinRequired    = $ConditionalPinRequired
        CrossPlatformConsistent   = $CrossPlatformConsistent
        ReviewRequired            = $UsesConditionalReferences -or $ConditionalPinRequired -or -not $CrossPlatformConsistent
        TfmResults                = @($TfmResults)
        Applied               = $false
        Reason                = [string]$Pin.reason
    }

    if ($ConditionalPinRequired) {
        $Warnings.Add(("PackageReference '{0}' requires different versions by target framework ({1}); introducing conditional references requires maintainer review and was not automated." -f $Pin.packageName, ($DistinctCandidateVersions -join ', ')))
        $Changes.Add($Change)
        continue
    }
    if (-not $CrossPlatformConsistent) {
        $Changes.Add($Change)
        continue
    }

    foreach ($ReferenceIndex in $UniqueReferenceIndices) {
        $ReferencesAtIndex = @($CurrentReferences | Where-Object { $_.Reference.Index -eq $ReferenceIndex })
        $CurrentVersion = [string]$ReferencesAtIndex[0].Reference.Version
        $ReferenceCandidateVersions = @($TfmResults | Where-Object ReferenceIndex -EQ $ReferenceIndex | ForEach-Object CandidateVersion | Sort-Object -Unique)
        if ($ReferenceCandidateVersions.Count -ne 1) {
            throw "PackageReference '$($Pin.packageName)' maps one project entry to incompatible target-framework candidates."
        }
        $FormattedVersion = [string]$ReferenceCandidateVersions[0]
        if ($CurrentVersion -eq $FormattedVersion) {
            continue
        }

        $ReferenceTargetFrameworks = @($ReferencesAtIndex.TargetFramework)
        if ($PSCmdlet.ShouldProcess($ResolvedProjectPath, ("Update {0} for {1} from {2} to {3}" -f $Pin.packageName, ($ReferenceTargetFrameworks -join ', '), $CurrentVersion, $FormattedVersion))) {
            $ProjectContent = @(ConvertTo-DLLPickleUpdatedPackageReferenceContent -ProjectContent $ProjectContent -Index $ReferenceIndex -NewVersion $FormattedVersion)
            $ProjectChanged = $true
            $Change.Applied = $true
            foreach ($TfmResult in @($Change.TfmResults | Where-Object { $_.ReferenceIndex -eq $ReferenceIndex })) {
                $TfmResult.Applied = $true
            }
        }
    }

    $Changes.Add($Change)
}

$BlockedFindings = @(
    foreach ($BlockedAssembly in @($Policy.blockedPreloadAssemblies)) {
        foreach ($InventoryRecord in $Inventories) {
            foreach ($Module in @($InventoryRecord.Data.Modules)) {
                foreach ($Assembly in @($Module.TrackedAssemblies)) {
                    if ([string]$Assembly.Name -eq [string]$BlockedAssembly.assemblyName) {
                        [PSCustomObject]@{
                            AssemblyName  = [string]$Assembly.Name
                            Version       = [string]$Assembly.Version
                            ModuleName    = [string]$Module.Name
                            ModuleVersion = [string]$Module.Version
                            RelativePath  = [string]$Assembly.RelativePath
                            ProfileKey    = [string]$InventoryRecord.ProfileKey
                            TargetFrameworks = @($BlockedAssembly.targetFrameworks)
                            Action        = [string]$BlockedAssembly.updateMode
                            Reason        = [string]$BlockedAssembly.reason
                        }
                    }
                }
            }
        }
    }
)

if ($ProjectChanged) {
    Set-Content -LiteralPath $ResolvedProjectPath -Value $ProjectContent -Encoding UTF8

    if ($Restore.IsPresent) {
        $ProjectDirectory = Split-Path -Path $ResolvedProjectPath -Parent
        Push-Location -LiteralPath $ProjectDirectory
        try {
            dotnet restore $ResolvedProjectPath --force-evaluate
            if ($LASTEXITCODE -ne 0) {
                throw "dotnet restore failed with exit code $LASTEXITCODE."
            }
        } finally {
            Pop-Location
        }
    }
}

$Report = [PSCustomObject]@{
    GeneratedAtUtc   = [System.DateTimeOffset]::UtcNow.ToString('o')
    InventoryPaths   = @($ResolvedInventoryPaths)
    PolicyPath       = $ResolvedPolicyPath
    ProjectPath      = $ResolvedProjectPath
    ProjectChanged   = $ProjectChanged
    ReviewRequired   = @($Changes | Where-Object ReviewRequired).Count -gt 0
    Changes          = @($Changes.ToArray())
    BlockedFindings  = @($BlockedFindings)
    Warnings         = @($Warnings.ToArray())
}

$OutputDirectory = Split-Path -Path $OutputPath -Parent
if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
}

$Report |
    ConvertTo-Json -Depth 20 |
    Set-Content -LiteralPath $OutputPath -Encoding UTF8

$Report
