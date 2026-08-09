<#
.SYNOPSIS
    Verifies the supported-profile composition of the built DLLPickle module.

.DESCRIPTION
    Asserts that the module contains exactly the target-framework directories declared
    by the shipped runtime policy, that each directory matches the build output used by
    the packaging task, and that optional multi-pwsh test tooling is absent from the
    artifact and runtime/build dependency declarations.

.PARAMETER ModulePath
    Built module directory to inspect.

.PARAMETER BuildOutputRoot
    Root containing one Release build-output directory per target framework.

.PARAMETER Strict
    Throw when any composition finding is present.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ModulePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'module\DLLPickle'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$BuildOutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\DLLPickle.Build\bin\Release'),

    [Parameter()]
    [switch]$SkipBuildOutputComparison,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SupportPolicyPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\DLLPickle\SupportedRuntimeProfiles.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\DLLPickle.Build\DLLPickle.csproj'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LockFilePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\DLLPickle.Build\packages.lock.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\package\artifact-composition.json'),

    [Parameter()]
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
$Findings = [System.Collections.Generic.List[object]]::new()

function Add-DLLPickleArtifactFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Code,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [string]$TargetFramework
    )

    $Findings.Add([PSCustomObject]@{
            Code            = $Code
            TargetFramework = $TargetFramework
            Message         = $Message
        })
}

function Get-DLLPickleRelativeFileSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.IO.FileInfo[]]$Files
    )

    @(
        foreach ($File in $Files) {
            [System.IO.Path]::GetRelativePath($Root, $File.FullName).Replace('\', '/')
        }
    ) | Sort-Object -Unique
}

$RequiredPaths = @($ModulePath, $SupportPolicyPath, $ProjectPath, $LockFilePath)
if (-not $SkipBuildOutputComparison.IsPresent) {
    $RequiredPaths += $BuildOutputRoot
}
foreach ($RequiredPath in $RequiredPaths) {
    if (-not (Test-Path -LiteralPath $RequiredPath)) {
        throw "Required package-inspection path was not found: $RequiredPath"
    }
}

$ResolvedModulePath = (Resolve-Path -LiteralPath $ModulePath).Path
$ResolvedBuildOutputRoot = if ($SkipBuildOutputComparison.IsPresent) { $null } else { (Resolve-Path -LiteralPath $BuildOutputRoot).Path }
$SupportPolicy = Get-Content -LiteralPath $SupportPolicyPath -Raw | ConvertFrom-Json -ErrorAction Stop
$ExpectedTargetFrameworks = @($SupportPolicy.profiles.targetFramework | ForEach-Object { [string]$_ } | Sort-Object -Unique)
if ($ExpectedTargetFrameworks.Count -eq 0) {
    throw 'The shipped support policy does not declare any target frameworks.'
}

$BinPath = Join-Path $ResolvedModulePath 'bin'
if (-not (Test-Path -LiteralPath $BinPath -PathType Container)) {
    Add-DLLPickleArtifactFinding -Code 'MissingBinDirectory' -Message "Module bin directory was not found: $BinPath"
    $ActualTargetFrameworks = @()
} else {
    $ActualTargetFrameworks = @(Get-ChildItem -LiteralPath $BinPath -Directory | Select-Object -ExpandProperty Name | Sort-Object -Unique)
}

foreach ($TargetFramework in $ExpectedTargetFrameworks) {
    if ($TargetFramework -notin $ActualTargetFrameworks) {
        Add-DLLPickleArtifactFinding -Code 'MissingTargetFramework' -TargetFramework $TargetFramework -Message "Expected target-framework directory '$TargetFramework' is absent from the module artifact."
    }
}
foreach ($TargetFramework in $ActualTargetFrameworks) {
    if ($TargetFramework -notin $ExpectedTargetFrameworks) {
        Add-DLLPickleArtifactFinding -Code 'UnexpectedTargetFramework' -TargetFramework $TargetFramework -Message "Unexpected target-framework directory '$TargetFramework' is present in the module artifact."
    }
}

$ProfileResults = @(
    foreach ($TargetFramework in $ExpectedTargetFrameworks) {
        $ArtifactTfmPath = Join-Path $BinPath $TargetFramework
        $BuildTfmPath = if ($ResolvedBuildOutputRoot) { Join-Path $ResolvedBuildOutputRoot $TargetFramework } else { $null }
        if (-not (Test-Path -LiteralPath $ArtifactTfmPath -PathType Container) -or ($BuildTfmPath -and -not (Test-Path -LiteralPath $BuildTfmPath -PathType Container))) {
            if ($BuildTfmPath -and -not (Test-Path -LiteralPath $BuildTfmPath -PathType Container)) {
                Add-DLLPickleArtifactFinding -Code 'MissingBuildOutput' -TargetFramework $TargetFramework -Message "Build output for '$TargetFramework' was not found at '$BuildTfmPath'."
            }
            continue
        }

        $ActualDlls = @(Get-ChildItem -LiteralPath $ArtifactTfmPath -File -Filter '*.dll' | Select-Object -ExpandProperty Name | Sort-Object -Unique)
        if ($ActualDlls.Count -eq 0) {
            Add-DLLPickleArtifactFinding -Code 'EmptyTargetFramework' -TargetFramework $TargetFramework -Message "Target-framework directory '$TargetFramework' contains no managed assemblies."
        }
        if (-not $SkipBuildOutputComparison.IsPresent) {
            $ExpectedDlls = @(Get-ChildItem -LiteralPath $BuildTfmPath -File -Filter '*.dll' | Where-Object Name -Match '^(Azure\.|Microsoft\.|System\.)' | Select-Object -ExpandProperty Name | Sort-Object -Unique)
            foreach ($Name in @($ExpectedDlls | Where-Object { $_ -notin $ActualDlls })) {
                Add-DLLPickleArtifactFinding -Code 'MissingManagedAsset' -TargetFramework $TargetFramework -Message "Expected managed asset '$Name' is absent."
            }
            foreach ($Name in @($ActualDlls | Where-Object { $_ -notin $ExpectedDlls })) {
                Add-DLLPickleArtifactFinding -Code 'UnexpectedManagedAsset' -TargetFramework $TargetFramework -Message "Managed asset '$Name' is not present in the packaging build output."
            }
        }

        $BuildRuntimePath = if ($BuildTfmPath) { Join-Path $BuildTfmPath 'runtimes' } else { $null }
        $ArtifactRuntimePath = Join-Path $ArtifactTfmPath 'runtimes'
        $ExpectedNativeFiles = if ($BuildRuntimePath -and (Test-Path -LiteralPath $BuildRuntimePath -PathType Container)) {
            Get-DLLPickleRelativeFileSet -Root $BuildRuntimePath -Files @(Get-ChildItem -LiteralPath $BuildRuntimePath -File -Recurse | Where-Object FullName -Match '[\\/]native[\\/]')
        } else {
            @()
        }
        $ActualNativeFiles = if (Test-Path -LiteralPath $ArtifactRuntimePath -PathType Container) {
            Get-DLLPickleRelativeFileSet -Root $ArtifactRuntimePath -Files @(Get-ChildItem -LiteralPath $ArtifactRuntimePath -File -Recurse)
        } else {
            @()
        }
        if (-not $SkipBuildOutputComparison.IsPresent) {
            foreach ($Name in @($ExpectedNativeFiles | Where-Object { $_ -notin $ActualNativeFiles })) {
                Add-DLLPickleArtifactFinding -Code 'MissingNativeAsset' -TargetFramework $TargetFramework -Message "Expected native asset '$Name' is absent."
            }
            foreach ($Name in @($ActualNativeFiles | Where-Object { $_ -notin $ExpectedNativeFiles })) {
                Add-DLLPickleArtifactFinding -Code 'UnexpectedNativeAsset' -TargetFramework $TargetFramework -Message "Native asset '$Name' is not present in the packaging build output."
            }
        }

        [PSCustomObject]@{
            TargetFramework = $TargetFramework
            ManagedAssets   = @($ActualDlls)
            NativeAssets    = @($ActualNativeFiles)
        }
    }
)

$ForbiddenPattern = '(?i)multi[-_ ]?pwsh'
$ForbiddenHits = [System.Collections.Generic.List[object]]::new()
$ArtifactFiles = @(Get-ChildItem -LiteralPath $ResolvedModulePath -File -Recurse)
foreach ($File in $ArtifactFiles) {
    $RelativePath = [System.IO.Path]::GetRelativePath($ResolvedModulePath, $File.FullName).Replace('\', '/')
    if ($RelativePath -match $ForbiddenPattern) {
        $ForbiddenHits.Add([PSCustomObject]@{ Source = 'ArtifactPath'; Path = $RelativePath })
    }

    if ($File.Extension -in @('.ps1', '.psm1', '.psd1', '.ps1xml', '.json', '.xml', '.txt', '.md', '.config')) {
        if ((Get-Content -LiteralPath $File.FullName -Raw -ErrorAction Stop) -match $ForbiddenPattern) {
            $ForbiddenHits.Add([PSCustomObject]@{ Source = 'ArtifactContent'; Path = $RelativePath })
        }
    }
}
foreach ($DeclarationPath in @($ProjectPath, $LockFilePath, (Join-Path $ResolvedModulePath 'DLLPickle.psd1'))) {
    if ((Get-Content -LiteralPath $DeclarationPath -Raw -ErrorAction Stop) -match $ForbiddenPattern) {
        $ForbiddenHits.Add([PSCustomObject]@{ Source = 'DependencyDeclaration'; Path = $DeclarationPath })
    }
}
foreach ($Hit in $ForbiddenHits) {
    Add-DLLPickleArtifactFinding -Code 'ForbiddenMultiPwshReference' -Message "Forbidden multi-pwsh reference detected in $($Hit.Source): $($Hit.Path)"
}

$Report = [PSCustomObject]@{
    SchemaVersion            = 1
    GeneratedAtUtc           = [System.DateTimeOffset]::UtcNow.ToString('o')
    ModulePath               = $ResolvedModulePath
    ExpectedTargetFrameworks = @($ExpectedTargetFrameworks)
    ActualTargetFrameworks   = @($ActualTargetFrameworks)
    Profiles                 = @($ProfileResults)
    ForbiddenHits            = @($ForbiddenHits)
    Findings                 = @($Findings)
    Passed                   = $Findings.Count -eq 0
}

$OutputDirectory = Split-Path -Path $OutputPath -Parent
if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
}
$Report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

if ($Strict.IsPresent -and -not $Report.Passed) {
    throw "DLLPickle artifact inspection failed: $($Findings.Message -join ' ')"
}

$Report
