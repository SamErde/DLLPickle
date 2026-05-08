function Import-DPBaseProfile {
    <#
    .SYNOPSIS
    Imports DLLPickle libraries and the validated base Microsoft service modules.

    .DESCRIPTION
    Imports DLLPickle's dependency libraries, then imports the base profile modules
    in the order validated for module import on Windows PowerShell 5.1 and
    PowerShell 7+.

    The default base profile order is ExchangeOnlineManagement, MicrosoftTeams,
    Microsoft.Graph.Authentication, and Az.Accounts. Windows PowerShell 5.1 is
    sensitive to this order because Az.Accounts can load an older Azure.Core
    identity before Microsoft.Graph.Authentication.

    In Windows PowerShell 5.1, Az.Accounts can still fail during
    Connect-AzAccount after Graph or Exchange has loaded its own Azure.Identity
    assemblies. Use PowerShell 7+ or process isolation for Az authentication when
    the full base profile must connect to all services.

    .PARAMETER ModuleName
    The modules to import after DLLPickle preloads its dependency libraries.
    Defaults to the validated base profile.

    .PARAMETER Force
    Re-import modules even if they are already loaded.

    .PARAMETER ShowLoaderExceptions
    Display detailed loader exception information from Import-DPLibrary.

    .PARAMETER SuppressLogo
    Suppress the DLLPickle logo during Import-DPLibrary.

    .EXAMPLE
    Import-DPBaseProfile

    Imports DLLPickle libraries, then imports ExchangeOnlineManagement,
    MicrosoftTeams, Microsoft.Graph.Authentication, and Az.Accounts.

    .EXAMPLE
    Import-DPBaseProfile -Force -SuppressLogo

    Re-imports the validated base profile order without displaying the logo.

    .OUTPUTS
    System.Management.Automation.PSCustomObject

    Returns one result for the DLLPickle preload step and one result for each
    imported module.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$ModuleName = @(
            'ExchangeOnlineManagement'
            'MicrosoftTeams'
            'Microsoft.Graph.Authentication'
            'Az.Accounts'
        ),

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$ShowLoaderExceptions,

        [Parameter()]
        [switch]$SuppressLogo
    )

    process {
        $PreloadParameters = @{}
        if ($ShowLoaderExceptions) {
            $PreloadParameters.ShowLoaderExceptions = $true
        }
        if ($SuppressLogo) {
            $PreloadParameters.SuppressLogo = $true
        }

        $PreloadResult = @(Import-DPLibrary @PreloadParameters)
        [PSCustomObject]@{
            PSTypeName = 'DLLPickle.ImportDPBaseProfileResult'
            Name       = 'DLLPickle'
            Version    = $null
            Kind       = 'DependencyPreload'
            Status     = if (@($PreloadResult | Where-Object Status -EQ 'Failed').Count -eq 0) { 'Imported' } else { 'Failed' }
            Error      = $null
        }

        if ($PSVersionTable.PSEdition -eq 'Desktop' -and $ModuleName -contains 'Az.Accounts') {
            Write-Warning ('Windows PowerShell can import the base profile order, but Connect-AzAccount may still fail after Graph or Exchange loads Azure.Identity. Use PowerShell 7+ or isolate Az.Accounts authentication in a separate process when this occurs.')
        }

        foreach ($Module in $ModuleName) {
            try {
                $ImportParameters = @{
                    Name        = $Module
                    ErrorAction = 'Stop'
                }
                if ($Force) {
                    $ImportParameters.Force = $true
                }

                $ImportedModule = Import-Module @ImportParameters -PassThru | Select-Object -First 1
                [PSCustomObject]@{
                    PSTypeName = 'DLLPickle.ImportDPBaseProfileResult'
                    Name       = $Module
                    Version    = if ($ImportedModule) { $ImportedModule.Version.ToString() } else { $null }
                    Kind       = 'Module'
                    Status     = 'Imported'
                    Error      = $null
                }
            } catch {
                [PSCustomObject]@{
                    PSTypeName = 'DLLPickle.ImportDPBaseProfileResult'
                    Name       = $Module
                    Version    = $null
                    Kind       = 'Module'
                    Status     = 'Failed'
                    Error      = $_.Exception.Message
                }

                $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $_.Exception,
                    'DPBaseProfileModuleImportFailed',
                    [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
                    $Module
                )
                $PSCmdlet.ThrowTerminatingError($ErrorRecord)
            }
        }
    }
}
