function Import-DPLibrary {
    <#
    .SYNOPSIS
    Import DLLPickle dependency libraries.

    .DESCRIPTION
    Import all relevant DLL files for the appropriate target framework and PowerShell edition.

    The latest versions of all dependencies are automatically imported, providing
    backwards compatibility and avoiding version conflicts.

    This function implements dependency-aware loading with automatic retry logic. Some assemblies
    have transitive dependencies that must be loaded first. The function will retry failed
    assemblies up to 5 times to allow for dependency resolution. This eliminates false warnings
    on initial load attempts in Windows PowerShell when dependency load order cannot be predicted.

    .PARAMETER ShowLoaderExceptions
    Display detailed loader exception information when an assembly fails to load.
    This is useful for diagnosing why specific types within an assembly cannot be loaded.

    .INPUTS
    None. This function does not accept pipeline input.

    .EXAMPLE
    Import-DPLibrary

    Imports all dependency DLLs from the appropriate TFM directory.

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

    The function uses a retry strategy to handle transitive dependencies: on the first failed
    load attempt, a verbose message is written instead of a warning. If the assembly loads
    successfully on a retry (after dependencies are satisfied), the original verbose message
    is suppressed. Warnings are shown for assemblies that still fail after all retry attempts,
    and for non-retryable errors.
    #>

    [CmdletBinding()]
    [OutputType('DLLPickle.ImportDPLibraryResult')]
    param (
        [Parameter()]
        [switch]$ShowLoaderExceptions
    )

    # Determine the module's base directory.
    $ModuleDirectory = if ($PSModuleRoot) {
        $PSModuleRoot
    } elseif ($PSScriptRoot) {
        Split-Path -Path $PSScriptRoot -Parent
    } else {
        $PWD.Path
    }

    $Settings = Get-DPConfig

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

    # Get all DLL files in the target framework moniker (TFM) directory. If no DLLs are found, throw an error to alert the user about potential installation issues.
    $DLLFiles = @(Get-ChildItem -Path $TFMDirectory -Filter '*.dll' -File -Recurse -ErrorAction Stop)
    if (-not $DLLFiles -or $DLLFiles.Count -eq 0) {
        throw "No DLL files found in '$TFMDirectory'. Ensure that the module is properly installed and the bin directory contains the expected assemblies."
    }

    # Skip libraries configured by the user.
    $SkipLibraries = @($Settings.SkipLibraries | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($SkipLibraries.Count -gt 0) {
        $OriginalCount = $DLLFiles.Count
        $DLLFiles = @($DLLFiles | Where-Object { $_.Name -notin $SkipLibraries })
        $SkippedByConfigCount = $OriginalCount - $DLLFiles.Count

        if ($SkippedByConfigCount -gt 0) {
            Write-Verbose "Skipped $SkippedByConfigCount libraries per config: $($SkipLibraries -join ', ')"
        }
    }

    # Import each DLL and record the results using dependency-aware loading with retry logic.
    # Some assemblies have transitive dependencies that must be loaded first. Retrying failed
    # assemblies allows dependencies to be satisfied from previous attempts.
    $DLLFileQueue = @($DLLFiles)
    $Results = [System.Collections.Generic.List[object]]::new()
    $ResultDLLNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $MaxRetries = 5
    $RetryCount = 0
    $LoadFailureDetailsByDLLName = @{}
    $InitiallyLoadedAssemblyKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Loaded in [System.AppDomain]::CurrentDomain.GetAssemblies()) {
        $LoadedName = $Loaded.GetName()
        [void]$InitiallyLoadedAssemblyKeys.Add("$($LoadedName.Name)|$($LoadedName.Version)")
    }

    $RecordFinalFailure = {
        param ($DLLFile)

        if ($ResultDLLNames.Contains($DLLFile.Name)) {
            return
        }

        $FilePath = $DLLFile.FullName
        $FailureDetails = $LoadFailureDetailsByDLLName[$DLLFile.Name]
        if ($FailureDetails) {
            Write-Warning "Failed to import $($DLLFile.Name): $($FailureDetails.ErrorMessage)"
            if ($ShowLoaderExceptions -and $FailureDetails.LoaderExceptions) {
                Write-Warning "Loader Exceptions ($($FailureDetails.LoaderExceptions.Count) total):"
                foreach ($LoaderException in $FailureDetails.LoaderExceptions | Select-Object -First 5) {
                    Write-Warning "  - $($LoaderException.Message)"
                }
                if ($FailureDetails.LoaderExceptions.Count -gt 5) {
                    Write-Warning "  ... and $($FailureDetails.LoaderExceptions.Count - 5) more exceptions"
                }
            }
        } else {
            Write-Warning "Failed to import $($DLLFile.Name): Unable to load one or more of the requested types. Retrieve the LoaderExceptions property for more information."
        }

        try {
            $AssemblyName = [System.Reflection.AssemblyName]::GetAssemblyName($FilePath)
        } catch {
            $AssemblyName = [PSObject]@{ Name = $DLLFile.BaseName }
        }

        if (-not $ResultDLLNames.Contains($DLLFile.Name)) {
            [void]$Results.Add([PSCustomObject]@{
                    PSTypeName      = 'DLLPickle.ImportDPLibraryResult'
                    DLLName         = $DLLFile.Name
                    AssemblyName    = $AssemblyName.Name
                    AssemblyVersion = $null
                    Status          = 'Failed'
                    Error           = 'Unable to load one or more of the requested types. Retrieve the LoaderExceptions property for more information.'
                })
            [void]$ResultDLLNames.Add($DLLFile.Name)
        }
    }

    while ($DLLFileQueue.Count -gt 0 -and $RetryCount -lt $MaxRetries) {
        $UnresolvedDLLFiles = [System.Collections.Generic.List[object]]::new()

        foreach ($DLLFile in $DLLFileQueue) {
            $FilePath = $DLLFile.FullName

            try {
                # Check if assembly is already loaded
                $AssemblyName = [System.Reflection.AssemblyName]::GetAssemblyName($FilePath)
                $AssemblyKey = "$($AssemblyName.Name)|$($AssemblyName.Version)"
                $LoadedAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
                    Where-Object { $_.GetName().Name -eq $AssemblyName.Name -and $_.GetName().Version -eq $AssemblyName.Version }

                if ($LoadedAssembly) {
                    $Status = if ($InitiallyLoadedAssemblyKeys.Contains($AssemblyKey)) { 'Already Loaded' } else { 'Imported' }
                    if ($Status -eq 'Already Loaded') {
                        Write-Verbose "Assembly already loaded: $($DLLFile.BaseName)"
                    } else {
                        Write-Verbose "Assembly was loaded during this invocation: $($DLLFile.BaseName)"
                    }
                    [void]$Results.Add([PSCustomObject]@{
                            PSTypeName      = 'DLLPickle.ImportDPLibraryResult'
                            DLLName         = $DLLFile.Name
                            AssemblyName    = $AssemblyName.Name
                            AssemblyVersion = $AssemblyName.Version.ToString()
                            Status          = $Status
                            Error           = $null
                        })
                    [void]$ResultDLLNames.Add($DLLFile.Name)
                } else {
                    Add-Type -Path $FilePath
                    Write-Verbose "Successfully imported: $($DLLFile.BaseName)"
                    [void]$Results.Add([PSCustomObject]@{
                            PSTypeName      = 'DLLPickle.ImportDPLibraryResult'
                            DLLName         = $DLLFile.Name
                            AssemblyName    = $AssemblyName.Name
                            AssemblyVersion = $AssemblyName.Version.ToString()
                            Status          = 'Imported'
                            Error           = $null
                        })
                    [void]$ResultDLLNames.Add($DLLFile.Name)
                }
            } catch [System.Reflection.ReflectionTypeLoadException] {
                # Assembly failed to load; dependencies may not be loaded yet. Retry later.
                [void]$UnresolvedDLLFiles.Add($DLLFile)
                $LoaderExceptions = $_.Exception.LoaderExceptions
                $ErrorMessage = $_.Exception.Message
                $LoadFailureDetailsByDLLName[$DLLFile.Name] = [PSCustomObject]@{
                    ErrorMessage     = $ErrorMessage
                    LoaderExceptions = $LoaderExceptions
                }

                if ($RetryCount -eq 0) {
                    # Only show verbose output on first attempt; dependencies may resolve on retry

                    if ($ShowLoaderExceptions -and $LoaderExceptions) {
                        Write-Verbose "Failed to import $($DLLFile.Name): $ErrorMessage"
                        Write-Verbose "Loader Exceptions ($($LoaderExceptions.Count) total):"
                        foreach ($LoaderException in $LoaderExceptions | Select-Object -First 5) {
                            Write-Verbose "  - $($LoaderException.Message)"
                        }
                        if ($LoaderExceptions.Count -gt 5) {
                            Write-Verbose "  ... and $($LoaderExceptions.Count - 5) more exceptions"
                        }
                    } else {
                        Write-Verbose "Failed to import $($DLLFile.Name) (attempt $(($RetryCount + 1))/$MaxRetries): $ErrorMessage"
                        if (-not $ShowLoaderExceptions) {
                            Write-Verbose 'Use -ShowLoaderExceptions to see detailed loader exception information'
                        }
                    }
                }
            } catch {
                # Other error; do not retry
                Write-Warning "Failed to import $($DLLFile.Name): $_"
                [void]$Results.Add([PSCustomObject]@{
                        PSTypeName      = 'DLLPickle.ImportDPLibraryResult'
                        DLLName         = $DLLFile.Name
                        AssemblyName    = $null
                        AssemblyVersion = $null
                        Status          = 'Failed'
                        Error           = $_.Exception.Message
                    })
                [void]$ResultDLLNames.Add($DLLFile.Name)
            }
        }

        # If all assemblies loaded successfully, exit the retry loop
        if ($UnresolvedDLLFiles.Count -eq 0) {
            $DLLFileQueue = @()
            break
        }

        # If no progress was made (same failures as last iteration), record failures and exit
        if ($UnresolvedDLLFiles.Count -eq $DLLFileQueue.Count) {
            $RetryCount++
            if ($RetryCount -ge $MaxRetries) {
                # Record remaining unresolved DLLs as failures
                foreach ($DLLFile in $UnresolvedDLLFiles) {
                    & $RecordFinalFailure $DLLFile
                }
                $DLLFileQueue = @()
                break
            }
        } else {
            $RetryCount++
        }

        $DLLFileQueue = $UnresolvedDLLFiles
    }

    if ($DLLFileQueue.Count -gt 0) {
        foreach ($DLLFile in $DLLFileQueue) {
            & $RecordFinalFailure $DLLFile
        }
    }

    $Results
}
