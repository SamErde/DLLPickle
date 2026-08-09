function Get-DLLPickleBuildToolPolicy {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Path = (Join-Path -Path $PSScriptRoot -ChildPath 'build-tool-versions.json')
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Build-tool policy not found: $Path"
    }

    $Policy = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($Policy.schemaVersion -ne 1) {
        throw "Unsupported build-tool policy schema version '$($Policy.schemaVersion)' in $Path."
    }

    $Modules = @($Policy.modules)
    if ($Modules.Count -eq 0) {
        throw "Build-tool policy contains no modules: $Path"
    }

    $Names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Module in $Modules) {
        if ([string]::IsNullOrWhiteSpace($Module.name)) {
            throw "Build-tool policy contains a module with no name: $Path"
        }
        if (-not $Names.Add([string]$Module.name)) {
            throw "Build-tool policy contains duplicate module '$($Module.name)': $Path"
        }

        $ParsedVersion = $null
        if (-not [version]::TryParse([string]$Module.version, [ref]$ParsedVersion)) {
            throw "Build-tool policy contains invalid version '$($Module.version)' for '$($Module.name)': $Path"
        }
        if ($ParsedVersion.Revision -ge 0) {
            throw "Build-tool policy versions must use Major.Minor.Patch syntax; found '$($Module.version)' for '$($Module.name)'."
        }
    }

    return $Policy
}

function Get-DLLPickleBuildToolVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Policy,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    $MatchingModules = @($Policy.modules | Where-Object { $_.name -eq $Name })
    if ($MatchingModules.Count -ne 1) {
        throw "Expected exactly one build-tool policy entry for '$Name'; found $($MatchingModules.Count)."
    }

    return [version]$MatchingModules[0].version
}

function Test-DLLPickleCommandParameter {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.CommandInfo]$Command,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ParameterName
    )

    return $Command.Parameters.ContainsKey($ParameterName)
}

function Test-DLLPickleToolVersionMatch {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [version]$ActualVersion,

        [Parameter(Mandatory)]
        [version]$RequiredVersion
    )

    if (
        $ActualVersion.Major -ne $RequiredVersion.Major -or
        $ActualVersion.Minor -ne $RequiredVersion.Minor -or
        $ActualVersion.Build -ne $RequiredVersion.Build
    ) {
        return $false
    }

    return $RequiredVersion.Revision -lt 0 -or $ActualVersion.Revision -eq $RequiredVersion.Revision
}

function Assert-DLLPicklePesterAssemblyVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [version]$RequiredVersion,

        [Parameter(Mandatory)]
        [System.Reflection.AssemblyName]$LoadedAssemblyName
    )

    if (-not (Test-DLLPickleToolVersionMatch -ActualVersion $LoadedAssemblyName.Version -RequiredVersion $RequiredVersion)) {
        throw "Pester assembly mismatch: version '$($LoadedAssemblyName.Version)' is already loaded, but version '$RequiredVersion' is required. Start a fresh pwsh -NoProfile -NonInteractive process."
    }
}

function Import-DLLPickleBuildTool {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSModuleInfo])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [version]$RequiredVersion
    )

    if ($Name -eq 'Pester') {
        $LoadedPesterAssemblyNames = @(
            [System.AppDomain]::CurrentDomain.GetAssemblies() |
                Where-Object { $_.GetName().Name -eq 'Pester' } |
                ForEach-Object { $_.GetName() }
        )
        foreach ($LoadedAssemblyName in $LoadedPesterAssemblyNames) {
            Assert-DLLPicklePesterAssemblyVersion -RequiredVersion $RequiredVersion -LoadedAssemblyName $LoadedAssemblyName
        }
    }

    $LoadedModules = @(Get-Module -Name $Name)
    foreach ($LoadedModule in $LoadedModules) {
        if (-not (Test-DLLPickleToolVersionMatch -ActualVersion $LoadedModule.Version -RequiredVersion $RequiredVersion)) {
            throw "Build-tool module mismatch: '$Name' version '$($LoadedModule.Version)' is already loaded, but version '$RequiredVersion' is required. Start a fresh pwsh -NoProfile -NonInteractive process."
        }
    }

    $ExactLoadedModule = $LoadedModules |
        Where-Object { Test-DLLPickleToolVersionMatch -ActualVersion $_.Version -RequiredVersion $RequiredVersion } |
        Select-Object -First 1
    if ($ExactLoadedModule) {
        return $ExactLoadedModule
    }

    Import-Module -Name $Name -RequiredVersion $RequiredVersion -Global -ErrorAction Stop
    $ImportedModule = Get-Module -Name $Name |
        Where-Object { Test-DLLPickleToolVersionMatch -ActualVersion $_.Version -RequiredVersion $RequiredVersion } |
        Select-Object -First 1
    if (-not $ImportedModule) {
        throw "Failed to import exact build-tool module '$Name' version '$RequiredVersion'."
    }

    return $ImportedModule
}
