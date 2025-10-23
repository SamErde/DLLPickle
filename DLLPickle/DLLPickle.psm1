# Initialize module-scope variable
$script:MsalLoadContext = $null

# Dot-source public/private functions.
$Public  = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public/*.ps1')  -Recurse -ErrorAction Stop)
$Private = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private/*.ps1') -Recurse -ErrorAction Stop)
foreach ($Import in @($Public + $Private)) {
    try {
        . $Import.FullName
    } catch {
        throw "Unable to dot source [$($Import.FullName)]"
    }
}

Export-ModuleMember -Function $Public.Basename

# Load the assembly on module import. In PowerShell 7+, use Assembly Load Context (ALC) to avoid conflicts.
try {
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-Verbose 'PS7+ detected. Using AssemblyLoadContext' -Verbose
        $script:MsalLoadContext = Add-MsalAssembly  -ModuleRoot $PSScriptRoot
        Write-Verbose "MsalLoadContext: $($script:MsalLoadContext)" -Verbose
    } else {
        Write-Verbose 'PS 5.1 Detected. Using Add-Type' -Verbose
        $MsalDllPath = Join-Path $PSScriptRoot 'lib\Microsoft.Identity.Client.dll'
        Add-Type -Path $MsalDllPath
    }
} catch {
    Write-Error "Failed to load MSAL assembly: $_"
}

# Unload the assembly on module removal (ALC requires PS 7 or higher).
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        # Access the module's script scope variable directly
        if ($null -ne $script:MsalLoadContext) {
            try {
                $ContextName = $script:MsalLoadContext.Name
                $script:MsalLoadContext.Unload()
                $script:MsalLoadContext = $null

                # Force garbage collection
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
