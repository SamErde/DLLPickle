function Import-DPLibrary {
    <#
    .SYNOPSIS
    Import DLLPickle libraries based on Packages.json configuration.

    .DESCRIPTION
    Import all DLLs (libraries) that are tracked and marked for auto-import in the Packages.json file.

    .PARAMETER ImportAll
    Ignore preset 'autoImport' values and attempt to import all packages.

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
    $LibraryDirectory = Join-Path -Path $ModuleDirectory -ChildPath 'Lib'
    $PackagesJsonPath = Join-Path -Path $LibraryDirectory -ChildPath 'Packages.json'
    if (-not (Test-Path -Path $PackagesJsonPath)) {
        throw "Packages.json not found at: $PackagesJsonPath"
    }

    try {
        $Packages = Get-Content -Path $PackagesJsonPath | ConvertFrom-Json | Select-Object -ExpandProperty packages
    } catch {
        throw "Failed to read or parse Packages.json at: $PackagesJsonPath. Error: $_"
    }

    foreach ($Package in $Packages) {
        $FilePath = Join-Path -Path $LibraryDirectory -ChildPath "$($Package.name).dll"
        if ( $Package.autoImport -eq $true -or $ImportAll) {
            Add-Type -Path $FilePath
        } else {
            Write-Verbose "Skipping auto-import for $FilePath."
        }
    }
}
