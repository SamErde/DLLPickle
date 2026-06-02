function Test-DPLibraryConflict {
    <#
    .SYNOPSIS
        Reports known module conflicts that are active in the current PowerShell session.
    .DESCRIPTION
        Compares DLLPickle's shipped knownConflicts list against the modules currently imported and
        writes a warning for each conflict whose modules are all loaded together (a combination known
        to fail, such as Az.Storage + ExchangeOnlineManagement sharing an incompatible Microsoft.OData
        version). Returns the active conflict objects. Advisory only - never throws.
    .PARAMETER KnownConflictsPath
        Optional path to a knownConflicts JSON file. Defaults to the file shipped with the module.
    .OUTPUTS
        The active conflict entries (or nothing if none are active).
    .EXAMPLE
        Test-DPLibraryConflict

        Warns if any known-incompatible module combination is currently loaded.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$KnownConflictsPath
    )

    process {
        $Conflicts = Get-DPKnownConflict -Path $KnownConflictsPath
        $LoadedModule = @(Get-Module | Select-Object -ExpandProperty Name)
        $Active = @(Test-DPModuleConflict -Conflict $Conflicts -LoadedModule $LoadedModule)
        foreach ($Entry in $Active) {
            Write-Warning -Message (Format-DPConflictWarning -Conflict $Entry)
        }
        $Active
    }
}
