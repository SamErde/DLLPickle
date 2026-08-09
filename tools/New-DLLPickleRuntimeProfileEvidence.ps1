<#
.SYNOPSIS
Capture structured DLLPickle runtime, bundle, assembly, and load-context evidence.

.PARAMETER PowerShellExecutable
Explicit stock pwsh/pwsh.exe used for the evidence process.

.PARAMETER PowerShellVersion
Expected exact PowerShell servicing patch.

.PARAMETER TargetFramework
Expected selected DLLPickle target framework.

.PARAMETER ModuleManifestPath
Path to the assembled DLLPickle module manifest.

.PARAMETER OutputPath
Destination JSON evidence path.

.OUTPUTS
System.IO.FileInfo
#>

[CmdletBinding()]
[OutputType([System.IO.FileInfo])]
param (
    [Parameter(Mandatory)]
    [string]$PowerShellExecutable,

    [Parameter(Mandatory)]
    [version]$PowerShellVersion,

    [Parameter(Mandatory)]
    [ValidatePattern('^net\d+\.0$')]
    [string]$TargetFramework,

    [Parameter(Mandatory)]
    [string]$ModuleManifestPath,

    [Parameter(Mandatory)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$ResolvedExecutable = (Resolve-Path -LiteralPath $PowerShellExecutable -ErrorAction Stop).Path
$ResolvedManifest = (Resolve-Path -LiteralPath $ModuleManifestPath -ErrorAction Stop).Path
$ModuleRoot = Split-Path -Path $ResolvedManifest -Parent
$SelectedBundlePath = Join-Path -Path (Join-Path -Path $ModuleRoot -ChildPath 'bin') -ChildPath $TargetFramework
if (-not (Test-Path -LiteralPath $SelectedBundlePath -PathType Container)) {
    throw "Expected DLLPickle bundle not found: $SelectedBundlePath"
}

$Payload = [ordered]@{
    manifestPath       = $ResolvedManifest
    selectedBundlePath = (Resolve-Path -LiteralPath $SelectedBundlePath).Path
    targetFramework    = $TargetFramework
}
$PayloadBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Payload | ConvertTo-Json -Compress)))
$EvidenceProbe = @'
$ErrorActionPreference = 'Stop'
$Payload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__')) | ConvertFrom-Json
Import-Module -Name $Payload.manifestPath -Force
$ImportResults = @(Import-DPLibrary -SuppressLogo -WarningAction SilentlyContinue)
$BundleRoot = [IO.Path]::GetFullPath($Payload.selectedBundlePath)
$AssemblyEvidence = @(
    [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.Location) -and
            [IO.Path]::GetFullPath($_.Location).StartsWith($BundleRoot, [StringComparison]::OrdinalIgnoreCase)
        } |
        Sort-Object -Property FullName -Unique |
        ForEach-Object {
            $LoadContext = [Runtime.Loader.AssemblyLoadContext]::GetLoadContext($_)
            [ordered]@{
                name = $_.GetName().Name
                version = $_.GetName().Version.ToString()
                fullName = $_.FullName
                path = $_.Location
                sha256 = (Get-FileHash -LiteralPath $_.Location -Algorithm SHA256).Hash.ToLowerInvariant()
                loadContext = if ($LoadContext) { $LoadContext.Name } else { $null }
                isCollectible = if ($LoadContext) { $LoadContext.IsCollectible } else { $false }
            }
        }
)
$Platform = if ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)) {
    'windows'
} elseif ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::OSX)) {
    'macos'
} else {
    'linux'
}
[ordered]@{
    schemaVersion = 1
    evidenceUtc = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    runIdentifier = if ($env:GITHUB_RUN_ID) { "$($env:GITHUB_RUN_ID).$($env:GITHUB_RUN_ATTEMPT)" } else { 'local' }
    powerShellVersion = $PSVersionTable.PSVersion.ToString()
    dotNetVersion = [Environment]::Version.ToString()
    dotNetMajor = [Environment]::Version.Major
    targetFramework = $Payload.targetFramework
    executablePath = [Environment]::ProcessPath
    psHome = $PSHOME
    platform = $Platform
    architecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLowerInvariant()
    selectedBundlePath = $Payload.selectedBundlePath
    importResults = $ImportResults
    assemblies = $AssemblyEvidence
} | ConvertTo-Json -Depth 12 -Compress
'@.Replace('__PAYLOAD__', $PayloadBase64)

$ProbeOutput = @(& $ResolvedExecutable -NoLogo -NoProfile -NonInteractive -Command $EvidenceProbe 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Runtime evidence probe failed: $($ProbeOutput -join [Environment]::NewLine)"
}

try {
    $Evidence = $ProbeOutput -join [Environment]::NewLine | ConvertFrom-Json -ErrorAction Stop
} catch {
    throw "Runtime evidence probe returned malformed JSON: $($ProbeOutput -join [Environment]::NewLine)"
}
if ([version]$Evidence.powerShellVersion -ne $PowerShellVersion) {
    throw "Runtime evidence PowerShell mismatch. Expected $PowerShellVersion but received $($Evidence.powerShellVersion)."
}
if ($Evidence.targetFramework -ne $TargetFramework -or [int]$Evidence.dotNetMajor -ne [int]($TargetFramework -replace '^net|\.0$')) {
    throw "Runtime evidence TFM/CLR mismatch for $TargetFramework."
}
if (@($Evidence.importResults | Where-Object Status -eq 'Failed').Count -gt 0) {
    throw 'Runtime evidence captured one or more failed DLL imports.'
}

$OutputDirectory = Split-Path -Path $OutputPath -Parent
if (-not [string]::IsNullOrWhiteSpace($OutputDirectory) -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
}
$Evidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding utf8
Get-Item -LiteralPath $OutputPath
