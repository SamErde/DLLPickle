function Get-ModulesWithVersionSortedIdentityClient {
    [CmdletBinding()]
    param(
        # A list of module names to evaluate for proper import order.
        [Parameter(
            Position = 0,
            ValueFromPipelineByPropertyName,
            HelpMessage = 'Enter a list of names to evaluate. Wildcards are allowed.'
        )]
        [string[]]$Name
    )

    begin {
        $ModulesWithVersionSortedIdentityClient = [System.Collections.Generic.List[PSCustomObject]]::new()
    } # end begin block

    process {

        # Call the function to determine the path and version of each module.
        $ModuleInfo = Get-ModuleImportCandidate -Name $Name

        # Find the version of 'Microsoft.Identity.Client.dll' that is packaged with each module.
        foreach ($Module in $ModuleInfo) {
            $DllVersion = Get-ChildItem -Path $Module.ModuleBase -File -Include 'Microsoft.Identity.Client.dll' -Recurse -Force |
                Sort-Object -Property { $_.VersionInfo.FileVersion } -Descending |
                    Select-Object -First 1 -Property @{Name = 'DLLVersion'; Expression = { [version]($_.VersionInfo.FileVersion) } }

            if (-not $DllVersion) {
                Write-Verbose "No 'Microsoft.Identity.Client.dll' found in $($Module.ModuleBase)."
                continue
            }

            # Store the module and DLL information in a custom object.
            $ThisModule = [PSCustomObject]@{
                Name          = $Module.Name
                ModuleBase    = $Module.ModuleBase
                ModuleVersion = $Module.Version
                DLLVersion    = $DllVersion.DLLVersion
            }

            # Add the module information to the ordered list.
            $ModulesWithVersionSortedIdentityClient.Add($ThisModule)
        }

        # Sort the modules by DLL version in descending order.
        $ModulesWithVersionSortedIdentityClient = $ModulesWithVersionSortedIdentityClient | Sort-Object -Property DLLVersion -Descending
        $ModulesWithVersionSortedIdentityClient
    } # end process block
} # end Get-ModulesWithVersionSortedIdentityClient function
