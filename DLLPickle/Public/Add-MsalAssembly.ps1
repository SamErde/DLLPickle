# Global variable to store the load context
$script:MsalLoadContext = $null

function Add-MsalAssembly {
    <#
    .SYNOPSIS
        Loads the MSAL assembly into a custom AssemblyLoadContext.

    .DESCRIPTION
        Loads Microsoft.Identity.Client.dll into an isolated load context
        that can be unloaded later. Requires PowerShell 7.0 or higher.
    #>
    [CmdletBinding()]
    param()

    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw "AssemblyLoadContext requires PowerShell 7.0 or higher. Current version: $($PSVersionTable.PSVersion)"
    }

    if ($null -ne $script:MsalLoadContext) {
        Write-Warning 'MSAL assembly is already loaded.'
        return
    }

    try {
        $MsalDllPath = Join-Path $PSScriptRoot 'lib\Microsoft.Identity.Client.dll'

        if (-not (Test-Path $MsalDllPath)) {
            throw "MSAL DLL not found at: $MsalDllPath"
        }

        # Create a collectible AssemblyLoadContext
        $script:MsalLoadContext = [System.Runtime.Loader.AssemblyLoadContext]::new('MsalContext', $true)

        # Load the assembly into the custom context
        $Assembly = $script:MsalLoadContext.LoadFromAssemblyPath($MsalDllPath)

        Write-Verbose "Loaded MSAL assembly: $($Assembly.FullName)"
        Write-Verbose "Assembly location: $($Assembly.Location)"

        # Make types available in the current scope by returning the assembly
        return $Assembly
    } catch {
        Write-Error "Failed to load MSAL assembly: $_"
        $script:MsalLoadContext = $null
        throw
    }
}
