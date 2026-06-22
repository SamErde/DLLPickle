<#
.SYNOPSIS
    Asserts that bundled (preload) NuGet packages ship a net8.0-compatible assembly asset.

.DESCRIPTION
    Implements Step 0(b) of the tracked-dependency release lifecycle in docs/Architecture.md
    section 8.2: the explicit "TFM-alignment" inspection. The Build gate (Step 0(a)) proves a
    package restores and builds green under --locked-mode; this tool proves the complementary
    half - that each preload package actually contains a target-framework asset net8.0 can
    consume (net8.0 or a lower netX.0/netcoreapp asset, or a netstandard2.0/2.1/1.x asset),
    rather than appearing to work only by luck of transitive resolution.

    Two modes:
      - PackageDirectory: inspect a single extracted NuGet package directory (one with a lib/
        folder) and return its alignment result.
      - Policy: resolve the preload set from build/dependency-policy.json, the restored versions
        from packages.lock.json, locate each package under the NuGet global-packages folder, and
        return an aggregate report (optionally failing in -Strict mode).

    This is a focused subset of NuGet's compatibility model sufficient for the in-scope MSAL +
    IdentityModel families (all ship netstandard2.0 and/or net8.0); it is not a full resolver.

.PARAMETER PackageDirectory
    Path to a single extracted NuGet package directory (containing a lib/ folder) to inspect.

.PARAMETER PackageName
    Optional package name to report for the PackageDirectory mode. Defaults to the directory leaf.

.PARAMETER PolicyPath
    Path to the dependency policy JSON file (Policy mode).

.PARAMETER LockFilePath
    Path to packages.lock.json, used to resolve each preload package's restored version (Policy mode).

.PARAMETER PackagesRoot
    NuGet global-packages folder that holds the restored packages. Defaults to $env:NUGET_PACKAGES,
    then to ~/.nuget/packages (Policy mode).

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
    [string]$PackagesRoot,

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
        [string]$Name
    )

    if (-not $LockObject.dependencies) {
        return $null
    }

    # Prefer the net8.0 dependency group, then any other, when reading the resolved version.
    $Groups = @($LockObject.dependencies.PSObject.Properties |
            Sort-Object -Property { if ($_.Name -eq 'net8.0') { 0 } else { 1 } })

    foreach ($Group in $Groups) {
        $Entry = $Group.Value.PSObject.Properties | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
        if ($Entry) {
            return [string]$Entry.Value.resolved
        }
    }

    return $null
}

if ($PSCmdlet.ParameterSetName -eq 'PackageDirectory') {
    $ResolvedDirectory = (Resolve-Path -LiteralPath $PackageDirectory).Path
    Test-DLLPickleSinglePackageAlignment -PackagePath $ResolvedDirectory -Name $PackageName
    return
}

if ([string]::IsNullOrWhiteSpace($PackagesRoot)) {
    $PackagesRoot = if (-not [string]::IsNullOrWhiteSpace($env:NUGET_PACKAGES)) {
        $env:NUGET_PACKAGES
    } else {
        Join-Path -Path $HOME -ChildPath '.nuget' -AdditionalChildPath 'packages'
    }
}

$ResolvedPolicyPath = (Resolve-Path -LiteralPath $PolicyPath).Path
$ResolvedLockPath = (Resolve-Path -LiteralPath $LockFilePath).Path
$Policy = Get-Content -LiteralPath $ResolvedPolicyPath -Raw | ConvertFrom-Json
$Lock = Get-Content -LiteralPath $ResolvedLockPath -Raw | ConvertFrom-Json

$PackageResults = foreach ($Pin in @($Policy.preload)) {
    $Name = [string]$Pin.packageName
    $Version = Get-DLLPickleResolvedPackageVersion -LockObject $Lock -Name $Name

    if ([string]::IsNullOrWhiteSpace($Version)) {
        [PSCustomObject]@{
            PackageName      = $Name
            ResolvedVersion  = $null
            PackageDirectory = $null
            IsAligned        = $false
            CompatibleAssets = @()
            AvailableAssets  = @()
            Reason           = "No resolved version for '$Name' was found in '$ResolvedLockPath'."
        }
        continue
    }

    $PackagePath = Join-Path -Path $PackagesRoot -ChildPath $Name.ToLowerInvariant() -AdditionalChildPath $Version.ToLowerInvariant()
    Test-DLLPickleSinglePackageAlignment -PackagePath $PackagePath -Name $Name -ResolvedVersion $Version
}

$PackageResultArray = @($PackageResults)
$Misaligned = @($PackageResultArray | Where-Object { -not $_.IsAligned } | ForEach-Object { $_.PackageName })
$IsAligned = ($PackageResultArray.Count -gt 0) -and ($Misaligned.Count -eq 0)

$Report = [PSCustomObject]@{
    GeneratedAtUtc = [System.DateTimeOffset]::UtcNow.ToString('o')
    PolicyPath     = $ResolvedPolicyPath
    LockFilePath   = $ResolvedLockPath
    PackagesRoot   = $PackagesRoot
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
    throw ("TFM alignment check failed: the following preload package(s) ship no net8.0/netstandard2.0-compatible asset: {0}." -f ($Misaligned -join ', '))
}

$Report
