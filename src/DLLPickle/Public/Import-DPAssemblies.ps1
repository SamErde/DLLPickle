function Import-DPAssembly {
    <#
    .SYNOPSIS
    Short description

    .DESCRIPTION
    Long description

    .EXAMPLE
    An example

    .NOTES
    General notes
    #>

    [CmdletBinding()]
    param (
        # Ignore preset 'autoImport' values and attempt to import all packages.
        [Parameter()]
        [switch] $ImportAll
    )

    $ModuleDirectory = if ($PSModuleRoot) { $PSModuleRoot } elseif ($PSScriptRoot) { Split-Path -Path $PSScriptRoot -Parent } else { $PWD }
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
