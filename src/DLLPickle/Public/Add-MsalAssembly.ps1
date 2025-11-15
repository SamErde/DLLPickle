function Add-MsalAssembly {
    <#
    .SYNOPSIS
        Loads the MSAL assembly into a custom AssemblyLoadContext.

    .DESCRIPTION
        Loads Microsoft.Identity.Client.dll into an isolated load context
        that can be unloaded later. Requires PowerShell 7.0 or higher.

    .PARAMETER ModuleRoot
        The root path of the module containing the 'Assembly' folder with the MSAL DLLs.

    .EXAMPLE
        Add-MsalAssembly -ModuleRoot $PSScriptRoot

        Loads the MSAL assembly into a custom AssemblyLoadContext.
    #>
    [CmdletBinding()]
    param(
        [string]$ModuleRoot
    )

    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Error 'AssemblyLoadContext requires PowerShell 7.0 or higher.'
        return
    }

    if (-not $ModuleRoot) {
        $ModuleRoot = (Join-Path -Path $PSScriptRoot -ChildPath '..')
    }

    try {
        $LibPath = Join-Path $ModuleRoot 'Assembly'

        if (-not (Test-Path $LibPath)) {
            throw "Assembly folder not found at: $LibPath"
        }

        # Reuse existing AssemblyLoadContext if available and alive
        if ($script:MsalLoadContext -and ($script:MsalLoadContext.IsAlive -eq $true)) {
            Write-Verbose "Reusing existing MSAL AssemblyLoadContext"
            return $script:MsalLoadContext
        }

        # Create a collectible AssemblyLoadContext
        $script:MsalLoadContext = [System.Runtime.Loader.AssemblyLoadContext]::new('MsalContext', $true)
        $LoadContext = $script:MsalLoadContext

        Write-Verbose "Loaded $($AllDlls.Count) MSAL assemblies into AssemblyLoadContext"

        $script:MsalLoadContext = $LoadContext
        return $LoadContext
    } catch {
        Write-Error "Failed to load MSAL assemblies: $_"
        throw
    }
}
