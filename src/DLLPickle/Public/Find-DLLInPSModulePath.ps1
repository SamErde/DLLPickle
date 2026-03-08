function Find-DLLInPSModulePath {
    <#
    .SYNOPSIS
        Find DLL files in module paths, filtered by product metadata.

    .DESCRIPTION
        Searches PowerShell module paths for DLL files and returns rich objects that include both
        file metadata and module path context. By default, searches all valid paths from PSModulePath.

        Scope filtering is cross-platform and classifies each path as CurrentUser, AllUsers, or Unknown
        based on common PowerShell module roots for Windows, Linux, and macOS.

    .PARAMETER ProductName
        The product name to search for in DLL ProductName properties. Supports wildcards. Defaults to 'Microsoft Identity'.

    .PARAMETER FileName
        The file name pattern to search for. Supports wildcards. Defaults to '*.dll' to search all DLL files.
        Use a specific pattern like 'Microsoft.IdentityModel*.dll' to narrow the search.

    .PARAMETER NewestVersion
        If specified, only the newest version of each matching DLL will be returned.

    .PARAMETER Path
        Locations to search for DLL files. Defaults to all valid directories from PSModulePath.

    .PARAMETER ExcludeDirectories
        Directory names to exclude from recursive inspection.

    .PARAMETER Scope
        Limits paths to CurrentUser, AllUsers, or Both. Unknown path classifications are included only when Scope is Both.

    .EXAMPLE
        Find-DLLInPSModulePath -ProductName "Microsoft Identity"

        Find all DLLs with 'Microsoft Identity' in their ProductName property within installed PowerShell module locations.

    .EXAMPLE
        Find-DLLInPSModulePath -FileName "Microsoft.IdentityModel*.dll"

        Find all DLL files matching the pattern 'Microsoft.IdentityModel*.dll' that also have 'Microsoft Identity' in their ProductName.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        DLLPickle.ModuleDllInfo

        Rich result objects with file metadata and path classification details.
    #>

    [CmdletBinding()]
    [OutputType('DLLPickle.ModuleDllInfo')]
    param (
        # The product name to search for in DLL ProductName properties. Supports wildcards. Defaults to 'Microsoft Identity'.
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ProductName = 'Microsoft Identity',

        # The file name pattern to search for. Supports wildcards. Defaults to '*.dll'.
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$FileName = '*.dll',

        # Locations to search for DLLs. Defaults to all valid directories in the PSModulePath environment variable.
        [Parameter()]
        [string[]]$Path = @( $env:PSModulePath -split [System.IO.Path]::PathSeparator | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container -ErrorAction SilentlyContinue) } ),

        # Directories to exclude from inspection so the process goes faster.
        [Parameter()]
        [string[]]$ExcludeDirectories = @('en-US', '.git'),

        # The module installation scope to search. Valid options are AllUsers, CurrentUser, or Both (default).
        [Parameter()]
        [ValidateSet('CurrentUser', 'AllUsers', 'Both')]
        [string]$Scope = 'Both',

        # If specified, only the newest version of each matching DLL will be returned.
        [switch]$NewestVersion
    )

    $NormalizePath = {
        param ([string]$InputPath)

        if ([string]::IsNullOrWhiteSpace($InputPath)) {
            return $null
        }

        return $InputPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    }

    $CurrentUserRoots = @(
        (Join-Path -Path $HOME -ChildPath 'Documents\PowerShell\Modules')
        (Join-Path -Path $HOME -ChildPath 'Documents\WindowsPowerShell\Modules')
        (Join-Path -Path $HOME -ChildPath '.local/share/powershell/Modules')
    ) | Where-Object { $_ }

    $AllUsersRoots = @(
        (Join-Path -Path $PSHOME -ChildPath 'Modules')
        (Join-Path -Path '/usr/local/share' -ChildPath 'powershell/Modules')
        (Join-Path -Path '/usr/share' -ChildPath 'powershell/Modules')
    ) | Where-Object { $_ }

    if ($env:ProgramFiles) {
        $AllUsersRoots += Join-Path -Path $env:ProgramFiles -ChildPath 'PowerShell\Modules'
    }
    if ($env:ProgramFiles -and $PSVersionTable.PSVersion.Major -lt 6) {
        $AllUsersRoots += Join-Path -Path $env:ProgramFiles -ChildPath 'WindowsPowerShell\Modules'
    }
    if (${env:ProgramFiles(x86)}) {
        $AllUsersRoots += Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'PowerShell\\Modules'
    }

    $CurrentUserRoots = @($CurrentUserRoots | ForEach-Object { & $NormalizePath $_ } | Where-Object { $_ } | Select-Object -Unique)
    $AllUsersRoots = @($AllUsersRoots | ForEach-Object { & $NormalizePath $_ } | Where-Object { $_ } | Select-Object -Unique)

    $GetPathScope = {
        param ([string]$PathItem)

        $NormalizedPath = & $NormalizePath $PathItem
        if (-not $NormalizedPath) {
            return 'Unknown'
        }

        foreach ($CurrentUserRoot in $CurrentUserRoots) {
            if ($NormalizedPath.StartsWith($CurrentUserRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                return 'CurrentUser'
            }
        }

        foreach ($AllUsersRoot in $AllUsersRoots) {
            if ($NormalizedPath.StartsWith($AllUsersRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                return 'AllUsers'
            }
        }

        return 'Unknown'
    }

    $ValidPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($PathItem in $Path) {
        if (Test-Path -LiteralPath $PathItem -PathType Container) {
            [void]$ValidPaths.Add($PathItem)
        } else {
            Write-Warning "Path does not exist or is not accessible: $PathItem"
        }
    }

    if ($ValidPaths.Count -eq 0) {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new('No valid module paths were provided.'),
            'NoValidModulePaths',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $Path
        )
        $PSCmdlet.WriteError($ErrorRecord)
        return
    }

    $ScopedPaths = [System.Collections.Generic.List[object]]::new()

    if ($Scope -eq 'CurrentUser') {
        foreach ($PathItem in $ValidPaths) {
            $PathScope = & $GetPathScope $PathItem
            if ($PathScope -eq 'CurrentUser') {
                [void]$ScopedPaths.Add([PSCustomObject]@{ Path = $PathItem; Scope = $PathScope })
            }
        }
    } elseif ($Scope -eq 'AllUsers') {
        foreach ($PathItem in $ValidPaths) {
            $PathScope = & $GetPathScope $PathItem
            if ($PathScope -eq 'AllUsers') {
                [void]$ScopedPaths.Add([PSCustomObject]@{ Path = $PathItem; Scope = $PathScope })
            }
        }
    } else {
        foreach ($PathItem in $ValidPaths) {
            [void]$ScopedPaths.Add([PSCustomObject]@{ Path = $PathItem; Scope = (& $GetPathScope $PathItem) })
        }
    }

    if ($ScopedPaths.Count -eq 0) {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Scope '$Scope' produced no valid paths."),
            'ScopePathsNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $Scope
        )
        $PSCmdlet.WriteError($ErrorRecord)
        return
    }

    $ScopedPathValues = @($ScopedPaths | Select-Object -ExpandProperty Path -Unique)

    Write-Verbose "Enumerating DLLs matching file pattern '$FileName' with ProductName containing '$ProductName' under:`n - $($ScopedPathValues -join "`n - ")"

    $ProductNamePattern = if ($ProductName -match '[\*\?\[]') {
        $ProductName
    } else {
        "*$ProductName*"
    }

    $Results = @(
        Get-ChildItem -Path $ScopedPathValues -Filter $FileName -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Directory.Name -notin $ExcludeDirectories } | ForEach-Object {
                $VersionInfo = $_.VersionInfo
                if ($VersionInfo.ProductName -like $ProductNamePattern) {
                    $PathScope = (& $GetPathScope $_.DirectoryName)
                    [PSCustomObject]@{
                        PSTypeName       = 'DLLPickle.ModuleDllInfo'
                        FileName         = $_.Name
                        FullName         = $_.FullName
                        Directory        = $_.DirectoryName
                        ModuleRoot       = $_.Directory.Parent.FullName
                        PathScope        = $PathScope
                        ProductName      = $VersionInfo.ProductName
                        ProductVersion   = $VersionInfo.ProductVersion
                        InternalName     = $VersionInfo.InternalName
                        OriginalFilename = $VersionInfo.OriginalFilename
                        FileVersion      = $VersionInfo.FileVersion
                        VersionInfo      = $VersionInfo
                    }
                }
            }
    )

    if ($Results.Count -eq 0) {
        Write-Warning "No DLLs found matching file pattern '$FileName' with ProductName containing '*$ProductName*'."
    }

    if ($NewestVersion) {
        $Results = @(
            $Results |
                Group-Object -Property OriginalFilename | ForEach-Object {
                    $_.Group |
                        Sort-Object -Property @{ Expression = {
                                try {
                                    [version]$_.FileVersion
                                } catch {
                                    [version]'0.0.0.0'
                                }
                            }
                        } -Descending | Select-Object -First 1
                    } | Sort-Object -Property InternalName
        )
    }

    $Results | Sort-Object -Property InternalName
}
