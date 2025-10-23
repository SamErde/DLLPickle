function Add-MsalAssembly {
    <#
    .SYNOPSIS
        Loads the MSAL assembly into a custom AssemblyLoadContext.

    .DESCRIPTION
        Loads Microsoft.Identity.Client.dll into an isolated load context
        that can be unloaded later. Requires PowerShell 7.0 or higher.

    .PARAMETER ModuleRoot
        The root path of the module containing the 'lib' folder with the MSAL DLLs.

    .EXAMPLE
        Add-MsalAssembly -ModuleRoot $PSScriptRoot

        Loads the MSAL assembly into a custom AssemblyLoadContext.
    #>
    [CmdletBinding()]
    param(
        [string]$ModuleRoot = (Join-Path -Path $PSScriptRoot -ChildPath '..')
    )

    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw 'AssemblyLoadContext requires PowerShell 7.0 or higher.'
    }

    try {
        $LibPath = Join-Path $ModuleRoot 'lib'

        if (-not (Test-Path $LibPath)) {
            throw "Lib folder not found at: $LibPath"
        }

        # Create a collectible AssemblyLoadContext
        $LoadContext = [System.Runtime.Loader.AssemblyLoadContext]::new('MsalContext', $true)

        # Load ALL MSAL-related DLLs
        $AllDlls = Get-ChildItem -Path (Join-Path $LibPath '*.dll')
        foreach ($Dll in $AllDlls) {
            Write-Verbose "Loading: $($Dll.Name)"
            $null = $LoadContext.LoadFromAssemblyPath($Dll.FullName)
        }

        Write-Verbose "Loaded $($AllDlls.Count) MSAL assemblies into AssemblyLoadContext"

        return $LoadContext
    } catch {
        Write-Error "Failed to load MSAL assemblies: $_"
        throw
    }
}
