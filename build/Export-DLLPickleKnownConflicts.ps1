<#
.SYNOPSIS
    Extracts the knownConflicts array from the dependency policy into a standalone JSON file shipped
    with the module, so the runtime conflict-warning can read it (the full policy is not shipped).
.PARAMETER PolicyPath
    Path to dependency-policy.json.
.PARAMETER OutputPath
    Path to write the extracted knownConflicts JSON (an array).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$Policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
$Conflicts = @($Policy.knownConflicts)

$OutputDirectory = Split-Path -Path $OutputPath -Parent
if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
}

ConvertTo-Json -InputObject $Conflicts -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
