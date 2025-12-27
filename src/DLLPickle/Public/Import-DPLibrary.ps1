function Import-DPLibrary {
    <#
    .SYNOPSIS
    Import DLLPickle libraries based on Packages.json configuration.

    .DESCRIPTION
    Import all DLLs (libraries) that are tracked and marked for auto-import in the Packages.json file.

    .EXAMPLE
    Import-DPLibrary
    Imports all DLLPickle libraries marked for auto-import.

    Import-DPLibrary -ImportAll
    Imports all DLLPickle libraries, ignoring auto-import settings.
    #>

    [CmdletBinding()]
    param (
        # Ignore preset 'autoImport' values and attempt to import all packages.
        [Parameter()]
        [switch] $ImportAll
    )

    $ModuleDirectory = if ($PSModuleRoot) {
        $PSModuleRoot
    } elseif ($PSScriptRoot) {
        Split-Path -Path $PSScriptRoot -Parent
    } else {
        $PWD
    }
    $AssemblyDirectory = Join-Path -Path $ModuleDirectory -ChildPath 'Assembly'
    $Packages = Get-Content -Path (Join-Path -Path $AssemblyDirectory -ChildPath 'Packages.json') |
        ConvertFrom-Json | Select-Object -ExpandProperty packages

    foreach ( $Package in $Packages) {
        $FilePath = Join-Path -Path $AssemblyDirectory -ChildPath "$($Package.name).dll"
        if ( $Package.autoImport -eq $true -or $PSBoundParameters.ContainsKey('ImportAll') ) {
            Add-Type -Path $FilePath
        } else {
            Write-Verbose "Skipping auto-import for $FilePath."
        }
    }
}
