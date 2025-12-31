#Requires -Version 7.0

$CSharpCode = @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Linq;
using System.Threading.Tasks;

public class FastFileSearch
{
    public static List<string> FindFile(string searchPath, string fileName, bool caseSensitive = false)
    {
        var results = new List<string>();
        var comparison = caseSensitive ? StringComparison.Ordinal : StringComparison.OrdinalIgnoreCase;
        var enumerationOptions = new EnumerationOptions
        {
            IgnoreInaccessible = true,
            RecurseSubdirectories = true,
            ReturnSpecialDirectories = false
        };

        try
        {
            var files = Directory.EnumerateFiles(searchPath, fileName, enumerationOptions);
            results.AddRange(files);
        }
        catch (Exception)
        {
            // Skip directories we can't access
        }

        return results;
    }

    public static List<string> FindFiles(string searchPath, string[] filePatterns, bool caseSensitive = false)
    {
        var results = new List<string>();

        foreach (var pattern in filePatterns)
        {
            var enumerationOptions = new EnumerationOptions
            {
                IgnoreInaccessible = true,
                RecurseSubdirectories = true,
                ReturnSpecialDirectories = false
            };

            try
            {
                var files = Directory.EnumerateFiles(searchPath, pattern, enumerationOptions);
                results.AddRange(files);
            }
            catch (Exception)
            {
                // Skip directories we can't access
            }
        }

        return results.Distinct().ToList();
    }

    public static List<string> FindFileParallel(string searchPath, string fileName, int? maxDegreeOfParallelism = null)
    {
        var results = new ConcurrentBag<string>();
        var enumerationOptions = new EnumerationOptions
        {
            IgnoreInaccessible = true,
            RecurseSubdirectories = false,
            ReturnSpecialDirectories = false
        };

        if (!maxDegreeOfParallelism.HasValue)
        {
            maxDegreeOfParallelism = Environment.ProcessorCount;
        }

        // Search root directory first
        try
        {
            var rootFiles = Directory.EnumerateFiles(searchPath, fileName, new EnumerationOptions
            {
                IgnoreInaccessible = true,
                RecurseSubdirectories = false
            });

            foreach (var file in rootFiles)
            {
                results.Add(file);
            }
        }
        catch (Exception)
        {
            // Skip if we can't access root
        }

        // Get all subdirectories to process in parallel
        var directories = new ConcurrentQueue<string>();
        try
        {
            var rootDirs = Directory.EnumerateDirectories(searchPath, "*", enumerationOptions);
            foreach (var dir in rootDirs)
            {
                directories.Enqueue(dir);
            }
        }
        catch (Exception)
        {
            return results.ToList();
        }

        // Process directories in parallel
        var parallelOptions = new ParallelOptions
        {
            MaxDegreeOfParallelism = maxDegreeOfParallelism.Value
        };

        Parallel.ForEach(directories, parallelOptions, directory =>
        {
            try
            {
                var filesInDir = Directory.EnumerateFiles(directory, fileName, new EnumerationOptions
                {
                    IgnoreInaccessible = true,
                    RecurseSubdirectories = true
                });

                foreach (var file in filesInDir)
                {
                    results.Add(file);
                }
            }
            catch (Exception)
            {
                // Silently skip directories we can't access
            }
        });

        return results.ToList();
    }

    public static List<string> FindFilesParallel(string searchPath, string[] filePatterns, int? maxDegreeOfParallelism = null)
    {
        var results = new ConcurrentBag<string>();
        var enumerationOptions = new EnumerationOptions
        {
            IgnoreInaccessible = true,
            RecurseSubdirectories = false,
            ReturnSpecialDirectories = false
        };

        if (!maxDegreeOfParallelism.HasValue)
        {
            maxDegreeOfParallelism = Environment.ProcessorCount;
        }

        // Search root directory first for all patterns
        foreach (var pattern in filePatterns)
        {
            try
            {
                var rootFiles = Directory.EnumerateFiles(searchPath, pattern, new EnumerationOptions
                {
                    IgnoreInaccessible = true,
                    RecurseSubdirectories = false
                });

                foreach (var file in rootFiles)
                {
                    results.Add(file);
                }
            }
            catch (Exception)
            {
                // Skip if we can't access root
            }
        }

        // Get all subdirectories to process in parallel
        var directories = new ConcurrentQueue<string>();
        try
        {
            var rootDirs = Directory.EnumerateDirectories(searchPath, "*", enumerationOptions);
            foreach (var dir in rootDirs)
            {
                directories.Enqueue(dir);
            }
        }
        catch (Exception)
        {
            return results.Distinct().ToList();
        }

        // Process directories in parallel
        var parallelOptions = new ParallelOptions
        {
            MaxDegreeOfParallelism = maxDegreeOfParallelism.Value
        };

        Parallel.ForEach(directories, parallelOptions, directory =>
        {
            foreach (var pattern in filePatterns)
            {
                try
                {
                    var filesInDir = Directory.EnumerateFiles(directory, pattern, new EnumerationOptions
                    {
                        IgnoreInaccessible = true,
                        RecurseSubdirectories = true
                    });

                    foreach (var file in filesInDir)
                    {
                        results.Add(file);
                    }
                }
                catch (Exception)
                {
                    // Silently skip directories we can't access
                }
            }
        });

        return results.Distinct().ToList();
    }
}
'@

Add-Type -TypeDefinition $CSharpCode

function Find-FileRecursive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName', 'PSPath')]
        [string[]]$Path,

        [Parameter(Mandatory = $true)]
        [string[]]$FilePattern,

        [Parameter(Mandatory = $false)]
        [switch]$Parallel,

        [Parameter(Mandatory = $false)]
        [int]$MaxThreads = [Environment]::ProcessorCount
    )

    begin {
        $AllResults = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($SearchPath in $Path) {
            try {
                $ResolvedPaths = Resolve-Path -Path $SearchPath -ErrorAction Stop
            } catch {
                Write-Warning "Path not found or inaccessible: $SearchPath"
                continue
            }

            foreach ($ResolvedPath in $ResolvedPaths) {
                $ActualPath = $ResolvedPath.Path

                if (-not (Test-Path -Path $ActualPath -PathType Container)) {
                    Write-Warning "Path is not a directory: $ActualPath"
                    continue
                }

                Write-Verbose "Searching in: $ActualPath"

                $Results = if ($FilePattern.Count -eq 1) {
                    if ($Parallel) {
                        [FastFileSearch]::FindFileParallel($ActualPath, $FilePattern[0], $MaxThreads)
                    } else {
                        [FastFileSearch]::FindFile($ActualPath, $FilePattern[0], $false)
                    }
                } else {
                    if ($Parallel) {
                        [FastFileSearch]::FindFilesParallel($ActualPath, $FilePattern, $MaxThreads)
                    } else {
                        [FastFileSearch]::FindFiles($ActualPath, $FilePattern, $false)
                    }
                }

                if ($null -ne $Results -and $Results.Count -gt 0) {
                    foreach ($Result in $Results) {
                        $AllResults.Add($Result)
                    }
                }
            }
        }
    }

    end {
        # Return unique results as FileInfo objects
        $UniqueResults = $AllResults | Select-Object -Unique | ForEach-Object { Get-Item -LiteralPath $_ }
        $UniqueResults
    }
}

<# Example Usage:
    Write-Verbose "System has $([Environment]::ProcessorCount) processor cores."

    $Patterns = @(
        "Microsoft.Identity.Client.dll",
        "Microsoft.IdentityModel.*.dll",
        "Microsoft.Identity.Client.*.dll"
    )

    Write-Host "Searching for patterns:" -ForegroundColor Cyan
    $Patterns | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
    Write-Host ""

    $Timer1 = [System.Diagnostics.Stopwatch]::StartNew()
    $Results1 = Find-FileRecursive -Path $SearchPath -FilePattern $Patterns -Parallel -Verbose
    $Timer1.Stop()
    Write-Host "`$Results1: Found $($Results1.Count) file(s) in $($Timer1.Elapsed.TotalSeconds.ToString('F2')) seconds" -ForegroundColor Green
    Write-Host ""

    Write-Host "Example 2: Multiple paths as array" -ForegroundColor Yellow
    $MultiplePaths = $env:PSModulePath -split [System.IO.Path]::PathSeparator | Where-Object { Test-Path $_ -PathType Container }
    $Timer2 = [System.Diagnostics.Stopwatch]::StartNew()
    $Results2 = Find-FileRecursive -Path $MultiplePaths -FilePattern $Patterns -Parallel -Verbose
    $Timer2.Stop()
    Write-Host "`$Results2: Found $($Results2.Count) file(s) in $($Timer2.Elapsed.TotalSeconds.ToString('F2')) seconds" -ForegroundColor Green
    Write-Host ""

    Write-Host "Example 3: Pipeline input from Get-ChildItem" -ForegroundColor Yellow
    $RootPath = if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6)
    {
        "C:\Program Files"
    }
    elseif ($IsMacOS)
    {
        "/Applications"
    }
    else
    {
        "/usr"
    }
    $Timer3 = [System.Diagnostics.Stopwatch]::StartNew()
    $Results3 = Get-ChildItem -Path $RootPath -Directory -ErrorAction SilentlyContinue |
        Select-Object -First 5 |
        Find-FileRecursive -FilePattern $Patterns -Parallel -Verbose
    $Timer3.Stop()
    Write-Host "`$Results3: Found $($Results3.Count) file(s) in $($Timer3.Elapsed.TotalSeconds.ToString('F2')) seconds" -ForegroundColor Green
    Write-Host ""

    Write-Host "Example 4: Pipeline input from string array" -ForegroundColor Yellow
    $Timer4 = [System.Diagnostics.Stopwatch]::StartNew()
    $Results4 = $MultiplePaths | Find-FileRecursive -FilePattern $Patterns -Parallel -Verbose
    $Timer4.Stop()
    Write-Host "`$Results4: Found $($Results4.Count) file(s) in $($Timer4.Elapsed.TotalSeconds.ToString('F2')) seconds" -ForegroundColor Green
    Write-Host ""
#>
