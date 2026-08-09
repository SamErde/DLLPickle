<#
.SYNOPSIS
    Builds a per-TFM dependency-change report for a Dependabot candidate.

.DESCRIPTION
    Compares baseline and candidate NuGet target graphs, selected assets, and
    packaged assembly inputs for every supported TFM. It also summarizes exact-host
    Pester XML evidence and incorporates the package-size report. The report computes
    a deterministic per-TFM delta for every assembly classified as preload or blocked;
    live upstream and ALC adjudication remains owned by the profile-aware upstream gate.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$BaselineProjectAssetsPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$CandidateProjectAssetsPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$BaselineBuildOutputRoot,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$CandidateBuildOutputRoot,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SupportPolicyPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DependencyPolicyPath,

    [Parameter()]
    [string]$SizeReportPath,

    [Parameter()]
    [string]$ScenarioEvidencePath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\dependency\dependency-change-report.json')
)

$ErrorActionPreference = 'Stop'

function Get-DLLPickleNuGetTargetGraph {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Assets,

        [Parameter(Mandatory)]
        [string]$TargetFramework
    )

    $TargetProperty = $Assets.targets.PSObject.Properties[$TargetFramework]
    if (-not $TargetProperty) {
        return @()
    }

    @(
        foreach ($LibraryProperty in @($TargetProperty.Value.PSObject.Properties | Sort-Object Name)) {
            $SeparatorIndex = $LibraryProperty.Name.LastIndexOf('/')
            $PackageName = if ($SeparatorIndex -gt 0) { $LibraryProperty.Name.Substring(0, $SeparatorIndex) } else { $LibraryProperty.Name }
            $PackageVersion = if ($SeparatorIndex -gt 0) { $LibraryProperty.Name.Substring($SeparatorIndex + 1) } else { $null }
            $CompileAssets = @($LibraryProperty.Value.compile.PSObject.Properties.Name | Where-Object { $_ -ne '_._' } | Sort-Object -Unique)
            $RuntimeAssets = @($LibraryProperty.Value.runtime.PSObject.Properties.Name | Where-Object { $_ -ne '_._' } | Sort-Object -Unique)
            [PSCustomObject]@{
                PackageName    = $PackageName
                PackageVersion = $PackageVersion
                CompileAssets  = @($CompileAssets)
                RuntimeAssets  = @($RuntimeAssets)
            }
        }
    )
}

function Get-DLLPicklePackagedAssemblyInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BuildOutputRoot,

        [Parameter(Mandatory)]
        [string]$TargetFramework
    )

    $TfmPath = Join-Path $BuildOutputRoot $TargetFramework
    if (-not (Test-Path -LiteralPath $TfmPath -PathType Container)) {
        return @()
    }

    $Files = @(
        Get-ChildItem -LiteralPath $TfmPath -File -Filter '*.dll' |
            Where-Object Name -Match '^(Azure\.|Microsoft\.|System\.)'
        $RuntimePath = Join-Path $TfmPath 'runtimes'
        if (Test-Path -LiteralPath $RuntimePath -PathType Container) {
            Get-ChildItem -LiteralPath $RuntimePath -File -Recurse |
                Where-Object FullName -Match '[\\/]native[\\/]'
        }
    )

    @(
        foreach ($File in @($Files | Sort-Object FullName)) {
            $AssemblyName = $null
            $AssemblyVersion = $null
            try {
                $ManagedIdentity = [System.Reflection.AssemblyName]::GetAssemblyName($File.FullName)
                $AssemblyName = [string]$ManagedIdentity.Name
                $AssemblyVersion = [string]$ManagedIdentity.Version
            } catch {
                # Native runtime payloads are still package inputs but do not have a managed identity.
                $AssemblyName = $null
                $AssemblyVersion = $null
            }
            $Sha256 = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            [PSCustomObject]@{
                RelativePath = [System.IO.Path]::GetRelativePath($TfmPath, $File.FullName).Replace('\', '/')
                Length       = [long]$File.Length
                Sha256       = $Sha256
                AssemblyName = $AssemblyName
                AssemblyVersion = $AssemblyVersion
                IdentityFingerprint = if ($AssemblyName) { "$AssemblyVersion|$Sha256" } else { $null }
            }
        }
    )
}

function Compare-DLLPickleNamedRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Baseline,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Candidate,

        [Parameter(Mandatory)]
        [string]$KeyProperty,

        [Parameter(Mandatory)]
        [string]$ValueProperty
    )

    $BaselineByKey = @{}
    foreach ($Row in $Baseline) { $BaselineByKey[[string]$Row.$KeyProperty] = $Row }
    $CandidateByKey = @{}
    foreach ($Row in $Candidate) { $CandidateByKey[[string]$Row.$KeyProperty] = $Row }
    $Keys = @($BaselineByKey.Keys + $CandidateByKey.Keys | Sort-Object -Unique)

    [PSCustomObject]@{
        Added = @($Keys | Where-Object { -not $BaselineByKey.ContainsKey($_) } | ForEach-Object { $CandidateByKey[$_] })
        Removed = @($Keys | Where-Object { -not $CandidateByKey.ContainsKey($_) } | ForEach-Object { $BaselineByKey[$_] })
        Changed = @(
            foreach ($Key in $Keys) {
                if ($BaselineByKey.ContainsKey($Key) -and $CandidateByKey.ContainsKey($Key) -and [string]$BaselineByKey[$Key].$ValueProperty -cne [string]$CandidateByKey[$Key].$ValueProperty) {
                    [PSCustomObject]@{
                        Key       = $Key
                        Baseline  = $BaselineByKey[$Key].$ValueProperty
                        Candidate = $CandidateByKey[$Key].$ValueProperty
                    }
                }
            }
        )
    }
}

foreach ($RequiredPath in @($BaselineProjectAssetsPath, $CandidateProjectAssetsPath, $BaselineBuildOutputRoot, $CandidateBuildOutputRoot, $SupportPolicyPath, $DependencyPolicyPath)) {
    if (-not (Test-Path -LiteralPath $RequiredPath)) {
        throw "Required dependency-report path was not found: $RequiredPath"
    }
}

$BaselineAssets = Get-Content -LiteralPath $BaselineProjectAssetsPath -Raw | ConvertFrom-Json -ErrorAction Stop
$CandidateAssets = Get-Content -LiteralPath $CandidateProjectAssetsPath -Raw | ConvertFrom-Json -ErrorAction Stop
$SupportPolicy = Get-Content -LiteralPath $SupportPolicyPath -Raw | ConvertFrom-Json -ErrorAction Stop
$DependencyPolicy = Get-Content -LiteralPath $DependencyPolicyPath -Raw | ConvertFrom-Json -ErrorAction Stop
$TargetFrameworks = @($SupportPolicy.profiles.targetFramework | ForEach-Object { [string]$_ } | Sort-Object -Unique)
$ConflictSensitiveAssemblyNames = @(
    @($DependencyPolicy.preload.assemblyName)
    @($DependencyPolicy.blockedPreloadAssemblies.assemblyName)
) |
    ForEach-Object { [string]$_ } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Sort-Object -Unique
$SizeReport = if ($SizeReportPath -and (Test-Path -LiteralPath $SizeReportPath -PathType Leaf)) {
    Get-Content -LiteralPath $SizeReportPath -Raw | ConvertFrom-Json -ErrorAction Stop
} else {
    $null
}

$ProfileReports = @(
    foreach ($TargetFramework in $TargetFrameworks) {
        $BaselineGraph = @(Get-DLLPickleNuGetTargetGraph -Assets $BaselineAssets -TargetFramework $TargetFramework)
        $CandidateGraph = @(Get-DLLPickleNuGetTargetGraph -Assets $CandidateAssets -TargetFramework $TargetFramework)
        $BaselineInputs = @(Get-DLLPicklePackagedAssemblyInput -BuildOutputRoot $BaselineBuildOutputRoot -TargetFramework $TargetFramework)
        $CandidateInputs = @(Get-DLLPicklePackagedAssemblyInput -BuildOutputRoot $CandidateBuildOutputRoot -TargetFramework $TargetFramework)
        $BaselineConflictInputs = @($BaselineInputs | Where-Object AssemblyName -IN $ConflictSensitiveAssemblyNames)
        $CandidateConflictInputs = @($CandidateInputs | Where-Object AssemblyName -IN $ConflictSensitiveAssemblyNames)
        $ConflictDelta = Compare-DLLPickleNamedRow -Baseline $BaselineConflictInputs -Candidate $CandidateConflictInputs -KeyProperty AssemblyName -ValueProperty IdentityFingerprint
        $SizeRow = if ($SizeReport) { @($SizeReport.Profiles | Where-Object Name -EQ $TargetFramework | Select-Object -First 1)[0] } else { $null }

        [PSCustomObject]@{
            TargetFramework      = $TargetFramework
            BaselineResolvedGraph = @($BaselineGraph)
            CandidateResolvedGraph = @($CandidateGraph)
            ResolvedGraphDelta   = Compare-DLLPickleNamedRow -Baseline $BaselineGraph -Candidate $CandidateGraph -KeyProperty PackageName -ValueProperty PackageVersion
            CandidateSelectedAssets = @($CandidateGraph | Select-Object PackageName,PackageVersion,CompileAssets,RuntimeAssets)
            AssemblyDelta        = Compare-DLLPickleNamedRow -Baseline $BaselineInputs -Candidate $CandidateInputs -KeyProperty RelativePath -ValueProperty Sha256
            Size                 = $SizeRow
            ConflictSurfaceDelta = [PSCustomObject]@{
                RequiredCheck = 'Validate upstream compatibility tooling'
                SensitiveAssemblyNames = @($ConflictSensitiveAssemblyNames)
                BaselineAssemblies = @($BaselineConflictInputs)
                CandidateAssemblies = @($CandidateConflictInputs)
                Delta = $ConflictDelta
                HasChanges = (
                    @($ConflictDelta.Added).Count -gt 0 -or
                    @($ConflictDelta.Removed).Count -gt 0 -or
                    @($ConflictDelta.Changed).Count -gt 0
                )
                UpstreamAlcAdjudication = 'required-profile-aware-gate'
            }
        }
    }
)

$ScenarioResults = @(
    if ($ScenarioEvidencePath -and (Test-Path -LiteralPath $ScenarioEvidencePath -PathType Container)) {
        foreach ($XmlFile in @(Get-ChildItem -LiteralPath $ScenarioEvidencePath -File -Filter '*.xml' -Recurse | Sort-Object FullName)) {
            try {
                [xml]$Xml = Get-Content -LiteralPath $XmlFile.FullName -Raw
                $Root = $Xml.DocumentElement
                [PSCustomObject]@{
                    File       = [System.IO.Path]::GetRelativePath($ScenarioEvidencePath, $XmlFile.FullName).Replace('\', '/')
                    Total      = [int]$Root.total
                    Failures   = [int]$Root.failures
                    Errors     = [int]$Root.errors
                    NotRun     = [int]$Root.'not-run'
                    Passed     = ([int]$Root.failures + [int]$Root.errors) -eq 0
                }
            } catch {
                [PSCustomObject]@{
                    File   = [System.IO.Path]::GetRelativePath($ScenarioEvidencePath, $XmlFile.FullName).Replace('\', '/')
                    Passed = $false
                    Error  = $_.Exception.Message
                }
            }
        }
    }
)

$Report = [PSCustomObject]@{
    SchemaVersion   = 2
    GeneratedAtUtc  = [System.DateTimeOffset]::UtcNow.ToString('o')
    TargetFrameworks = @($TargetFrameworks)
    Profiles        = @($ProfileReports)
    ScenarioOutcomes = @($ScenarioResults)
    RequiredChecks  = @('Build gate', 'Validate upstream compatibility tooling', 'dependency-review')
    ReviewRequired  = $true
}

$OutputDirectory = Split-Path -Path $OutputPath -Parent
if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
}
$Report | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$Report
