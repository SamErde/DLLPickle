function Invoke-DPConflictCheck {
    <#
    .SYNOPSIS
        After preload, warns about (or arms a best-effort one-shot warning for) known incompatible
        module pairs.
    .DESCRIPTION
        For each known conflict: if every module is already loaded, warn immediately. Otherwise, if
        every module is installed (so the clash can still happen later), register a single AssemblyLoad
        handler that warns only once every module in the pair has actually been co-loaded, then
        unregisters itself.

        Best-effort and advisory: it is fully guarded and never throws, is skipped under Constrained
        Language Mode, and warns at most once per conflict per session. It cannot pre-empt a module
        whose import fails outright before any of its assemblies load (a rejected load raises no
        AssemblyLoad event), and it keys on imported modules, so a module removed with Remove-Module
        after its assemblies are already resident is not re-detected. Test-DPLibraryConflict is the
        reliable on-demand check; the authoritative protection is the separate-process workaround.
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

            # Warn/arm at most once per conflict per session: repeated Import-DPLibrary calls must not
            # stack AssemblyLoad handlers or re-emit the same warning. Module-scoped so it persists.
            if (-not $script:DPConflictHandled) {
                $script:DPConflictHandled = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            }

            $LoadedNames = @(Get-Module | Select-Object -ExpandProperty Name)

            foreach ($Conflict in $Conflicts) {
                $Modules = @($Conflict.modules)
                if ($Modules.Count -eq 0) { continue }

                $ConflictId = [string]$Conflict.id
                if ($ConflictId -and $script:DPConflictHandled.Contains($ConflictId)) { continue }

                $LoadedCount = @($Modules | Where-Object { $LoadedNames -contains $_ }).Count
                if ($LoadedCount -eq $Modules.Count) {
                    Write-Warning -Message (Format-DPConflictWarning -Conflict $Conflict)
                    if ($ConflictId) { [void]$script:DPConflictHandled.Add($ConflictId) }
                    continue
                }

                # Arm a watch for the not-yet-loaded module(s). For each, collect ALL installed version
                # base paths (a version-pinned import may load from a non-latest copy). Query only these
                # specific module names, not all of PSModulePath. Arm only when every one is installed.
                $NotLoaded = @($Modules | Where-Object { $LoadedNames -notcontains $_ })
                $WatchedModule = [System.Collections.Generic.List[object]]::new()
                $AllInstalled = $true
                foreach ($Name in $NotLoaded) {
                    # Normalize each base to end with a directory separator so the handler's StartsWith
                    # check is a true directory-prefix match (e.g. '...\Az.Storage\' must not match a
                    # sibling '...\Az.Storage.Custom\').
                    $Bases = @(
                        Get-Module -ListAvailable -Name $Name |
                            ForEach-Object {
                                if ($_.ModuleBase) {
                                    $Full = [System.IO.Path]::GetFullPath($_.ModuleBase)
                                    if (-not $Full.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
                                        $Full += [System.IO.Path]::DirectorySeparatorChar
                                    }
                                    $Full
                                }
                            } |
                            Select-Object -Unique
                    )
                    if ($Bases.Count -eq 0) { $AllInstalled = $false; break }
                    $WatchedModule.Add([PSCustomObject]@{ Name = $Name; Bases = $Bases })
                }
                if (-not $AllInstalled -or $WatchedModule.Count -eq 0) { continue }

                # The handler marks a watched module "seen" when an assembly loads from any of its base
                # paths, and warns only once EVERY watched module has been seen (i.e. the whole pair is
                # co-loaded) - not when just one of them loads.
                $State = [PSCustomObject]@{
                    Conflict = $Conflict
                    Watched  = $WatchedModule.ToArray()
                    Seen     = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    Handler  = $null
                }
                $State.Handler = [System.AssemblyLoadEventHandler]{
                    param($EventSender, $LoadArgs)
                    [void]$EventSender
                    try {
                        $Location = $LoadArgs.LoadedAssembly.Location
                        if ($Location) {
                            $FullLocation = [System.IO.Path]::GetFullPath($Location)
                            foreach ($Module in $State.Watched) {
                                foreach ($Base in $Module.Bases) {
                                    if ($FullLocation.StartsWith($Base, [System.StringComparison]::OrdinalIgnoreCase)) {
                                        [void]$State.Seen.Add($Module.Name)
                                        break
                                    }
                                }
                            }
                            if ($State.Seen.Count -ge $State.Watched.Count) {
                                Write-Warning -Message (Format-DPConflictWarning -Conflict $State.Conflict)
                                [System.AppDomain]::CurrentDomain.remove_AssemblyLoad($State.Handler)
                            }
                        }
                    } catch {
                        Write-Verbose "AssemblyLoad conflict-watch handler error (advisory, suppressed): $_"
                    }
                }.GetNewClosure()
                [System.AppDomain]::CurrentDomain.add_AssemblyLoad($State.Handler)
                if ($ConflictId) { [void]$script:DPConflictHandled.Add($ConflictId) }
            }
        } catch {
            Write-Verbose "Conflict check skipped due to error: $_"
        }
    }
}
