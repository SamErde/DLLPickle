# Dot-source public/private functions.
$Public = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public/*.ps1') -Recurse -ErrorAction Stop)
$Private = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private/*.ps1') -Recurse -ErrorAction Stop)
foreach ($Import in @($Public + $Private)) {
    try {
        . $Import.FullName
    } catch {
        throw "Unable to dot source [$($Import.FullName)]"
    }
}

# Export public functions for the user.
Export-ModuleMember -Function $Public.Basename

# Load the assembly on module import. In PowerShell 7+, use Assembly Load Context (ALC) to avoid conflicts.
try {
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-Verbose 'PS7+ detected. Using AssemblyLoadContext'
        # Initialize module-scope variable
        $script:MsalLoadContext = $null
        $script:MsalLoadContext = Add-MsalAssembly -ModuleRoot $PSScriptRoot
        Write-Verbose "MsalLoadContext: $($script:MsalLoadContext)"
    } else {
        Write-Verbose 'PS 5.1 Detected. Using Add-Type'
        $MsalDllPath = Join-Path $PSScriptRoot 'lib\Microsoft.Identity.Client.dll'
        Add-Type -Path $MsalDllPath
    }
} catch {
    Write-Error "Failed to load MSAL assembly: $_"
}

# Unload the assembly on module removal (ALC requires PS 7 or higher). May not work yet.
if ($PSVersionTable.PSVersion.Major -ge 7) {
    # The OnRemove script block will form a closure, capturing the current
    # value of $script:MsalLoadContext. This ensures that the AssemblyLoadContext
    # object is available when the module is removed.
    $capturedContext = $script:MsalLoadContext
    $MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
        if ($null -ne $capturedContext) {
            try {
                $ContextName = $capturedContext.Name
                $capturedContext.Unload()
                Remove-Variable capturedContext -ErrorAction SilentlyContinue

                # Force garbage collection to promptly unload the DLLs.
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                [System.GC]::Collect()

                Write-Verbose "Unloaded AssemblyLoadContext: $ContextName" -Verbose
            } catch {
                Write-Warning "Failed to unload MSAL assembly: $_"
            }
        }
    }
}
