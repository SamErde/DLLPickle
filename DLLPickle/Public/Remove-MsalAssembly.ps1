function Remove-MsalAssembly {
    <#
    .SYNOPSIS
        Unloads the MSAL assembly from memory.

    .DESCRIPTION
        Unloads the MSAL AssemblyLoadContext and triggers garbage collection
        to free memory. Requires PowerShell 7.0 or higher.

    .NOTES
        Unloading may not happen immediately. The GC will unload when all
        references to types from the assembly are released.
    #>
    [CmdletBinding()]
    param()

    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw "AssemblyLoadContext requires PowerShell 7.0 or higher. Current version: $($PSVersionTable.PSVersion)"
    }

    if ($null -eq $script:MsalLoadContext) {
        Write-Warning 'MSAL assembly is not currently loaded.'
        return
    }

    try {
        # Get the context name before unloading
        $ContextName = $script:MsalLoadContext.Name

        # Unload the context
        $script:MsalLoadContext.Unload()

        # Clear the reference
        $script:MsalLoadContext = $null

        # Force garbage collection to actually unload the assembly
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        [System.GC]::Collect()

        Write-Verbose "Unloaded AssemblyLoadContext: $ContextName"
        Write-Verbose 'Garbage collection completed.'
    } catch {
        Write-Error "Failed to unload MSAL assembly: $_"
        throw
    }
}
