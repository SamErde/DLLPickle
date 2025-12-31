function Get-NewestFileVersion {
    <#
    .SYNOPSIS
    Analyzes file version information and identifies the newest version of each unique filename.

    .DESCRIPTION
    The Get-NewestFileVersion function processes file paths or FileInfo objects to extract version
    information and group files by their filename. For each unique filename, it identifies which
    instance has the newest version (or most recent LastWriteTime if version info is unavailable).

    This function is designed to work seamlessly with Find-FileRecursive or Get-ChildItem to help
    identify version conflicts when multiple copies of the same DLL or executable exist across
    different directories.

    .PARAMETER Path
    Specifies the path(s) to files to analyze. Accepts:
    - String paths (e.g., "C:\Windows\System32\kernel32.dll")
    - Arrays of string paths
    - FileInfo objects from Get-ChildItem or Find-FileRecursive
    - Pipeline input from any command that outputs file paths or FileInfo objects

    This parameter accepts pipeline input and can be bound by property name (FullName, PSPath).

    .PARAMETER SkipFilesWithoutVersion
    When specified, files that do not contain embedded version information will be excluded from
    the results. By default, files without version info are included and sorted by LastWriteTime.

    .PARAMETER AsHashTable
    When specified, returns the results as a hashtable instead of an array of PSCustomObjects.
    The filenames are stored as keys, and the full details are stored as PSCustomObjects in the
    hashtable item values.

    This format is useful for quick lookups by filename or for programmatic access to specific
    file version data.

    .INPUTS
    System.String[]
    System.IO.FileInfo[]

    You can pipe file paths (strings) or FileInfo objects to Get-NewestFileVersion.

    .OUTPUTS
    PSCustomObject[] (default)
    System.Collections.Hashtable (when -AsHashTable is specified)

    Default output is an array of custom objects with the following properties:
    - FileName: The name of the file (e.g., "kernel32.dll")
    - NewestVersion: The file version of the newest instance (e.g., "10.0.19041.1")
    - NewestPath: Full path to the file with the newest version
    - LastWriteTime: The LastWriteTime of the newest file
    - HasVersionInfo: Boolean indicating if the newest file has version information
    - TotalInstancesFound: Count of all instances of this filename found
    - FilesWithVersion: Count of instances that have version information
    - FilesWithoutVersion: Count of instances without version information
    - AllVersions: Array of all unique versions found, sorted descending
    - AllPaths: Array of full paths to all instances of this filename

    When -AsHashTable is specified, returns a hashtable where keys are filenames and values
    are the PSCustomObjects described above.

    .EXAMPLE
    Find-FileRecursive -Path "C:\Program Files" -FilePattern "Microsoft.Identity.Client.dll" -Parallel | Get-NewestFileVersion

    Searches for all instances of a DLL across 'Program Files' and identifies the newest version.

    .EXAMPLE
    $ModulePaths = $env:PSModulePath -split [System.IO.Path]::PathSeparator
    $Results = Find-FileRecursive -Path $ModulePaths `
        -FilePattern @('Microsoft.Identity*.dll', 'Microsoft.IdentityModel*.dll') -Parallel | Get-NewestFileVersion

    $Results | Format-Table FileName, NewestVersion, TotalInstancesFound, NewestPath -AutoSize

    Finds all Microsoft Identity-related DLLs across PowerShell module paths, groups them by
    filename, and displays a summary table showing the newest version of each.

    .EXAMPLE
    $ModulePaths = $env:PSModulePath -split [System.IO.Path]::PathSeparator
    $VersionMap = Find-FileRecursive -Path $ModulePaths -FilePattern 'Microsoft.Identity*.dll' -Parallel |
        Get-NewestFileVersion -AsHashTable

    $VersionMap['Microsoft.Identity.Client.dll']
    $VersionMap['Microsoft.Identity.Client.dll'].NewestVersion
    $VersionMap['Microsoft.Identity.Client.dll'].NewestPath

    Returns results as a hashtable for quick lookups. You can access version information for any specific filename directly
    using the hashtable key.

    .NOTES
    Requires: PowerShell 7.0+

    The function uses FileVersionInfo to read embedded version information from executables and
    DLLs. If a file does not have version information, it falls back to using LastWriteTime for
    comparison unless -SkipFilesWithoutVersion is specified.

    When comparing versions, the function attempts to parse FileVersion as a [version] object
    for accurate semantic version comparison. If parsing fails, it falls back to LastWriteTime.

    The -AsHashTable parameter is useful when you need O(1) lookup performance for specific
    filenames or when building version comparison logic in scripts.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName', 'PSPath')]
        [object[]]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$SkipFilesWithoutVersion,

        [Parameter(Mandatory = $false)]
        [switch]$AsHashTable
    )

    begin {
        $FileGroups = @{}
    }

    process {
        foreach ($Item in $Path) {
            $FilePath = if ($Item -is [System.IO.FileInfo]) {
                $Item.FullName
            } elseif ($Item -is [string]) {
                $Item
            } else {
                $Item.ToString()
            }

            try {
                $FileInfo = if ($Item -is [System.IO.FileInfo]) {
                    $Item
                } else {
                    Get-Item -LiteralPath $FilePath -ErrorAction Stop
                }

                $FileName = $FileInfo.Name

                try {
                    $VersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($FileInfo.FullName)

                    $HasVersion = -not [string]::IsNullOrWhiteSpace($VersionInfo.FileVersion)

                    if ($SkipFilesWithoutVersion -and -not $HasVersion) {
                        Write-Verbose "Skipping file without version: $($FileInfo.FullName)"
                        continue
                    }

                    $FileData = [PSCustomObject]@{
                        FullName       = $FileInfo.FullName
                        Name           = $FileName
                        FileVersion    = if ($HasVersion) { $VersionInfo.FileVersion } else { $null }
                        ProductVersion = if (-not [string]::IsNullOrWhiteSpace($VersionInfo.ProductVersion)) { $VersionInfo.ProductVersion } else { $null }
                        LastWriteTime  = $FileInfo.LastWriteTime
                        Length         = $FileInfo.Length
                        HasVersionInfo = $HasVersion
                    }

                    if (-not $FileGroups.ContainsKey($FileName)) {
                        $FileGroups[$FileName] = [System.Collections.Generic.List[object]]::new()
                    }
                    $FileGroups[$FileName].Add($FileData)
                } catch {
                    Write-Warning "Could not read version info for: $($FileInfo.FullName) - $($_.Exception.Message)"

                    if (-not $SkipFilesWithoutVersion) {
                        $FileData = [PSCustomObject]@{
                            FullName       = $FileInfo.FullName
                            Name           = $FileName
                            FileVersion    = $null
                            ProductVersion = $null
                            LastWriteTime  = $FileInfo.LastWriteTime
                            Length         = $FileInfo.Length
                            HasVersionInfo = $false
                        }

                        if (-not $FileGroups.ContainsKey($FileName)) {
                            $FileGroups[$FileName] = [System.Collections.Generic.List[object]]::new()
                        }
                        $FileGroups[$FileName].Add($FileData)
                    }
                }
            } catch {
                Write-Warning "Could not access file: $FilePath - $($_.Exception.Message)"
            }
        }
    }

    end {
        if ($AsHashTable) {
            $ResultHashTable = @{}

            foreach ($FileName in $FileGroups.Keys) {
                $Files = $FileGroups[$FileName]

                $Newest = $Files | Sort-Object {
                    if ($_.HasVersionInfo -and $_.FileVersion) {
                        try {
                            [version]$_.FileVersion
                        } catch {
                            $_.LastWriteTime
                        }
                    } else {
                        $_.LastWriteTime
                    }
                } -Descending | Select-Object -First 1

                $ResultHashTable[$FileName] = [PSCustomObject]@{
                    FileName            = $FileName
                    NewestVersion       = $Newest.FileVersion
                    NewestPath          = $Newest.FullName
                    LastWriteTime       = $Newest.LastWriteTime
                    HasVersionInfo      = $Newest.HasVersionInfo
                    TotalInstancesFound = $Files.Count
                    FilesWithVersion    = ($Files | Where-Object { $_.HasVersionInfo }).Count
                    FilesWithoutVersion = ($Files | Where-Object { -not $_.HasVersionInfo }).Count
                    AllVersions         = ($Files | Where-Object { $_.HasVersionInfo } | Select-Object -ExpandProperty FileVersion -Unique | Sort-Object -Descending)
                    AllPaths            = $Files.FullName
                }
            }

            $ResultHashTable
        } else {
            foreach ($FileName in ($FileGroups.Keys | Sort-Object)) {
                $Files = $FileGroups[$FileName]

                $Newest = $Files | Sort-Object {
                    if ($_.HasVersionInfo -and $_.FileVersion) {
                        try {
                            [version]$_.FileVersion
                        } catch {
                            $_.LastWriteTime
                        }
                    } else {
                        $_.LastWriteTime
                    }
                } -Descending | Select-Object -First 1

                [PSCustomObject]@{
                    FileName            = $FileName
                    NewestVersion       = $Newest.FileVersion
                    NewestPath          = $Newest.FullName
                    LastWriteTime       = $Newest.LastWriteTime
                    HasVersionInfo      = $Newest.HasVersionInfo
                    TotalInstancesFound = $Files.Count
                    FilesWithVersion    = ($Files | Where-Object { $_.HasVersionInfo }).Count
                    FilesWithoutVersion = ($Files | Where-Object { -not $_.HasVersionInfo }).Count
                    AllVersions         = ($Files | Where-Object { $_.HasVersionInfo } | Select-Object -ExpandProperty FileVersion -Unique | Sort-Object -Descending)
                    AllPaths            = $Files.FullName
                }
            }
        }
    }
}
