function Import-DPLibrary {
    <#
    .SYNOPSIS
    Import DLLPickle dependency libraries.

    .DESCRIPTION
    Import all DLL files from the appropriate target framework moniker (TFM) directory.
    DLLs are loaded from the TFM folder based on the PowerShell edition:
    - PowerShell Desktop Edition: bin/net48/
    - PowerShell Core Edition: bin/net8.0/

    The latest versions of all dependencies are automatically imported, providing
    backwards compatibility and avoiding version conflicts.

    .EXAMPLE
    Import-DPLibrary
    Imports all dependency DLLs from the appropriate TFM directory.

    .OUTPUTS
    System.Management.Automation.PSCustomObject
    Returns information about each imported DLL.
    #>

    [CmdletBinding()]
    param ()

    # Determine module directory.
    $ModuleDirectory = if ($PSModuleRoot) {
        $PSModuleRoot
    } elseif ($PSScriptRoot) {
        Split-Path -Path $PSScriptRoot -Parent
    } else {
        $PWD
    }

    # Determine the appropriate target framework moniker (TFM) based on PowerShell edition
    $TargetFramework = if ($PSEdition -eq 'Core') {
        'net8.0'
    } else {
        'net48'
    }

    $BinDirectory = Join-Path -Path $ModuleDirectory -ChildPath 'bin'
    $TFMDirectory = Join-Path -Path $BinDirectory -ChildPath $TargetFramework

    Write-Verbose "Using target framework: $TargetFramework"
    Write-Verbose "DLL directory: $TFMDirectory"

    if (-not (Test-Path -Path $TFMDirectory)) {
        throw "Binary directory not found for target framework '$TargetFramework' at: $TFMDirectory"
    }

    # Get all DLL files in the TFM directory
    $DLLFiles = @(Get-ChildItem -Path $TFMDirectory -Filter '*.dll' -ErrorAction Stop)

    if (-not $DLLFiles) {
        Write-Verbose "No DLL files found in $TFMDirectory"
        return
    }

    # Import each DLL and record the results.
    $Results = foreach ($DLLFile in $DLLFiles) {
        $FilePath = $DLLFile.FullName

        try {
            # Check if assembly is already loaded
            $AssemblyName = [System.Reflection.AssemblyName]::GetAssemblyName($FilePath)
            $LoadedAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
                Where-Object { $_.GetName().Name -eq $AssemblyName.Name }

            if ($LoadedAssembly) {
                Write-Verbose "Assembly already loaded: $($DLLFile.BaseName)"
                [PSCustomObject]@{
                    DLLName         = $DLLFile.Name
                    AssemblyName    = $AssemblyName.Name
                    AssemblyVersion = $AssemblyName.Version.ToString()
                    Status          = 'Already Loaded'
                    Error           = $null
                }
            } else {
                Add-Type -Path $FilePath
                Write-Verbose "Successfully imported: $($DLLFile.BaseName)"
                [PSCustomObject]@{
                    DLLName         = $DLLFile.Name
                    AssemblyName    = $AssemblyName.Name
                    AssemblyVersion = $AssemblyName.Version.ToString()
                    Status          = 'Imported'
                    Error           = $null
                }
            }
        } catch {
            Write-Warning "Failed to import $($DLLFile.Name): $_"
            [PSCustomObject]@{
                DLLName         = $DLLFile.Name
                AssemblyName    = $null
                AssemblyVersion = $null
                Status          = 'Failed'
                Error           = $_.Exception.Message
            }
        }
    }

    $Results
}
