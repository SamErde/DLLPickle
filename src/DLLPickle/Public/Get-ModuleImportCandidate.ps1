    function Get-ModuleImportCandidate {
        <#
        .SYNOPSIS
        Reports the version, path, and scope that would be imported for a given module name.

        .DESCRIPTION
        Searches PSModulePath in order to determine which version of a module would be imported
        by Import-Module, mimicking PowerShell's module resolution logic.

        .PARAMETER Name
        The name or array of names of the module to check.

        .PARAMETER Scope
        Limits the search to modules installed for the CurrentUser, AllUsers, or Any (default) scope.

        .OUTPUTS
        A full [System.Management.Automation.PSModuleInfo] object with a Scope and custom type name (DLLPickle.ModuleImportCandidate) added.

        .EXAMPLE
        Get-ModuleImportCandidate -Name "Pester"
        Gets the effective module information for Pester from any scope.

        .EXAMPLE
        Get-ModuleImportCandidate "PSReadLine" -Scope CurrentUser
        Gets the effective module information for PSReadLine only from the CurrentUser scope.

        .EXAMPLE
        "Pester", "PSReadLine" | Get-ModuleImportCandidate
        Gets the effective module information for multiple modules from any scope.
        #>
        [CmdletBinding()]
        [OutputType([PSCustomObject])]
        param(
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [ValidateNotNullOrEmpty()]
            [string[]]$Name,

            [Parameter(Mandatory = $false)]
            [ValidateSet('CurrentUser', 'AllUsers', 'Any')]
            [string]$Scope = 'Any'
        )

        begin {
            # Set a flag to indicate if the module path was found.
            $FoundModule = $false

            # Split PSModulePath into individual paths, using a switch statement to only get paths in the specified scope or default to any scope.
            $ScopeFilter = switch ($Scope) {
                'CurrentUser' { [ScriptBlock] { $_ -like "$HOME*" -and (Test-Path -Path $_ -PathType Container -ErrorAction SilentlyContinue) } }
                'AllUsers' { [ScriptBlock] { $_ -notlike "$HOME*" -and (Test-Path -Path $_ -PathType Container -ErrorAction SilentlyContinue) } }
                'Any' { [ScriptBlock] { Test-Path -Path $_ -PathType Container -ErrorAction SilentlyContinue } }
            }
            $ModulePaths = $env:PSModulePath -split [System.IO.Path]::PathSeparator |
                Where-Object -FilterScript $ScopeFilter
        } # end begin

        process {

            foreach ($ModuleName in $Name) {
                $FoundModule = $false
                foreach ($BasePath in $ModulePaths) {
                    # Get the full module path and scope to check.
                    $ModuleFolder = Join-Path -Path $BasePath -ChildPath $ModuleName
                    $BasePathScope = if ($BasePath -like "$HOME*") { 'CurrentUser' } else { 'AllUsers' }
                    if (Test-Path -Path $ModuleFolder) {
                        # Found the module, now get the highest version for directories that can be parsed as versions.
                        $VersionFolders = Get-ChildItem -Path $ModuleFolder -Directory -ErrorAction SilentlyContinue |
                            Where-Object { [version]::TryParse($_.Name, [ref]$null) } |
                                Sort-Object { [version]$_.Name } -Descending

                        if ($VersionFolders) {
                            $HighestVersion = $VersionFolders | Select-Object -ExpandProperty Name -First 1
                            $ModuleInfo = Get-Module -Name $ModuleName -ListAvailable |
                                Where-Object { $_.Version -eq [version]$HighestVersion }
                            $ModuleInfo | Add-Member -MemberType NoteProperty -Name Scope -Value $BasePathScope
                            $ModuleInfo.PSObject.TypeNames.Insert(0, 'DLLPickle.ModuleImportCandidate')
                        } else {
                            # Module folder exists but no version sub-folders.
                            $ModuleInfo = Get-Module -Name $ModuleName -ListAvailable | Sort-Object -Property Version -Descending -Unique | Select-Object -First 1
                            $ModuleInfo | Add-Member -MemberType NoteProperty -Name Scope -Value $BasePathScope
                            $ModuleInfo.PSObject.TypeNames.Insert(0, 'DLLPickle.ModuleImportCandidate')
                        } # end if VersionFolders

                        # Stop searching after first match
                        $FoundModule = $true
                        break
                    } # end if Test-Path ModuleFolder
                } # end foreach BasePath

                if ($FoundModule) {
                    # Output the module info object
                    $ModuleInfo
                } else {
                    # Module not found in any path. Return an empty, but named object with null properties.
                    Write-Warning "Module '$ModuleName' not found in PSModulePath (Scope: $Scope).`n"
                    $null
                } # end if FoundModule
            } # end foreach ModuleName
        } # end process
    } # end function Get-ModuleImportCandidate
