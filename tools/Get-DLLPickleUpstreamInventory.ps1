<#
.SYNOPSIS
    Builds an assembly inventory for upstream PowerShell modules.

.DESCRIPTION
    Reads build/dependency-policy.json, resolves the newest monitored module release
    compatible with the exact tested PowerShell line, and launches that explicit stock
    executable to capture only the tracked assembly assets actually selected at runtime.
    The report records the PowerShell/CLR/TFM/OS profile, umbrella and constituent module,
    assembly identity, hash, path, and load context.

.PARAMETER PolicyPath
    Path to the dependency policy JSON file.

.PARAMETER OutputPath
    Path where the JSON inventory report is written.

.PARAMETER ModuleCachePath
    Directory used to save or read upstream PowerShell modules.

.PARAMETER ModuleName
    Optional subset of policy modules to inventory.

.PARAMETER SkipDownload
    Uses modules already present in ModuleCachePath instead of calling
    Find-Module and Save-Module.

.PARAMETER Force
    Removes any existing saved copy before downloading a module.

.PARAMETER PowerShellExecutable
    Exact stock pwsh/pwsh.exe used for runtime asset selection.

.PARAMETER TestMatrixPath
    Canonical exact servicing-patch and profile matrix.

.EXAMPLE
    ./tools/Get-DLLPickleUpstreamInventory.ps1 -OutputPath ./artifacts/upstream/inventory.json

.OUTPUTS
    PSCustomObject. The inventory report that is also written as JSON.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'build/dependency-policy.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'artifacts/upstreamCompatibility/upstream-inventory.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ModuleCachePath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'artifacts/upstreamCompatibility/modules'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$ModuleName,

    [Parameter()]
    [switch]$SkipDownload,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PowerShellExecutable = [Environment]::ProcessPath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TestMatrixPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'build/powershell-test-matrix.json')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function ConvertTo-DLLPicklePackageVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [version]$AssemblyVersion
    )

    if ($AssemblyVersion.Revision -eq 0) {
        return '{0}.{1}.{2}' -f $AssemblyVersion.Major, $AssemblyVersion.Minor, $AssemblyVersion.Build
    }

    return $AssemblyVersion.ToString()
}

function Get-DLLPickleLatestModulePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $ModuleRoot = Join-Path -Path $RootPath -ChildPath $Name
    if (-not (Test-Path -LiteralPath $ModuleRoot -PathType Container)) {
        return $null
    }

    Get-ChildItem -LiteralPath $ModuleRoot -Directory |
        Sort-Object -Property {
            try {
                [version]$_.Name
            } catch {
                [version]'0.0'
            }
        } -Descending |
        Select-Object -First 1
}

function Get-DLLPickleRuntimeIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ExecutablePath
    )

    $Probe = @'
$Platform = if ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)) {
    'windows'
} elseif ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::OSX)) {
    'macos'
} else {
    'linux'
}
[ordered]@{
    powerShellVersion = $PSVersionTable.PSVersion.ToString()
    dotNetVersion = [Environment]::Version.ToString()
    dotNetMajor = [Environment]::Version.Major
    executablePath = [Environment]::ProcessPath
    psHome = $PSHOME
    platform = $Platform
    architecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLowerInvariant()
} | ConvertTo-Json -Compress
'@
    $Raw = @(& $ExecutablePath -NoLogo -NoProfile -NonInteractive -Command $Probe 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "PowerShell runtime identity probe failed: $($Raw -join [Environment]::NewLine)"
    }
    $Raw -join [Environment]::NewLine | ConvertFrom-Json -ErrorAction Stop
}

$ResolvedPolicyPath = (Resolve-Path -LiteralPath $PolicyPath).Path
$Policy = Get-Content -LiteralPath $ResolvedPolicyPath -Raw | ConvertFrom-Json
$ResolvedMatrixPath = (Resolve-Path -LiteralPath $TestMatrixPath).Path
$TestMatrix = Get-Content -LiteralPath $ResolvedMatrixPath -Raw | ConvertFrom-Json
$ExecutableCommand = Get-Command -Name $PowerShellExecutable -ErrorAction Stop
if ($ExecutableCommand.CommandType -ne 'Application') {
    throw "PowerShellExecutable must resolve to an application: $PowerShellExecutable"
}
$ResolvedPowerShellExecutable = $ExecutableCommand.Source
$RuntimeIdentity = Get-DLLPickleRuntimeIdentity -ExecutablePath $ResolvedPowerShellExecutable
$RuntimeProfiles = @($TestMatrix.profiles | Where-Object powerShellVersion -eq $RuntimeIdentity.powerShellVersion)
if ($RuntimeProfiles.Count -ne 1) {
    throw "Runtime PowerShell $($RuntimeIdentity.powerShellVersion) is not an exact, unique test-matrix profile."
}
$RuntimeProfile = $RuntimeProfiles[0]
if ([int]$RuntimeIdentity.dotNetMajor -ne [int]$RuntimeProfile.dotnetMajor) {
    throw "Runtime CLR mismatch for PowerShell $($RuntimeIdentity.powerShellVersion). Expected CLR $($RuntimeProfile.dotnetMajor), detected CLR $($RuntimeIdentity.dotNetMajor)."
}
$ProfileKey = 'ps{0}-{1}-{2}-{3}' -f (
    '{0}.{1}' -f $RuntimeProfile.powerShellMajor, $RuntimeProfile.powerShellMinor
), $RuntimeProfile.targetFramework, $RuntimeIdentity.platform, $RuntimeIdentity.architecture
$SnapshotScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'Get-DLLPickleRuntimeAssemblySnapshot.ps1'
$PolicyModules = @($Policy.monitoredModules)
if ($ModuleName) {
    $Requested = @{}
    foreach ($Name in $ModuleName) {
        $Requested[$Name] = $true
    }
    $PolicyModules = @($PolicyModules | Where-Object { $Requested[[string]$_.name] })
}

if ($PolicyModules.Count -eq 0) {
    throw 'No monitored modules matched the dependency policy and ModuleName filter.'
}

$null = New-Item -Path $ModuleCachePath -ItemType Directory -Force
$ResolvedModuleVersions = @{}
if (-not $SkipDownload.IsPresent) {
    # Resolve the complete upstream snapshot before downloading anything. This prevents a module
    # release published midway through the run from producing an internally mixed baseline.
    foreach ($PolicyModule in $PolicyModules) {
        $Name = [string]$PolicyModule.name
        $Repository = if ($PolicyModule.repository) { [string]$PolicyModule.repository } else { 'PSGallery' }
        $GalleryModules = @(Find-Module -Name $Name -Repository $Repository -AllVersions -ErrorAction Stop)
        $GalleryModule = $GalleryModules |
            Where-Object {
                -not $_.PowerShellVersion -or [version]$_.PowerShellVersion -le [version]$RuntimeIdentity.powerShellVersion
            } |
            Sort-Object -Property { [version]([string]$_.Version) } -Descending |
            Select-Object -First 1
        if (-not $GalleryModule) {
            throw "No release of module '$Name' declares compatibility with PowerShell $($RuntimeIdentity.powerShellVersion)."
        }
        $ResolvedModuleVersions[$Name] = $GalleryModule.Version
    }
}

$ModuleResults = foreach ($PolicyModule in $PolicyModules) {
    $Name = [string]$PolicyModule.name
    $Repository = if ($PolicyModule.repository) { [string]$PolicyModule.repository } else { 'PSGallery' }

    if (-not $SkipDownload.IsPresent) {
        $ModuleRoot = Join-Path -Path $ModuleCachePath -ChildPath $Name
        if ($Force.IsPresent -and (Test-Path -LiteralPath $ModuleRoot)) {
            Remove-Item -LiteralPath $ModuleRoot -Recurse -Force
        }

        $SaveModuleParameters = @{
            Name            = $Name
            RequiredVersion = $ResolvedModuleVersions[$Name]
            Repository      = $Repository
            Path            = $ModuleCachePath
            Force           = $true
            ErrorAction     = 'Stop'
        }
        if ((Get-Command -Name Save-Module).Parameters.ContainsKey('AcceptLicense')) {
            $SaveModuleParameters['AcceptLicense'] = $true
        }
        Save-Module @SaveModuleParameters
    }

    $SavedModule = Get-DLLPickleLatestModulePath -RootPath $ModuleCachePath -Name $Name
    if (-not $SavedModule) {
        throw "Module '$Name' was not found under '$ModuleCachePath'."
    }

    $ModuleManifestPath = Get-ChildItem -LiteralPath $SavedModule.FullName -Filter "$Name.psd1" -File -Recurse |
        Sort-Object -Property { $_.FullName.Length } |
        Select-Object -First 1
    if (-not $ModuleManifestPath) {
        throw "Module manifest '$Name.psd1' was not found under '$($SavedModule.FullName)'."
    }
    $OriginalPSModulePath = $env:PSModulePath
    $Manifest = $null
    try {
        $SystemModulePath = Join-Path -Path $RuntimeIdentity.psHome -ChildPath 'Modules'
        $env:PSModulePath = @($ModuleCachePath, $SystemModulePath) -join [System.IO.Path]::PathSeparator
        # Real gallery manifests can contain module-manifest expressions such as a
        # PSEdition-dependent RootModule. Import-PowerShellDataFile deliberately rejects
        # those expressions; Test-ModuleManifest evaluates the constrained manifest grammar
        # and returns the compatibility metadata PowerShell itself uses. Validate only after
        # isolating PSModulePath so RequiredModules saved beside the monitored module resolve.
        $Manifest = Test-ModuleManifest -Path $ModuleManifestPath.FullName -ErrorAction Stop

        $SnapshotParameters = @{
            ModuleName              = @($Name)
            ModuleManifestPath      = @($ModuleManifestPath.FullName)
            ModuleSearchPath        = @($ModuleCachePath, $SystemModulePath)
            PolicyPath              = $ResolvedPolicyPath
            PowerShellExecutable    = $ResolvedPowerShellExecutable
            PowerShellVersion       = [version]$RuntimeIdentity.powerShellVersion
            TargetFramework         = [string]$RuntimeProfile.targetFramework
            Strict                  = $true
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$PolicyModule.deterministicProbeCommand)) {
            $SnapshotParameters['ProbeCommand'] = [string]$PolicyModule.deterministicProbeCommand
        }
        $RuntimeAssemblies = @(& $SnapshotScriptPath @SnapshotParameters)
    } finally {
        $env:PSModulePath = $OriginalPSModulePath
    }

    $Assemblies = @(
        foreach ($Assembly in $RuntimeAssemblies) {
            $ConstituentModule = $Name
            if (-not [string]::IsNullOrWhiteSpace([string]$Assembly.Path)) {
                $FullAssemblyPath = [System.IO.Path]::GetFullPath($Assembly.Path)
                $FullModuleCachePath = [System.IO.Path]::GetFullPath($ModuleCachePath)
                $FullPSHomePath = [System.IO.Path]::GetFullPath($RuntimeIdentity.psHome)
                $RelativeToCache = [System.IO.Path]::GetRelativePath(
                    $FullModuleCachePath,
                    $FullAssemblyPath
                )
                $RelativeToPSHome = [System.IO.Path]::GetRelativePath($FullPSHomePath, $FullAssemblyPath)
                $IsWithinModuleCache = -not $RelativeToCache.StartsWith('..', [System.StringComparison]::Ordinal) -and
                    -not [System.IO.Path]::IsPathRooted($RelativeToCache)
                $IsWithinPSHome = -not $RelativeToPSHome.StartsWith('..', [System.StringComparison]::Ordinal) -and
                    -not [System.IO.Path]::IsPathRooted($RelativeToPSHome)
                if (-not $IsWithinModuleCache -and -not $IsWithinPSHome) {
                    throw "Runtime evidence selected an assembly outside the isolated module cache and exact PSHOME: $FullAssemblyPath"
                }
                if ($IsWithinModuleCache) {
                    $ConstituentModule = ($RelativeToCache -split '[\\/]')[0]
                }
            }
            [PSCustomObject]@{
                Name                    = [string]$Assembly.Name
                Version                 = [string]$Assembly.Version
                PackageVersionCandidate = ConvertTo-DLLPicklePackageVersion -AssemblyVersion ([version]$Assembly.Version)
                FullName                = [string]$Assembly.FullName
                Path                    = [string]$Assembly.Path
                SelectedAssetPath       = [string]$Assembly.Path
                Sha256                  = [string]$Assembly.Sha256
                Alc                     = [string]$Assembly.Alc
                IsCollectible           = [bool]$Assembly.IsCollectible
                ConstituentModule       = $ConstituentModule
                PowerShellVersion       = [string]$Assembly.PowerShellVersion
                DotNetVersion           = [string]$Assembly.DotNetVersion
                TargetFramework         = [string]$Assembly.TargetFramework
                OS                      = [string]$Assembly.OS
                Platform                = [string]$Assembly.Platform
                Architecture            = [string]$Assembly.Architecture
            }
        }
    )
    [PSCustomObject]@{
        Name                       = $Name
        UmbrellaModule             = if ($PolicyModule.umbrellaModule) { [string]$PolicyModule.umbrellaModule } else { $Name }
        ConstituentModule          = $Name
        Version                    = $SavedModule.Name
        LatestCompatibleVersion    = $SavedModule.Name
        Repository                 = $Repository
        ModulePath                 = $SavedModule.FullName
        ModuleManifestPath         = if ($ModuleManifestPath) { $ModuleManifestPath.FullName } else { $null }
        ManifestPowerShellVersion  = if ($Manifest -and $Manifest.PowerShellVersion) { $Manifest.PowerShellVersion.ToString() } else { $null }
        CompatiblePSEditions       = if ($Manifest) { @($Manifest.CompatiblePSEditions) } else { @() }
        Purpose                    = [string]$PolicyModule.purpose
        DeterministicProbeCommand  = [string]$PolicyModule.deterministicProbeCommand
        Assemblies                 = $Assemblies
        TrackedAssemblies          = $Assemblies
    }
}

$Report = [PSCustomObject]@{
    SchemaVersion   = 2
    GeneratedAtUtc  = [System.DateTimeOffset]::UtcNow.ToString('o')
    PolicyPath      = $ResolvedPolicyPath
    TestMatrixPath  = $ResolvedMatrixPath
    ModuleCachePath = (Resolve-Path -LiteralPath $ModuleCachePath).Path
    ProfileKey      = $ProfileKey
    ValidationTier  = 'DeterministicImportNoAuth'
    Profile         = [PSCustomObject]@{
        PowerShellVersion = [string]$RuntimeIdentity.powerShellVersion
        PowerShellLine    = '{0}.{1}' -f $RuntimeProfile.powerShellMajor, $RuntimeProfile.powerShellMinor
        DotNetVersion     = [string]$RuntimeIdentity.dotNetVersion
        DotNetMajor       = [int]$RuntimeIdentity.dotNetMajor
        TargetFramework   = [string]$RuntimeProfile.targetFramework
        ExecutablePath    = [string]$RuntimeIdentity.executablePath
        PSHome            = [string]$RuntimeIdentity.psHome
        Platform          = [string]$RuntimeIdentity.platform
        Architecture      = [string]$RuntimeIdentity.architecture
    }
    ModuleSet       = @($ModuleResults.Name)
    Modules         = @($ModuleResults)
}

$OutputDirectory = Split-Path -Path $OutputPath -Parent
if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
}

$Report |
    ConvertTo-Json -Depth 20 |
    Set-Content -LiteralPath $OutputPath -Encoding UTF8

$Report
