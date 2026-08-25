<#
.SYNOPSIS
Generate the authoritative exact PowerShell and operating-system CI matrix.

.PARAMETER MatrixPath
Path to the canonical non-shipped PowerShell test matrix.

.PARAMETER Compress
Emit compressed JSON for a GitHub Actions job output.

.OUTPUTS
System.String
#>

[CmdletBinding()]
[OutputType([string])]
param (
    [Parameter()]
    [string]$MatrixPath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'build/powershell-test-matrix.json'),

    [Parameter()]
    [switch]$Compress
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $MatrixPath -PathType Leaf)) {
    throw "PowerShell test matrix not found: $MatrixPath"
}

$Policy = Get-Content -LiteralPath $MatrixPath -Raw | ConvertFrom-Json -ErrorAction Stop
$Cells = @(
    foreach ($RuntimeProfile in @($Policy.profiles)) {
        foreach ($Lane in @($Policy.lanes)) {
            [ordered]@{
                powerShellVersion = [string]$RuntimeProfile.powerShellVersion
                powerShellLine    = '{0}.{1}' -f $RuntimeProfile.powerShellMajor, $RuntimeProfile.powerShellMinor
                dotnetMajor       = [int]$RuntimeProfile.dotnetMajor
                targetFramework   = [string]$RuntimeProfile.targetFramework
                platform          = [string]$Lane.platform
                runner            = [string]$Lane.runner
                architecture      = [string]$Lane.architecture
                provider          = [string]$Policy.provisioning.defaultProvider
            }
        }
    }
)

$ExpectedCellCount = @($Policy.profiles).Count * @($Policy.lanes).Count
if ($ExpectedCellCount -eq 0 -or $Cells.Count -ne $ExpectedCellCount) {
    throw "The authoritative DLLPickle runtime matrix must contain exactly $ExpectedCellCount cells; found $($Cells.Count)."
}

$CellKeys = @($Cells | ForEach-Object { '{0}|{1}|{2}' -f $_.powerShellVersion, $_.platform, $_.architecture })
if (@($CellKeys | Sort-Object -Unique).Count -ne $Cells.Count) {
    throw 'The authoritative DLLPickle runtime matrix contains duplicate cells.'
}

[ordered]@{ include = $Cells } | ConvertTo-Json -Depth 10 -Compress:$Compress
