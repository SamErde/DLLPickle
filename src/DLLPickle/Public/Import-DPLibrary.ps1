function Import-DPLibrary {
    <#
    .SYNOPSIS
    Import DLLPickle dependency libraries.

    .DESCRIPTION
    Import all relevant DLL files for the appropriate target framework and PowerShell edition.

    The latest versions of all dependencies are automatically imported, providing
    backwards compatibility and avoiding version conflicts.

    .PARAMETER SkipProblematicAssemblies
    When running in Windows PowerShell, skip assemblies known to have compatibility issues
    with .NET Framework 4.8. This prevents warning messages while still loading all
    compatible dependencies.

    .PARAMETER ShowLoaderExceptions
    Display detailed loader exception information when an assembly fails to load.
    This is useful for diagnosing why specific types within an assembly cannot be loaded.

    .INPUTS
    None. This function does not accept pipeline input.

    .EXAMPLE
    Import-DPLibrary
    Imports all dependency DLLs from the appropriate TFM directory.

    .EXAMPLE
    Import-DPLibrary -SkipProblematicAssemblies
    Imports compatible DLLs and skips known problematic assemblies in Windows PowerShell.

    .EXAMPLE
    Import-DPLibrary -ShowLoaderExceptions
    Imports DLLs and displays detailed diagnostic information for any failures.

    .OUTPUTS
    System.Management.Automation.PSCustomObject
    Returns information about each imported DLL.

    .NOTES
    Some assemblies may have partial compatibility issues in Windows PowerShell due to
    dependencies on types not available in .NET Framework 4.8. The function will continue
    loading other assemblies and provide detailed diagnostic information about failures.

    A status of 'Imported' indicates the assembly file was successfully loaded by the runtime,
    but this does not guarantee that all types within the assembly are usable. Some types may
    remain unavailable due to unresolved transitive dependencies.
    #>

    [CmdletBinding()]
    param (
        [Parameter()]
        [switch]$SkipProblematicAssemblies,

        [Parameter()]
        [switch]$ShowLoaderExceptions
    )

    # Determine the module's base directory.
    $ModuleDirectory = if ($PSModuleRoot) {
        $PSModuleRoot
    } elseif ($PSScriptRoot) {
        Split-Path -Path $PSScriptRoot -Parent
    } else {
        $PWD
    }

    # Determine the appropriate target framework moniker (TFM) based on PowerShell edition.
    $TargetFramework = if ($PSEdition -eq 'Core') {
        'net8.0'
    } else {
        'net48'
    }

    $BinDirectory = Join-Path -Path $ModuleDirectory -ChildPath 'bin'
    $TFMDirectory = Join-Path -Path $BinDirectory -ChildPath $TargetFramework

    Write-Verbose "Using PowerShell edition: $PSEdition"
    Write-Verbose "Using target framework: $TargetFramework"
    Write-Verbose "DLL directory: $TFMDirectory"

    if (-not (Test-Path -Path $TFMDirectory)) {
        throw "Binary directory not found for target framework '$TargetFramework' at: $TFMDirectory"
    }

    <# About Problematic Assemblies in Windows PowerShell
    There are some known problematic assemblies in Windows PowerShell (.NET Framework 4.8). These assemblies may contain
    types that depend on APIs not available in .NET Framework 4.8, leading to loader exceptions for those types. Skipping
    these assemblies prevents warnings while still loading all compatible dependencies.
    #>
    $ProblematicAssemblies = @(
        'Microsoft.Identity.Client.dll'
        'System.Diagnostics.DiagnosticSource.dll'
    )

    # Get all DLL files in the TFM directory. If no DLLs are found, throw an error to alert the user about potential installation issues.
    $DLLFiles = @(Get-ChildItem -Path $TFMDirectory -Filter '*.dll' -File -Recurse -ErrorAction Stop)
    if (-not $DLLFiles -or $DLLFiles.Count -eq 0) {
        throw "No DLL files found in '$TFMDirectory'. Ensure that the module is properly installed and the bin directory contains the expected assemblies."
    }

    # Filter out problematic assemblies if requested and if running in Windows PowerShell.
    if ($SkipProblematicAssemblies -and $PSEdition -ne 'Core') {
        $OriginalCount = $DLLFiles.Count
        $DLLFiles = $DLLFiles | Where-Object { $_.Name -notin $ProblematicAssemblies }
        $SkippedCount = $OriginalCount - $DLLFiles.Count
        if ($SkippedCount -gt 0) {
            Write-Verbose "Skipped $SkippedCount known problematic assemblies in Windows PowerShell: $($ProblematicAssemblies -join ', ')"
        }
    }

    # Import each DLL and record the results.
    $Results = foreach ($DLLFile in $DLLFiles) {
        $FilePath = $DLLFile.FullName

        try {
            # Check if assembly is already loaded
            $AssemblyName = [System.Reflection.AssemblyName]::GetAssemblyName($FilePath)
            $LoadedAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
                Where-Object { $_.GetName().Name -eq $AssemblyName.Name -and $_.GetName().Version -eq $AssemblyName.Version }

            if ($LoadedAssembly) {
                Write-Verbose "Assembly already loaded: $($DLLFile.BaseName)"
                [PSCustomObject]@{
                    PSTypeName      = 'DLLPickle.ImportDPLibraryResult'
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
                    PSTypeName      = 'DLLPickle.ImportDPLibraryResult'
                    DLLName         = $DLLFile.Name
                    AssemblyName    = $AssemblyName.Name
                    AssemblyVersion = $AssemblyName.Version.ToString()
                    Status          = 'Imported'
                    Error           = $null
                }
            }
        } catch [System.Reflection.ReflectionTypeLoadException] {
            # Handle ReflectionTypeLoadException specifically to provide detailed diagnostics
            $LoaderExceptions = $_.Exception.LoaderExceptions
            $ErrorMessage = $_.Exception.Message

            # Build detailed error information
            if ($ShowLoaderExceptions -and $LoaderExceptions) {
                Write-Warning "Failed to import $($DLLFile.Name): $ErrorMessage"
                Write-Warning "Loader Exceptions ($($LoaderExceptions.Count) total):"
                foreach ($LoaderException in $LoaderExceptions | Select-Object -First 5) {
                    Write-Warning "  - $($LoaderException.Message)"
                }
                if ($LoaderExceptions.Count -gt 5) {
                    Write-Warning "  ... and $($LoaderExceptions.Count - 5) more exceptions"
                }
            } else {
                Write-Warning "Failed to import $($DLLFile.Name): $ErrorMessage"
                if (-not $ShowLoaderExceptions) {
                    Write-Verbose 'Use -ShowLoaderExceptions to see detailed loader exception information'
                }
            }

            [PSCustomObject]@{
                PSTypeName      = 'DLLPickle.ImportDPLibraryResult'
                DLLName         = $DLLFile.Name
                AssemblyName    = $null
                AssemblyVersion = $null
                Status          = 'Failed'
                Error           = $ErrorMessage
            }
        } catch {
            Write-Warning "Failed to import $($DLLFile.Name): $_"
            [PSCustomObject]@{
                PSTypeName      = 'DLLPickle.ImportDPLibraryResult'
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
