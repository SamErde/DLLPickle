function Get-DPRuntimeProfile {
    <#
    .SYNOPSIS
    Resolve the DLLPickle runtime profile for the current PowerShell process.

    .DESCRIPTION
    Validates the shipped runtime profile policy, selects the entry matching the
    PowerShell major/minor line, and verifies that the host CLR major matches.
    Unsupported, ambiguous, or malformed mappings fail closed before any bundled
    assembly is loaded.

    .PARAMETER PolicyPath
    Path to the shipped SupportedRuntimeProfiles.json policy.

    .PARAMETER PowerShellVersion
    PowerShell version to resolve. Defaults to the current process version.

    .PARAMETER DotNetMajor
    CLR major version to validate. Defaults to the current process CLR major.

    .OUTPUTS
    System.Management.Automation.PSCustomObject
    #>

    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter()]
        [string]$PolicyPath,

        [Parameter()]
        [version]$PowerShellVersion = $PSVersionTable.PSVersion,

        [Parameter()]
        [int]$DotNetMajor = [Environment]::Version.Major
    )

    $CandidateRoots = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
        $ExplicitModuleRoot = Get-Variable -Name PSModuleRoot -ValueOnly -ErrorAction SilentlyContinue
        if (-not [string]::IsNullOrWhiteSpace($ExplicitModuleRoot)) {
            $CandidateRoots.Add($ExplicitModuleRoot)
        }
        if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
            $CandidateRoots.Add($PSScriptRoot)
            $CandidateRoots.Add((Split-Path -Path $PSScriptRoot -Parent))
        }

        foreach ($CandidateRoot in @($CandidateRoots | Select-Object -Unique)) {
            $CandidatePath = Join-Path -Path $CandidateRoot -ChildPath 'SupportedRuntimeProfiles.json'
            if (Test-Path -LiteralPath $CandidatePath -PathType Leaf) {
                $PolicyPath = $CandidatePath
                break
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
        $SearchedRoots = @($CandidateRoots | Select-Object -Unique) -join ', '
        throw "DLLPickle runtime profile policy 'SupportedRuntimeProfiles.json' was not found. Searched: $SearchedRoots. Reinstall the module from a complete package."
    }

    if (-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)) {
        throw "DLLPickle runtime profile policy was not found at '$PolicyPath'. Reinstall the module from a complete package."
    }

    try {
        $Policy = Get-Content -LiteralPath $PolicyPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "DLLPickle runtime profile policy is malformed: $($_.Exception.Message)"
    }

    if ($Policy.schemaVersion -ne 1) {
        throw "DLLPickle runtime profile policy has unsupported schemaVersion '$($Policy.schemaVersion)'; expected 1."
    }

    $Profiles = @($Policy.profiles)
    if ($Profiles.Count -eq 0) {
        throw 'DLLPickle runtime profile policy is malformed: profiles must contain at least one mapping.'
    }

    $ProfileByPowerShellLine = @{}
    $RequiredPropertyNames = @('powerShellMajor', 'powerShellMinor', 'dotnetMajor', 'targetFramework', 'hostProvidedAssemblyNames')
    foreach ($RuntimeProfileEntry in $Profiles) {
        foreach ($RequiredPropertyName in $RequiredPropertyNames) {
            if ($RuntimeProfileEntry.PSObject.Properties.Name -notcontains $RequiredPropertyName) {
                throw "DLLPickle runtime profile policy is malformed: a profile is missing '$RequiredPropertyName'."
            }
        }

        $PowerShellMajor = 0
        $PowerShellMinor = 0
        $ProfileDotNetMajor = 0
        if (
            -not [int]::TryParse([string]$RuntimeProfileEntry.powerShellMajor, [ref]$PowerShellMajor) -or
            -not [int]::TryParse([string]$RuntimeProfileEntry.powerShellMinor, [ref]$PowerShellMinor) -or
            -not [int]::TryParse([string]$RuntimeProfileEntry.dotnetMajor, [ref]$ProfileDotNetMajor) -or
            $PowerShellMajor -lt 1 -or
            $PowerShellMinor -lt 0 -or
            $ProfileDotNetMajor -lt 1
        ) {
            throw 'DLLPickle runtime profile policy is malformed: version components must be valid integers.'
        }

        $ExpectedTargetFramework = 'net{0}.0' -f $ProfileDotNetMajor
        if ([string]$RuntimeProfileEntry.targetFramework -cne $ExpectedTargetFramework) {
            throw "DLLPickle runtime profile policy targetFramework '$($RuntimeProfileEntry.targetFramework)' does not match declared CLR major $ProfileDotNetMajor; expected '$ExpectedTargetFramework'."
        }

        foreach ($RuntimePlatform in @('windows', 'linux', 'macos')) {
            if ($RuntimeProfileEntry.hostProvidedAssemblyNames.PSObject.Properties.Name -notcontains $RuntimePlatform) {
                throw "DLLPickle runtime profile policy is malformed: hostProvidedAssemblyNames is missing '$RuntimePlatform'."
            }
            $HostProvidedNames = @($RuntimeProfileEntry.hostProvidedAssemblyNames.$RuntimePlatform | ForEach-Object { [string]$_ })
            if (@($HostProvidedNames | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
                throw "DLLPickle runtime profile policy is malformed: hostProvidedAssemblyNames.$RuntimePlatform contains an empty assembly name."
            }
            if (@($HostProvidedNames | Sort-Object -Unique).Count -ne $HostProvidedNames.Count) {
                throw "DLLPickle runtime profile policy is malformed: hostProvidedAssemblyNames.$RuntimePlatform contains duplicate assembly names."
            }
        }

        $PowerShellLine = '{0}.{1}' -f $PowerShellMajor, $PowerShellMinor
        if ($ProfileByPowerShellLine.ContainsKey($PowerShellLine)) {
            throw "DLLPickle runtime profile policy contains a duplicate mapping for PowerShell $PowerShellLine."
        }
        $ProfileByPowerShellLine[$PowerShellLine] = $RuntimeProfileEntry
    }

    $CurrentPowerShellLine = '{0}.{1}' -f $PowerShellVersion.Major, $PowerShellVersion.Minor
    if (-not $ProfileByPowerShellLine.ContainsKey($CurrentPowerShellLine)) {
        $SupportedLines = @($ProfileByPowerShellLine.Keys | Sort-Object) -join ', '
        throw "Unsupported PowerShell runtime $PowerShellVersion. DLLPickle supports these PowerShell lines: $SupportedLines."
    }

    $SelectedProfile = $ProfileByPowerShellLine[$CurrentPowerShellLine]
    if ([int]$SelectedProfile.dotnetMajor -ne $DotNetMajor) {
        throw "CLR mismatch for PowerShell $CurrentPowerShellLine. DLLPickle expected CLR $($SelectedProfile.dotnetMajor) but detected CLR $DotNetMajor."
    }

    $SelectedProfile
}
