function Find-MSIdentityAssembly {
    <#
    .SYNOPSIS
        Show a list of all files in the current location that have 'Microsoft Identity' in their product name.

    .DESCRIPTION
        Check all installed PowerShell locations for DLL files that have 'Microsoft Identity' in their file's Productname attribute. (Can optionally check other locations.)

    .EXAMPLE
        Find-MSIdentityAssembly

        Find all Microsoft Identity-related DLLs within installed PowerShell module locations.

    .EXAMPLE
        Find-MSIdentityAssembly | Format-Table InternalName, @{Label = 'ProductVersion'; Expression = { $_.ProductVersionRaw } }, @{Label = 'Module'; Expression = { $($_.FileName -replace '^.*Modules[\\/]([^\\/]+)([\\/].*)?', '$1') }}

        Find all Microsoft Identity-related DLLs within installed PowerShell module locations. Shows the name of the module that the DLL is included in.

    .NOTES

        To do: add informational output if no libraries are found.

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
    param (

        # Locations to search for Microsoft Identity-related DLLs.
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string[]]$Path = @($env:PSModulePath -split ';'),

        # Support the PassThru common parameter.
        [switch] $PassThru
    )

    $MicrosoftIdentityFile = @(Get-ChildItem -Path $Path -Filter '*.dll' -Recurse | Select-Object -ExpandProperty VersionInfo -ErrorAction SilentlyContinue | Where-Object { $_.ProductName -match 'Microsoft Identity' })
    $NewestMicrosoftIdentityFile = $MicrosoftIdentityFile | Group-Object -Property OriginalFilename | ForEach-Object { $_.Group | Sort-Object -Property Version -Descending | Select-Object -First 1 }

    if ($PSBoundParameters.ContainsKey('PassThru')) {
        $NewestMicrosoftIdentityFile | Format-Table InternalName, @{Label = 'ProductVersion'; Expression = { $_.ProductVersionRaw } }, @{Label = 'Module'; Expression = { $($_.FileName -replace '^.*Modules[\\/]([^\\/]+)([\\/].*)?', '$1') } }, FileDescription | Out-Host
    }

    $NewestMicrosoftIdentityFile
}
