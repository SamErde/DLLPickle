function Invoke-DPConflictCheck {
    <#
    .SYNOPSIS
        After preload, warns about (or arms a one-shot warning for) known incompatible module pairs.
    .DESCRIPTION
        For each known conflict: if every module is already loaded, warn immediately. Otherwise, if
        every module is installed (so the clash can still happen later), register a single
        AssemblyLoad handler that warns the first time the remaining module's assemblies load, then
        unregisters itself. Advisory only: fully guarded, never throws, and skipped under Constrained
        Language Mode (where the AppDomain APIs are unavailable).
    .PARAMETER KnownConflictsPath
        Optional override for the knownConflicts file (testing). Defaults to the shipped file.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$KnownConflictsPath
    )

    process {
        try {
            if ($ExecutionContext.SessionState.LanguageMode -eq [System.Management.Automation.PSLanguageMode]::ConstrainedLanguage) {
                Write-Verbose 'Constrained Language Mode: skipping conflict-watch arming.'
                return
            }

            $Conflicts = Get-DPKnownConflict -Path $KnownConflictsPath
            if (@($Conflicts).Count -eq 0) { return }

            $LoadedNames = @(Get-Module | Select-Object -ExpandProperty Name)
            $AvailableNames = @(Get-Module -ListAvailable | Select-Object -ExpandProperty Name -Unique)

            foreach ($Conflict in $Conflicts) {
                $Modules = @($Conflict.modules)
                if ($Modules.Count -eq 0) { continue }

                $LoadedCount = @($Modules | Where-Object { $LoadedNames -contains $_ }).Count
                if ($LoadedCount -eq $Modules.Count) {
                    Write-Warning -Message (Format-DPConflictWarning -Conflict $Conflict)
                    continue
                }

                $AllInstalled = $true
                foreach ($Name in $Modules) {
                    if ($AvailableNames -notcontains $Name) { $AllInstalled = $false; break }
                }
                if (-not $AllInstalled) { continue }

                # Watch the not-yet-loaded module(s): capture their installed base path(s) now, and warn
                # the first time an assembly loads from one of them (meaning the pair is now co-loaded).
                $WatchedBase = @(
                    $Modules |
                        Where-Object { $LoadedNames -notcontains $_ } |
                        ForEach-Object { Get-Module -ListAvailable -Name $_ | Sort-Object Version -Descending | Select-Object -First 1 -ExpandProperty ModuleBase } |
                        Where-Object { $_ }
                )
                if ($WatchedBase.Count -eq 0) { continue }

                $State = [PSCustomObject]@{ Conflict = $Conflict; Bases = $WatchedBase; Handler = $null }
                $State.Handler = [System.AssemblyLoadEventHandler]{
                    param($EventSender, $LoadArgs)
                    [void]$EventSender
                    try {
                        $Location = $LoadArgs.LoadedAssembly.Location
                        if ($Location) {
                            foreach ($Base in $State.Bases) {
                                if ($Location.StartsWith($Base, [System.StringComparison]::OrdinalIgnoreCase)) {
                                    Write-Warning -Message (Format-DPConflictWarning -Conflict $State.Conflict)
                                    [System.AppDomain]::CurrentDomain.remove_AssemblyLoad($State.Handler)
                                    break
                                }
                            }
                        }
                    } catch {
                        Write-Verbose "AssemblyLoad conflict-watch handler error (advisory, suppressed): $_"
                    }
                }.GetNewClosure()
                [System.AppDomain]::CurrentDomain.add_AssemblyLoad($State.Handler)
            }
        } catch {
            Write-Verbose "Conflict check skipped due to error: $_"
        }
    }
}
