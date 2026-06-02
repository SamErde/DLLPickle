function Test-DPModuleConflict {
    <#
    .SYNOPSIS
        Returns the known conflicts whose every module is currently loaded.
    .DESCRIPTION
        Pure comparison: given the knownConflicts data and the set of loaded module names, returns the
        conflict entries where every module in the pair appears in the loaded set. No side effects.
    .PARAMETER Conflict
        The knownConflicts entries (each with a .modules string array).
    .PARAMETER LoadedModule
        The names of modules currently imported in the session.
    .OUTPUTS
        The subset of Conflict whose modules are all loaded.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$Conflict,

        [Parameter()]
        [string[]]$LoadedModule
    )

    process {
        foreach ($Entry in @($Conflict)) {
            $Modules = @($Entry.modules)
            if ($Modules.Count -eq 0) { continue }
            $AllLoaded = $true
            foreach ($Name in $Modules) {
                if ($LoadedModule -notcontains $Name) { $AllLoaded = $false; break }
            }
            if ($AllLoaded) { $Entry }
        }
    }
}
