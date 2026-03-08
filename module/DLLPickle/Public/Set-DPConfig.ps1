function Set-DPConfig {
    <#
    .SYNOPSIS
    Sets DLLPickle configuration options.

    .DESCRIPTION
    Modifies DLLPickle configuration settings stored in the current user's application data folder.
    Configuration is persisted as a JSON file. If the configuration file does not exist, it is created
    with default values, then the specified settings are applied.

    Individual parameters can be updated independently without affecting other settings. Use the -Reset
    parameter to restore all configuration to defaults.

    .PARAMETER CheckForUpdates
    Enable or disable automatic check for updates when importing the DLLPickle module.
    Default value is $true if not specified.

    .PARAMETER ShowLogo
    Show or hide the DLLPickle logo during execution.
    Default value is $true if not specified.

    .PARAMETER SkipLibraries
    Array of library (DLL) filenames to skip during Import-DPLibrary operations (use for testing exclusions).
    Filenames should be specified without path (e.g., 'DLLPickle1.dll', 'DLLPickle2.dll').

    .PARAMETER Reset
    Reset all configuration settings to defaults. When specified, all other parameters are ignored and
    the configuration file is overwritten with defaults.

    .PARAMETER PassThru
    Returns the updated configuration object. By default, no output is generated.

    .EXAMPLE
    Set-DPConfig -CheckForUpdates $false

    Disables automatic update checks while preserving other configuration settings.

    .EXAMPLE
    Set-DPConfig -SkipLibraries @('DLLPickle1.dll', 'DLLPickle2.dll')

    Sets the list of libraries to skip during import operations.

    .EXAMPLE
    Set-DPConfig -Reset

    Resets all configuration to defaults.

    .EXAMPLE
    Set-DPConfig -ShowLogo $false -PassThru

    Disables the DLLPickle logo and returns the updated configuration object.

    .OUTPUTS
    PSCustomObject
    When the -PassThru parameter is specified, returns a configuration object with properties:
    - CheckForUpdates [bool]
    - ShowLogo [bool]
    - SkipLibraries [string[]]

    .NOTES
    The function follows XDG standard conventions or standard Windows locations for application data files.
    #>
    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'Low'
    )]
    # Suppress warnings about PSAvoidUsingWriteHost since we want to provide user feedback on successful updates.
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Provide user feedback on successful updates.')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(
            HelpMessage = 'Enable or disable automatic check for updates.'

        )]
        [bool]$CheckForUpdates,

        [Parameter(
            HelpMessage = 'Show or hide the DLLPickle logo during execution.'
        )]
        [bool]$ShowLogo,

        [Parameter(
            HelpMessage = 'List of library (DLL) filenames to skip during Import-DPLibrary.'
        )]
        [ValidateNotNull()]
        [string[]]$SkipLibraries,

        [Parameter(
            HelpMessage = 'Reset configuration to module defaults.'
        )]
        [switch]$Reset,

        [Parameter(
            HelpMessage = 'Return the updated configuration object.'
        )]
        [switch]$PassThru
    )

    process {
        # Define configuration paths using .NET for cross-platform compatibility
        $AppData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ApplicationData)
        $ConfigDir = Join-Path -Path $AppData -ChildPath 'DLLPickle'
        $ConfigFile = Join-Path -Path $ConfigDir -ChildPath 'config.json'

        # Define factory default settings
        $DefaultSettings = @{
            CheckForUpdates = $true
            ShowLogo        = $true
            SkipLibraries   = @()
        }

        # Create the configuration directory if it doesn't exist
        if (-not (Test-Path -LiteralPath $ConfigDir -PathType Container)) {
            Write-Verbose "Creating configuration directory at '$ConfigDir'."
            try {
                New-Item -ItemType Directory -Path $ConfigDir -Force -ErrorAction Stop | Out-Null
            } catch {
                $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new(
                        "Failed to create configuration directory at '$ConfigDir'.",
                        $_.Exception
                    ),
                    'DPConfigDirectoryCreateFailed',
                    [System.Management.Automation.ErrorCategory]::WriteError,
                    $ConfigDir
                )
                $PSCmdlet.ThrowTerminatingError($ErrorRecord)
            }
        }

        # Load existing configuration or use defaults
        if ($Reset) {
            Write-Verbose 'Resetting configuration to module defaults.'
            if (-not $PSCmdlet.ShouldProcess($ConfigFile, 'Reset to module defaults')) {
                return
            }
            $CurrentSettings = $DefaultSettings.Clone()
        } elseif (Test-Path -LiteralPath $ConfigFile -PathType Leaf) {
            Write-Verbose "Loading existing configuration from '$ConfigFile'."
            try {
                $RawContent = Get-Content -LiteralPath $ConfigFile -Raw -ErrorAction Stop
                $ParsedConfig = $RawContent | ConvertFrom-Json -ErrorAction Stop -AsHashtable
                $CurrentSettings = $ParsedConfig
            } catch {
                $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new(
                        "Failed to load configuration from '$ConfigFile'. Using module defaults.",
                        $_.Exception
                    ),
                    'DPConfigReadFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $ConfigFile
                )
                $PSCmdlet.WriteError($ErrorRecord)
                $CurrentSettings = $DefaultSettings.Clone()
            }
        } else {
            Write-Verbose 'No existing configuration found. Using factory defaults.'
            $CurrentSettings = $DefaultSettings.Clone()
        }

        # Update only the values provided by the user
        if ($PSBoundParameters.ContainsKey('CheckForUpdates')) {
            $CurrentSettings.CheckForUpdates = $CheckForUpdates
            Write-Verbose "Set CheckForUpdates = $CheckForUpdates"
        }
        if ($PSBoundParameters.ContainsKey('ShowLogo')) {
            $CurrentSettings.ShowLogo = $ShowLogo
            Write-Verbose "Set ShowLogo = $ShowLogo"
        }
        if ($PSBoundParameters.ContainsKey('SkipLibraries')) {
            $CurrentSettings.SkipLibraries = @([string[]]$SkipLibraries)
            Write-Verbose "Set SkipLibraries = $($CurrentSettings.SkipLibraries -join ', ')"
        }

        # Normalize configuration shape to ensure expected types are always present.
        [string[]]$NormalizedSkipLibraries = @()
        if ($null -ne $CurrentSettings.SkipLibraries) {
            $NormalizedSkipLibraries = @($CurrentSettings.SkipLibraries | ForEach-Object { [string]$_ })
        }

        $CurrentSettings = @{
            CheckForUpdates = if ($null -ne $CurrentSettings.CheckForUpdates) { [bool]$CurrentSettings.CheckForUpdates } else { [bool]$DefaultSettings.CheckForUpdates }
            ShowLogo        = if ($null -ne $CurrentSettings.ShowLogo) { [bool]$CurrentSettings.ShowLogo } else { [bool]$DefaultSettings.ShowLogo }
            SkipLibraries   = $NormalizedSkipLibraries
        }

        # Write configuration to disk with error handling
        try {
            # Use an explicit UTF8 encoding instance to avoid provider-specific string conversion issues.
            $Utf8Encoding = [System.Text.UTF8Encoding]::new($false)
            $CurrentSettings | ConvertTo-Json -ErrorAction Stop | Out-File -LiteralPath $ConfigFile -Force -Encoding $Utf8Encoding -ErrorAction Stop
            Write-Verbose "Configuration saved to '$ConfigFile'."
        } catch {
            $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new(
                    "Failed to save configuration to '$ConfigFile'.",
                    $_.Exception
                ),
                'DPConfigWriteFailed',
                [System.Management.Automation.ErrorCategory]::WriteError,
                $ConfigFile
            )
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }

        # Return the configuration if PassThru is specified
        if ($PassThru) {
            [PSCustomObject]$CurrentSettings
        } else {
            Write-Host 'Configuration updated successfully.' -ForegroundColor Green
        }
    }
}
