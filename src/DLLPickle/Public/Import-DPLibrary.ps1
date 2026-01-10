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

    .EXAMPLE
    Import-DPLibrary -ImportAll
    Imports all DLLPickle libraries, ignoring auto-import settings.

    .OUTPUTS
    System.Management.Automation.PSCustomObject
    Returns information about imported libraries.
    #>

    [CmdletBinding()]
    param (
        # Ignore preset 'autoImport' values and attempt to import all packages.
        [Parameter()]
        [switch] $ImportAll
    )

    # Determine module directory.
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

    # Import each package as per the autoImport setting or ImportAll flag and record the results.
    $Results = foreach ($Package in $Packages) {
        $FilePath = Join-Path -Path $LibraryDirectory -ChildPath "$($Package.name).dll"

        if ($Package.autoImport -or $ImportAll) {
            if (-not (Test-Path -Path $FilePath)) {
                Write-Warning "DLL not found: $FilePath"
                [PSCustomObject]@{
                    PackageName = $Package.name
                    Version     = $Package.version
                    Status      = 'Not Found'
                    Error       = 'File does not exist'
                }
                continue
            }

            try {
                # Check if assembly is already loaded
                $AssemblyName = [System.Reflection.AssemblyName]::GetAssemblyName($FilePath)
                $LoadedAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
                    Where-Object { $_.GetName().Name -eq $AssemblyName.Name }

                if ($LoadedAssembly) {
                    Write-Verbose "Assembly already loaded: $($Package.name)"
                    [PSCustomObject]@{
                        PackageName = $Package.name
                        Version     = $Package.version
                        Status      = 'Already Loaded'
                        Error       = $null
                    }
                } else {
                    Add-Type -Path $FilePath
                    Write-Verbose "Successfully imported: $($Package.name)"
                    [PSCustomObject]@{
                        PackageName = $Package.name
                        Version     = $Package.version
                        Status      = 'Imported'
                        Error       = $null
                    }
                }
            } catch {
                Write-Warning "Failed to import $($Package.name): $_"
                [PSCustomObject]@{
                    PackageName = $Package.name
                    Version     = $Package.version
                    Status      = 'Failed'
                    Error       = $_.Exception.Message
                }
            }
        } else {
            Write-Verbose "Skipping auto-import for $($Package.name)."
            [PSCustomObject]@{
                PackageName = $Package.name
                Version     = $Package.version
                Status      = 'Skipped'
                Error       = $null
            }
        }
    }

    $Results
}
