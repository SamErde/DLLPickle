<#
.SYNOPSIS
    Applies safe candidate dependency pin updates from upstream inventory.

.DESCRIPTION
    Reads an upstream compatibility inventory and dependency policy, compares
    exact-pin rules with src/DLLPickle.Build/DLLPickle.csproj, updates supported
    package references when upstream module assembly identities require it, and
    writes a JSON candidate report. Blocked preload families are reported but not
    applied.

.PARAMETER InventoryPath
    Path to a JSON report produced by Get-DLLPickleUpstreamInventory.ps1.

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
    [string]$InventoryPath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'build\dependency-policy.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'src\DLLPickle.Build\DLLPickle.csproj'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'artifacts\upstreamCompatibility\candidate-report.json'),

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

    for ($Index = 0; $Index -lt $ProjectContent.Count; $Index++) {
        $Line = $ProjectContent[$Index]
        if ($Line -match ('Include="{0}"' -f [regex]::Escape($PackageName)) -and
            $Line -match ('TargetFramework.*{0}' -f [regex]::Escape($TargetFramework))) {
            $VersionMatch = [regex]::Match($Line, 'Version="([^"]+)"')
            if ($VersionMatch.Success) {
                return [PSCustomObject]@{
                    Index   = $Index
                    Line    = $Line
                    Version = $VersionMatch.Groups[1].Value
                }
            }
        }
    }

    return $null
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

$ResolvedInventoryPath = (Resolve-Path -LiteralPath $InventoryPath).Path
$ResolvedPolicyPath = (Resolve-Path -LiteralPath $PolicyPath).Path
$ResolvedProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path

$Inventory = Get-Content -LiteralPath $ResolvedInventoryPath -Raw | ConvertFrom-Json
$Policy = Get-Content -LiteralPath $ResolvedPolicyPath -Raw | ConvertFrom-Json
$ProjectContent = @(Get-Content -LiteralPath $ResolvedProjectPath)
$ProjectChanged = $false

$Changes = New-Object System.Collections.Generic.List[object]
$Warnings = New-Object System.Collections.Generic.List[string]

foreach ($Pin in @($Policy.exactPins)) {
    $SourceModuleLookup = @{}
    foreach ($SourceModule in @($Pin.sourceModules)) {
        $SourceModuleLookup[[string]$SourceModule] = $true
    }

    $CandidateAssemblies = @(
        foreach ($Module in @($Inventory.Modules)) {
            if (-not $SourceModuleLookup[[string]$Module.Name]) {
                continue
            }

            foreach ($Assembly in @($Module.TrackedAssemblies)) {
                if ([string]$Assembly.Name -eq [string]$Pin.assemblyName) {
                    [PSCustomObject]@{
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

    if ($CandidateAssemblies.Count -eq 0) {
        $Warnings.Add(("No upstream assembly '{0}' was found in source modules: {1}" -f $Pin.assemblyName, (@($Pin.sourceModules) -join ', ')))
        continue
    }

    $TargetAssembly = $CandidateAssemblies |
        Sort-Object -Property { [version]$_.AssemblyVersion } -Descending |
        Select-Object -First 1
    $TargetVersion = [string]$TargetAssembly.PackageVersion
    $FormattedVersion = if ([string]$Pin.versionSyntax -eq 'exact') { '[{0}]' -f $TargetVersion } else { $TargetVersion }
    $CurrentReference = Get-DLLPickleCurrentPackageReference -ProjectContent $ProjectContent -PackageName ([string]$Pin.packageName) -TargetFramework ([string]$Pin.targetFramework)

    if (-not $CurrentReference) {
        $Warnings.Add(("PackageReference '{0}' for target framework '{1}' was not found; no automatic insert was attempted." -f $Pin.packageName, $Pin.targetFramework))
        continue
    }

    $Change = [PSCustomObject]@{
        PackageName           = [string]$Pin.packageName
        TargetFramework       = [string]$Pin.targetFramework
        CurrentVersion        = [string]$CurrentReference.Version
        CandidateVersion      = $FormattedVersion
        SourceModule          = [string]$TargetAssembly.ModuleName
        SourceModuleVersion   = [string]$TargetAssembly.ModuleVersion
        SourceAssemblyVersion = [string]$TargetAssembly.AssemblyVersion
        Applied               = $false
        Reason                = [string]$Pin.reason
    }

    if ([string]$CurrentReference.Version -ne $FormattedVersion) {
        if ($PSCmdlet.ShouldProcess($ResolvedProjectPath, ("Update {0} {1} from {2} to {3}" -f $Pin.packageName, $Pin.targetFramework, $CurrentReference.Version, $FormattedVersion))) {
            $ProjectContent = @(ConvertTo-DLLPickleUpdatedPackageReferenceContent -ProjectContent $ProjectContent -Index $CurrentReference.Index -NewVersion $FormattedVersion)
            $ProjectChanged = $true
            $Change.Applied = $true
        }
    }

    $Changes.Add($Change)
}

$BlockedFindings = @(
    foreach ($BlockedAssembly in @($Policy.blockedPreloadAssemblies)) {
        foreach ($Module in @($Inventory.Modules)) {
            foreach ($Assembly in @($Module.TrackedAssemblies)) {
                if ([string]$Assembly.Name -eq [string]$BlockedAssembly.assemblyName) {
                    [PSCustomObject]@{
                        AssemblyName  = [string]$Assembly.Name
                        Version       = [string]$Assembly.Version
                        ModuleName    = [string]$Module.Name
                        ModuleVersion = [string]$Module.Version
                        RelativePath  = [string]$Assembly.RelativePath
                        Action        = [string]$BlockedAssembly.updateMode
                        Reason        = [string]$BlockedAssembly.reason
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
    InventoryPath    = $ResolvedInventoryPath
    PolicyPath       = $ResolvedPolicyPath
    ProjectPath      = $ResolvedProjectPath
    ProjectChanged   = $ProjectChanged
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
