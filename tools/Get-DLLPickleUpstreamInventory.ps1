<#
.SYNOPSIS
    Builds an assembly inventory for upstream PowerShell modules.

.DESCRIPTION
    Reads build/dependency-policy.json, downloads the latest monitored modules
    from PSGallery unless SkipDownload is used, inventories bundled DLL assembly
    identities, and writes a structured JSON report for CI/CD compatibility
    checks.

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

.EXAMPLE
    ./tools/Get-DLLPickleUpstreamInventory.ps1 -OutputPath ./artifacts/upstream/inventory.json

.OUTPUTS
    PSCustomObject. The inventory report that is also written as JSON.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'build\dependency-policy.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'artifacts\upstreamCompatibility\upstream-inventory.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ModuleCachePath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'artifacts\upstreamCompatibility\modules'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$ModuleName,

    [Parameter()]
    [switch]$SkipDownload,

    [Parameter()]
    [switch]$Force
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

function Get-DLLPickleAssemblyInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModulePath,

        [Parameter(Mandatory)]
        [string[]]$TrackedAssembly
    )

    $TrackedLookup = @{}
    foreach ($AssemblyName in $TrackedAssembly) {
        $TrackedLookup[$AssemblyName] = $true
    }

    Get-ChildItem -LiteralPath $ModulePath -Filter '*.dll' -File -Recurse |
        ForEach-Object {
            try {
                $AssemblyName = [System.Reflection.AssemblyName]::GetAssemblyName($_.FullName)
                [PSCustomObject]@{
                    Name                   = $AssemblyName.Name
                    Version                = $AssemblyName.Version.ToString()
                    PackageVersionCandidate = ConvertTo-DLLPicklePackageVersion -AssemblyVersion $AssemblyName.Version
                    FullName               = $AssemblyName.FullName
                    RelativePath           = $_.FullName.Substring($ModulePath.Length).TrimStart('\', '/')
                    Path                   = $_.FullName
                    IsTracked              = [bool]$TrackedLookup[$AssemblyName.Name]
                }
            } catch [System.BadImageFormatException] {
                Write-Verbose "Skipping non-.NET DLL '$($_.FullName)'."
            }
        } |
        Sort-Object -Property Name, Version, RelativePath
}

$ResolvedPolicyPath = (Resolve-Path -LiteralPath $PolicyPath).Path
$Policy = Get-Content -LiteralPath $ResolvedPolicyPath -Raw | ConvertFrom-Json
$TrackedAssemblies = @($Policy.trackedAssemblies | ForEach-Object { [string]$_ })
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
$ModuleResults = foreach ($PolicyModule in $PolicyModules) {
    $Name = [string]$PolicyModule.name
    $Repository = if ($PolicyModule.repository) { [string]$PolicyModule.repository } else { 'PSGallery' }

    if (-not $SkipDownload.IsPresent) {
        $ModuleRoot = Join-Path -Path $ModuleCachePath -ChildPath $Name
        if ($Force.IsPresent -and (Test-Path -LiteralPath $ModuleRoot)) {
            Remove-Item -LiteralPath $ModuleRoot -Recurse -Force
        }

        $GalleryModule = Find-Module -Name $Name -Repository $Repository -ErrorAction Stop
        $SaveModuleParameters = @{
            Name            = $Name
            RequiredVersion = $GalleryModule.Version
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

    $Assemblies = @(Get-DLLPickleAssemblyInventory -ModulePath $SavedModule.FullName -TrackedAssembly $TrackedAssemblies)
    [PSCustomObject]@{
        Name              = $Name
        Version           = $SavedModule.Name
        Repository        = $Repository
        ModulePath        = $SavedModule.FullName
        Purpose           = [string]$PolicyModule.purpose
        Assemblies        = $Assemblies
        TrackedAssemblies = @($Assemblies | Where-Object IsTracked)
    }
}

$Report = [PSCustomObject]@{
    GeneratedAtUtc  = [System.DateTimeOffset]::UtcNow.ToString('o')
    PolicyPath      = $ResolvedPolicyPath
    ModuleCachePath = (Resolve-Path -LiteralPath $ModuleCachePath).Path
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
