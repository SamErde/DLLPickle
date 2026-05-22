function Import-DPBaseProfile {
    <#
    .SYNOPSIS
    Imports DLLPickle libraries and the validated base Microsoft service modules.

    .DESCRIPTION
    Imports DLLPickle's dependency libraries, then imports the base profile modules
    in a validated import order for mixed Microsoft service module sessions.

    The default base profile order is ExchangeOnlineManagement, MicrosoftTeams,
    Microsoft.Graph.Authentication, and Az.Accounts.

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
        $FailedPreloadResult = @($PreloadResult | Where-Object Status -EQ 'Failed')
        $PreloadError = if ($FailedPreloadResult.Count -eq 0) {
            $null
        } else {
            @(
                foreach ($FailedResult in $FailedPreloadResult) {
                    if ($FailedResult.DLLName -and $FailedResult.Error) {
                        '{0}: {1}' -f $FailedResult.DLLName, $FailedResult.Error
                    } elseif ($FailedResult.DLLName) {
                        '{0} failed to import.' -f $FailedResult.DLLName
                    } elseif ($FailedResult.Error) {
                        $FailedResult.Error
                    } else {
                        'An unknown DLL preload failure occurred.'
                    }
                }
            ) -join [System.Environment]::NewLine
        }
        [PSCustomObject]@{
            PSTypeName = 'DLLPickle.ImportDPBaseProfileResult'
            Name       = 'DLLPickle'
            Version    = $null
            Kind       = 'DependencyPreload'
            Status     = if ($FailedPreloadResult.Count -eq 0) { 'Imported' } else { 'Failed' }
            Error      = $PreloadError
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
