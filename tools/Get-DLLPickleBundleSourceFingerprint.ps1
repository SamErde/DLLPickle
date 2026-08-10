<#
.SYNOPSIS
Computes a deterministic fingerprint of every published-bundle source input.

.DESCRIPTION
Hashes the exact paths used by the release workflow's automatic bundle-change
gate: src/DLLPickle/**, DLLPickle.csproj, and packages.lock.json. Repository-root
paths and timestamps are excluded. The result can bind transitional manual
authenticated evidence to bundle content even though committing that evidence
necessarily changes the Git commit SHA.

.PARAMETER RepositoryRoot
Repository root containing src/DLLPickle and src/DLLPickle.Build.

.PARAMETER OutputPath
Optional JSON report path.

.OUTPUTS
System.Management.Automation.PSCustomObject
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param (
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RepositoryRoot = (Split-Path -Path $PSScriptRoot -Parent),

    [Parameter()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$ResolvedRepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$ModuleSourceRoot = Join-Path $ResolvedRepositoryRoot 'src/DLLPickle'
$BuildProjectPath = Join-Path $ResolvedRepositoryRoot 'src/DLLPickle.Build/DLLPickle.csproj'
$LockFilePath = Join-Path $ResolvedRepositoryRoot 'src/DLLPickle.Build/packages.lock.json'
if (-not (Test-Path -LiteralPath $ModuleSourceRoot -PathType Container)) {
    throw "Published module source directory was not found: $ModuleSourceRoot"
}
foreach ($RequiredFile in @($BuildProjectPath, $LockFilePath)) {
    if (-not (Test-Path -LiteralPath $RequiredFile -PathType Leaf)) {
        throw "Published bundle input was not found: $RequiredFile"
    }
}

$SourceFiles = @(
    Get-ChildItem -LiteralPath $ModuleSourceRoot -File -Recurse
    Get-Item -LiteralPath $BuildProjectPath
    Get-Item -LiteralPath $LockFilePath
) | Sort-Object FullName -Unique
if ($SourceFiles.Count -eq 0) {
    throw 'No published bundle source inputs were found.'
}

$Rows = @(
    foreach ($SourceFile in $SourceFiles) {
        if (($SourceFile.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Published bundle input must not be a symbolic link or reparse point: $($SourceFile.FullName)"
        }
        $RelativePath = [System.IO.Path]::GetRelativePath($ResolvedRepositoryRoot, $SourceFile.FullName).Replace('\', '/')
        if ($RelativePath.StartsWith('../', [System.StringComparison]::Ordinal)) {
            throw "Published bundle input escaped the repository root: $($SourceFile.FullName)"
        }
        $ContentBytes = [System.IO.File]::ReadAllBytes($SourceFile.FullName)
        $Sha256 = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($ContentBytes)).Replace('-', '').ToLowerInvariant()
        [ordered]@{
            path = $RelativePath
            sha256 = $Sha256
            length = [long]$SourceFile.Length
        }
    }
)
$CanonicalRows = @(
    'schemaVersion=1'
    $Rows | ForEach-Object { '{0}|{1}|{2}' -f $_.path, $_.sha256, $_.length }
) -join [char]10
$FingerprintBytes = [System.Text.Encoding]::UTF8.GetBytes($CanonicalRows)
$Fingerprint = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($FingerprintBytes)).Replace('-', '').ToLowerInvariant()
$Report = [pscustomobject][ordered]@{
    schemaVersion = 1
    fingerprint = $Fingerprint
    files = $Rows
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputDirectory = Split-Path -Path $OutputPath -Parent
    if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
    }
    $Report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
}
$Report
