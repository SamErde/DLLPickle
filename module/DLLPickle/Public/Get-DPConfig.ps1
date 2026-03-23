function Get-DPConfig {
    <#
    .SYNOPSIS
    Gets the current DLLPickle configuration.

    .DESCRIPTION
    Reads the DLLPickle configuration from the current user's Application Data folder. If the configuration file does
    not exist, cannot be read, or contains invalid JSON, default configuration values are returned.

    .OUTPUTS
    PSCustomObject
    Returns a configuration object with CheckForUpdates, ShowLogo, and SkipLibraries properties.

    .EXAMPLE
    Get-DPConfig

    Returns the current configuration values.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    process {
        $Defaults = @{
            CheckForUpdates = $true
            ShowLogo        = $true
            SkipLibraries   = @()
        }

        $AppData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ApplicationData)
        $ConfigDir = Join-Path -Path $AppData -ChildPath 'DLLPickle'
        $ConfigFile = Join-Path -Path $ConfigDir -ChildPath 'config.json'

        if (-not (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) {
            Write-Verbose "No configuration file found at '$ConfigFile'. Returning defaults."
            return [PSCustomObject]$Defaults
        }

        try {
            $RawContent = Get-Content -LiteralPath $ConfigFile -Raw -ErrorAction Stop
            $ParsedConfig = $RawContent | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new("Failed to load configuration from '$ConfigFile'.", $_.Exception),
                'DPConfigReadFailed',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $ConfigFile
            )
            $PSCmdlet.WriteError($ErrorRecord)
            return [PSCustomObject]$Defaults
        }

        $NormalizedConfig = [PSCustomObject]@{
            CheckForUpdates = if ($null -ne $ParsedConfig.CheckForUpdates) { [bool]$ParsedConfig.CheckForUpdates } else { [bool]$Defaults.CheckForUpdates }
            ShowLogo        = if ($null -ne $ParsedConfig.ShowLogo) { [bool]$ParsedConfig.ShowLogo } else { [bool]$Defaults.ShowLogo }
            SkipLibraries   = if ($null -ne $ParsedConfig.SkipLibraries) { @([string[]]$ParsedConfig.SkipLibraries) } else { @([string[]]$Defaults.SkipLibraries) }
        }

        Write-Verbose "Configuration loaded from '$ConfigFile'."
        return $NormalizedConfig
    }
}
