function Invoke-DPConflictCheck {
    <#
    .SYNOPSIS
        Warns about known incompatible module pairs that are already loaded.
    .DESCRIPTION
        Compares the shipped known-conflict data with modules currently loaded in the session and
        emits each conflict warning at most once. This advisory check never installs CLR assembly
        event handlers; use Test-DPLibraryConflict for a reliable on-demand check after later imports.
    .PARAMETER KnownConflictsPath
        Optional override for the known-conflicts file used by tests. Defaults to the shipped file.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$KnownConflictsPath
    )

    process {
        try {
            $Conflicts = Get-DPKnownConflict -Path $KnownConflictsPath
            if (@($Conflicts).Count -eq 0) {
                return
            }

            if (-not $script:DPConflictHandled) {
                $script:DPConflictHandled = [System.Collections.Generic.HashSet[string]]::new(
                    [System.StringComparer]::OrdinalIgnoreCase
                )
            }

            $LoadedNames = @(Get-Module | Select-Object -ExpandProperty Name)
            foreach ($Conflict in $Conflicts) {
                $Modules = @($Conflict.modules)
                if ($Modules.Count -eq 0) {
                    continue
                }

                $ConflictId = [string]$Conflict.id
                if ($ConflictId -and $script:DPConflictHandled.Contains($ConflictId)) {
                    continue
                }

                $LoadedCount = @($Modules | Where-Object { $LoadedNames -contains $_ }).Count
                if ($LoadedCount -ne $Modules.Count) {
                    continue
                }

                Write-Warning -Message (Format-DPConflictWarning -Conflict $Conflict)
                if ($ConflictId) {
                    [void]$script:DPConflictHandled.Add($ConflictId)
                }
            }
        } catch {
            Write-Verbose "Conflict check skipped due to error: $_"
        }
    }
}

