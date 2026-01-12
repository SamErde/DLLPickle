function Find-DLLInPSModulePath {
    <#
    .SYNOPSIS
        Show a list of all DLLs in PowerShell module paths that contain the specified product name in their FileInfo property.

    .DESCRIPTION
        Check all installed PowerShell module locations for DLL files that have the specified product name
        (e.g., 'Microsoft Identity') in their file's ProductName attribute. By default, searches all paths
        in the PSModulePath environment variable. Can optionally check custom locations using the -Path parameter.

    .PARAMETER ProductName
        The product name to search for in DLL ProductName properties. Supports wildcards. Defaults to 'Microsoft Identity'.

    .PARAMETER FileName
        The file name pattern to search for. Supports wildcards. Defaults to '*.dll' to search all DLL files.
        Use a specific pattern like 'Microsoft.IdentityModel*.dll' to narrow the search.

    .PARAMETER NewestVersion
        If specified, only the newest version of each matching DLL will be returned.

    .PARAMETER ShowDetails
        Display formatted output to host in addition to returning objects to the pipeline.

    .EXAMPLE
        Find-DLLInPSModulePath -ProductName "Microsoft Identity"

        Find all DLLs with 'Microsoft Identity' in their ProductName property within installed PowerShell module locations.

    .EXAMPLE
        Find-DLLInPSModulePath -FileName "Microsoft.IdentityModel*.dll"

        Find all DLL files matching the pattern 'Microsoft.IdentityModel*.dll' that also have 'Microsoft Identity' in their ProductName.

        Example Output:

        InternalName                                        ProductVersion Module
        ------------                                        -------------- ------
        Microsoft.Identity.Abstractions.dll                 9.5.0.0        DLLPickle
        Microsoft.IdentityModel.Abstractions.dll            0.0.0.0        Az.Accounts
        Microsoft.IdentityModel.JsonWebTokens.dll           8.6.0.0        ExchangeOnlineManagement
        Microsoft.IdentityModel.Logging.dll                 8.6.0.0        ExchangeOnlineManagement
        Microsoft.IdentityModel.Protocols.dll               8.6.1.0        WinTuner
        Microsoft.IdentityModel.Protocols.OpenIdConnect.dll 8.6.1.0        WinTuner
        Microsoft.IdentityModel.Tokens.dll                  8.6.0.0        ExchangeOnlineManagement
        Microsoft.IdentityModel.Validators.dll              8.6.1.0        WinTuner
        System.IdentityModel.Tokens.Jwt.dll                 8.6.0.0        ExchangeOnlineManagement
    #>

    [CmdletBinding()]
    [OutputType([System.Diagnostics.FileVersionInfo])]
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
        [switch]$NewestVersion,

        # Display formatted output to host in addition to returning objects to the pipeline.
        [switch]$ShowDetails
    )

    # Validate that all provided paths exist
    foreach ($pathItem in $Path) {
        if (-not (Test-Path -LiteralPath $pathItem -PathType Container)) {
            Write-Warning "Path does not exist or is not accessible: $pathItem"
        }
    }

    # Determine the scoped paths to inspect. Defaults to all scopes.
    if ($Scope -eq 'CurrentUser') {
        $ScopedPath = @( $Path | Where-Object { $_ -match '\bUser(s)?\b' } )
    } elseif ($Scope -eq 'AllUsers') {
        $ScopedPath = @( $Path | Where-Object { $_ -notmatch '\bUser(s)?\b' } )
    } else {
        $ScopedPath = $Path
    }

    # Write an error and exit if none of the specified paths are found in the specified scope.
    if (-not $ScopedPath -or $ScopedPath.Count -eq 0) {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Scope '$Scope' produced no valid paths."), 'ScopePathsNotFound', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Scope
        )
        $PSCmdlet.WriteError($ErrorRecord)
        return
    }

    Write-Verbose "Enumerating DLLs matching file pattern '$FileName' with ProductName containing '$ProductName' under:`n - $($ScopedPath -join "`n - ")"
    $DLLs = @(
        Get-ChildItem -Path $ScopedPath -Filter $FileName -File -Recurse | Where-Object { $_.Directory.Name -notin $ExcludeDirectories } | ForEach-Object {
            $VersionInfo = $_.VersionInfo
            if ($VersionInfo.ProductName -like "*$ProductName*") {
                $VersionInfo.PSObject.TypeNames.Insert(0, 'DLLPickle.FileVersionInfo')
                $VersionInfo
            }
        }
    )

    if ($DLLs.Count -eq 0) {
        Write-Warning "No DLLs found matching file pattern '$FileName' with ProductName containing '*$ProductName*'."
    }

    # If the NewestVersion switch is specified, filter to only the newest version of each DLL.
    if ($NewestVersion) {
        $DLLs = $DLLs | Group-Object -Property OriginalFilename | ForEach-Object {
            $_.Group | Sort-Object -Property FileVersion -Descending | Select-Object -First 1
        } | Sort-Object -Property InternalName
    }

    # Display detailed output to host if the ShowDetails switch is specified.
    if ($PSBoundParameters.ContainsKey('ShowDetails')) {
        # Show the results as a table to the host in addition to returning to the pipeline.
        $DLLs | Out-Host
    }

    $DLLs
}
