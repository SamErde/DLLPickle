<#
.SYNOPSIS
    Assert that every preload package resolves an assembly asset for every supported TFM.

.DESCRIPTION
    Implements Step 0(b) of the tracked-dependency release lifecycle. Policy mode reads NuGet's
    restored project.assets.json and verifies the actual compile/runtime asset selection for every
    preload package under net8.0, net9.0, and net10.0. It does not approximate NuGet compatibility
    with a handwritten TFM model.

    Two modes:
      - PackageDirectory: inspect a single extracted NuGet package directory (one with a lib/
        folder) and return its alignment result.
      - Policy: inspect NuGet's resolved target graph and selected assets for all supported TFMs,
        then return an aggregate report (optionally failing in -Strict mode).

.PARAMETER PackageDirectory
    Path to a single extracted NuGet package directory (containing a lib/ folder) to inspect.

.PARAMETER PackageName
    Optional package name to report for the PackageDirectory mode. Defaults to the directory leaf.

.PARAMETER PolicyPath
    Path to the dependency policy JSON file (Policy mode).

.PARAMETER LockFilePath
    Path to packages.lock.json, used to resolve each preload package's restored version (Policy mode).

.PARAMETER ProjectAssetsPath
    Restored NuGet project.assets.json used as the authority for TFM asset selection.

.PARAMETER OutputPath
    Optional path where the JSON alignment report is written (Policy mode).

.PARAMETER Strict
    Throw when any preload package is not TFM-aligned (Policy mode). Used by CI to fail closed.

.EXAMPLE
    ./tools/Test-DLLPickleTfmAlignment.ps1 -PackageDirectory ~/.nuget/packages/microsoft.identity.client/4.84.1

.EXAMPLE
    ./tools/Test-DLLPickleTfmAlignment.ps1 -OutputPath ./artifacts/upstreamCompatibility/tfm-alignment.json -Strict

.OUTPUTS
    PSCustomObject. A single package result (PackageDirectory mode) or an aggregate report (Policy mode).
#>

[CmdletBinding(DefaultParameterSetName = 'Policy')]
[OutputType([PSCustomObject])]
param(
    [Parameter(Mandatory, ParameterSetName = 'PackageDirectory')]
    [ValidateNotNullOrEmpty()]
    [string]$PackageDirectory,

    [Parameter(ParameterSetName = 'PackageDirectory')]
    [string]$PackageName,

    [Parameter(ParameterSetName = 'Policy')]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'build\dependency-policy.json'),

    [Parameter(ParameterSetName = 'Policy')]
    [ValidateNotNullOrEmpty()]
    [string]$LockFilePath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'src\DLLPickle.Build\packages.lock.json'),

    [Parameter(ParameterSetName = 'Policy')]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectAssetsPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'src\DLLPickle.Build\obj\project.assets.json'),

    [Parameter(ParameterSetName = 'Policy')]
    [string]$OutputPath,

    [Parameter(ParameterSetName = 'Policy')]
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'

function Test-DLLPickleTargetFrameworkCompatible {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$TargetFramework
    )

    $Moniker = ([string]$TargetFramework).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($Moniker)) {
        return $false
    }

    # Reject OS-specific TFMs (e.g. net8.0-windows, net8.0-browser, net8.0-android). DLLPickle's
    # bundle is validated as a PORTABLE net8.0 asset across Windows/Linux/macOS, so a package that
    # ships only an OS-specific asset has no portable asset to preload and is not Step 0b-aligned.
    if ($Moniker.Contains('-')) {
        return $false
    }

    # .NET Standard (1.x-2.1): loadable on net8.0.
    if ($Moniker -match '^netstandard\d+\.\d+$') {
        return $true
    }

    # .NET Core 1.x-3.1 (netcoreapp): consumable by net8.0.
    if ($Moniker -match '^netcoreapp\d+\.\d+$') {
        return $true
    }

    # .NET 5+ (netX.0, with a dot): consumable only up to the supported runtime major (8);
    # a net9.0+ asset references a newer runtime contract and is not loadable on net8.0.
    $NetCoreMatch = [regex]::Match($Moniker, '^net(\d+)\.\d+$')
    if ($NetCoreMatch.Success) {
        return ([int]$NetCoreMatch.Groups[1].Value -le 8)
    }

    # .NET Framework (net20-net48, no dot) is a different runtime, not loadable on net8.0.
    # Anything else (unknown/garbage monikers) is fail-closed.
    return $false
}

function Get-DLLPickleLibTargetFramework {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$PackagePath
    )

    $LibDirectory = Join-Path -Path $PackagePath -ChildPath 'lib'
    if (-not (Test-Path -LiteralPath $LibDirectory -PathType Container)) {
        return [PSCustomObject]@{ HasLib = $false; IsFlatLib = $false; TargetFrameworks = @() }
    }

    $AllSubdirectories = @(Get-ChildItem -LiteralPath $LibDirectory -Directory -ErrorAction SilentlyContinue)
    if ($AllSubdirectories.Count -eq 0) {
        # Legacy flat lib/ layout: assemblies placed directly under lib/ apply to any target framework.
        $FlatAssemblies = @(Get-ChildItem -LiteralPath $LibDirectory -Filter '*.dll' -File -ErrorAction SilentlyContinue)
        return [PSCustomObject]@{ HasLib = $true; IsFlatLib = ($FlatAssemblies.Count -gt 0); TargetFrameworks = @() }
    }

    # Only count a TFM folder as an available asset if it actually contains an assembly. An empty
    # folder or a NuGet `_._` placeholder is "compatible" to NuGet but ships nothing for DLLPickle
    # to preload, so it must not satisfy Step 0b.
    $PopulatedTfmDirectories = @($AllSubdirectories | Where-Object {
            @(Get-ChildItem -LiteralPath $_.FullName -Filter '*.dll' -File -ErrorAction SilentlyContinue).Count -gt 0
        })

    [PSCustomObject]@{
        HasLib           = $true
        IsFlatLib        = $false
        TargetFrameworks = @($PopulatedTfmDirectories | ForEach-Object { $_.Name })
    }
}

function Test-DLLPickleSinglePackageAlignment {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$PackagePath,

        [Parameter()]
        [string]$Name,

        [Parameter()]
        [string]$ResolvedVersion
    )

    $ResolvedName = if (-not [string]::IsNullOrWhiteSpace($Name)) { $Name } else { Split-Path -Path $PackagePath -Leaf }

    $Available = @()
    $Compatible = @()

    if (-not (Test-Path -LiteralPath $PackagePath -PathType Container)) {
        $IsAligned = $false
        $Reason = "Package directory '$PackagePath' was not found; cannot inspect TFM assets."
    } else {
        $Lib = Get-DLLPickleLibTargetFramework -PackagePath $PackagePath
        if (-not $Lib.HasLib) {
            $IsAligned = $false
            $Reason = 'No lib/ folder is present, so the package ships no net8.0/netstandard2.0 runtime asset.'
        } elseif ($Lib.IsFlatLib) {
            $IsAligned = $true
            $Available = @('lib')
            $Compatible = @('lib')
            $Reason = 'Legacy flat lib/ layout: assemblies apply to any target framework, including net8.0.'
        } else {
            $Available = @($Lib.TargetFrameworks)
            $Compatible = @($Available | Where-Object { Test-DLLPickleTargetFrameworkCompatible -TargetFramework $_ })
            if ($Compatible.Count -gt 0) {
                $IsAligned = $true
                $Reason = "net8.0-compatible asset(s) present: $($Compatible -join ', ')."
            } else {
                $IsAligned = $false
                $Reason = "No net8.0/netstandard2.0-compatible asset; lib/ ships only: $($Available -join ', ')."
            }
        }
    }

    [PSCustomObject]@{
        PackageName      = $ResolvedName
        ResolvedVersion  = $ResolvedVersion
        PackageDirectory = $PackagePath
        IsAligned        = $IsAligned
        CompatibleAssets = @($Compatible)
        AvailableAssets  = @($Available)
        Reason           = $Reason
    }
}

function Get-DLLPickleResolvedPackageVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object]$LockObject,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$TargetFramework
    )

    if (-not $LockObject.dependencies) {
        return $null
    }

    $Group = $LockObject.dependencies.PSObject.Properties | Where-Object Name -eq $TargetFramework | Select-Object -First 1
    if ($Group) {
        $Entry = $Group.Value.PSObject.Properties | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
        if ($Entry) { return [string]$Entry.Value.resolved }
    }

    return $null
}

if ($PSCmdlet.ParameterSetName -eq 'PackageDirectory') {
    $ResolvedDirectory = (Resolve-Path -LiteralPath $PackageDirectory).Path
    Test-DLLPickleSinglePackageAlignment -PackagePath $ResolvedDirectory -Name $PackageName
    return
}

$ResolvedPolicyPath = (Resolve-Path -LiteralPath $PolicyPath).Path
$ResolvedLockPath = (Resolve-Path -LiteralPath $LockFilePath).Path
$ResolvedProjectAssetsPath = (Resolve-Path -LiteralPath $ProjectAssetsPath).Path
$Policy = Get-Content -LiteralPath $ResolvedPolicyPath -Raw | ConvertFrom-Json
$Lock = Get-Content -LiteralPath $ResolvedLockPath -Raw | ConvertFrom-Json
$ProjectAssets = Get-Content -LiteralPath $ResolvedProjectAssetsPath -Raw | ConvertFrom-Json
$TargetFrameworks = if ($Policy.PSObject.Properties.Name -contains 'runtimeProfiles') {
    @($Policy.runtimeProfiles.targetFramework | Sort-Object -Unique)
} else {
    @($Lock.dependencies.PSObject.Properties.Name | Sort-Object -Unique)
}

$PackageResults = foreach ($TargetFramework in $TargetFrameworks) {
    $TargetGraphProperty = $ProjectAssets.targets.PSObject.Properties |
        Where-Object Name -eq $TargetFramework |
        Select-Object -First 1

    foreach ($Pin in @($Policy.preload)) {
        $Name = [string]$Pin.packageName
        $Version = Get-DLLPickleResolvedPackageVersion -LockObject $Lock -Name $Name -TargetFramework $TargetFramework
        $SelectedAssets = @()
        $Reason = $null

        if ([string]::IsNullOrWhiteSpace($Version)) {
            $Reason = "No resolved version for '$Name' was found in '$ResolvedLockPath' under '$TargetFramework'."
        } elseif (-not $TargetGraphProperty) {
            $Reason = "NuGet project.assets.json contains no restored target graph for '$TargetFramework'."
        } else {
            $PackageKey = '{0}/{1}' -f $Name, $Version
            $PackageProperty = $TargetGraphProperty.Value.PSObject.Properties |
                Where-Object Name -ieq $PackageKey |
                Select-Object -First 1
            if (-not $PackageProperty) {
                $Reason = "NuGet selected no '$PackageKey' entry for '$TargetFramework'."
            } else {
                $RuntimeAssets = if ($PackageProperty.Value.runtime) {
                    @($PackageProperty.Value.runtime.PSObject.Properties.Name | Where-Object { $_ -match '\.dll$' })
                } else {
                    @()
                }
                $CompileAssets = if ($PackageProperty.Value.compile) {
                    @($PackageProperty.Value.compile.PSObject.Properties.Name | Where-Object { $_ -match '\.dll$' })
                } else {
                    @()
                }
                $SelectedAssets = if ($RuntimeAssets.Count -gt 0) { $RuntimeAssets } else { $CompileAssets }
                if ($SelectedAssets.Count -gt 0) {
                    $Reason = "NuGet selected asset(s) for ${TargetFramework}: $($SelectedAssets -join ', ')."
                } else {
                    $Reason = "NuGet selected '$PackageKey' for '$TargetFramework' but no assembly compile/runtime asset."
                }
            }
        }

        [PSCustomObject]@{
            PackageName      = $Name
            ResolvedVersion  = $Version
            TargetFramework  = $TargetFramework
            IsAligned        = $SelectedAssets.Count -gt 0
            SelectedAssets   = @($SelectedAssets)
            CompatibleAssets = @($SelectedAssets)
            AvailableAssets  = @($SelectedAssets)
            Reason           = $Reason
        }
    }
}

$PackageResultArray = @($PackageResults)
$Misaligned = @($PackageResultArray | Where-Object { -not $_.IsAligned } | ForEach-Object { '{0}/{1}' -f $_.TargetFramework, $_.PackageName })
$IsAligned = ($PackageResultArray.Count -gt 0) -and ($Misaligned.Count -eq 0)

$Report = [PSCustomObject]@{
    GeneratedAtUtc = [System.DateTimeOffset]::UtcNow.ToString('o')
    PolicyPath     = $ResolvedPolicyPath
    LockFilePath   = $ResolvedLockPath
    ProjectAssetsPath = $ResolvedProjectAssetsPath
    TargetFrameworks = $TargetFrameworks
    IsAligned      = $IsAligned
    Packages       = $PackageResultArray
    Misaligned     = $Misaligned
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputDirectory = Split-Path -Path $OutputPath -Parent
    if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
    }
    $Report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}

if ($Strict.IsPresent -and -not $IsAligned) {
    throw ("TFM alignment check failed: NuGet selected no assembly asset for: {0}." -f ($Misaligned -join ', '))
}

$Report
