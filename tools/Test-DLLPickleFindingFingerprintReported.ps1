<#
.SYNOPSIS
Tests whether a stable DLLPickle finding fingerprint is already present in report text.

.DESCRIPTION
This deterministic helper recognizes only the exact HTML marker used by scheduled
GitHub issue bodies and comments. It performs no network access or external writes.
#>

[CmdletBinding()]
[OutputType([bool])]
param (
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-fA-F0-9]{64}$')]
    [string]$Fingerprint,

    [Parameter()]
    [AllowEmptyCollection()]
    [AllowEmptyString()]
    [string[]]$Text = @()
)

$Marker = '<!-- dllpickle-finding-fingerprint:{0} -->' -f $Fingerprint.ToLowerInvariant()
return @($Text | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_.Contains($Marker) }).Count -gt 0
