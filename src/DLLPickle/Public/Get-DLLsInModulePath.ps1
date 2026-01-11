function Get-DLLsInModulePath {
    <#
    .SYNOPSIS
        Show a list of all DLLs in PowerShell module paths that contain the specified product name in their FileInfo property.

    .DESCRIPTION
        Check all installed PowerShell module locations for DLL files that have the specified product name (e.g., 'Microsoft Identity') in their file's ProductName attribute.
        By default, searches all paths in the PSModulePath environment variable. Can optionally check custom locations using the -Path parameter.

    .EXAMPLE
        Get-DLLsInModulePath -ProductName "Microsoft Identity"

        Find all Microsoft Identity-related DLLs within installed PowerShell module locations.

    .EXAMPLE
        Get-DLLsInModulePath -ProductName "Microsoft Identity" | Sort-Object -Property InternalName | Format-Table InternalName, @{Label = 'ProductVersion'; Expression = { $_.ProductVersionRaw } }, @{Label = 'Module'; Expression = { $($_.FileName -replace '^.*Modules[\\/]([^\\/]+)([\\/].*)?', '$1') }}

        Find all Microsoft Identity-related DLLs within installed PowerShell module locations. Shows the name of the module that the DLL is included in.

    .PARAMETER ShowDetails
        Display formatted output to host in addition to returning objects to the pipeline.

    .NOTES
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
        # The product name to search for in DLL file info properties. Defaults to 'Microsoft Identity'.
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ProductName = 'Microsoft Identity',

        # Locations to search for Microsoft Identity-related DLLs. Defaults to all valid directories in the PSModulePath environment variable.
        [Parameter()]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string[]]$Path = @( $env:PSModulePath -split [System.IO.Path]::PathSeparator | Where-Object { Test-Path $_ -PathType Container } ),

        # Directories to exclude from inspection so the process goes faster.
        [Parameter()]
        [string[]]$ExcludeDirectories = @('en-US', 'help', 'Tests', '.git'),

        # The module installation scope to search. Valid options are AllUsers, CurrentUser, or Both (default).
        [Parameter()]
        [ValidateSet('CurrentUser', 'AllUsers', 'Both')]
        [string]$Scope = 'Both',

        # Display formatted output to host in addition to returning objects to the pipeline.
        [switch] $ShowDetails
    )

    # Determine the scoped paths to inspect. Defaults to all scopes.
    if ($Scope -eq 'CurrentUser') {
        $ScopedPath = @( $Path | Where-Object { $_ -match 'User' } )
    } elseif ($Scope -eq 'AllUsers') {
        $ScopedPath = @( $Path | Where-Object { $_ -notmatch 'User' } )
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

    Write-Verbose "Enumerating DLLs with the product name '$ProductName' under:`n - $($ScopedPath -join "`n - ")"

    # Get the newest version of any DLLs that have "Microsoft Identity" in their ProductName property.
    $DLLs = @(
        Get-ChildItem -Path $ScopedPath -Filter '*.dll' -File -Recurse | Where-Object { $_.Directory.Name -notin $ExcludeDirectories } | ForEach-Object {
            $VersionInfo = $_.VersionInfo
            if ($VersionInfo.ProductName -like "*$ProductName*") {
                # Pass the VersionInfo object on through the pipeline if it matches the desired product name.
                $VersionInfo
            }
        } | Group-Object -Property OriginalFilename | ForEach-Object {
            # Get the newest version of each DLL.
            $_.Group | Sort-Object -Property Version -Descending | Select-Object -First 1
        }
    )

    if ($DLLs.Count -eq 0) {
        Write-Warning "No DLLs found matching the product name pattern '*$ProductName*'."
    }

    if ($PSBoundParameters.ContainsKey('ShowDetails')) {
        # Show the results as a table to the host in addition to returning to the pipeline.
        $DLLs | Sort-Object -Property InternalName | Format-Table InternalName, @{Label = 'ProductVersion'; Expression = { $_.ProductVersionRaw } }, @{Label = 'Module'; Expression = { $($_.FileName -replace '^.*Modules[\\/]([^\\/]+)([\\/].*)?', '$1') } }, FileDescription | Out-Host
    }

    $DLLs
}
