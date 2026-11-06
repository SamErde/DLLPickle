function Get-DPConfig {
    <#
    .SYNOPSIS
    Gets the current DLLPickle configuration.

    .DESCRIPTION
    Reads the DLLPickle configuration from the current user's Application Data folder. If the configuration file does
    not exist, cannot be read, or contains invalid JSON or invalid setting types, default configuration values are returned.
    The JSON root must be an object. Non-null CheckForUpdates and ShowLogo values must be booleans;
    non-null SkipLibraries must be an array of strings. Missing or null settings use defaults. Unknown settings are ignored.
    Setting names are case-insensitive; repeated recognized settings are rejected. Comments and trailing commas
    are accepted, with JSON nesting limited to 64 levels.

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
            # Inspect JSON kinds before conversion. ConvertFrom-Json can unwrap arrays
            # and convert date-like strings to DateTime on supported PowerShell versions.
            $JsonOptions = [System.Text.Json.JsonDocumentOptions]::new()
            $JsonOptions.CommentHandling = [System.Text.Json.JsonCommentHandling]::Skip
            $JsonOptions.AllowTrailingCommas = $true
            $Document = [System.Text.Json.JsonDocument]::Parse([string]$RawContent, $JsonOptions)
            try {
                if ($Document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
                    throw 'Configuration must be a JSON object.'
                }

                $ParsedConfig = @{}
                foreach ($Property in $Document.RootElement.EnumerateObject()) {
                    $SettingName = $Property.Name
                    if (-not $Defaults.ContainsKey($SettingName)) {
                        continue
                    }
                    if ($ParsedConfig.ContainsKey($SettingName)) {
                        throw "Configuration setting '$SettingName' must not be repeated."
                    }
                    $ParsedConfig[$SettingName] = $null
                    if ($Property.Value.ValueKind -eq [System.Text.Json.JsonValueKind]::Null) {
                        continue
                    }
                    if ($SettingName -eq 'SkipLibraries') {
                        if ($Property.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::Array) {
                            throw 'Configuration setting SkipLibraries must be a JSON array of strings or null.'
                        }
                        $ParsedConfig[$SettingName] = @(
                            foreach ($Library in $Property.Value.EnumerateArray()) {
                                if ($Library.ValueKind -ne [System.Text.Json.JsonValueKind]::String) {
                                    throw 'Configuration setting SkipLibraries must contain only strings.'
                                }
                                $Library.GetString()
                            }
                        )
                    } else {
                        if ($Property.Value.ValueKind -notin @([System.Text.Json.JsonValueKind]::True, [System.Text.Json.JsonValueKind]::False)) {
                            throw "Configuration setting '$SettingName' must be a JSON boolean or null."
                        }
                        $ParsedConfig[$SettingName] = $Property.Value.GetBoolean()
                    }
                }
            } finally {
                $Document.Dispose()
            }
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

        [string[]]$SkipLibraries = @()
        if ($null -ne $ParsedConfig.SkipLibraries) {
            $SkipLibraries = [string[]]$ParsedConfig.SkipLibraries
        }
        $NormalizedConfig = [PSCustomObject]@{
            CheckForUpdates = if ($null -ne $ParsedConfig.CheckForUpdates) { [bool]$ParsedConfig.CheckForUpdates } else { [bool]$Defaults.CheckForUpdates }
            ShowLogo        = if ($null -ne $ParsedConfig.ShowLogo) { [bool]$ParsedConfig.ShowLogo } else { [bool]$Defaults.ShowLogo }
            SkipLibraries   = $SkipLibraries
        }

        Write-Verbose "Configuration loaded from '$ConfigFile'."
        return $NormalizedConfig
    }
}
