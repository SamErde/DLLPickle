function Test-DPVersion {
    <#
    .SYNOPSIS
    Checks whether a newer DLLPickle module version is available.

    .DESCRIPTION
    Gets the highest DLLPickle version installed locally and compares it with the latest available remote version.
    The function checks PowerShell Gallery first and falls back to GitHub releases when needed.

    By default, prerelease versions are ignored. Use IncludePrerelease to consider prerelease versions.

    .PARAMETER IncludePrerelease
    Includes prerelease versions when evaluating source repositories.

    .OUTPUTS
    PSCustomObject
    Returns a stable result object with module/version metadata and update status.

    .EXAMPLE
    Test-DPVersion

    Checks for updates using stable versions only.

    .EXAMPLE
    Test-DPVersion -IncludePrerelease -Verbose

    Checks for updates and allows prerelease versions while emitting verbose diagnostics.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$IncludePrerelease
    )

    begin {
        $ModuleName = 'DLLPickle'
        $CheckedAtUtc = [System.DateTime]::UtcNow

        function Get-DPNormalizedVersionInfo {
            [CmdletBinding()]
            param(
                [Parameter()]
                [AllowNull()]
                [AllowEmptyString()]
                [string]$VersionString,

                [Parameter()]
                [switch]$AllowPrerelease
            )

            if ([string]::IsNullOrWhiteSpace($VersionString)) {
                return $null
            }

            $SanitizedVersionString = $VersionString.Trim()
            $NormalizedVersionString = $SanitizedVersionString -replace '^[vV]', ''
            $IsPrerelease = $NormalizedVersionString -match '-'

            if ($IsPrerelease -and -not $AllowPrerelease.IsPresent) {
                return [PSCustomObject]@{
                    ParsedVersion       = $null
                    NormalizedVersion   = $NormalizedVersionString
                    IsPrerelease        = $true
                    IsIgnoredPrerelease = $true
                }
            }

            $StableVersionSegment = ($NormalizedVersionString -split '[-+]')[0]
            $ParsedVersion = $null

            if (-not [System.Version]::TryParse($StableVersionSegment, [ref]$ParsedVersion)) {
                return $null
            }

            return [PSCustomObject]@{
                ParsedVersion       = $ParsedVersion
                NormalizedVersion   = $NormalizedVersionString
                IsPrerelease        = $IsPrerelease
                IsIgnoredPrerelease = $false
            }
        }

        function New-DPVersionCheckResult {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [bool]$IsSuccess,

                [Parameter()]
                [AllowNull()]
                [System.Version]$CurrentVersion,

                [Parameter()]
                [AllowNull()]
                [System.Version]$LatestVersion,

                [Parameter()]
                [AllowNull()]
                [string]$LatestVersionString,

                [Parameter()]
                [AllowNull()]
                [string]$Source,

                [Parameter()]
                [bool]$IsPrerelease,

                [Parameter(Mandatory)]
                [string]$Message,

                [Parameter()]
                [AllowNull()]
                [string]$Recommendation
            )

            $IsUpdateAvailable = $false
            if ($null -ne $CurrentVersion -and $null -ne $LatestVersion) {
                $IsUpdateAvailable = $LatestVersion -gt $CurrentVersion
            }

            return [PSCustomObject]@{
                PSTypeName          = 'DLLPickle.VersionCheckResult'
                ModuleName          = $ModuleName
                IsSuccess           = $IsSuccess
                CheckedAtUtc        = $CheckedAtUtc
                CurrentVersion      = $CurrentVersion
                LatestVersion       = $LatestVersion
                LatestVersionString = $LatestVersionString
                Source              = $Source
                IncludePrerelease   = [bool]$IncludePrerelease
                IsPrerelease        = $IsPrerelease
                IsUpdateAvailable   = $IsUpdateAvailable
                Message             = $Message
                Recommendation      = $Recommendation
            }
        }
    }

    process {
        $LocalModule = Get-Module -Name $ModuleName -ListAvailable | Sort-Object -Property Version -Descending | Select-Object -First 1
        if (-not $LocalModule) {
            $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.IO.FileNotFoundException]::new("$ModuleName module not found in PSModulePath."),
                'DPModuleNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $ModuleName
            )
            $PSCmdlet.WriteError($ErrorRecord)

            return New-DPVersionCheckResult -IsSuccess $false -CurrentVersion $null -LatestVersion $null -LatestVersionString $null -Source 'Local' -IsPrerelease $false -Message "$ModuleName is not installed locally." -Recommendation "Install-Module $ModuleName"
        }

        $CurrentVersion = [System.Version]$LocalModule.Version
        $LatestVersion = $null
        $LatestVersionString = $null
        $Source = $null
        $IsPrerelease = $false
        $GalleryError = $null
        $GithubError = $null

        Write-Verbose 'Checking PowerShell Gallery for updates.'
        try {
            $GalleryUri = "https://www.powershellgallery.com/api/v2/Packages?`$filter=Id eq '$ModuleName' and IsLatestVersion"
            $GalleryData = Invoke-RestMethod -Uri $GalleryUri -ErrorAction Stop

            $CandidateVersionString = $null
            if ($null -ne $GalleryData -and $null -ne $GalleryData.properties -and $null -ne $GalleryData.properties.Version) {
                $CandidateVersionString = [string]$GalleryData.properties.Version
            }

            $GalleryVersionInfo = Get-DPNormalizedVersionInfo -VersionString $CandidateVersionString -AllowPrerelease:$IncludePrerelease
            if ($null -ne $GalleryVersionInfo -and $null -ne $GalleryVersionInfo.ParsedVersion) {
                $LatestVersion = $GalleryVersionInfo.ParsedVersion
                $LatestVersionString = $GalleryVersionInfo.NormalizedVersion
                $IsPrerelease = [bool]$GalleryVersionInfo.IsPrerelease
                $Source = 'PowerShellGallery'
                Write-Verbose "PowerShell Gallery returned version '$LatestVersionString'."
            } elseif ($null -ne $GalleryVersionInfo -and $GalleryVersionInfo.IsIgnoredPrerelease) {
                Write-Verbose "PowerShell Gallery returned prerelease version '$($GalleryVersionInfo.NormalizedVersion)' and it was ignored."
            }
        } catch {
            $GalleryError = $_
            Write-Verbose "PowerShell Gallery check failed: $($_.Exception.Message)"
        }

        if ($null -eq $LatestVersion) {
            Write-Verbose 'Checking GitHub releases for updates.'
            try {
                $GithubUri = 'https://api.github.com/repos/SamErde/DLLPickle/releases/latest'
                $GithubData = Invoke-RestMethod -Uri $GithubUri -Headers @{ 'User-Agent' = 'DLLPickle-VersionCheck' } -ErrorAction Stop

                $TagName = if ($null -ne $GithubData.tag_name) { [string]$GithubData.tag_name } else { $null }
                $GithubVersionInfo = Get-DPNormalizedVersionInfo -VersionString $TagName -AllowPrerelease:$IncludePrerelease

                if ($null -ne $GithubVersionInfo -and $null -ne $GithubVersionInfo.ParsedVersion) {
                    $LatestVersion = $GithubVersionInfo.ParsedVersion
                    $LatestVersionString = $GithubVersionInfo.NormalizedVersion
                    $IsPrerelease = [bool]$GithubVersionInfo.IsPrerelease
                    $Source = 'GitHub'
                    Write-Verbose "GitHub returned version '$LatestVersionString'."
                } elseif ($null -ne $GithubVersionInfo -and $GithubVersionInfo.IsIgnoredPrerelease) {
                    Write-Verbose "GitHub returned prerelease version '$($GithubVersionInfo.NormalizedVersion)' and it was ignored."
                }
            } catch {
                $GithubError = $_
                Write-Verbose "GitHub check failed: $($_.Exception.Message)"
            }
        }

        if ($null -eq $LatestVersion) {
            $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new('Unable to resolve a remote version from PowerShell Gallery or GitHub.'),
                'DPVersionLookupFailed',
                [System.Management.Automation.ErrorCategory]::ConnectionError,
                $ModuleName
            )
            $PSCmdlet.WriteError($ErrorRecord)

            if ($null -ne $GalleryError) {
                Write-Verbose "PowerShell Gallery failure details: $($GalleryError.Exception.Message)"
            }
            if ($null -ne $GithubError) {
                Write-Verbose "GitHub failure details: $($GithubError.Exception.Message)"
            }

            return New-DPVersionCheckResult -IsSuccess $false -CurrentVersion $CurrentVersion -LatestVersion $null -LatestVersionString $null -Source 'Unavailable' -IsPrerelease $false -Message 'Unable to determine latest remote version.' -Recommendation 'Verify internet connectivity and upstream API availability.'
        }

        $Message = if ($LatestVersion -gt $CurrentVersion) {
            "Update available. Current version is $CurrentVersion and latest version is $LatestVersionString."
        } else {
            "Module is up to date at version $CurrentVersion."
        }

        $Recommendation = if ($LatestVersion -gt $CurrentVersion) {
            "Update-Module $ModuleName"
        } else {
            $null
        }

        return New-DPVersionCheckResult -IsSuccess $true -CurrentVersion $CurrentVersion -LatestVersion $LatestVersion -LatestVersionString $LatestVersionString -Source $Source -IsPrerelease $IsPrerelease -Message $Message -Recommendation $Recommendation
    }
}
