function Get-DPKnownConflict {
    <#
    .SYNOPSIS
        Reads the module's shipped knownConflicts data.
    .DESCRIPTION
        Loads KnownConflicts.json (shipped at the module root by the build) and returns the conflict
        array. Returns an empty array - never throws - if the file is missing or malformed, so the
        advisory warning can never break a session.
    .PARAMETER Path
        Optional path to a knownConflicts JSON file. Defaults to KnownConflicts.json at the module root
        (this script lives in <module>/Private, so the module root is its parent directory).
    .OUTPUTS
        The knownConflicts entries, or an empty array.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path
    )

    process {
        if (-not $Path) {
            $Path = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'KnownConflicts.json'
        }
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            Write-Verbose "No knownConflicts file at '$Path'."
            return @()
        }
        try {
            return @((Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json))
        } catch {
            Write-Verbose "Could not parse knownConflicts at '$Path': $_"
            return @()
        }
    }
}
