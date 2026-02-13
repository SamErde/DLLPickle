# This PSM1 is for local testing and development use only.

# Dot-source the parent import for local development variables.
# . $PSScriptRoot\Imports.ps1

# Discover all PS1 file(s) in Public and Private paths.
$ItemSplat = @{
    Filter      = '*.ps1'
    Recurse     = $true
    ErrorAction = 'Stop'
}
try {
    $Public = @(Get-ChildItem -Path "$PSScriptRoot\Public" @ItemSplat)
    $Private = @(Get-ChildItem -Path "$PSScriptRoot\Private" @ItemSplat)
    #$Classes = @(Get-ChildItem -Path "$PSScriptRoot\Classes" @itemSplat)
} catch {
    Write-Error $_
    throw 'Unable to get get file information from Public/Private/Classes src.'
}

# Dot-source all .ps1 file(s) found.
foreach ($File in @($Public + $Private)) {
    try {
        . $File.FullName
    } catch {
        throw ('Unable to dot source {0}' -f $File.FullName)
    }
}

# Export all public functions.
Export-ModuleMember -Function $Public.Basename

