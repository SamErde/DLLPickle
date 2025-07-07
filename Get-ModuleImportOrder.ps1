function Get-ModuleImportOrder {
    <#
    .SYNOPSIS
    Evaluates the import order of specified modules based on their versions and the location in PSModulePath.

    .DESCRIPTION
    This function evaluates the import order of specified modules based on their versions and the location in PSModulePath.
    It uses Get-ModuleImportCandidate to determine which version of each module would be imported by Import-Module,
    and then sorts them by the version of 'Microsoft.Identity.Client.dll' that is packaged with each module.

    .PARAMETER Name
    A list of module names to evaluate for proper import order. Wildcards are allowed.

    .EXAMPLE
    Get-ModuleImportOrder -Name 'Az.Accounts','ExchangeOnlineManagement'

    Returns a list of modules ordered by the version of 'Microsoft.Identity.Client.dll' they contain.

    #>
    [CmdletBinding()]
    param(
        # A list of module names to evaluate for proper import and connection order.
        [Parameter(
            Position = 0,
            ValueFromPipelineByPropertyName,
            HelpMessage = 'Enter a list of names to evaluate. Wildcards are allowed.'
        )]
        [string[]]$Name
    )

    process {
        $ModulesWithVersionSortedIdentityClient = Get-ModulesWithVersionSortedIdentityClient -Name $Name
        $ModulesWithVersionSortedIdentityClient
    } # end process block

} # end function
