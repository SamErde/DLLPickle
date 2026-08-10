. (Join-Path $PSScriptRoot 'DLLPickle.ProfileEvidence.ps1')

function ConvertTo-DLLPickleCollapsedAssetPath {
    <#
    .SYNOPSIS
    Collapses a normalized relative asset path without permitting root escape.

    .PARAMETER Path
    Forward- or backslash-delimited relative path.

    .OUTPUTS
    System.String
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $Segments = [System.Collections.Generic.List[string]]::new()
    foreach ($Segment in @($Path.Replace('\', '/') -split '/')) {
        if ([string]::IsNullOrWhiteSpace($Segment) -or $Segment -eq '.') {
            continue
        }
        if ($Segment -eq '..') {
            if ($Segments.Count -eq 0) {
                throw "Asset path '$Path' escapes its root."
            }
            $Segments.RemoveAt($Segments.Count - 1)
            continue
        }
        $Segments.Add($Segment)
    }
    $Segments -join '/'
}

function ConvertTo-DLLPickleManualEvidencePath {
    <#
    .SYNOPSIS
    Replaces an authenticated-evidence path root with a stable identifier.

    .PARAMETER Path
    Path to normalize.

    .PARAMETER ModuleCacheRoot
    Prepared upstream module-cache root.

    .PARAMETER DLLPickleRoot
    Prepared DLLPickle module root.

    .PARAMETER RuntimeRoot
    Exact PowerShell runtime root.

    .OUTPUTS
    System.String
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Path,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ModuleCacheRoot,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$DLLPickleRoot,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$RuntimeRoot
    )

    $NormalizedPath = $Path.Replace('\', '/').TrimEnd('/')
    $Roots = [ordered]@{
        upstream = $ModuleCacheRoot.Replace('\', '/').TrimEnd('/')
        dllpickle = $DLLPickleRoot.Replace('\', '/').TrimEnd('/')
        runtime = $RuntimeRoot.Replace('\', '/').TrimEnd('/')
    }
    foreach ($RootEntry in $Roots.GetEnumerator()) {
        if ($NormalizedPath -eq $RootEntry.Value) {
            return "$($RootEntry.Key):."
        }
        if ($NormalizedPath.StartsWith("$($RootEntry.Value)/", [System.StringComparison]::OrdinalIgnoreCase)) {
            $Relative = $NormalizedPath.Substring($RootEntry.Value.Length + 1)
            return '{0}:{1}' -f $RootEntry.Key, (ConvertTo-DLLPickleCollapsedAssetPath -Path $Relative)
        }
    }
    throw "Authenticated evidence path '$Path' is outside the upstream, DLLPickle, and exact runtime roots."
}

function ConvertTo-DLLPickleUpstreamManifestIdentifier {
    <#
    .SYNOPSIS
    Converts a prepared module manifest path to an upstream evidence identifier.

    .PARAMETER ManifestPath
    Absolute selected module manifest path.

    .PARAMETER ModuleCachePath
    Absolute prepared module-cache root.

    .OUTPUTS
    System.String
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ManifestPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ModuleCachePath
    )

    $NormalizedManifest = $ManifestPath.Replace('\', '/').TrimEnd('/')
    $NormalizedRoot = $ModuleCachePath.Replace('\', '/').TrimEnd('/')
    if (-not $NormalizedManifest.StartsWith("$NormalizedRoot/", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Module manifest '$ManifestPath' is outside its prepared module cache."
    }
    $Relative = ConvertTo-DLLPickleCollapsedAssetPath -Path $NormalizedManifest.Substring($NormalizedRoot.Length + 1)
    'upstream:{0}' -f $Relative
}

function Get-DLLPicklePreparedInventoryFingerprint {
    <#
    .SYNOPSIS
    Fingerprints the exact selected profile and every prepared module file.

    .PARAMETER Inventory
    Upstream inventory whose selected modules must be bound to checkpoints.

    .OUTPUTS
    System.String
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Inventory
    )

    $ModuleCacheRoot = [System.IO.Path]::GetFullPath([string]$Inventory.ModuleCachePath)
    if (-not (Test-Path -LiteralPath $ModuleCacheRoot -PathType Container)) {
        throw "Prepared module cache was not found: $ModuleCacheRoot"
    }
    $CanonicalRows = [System.Collections.Generic.List[string]]::new()
    $CanonicalRows.Add('schemaVersion=1')
    $ProfileRow = 'profile|{0}|{1}|{2}|{3}|{4}|{5}' -f @(
            [string]$Inventory.Profile.PowerShellVersion,
            [string]$Inventory.Profile.PowerShellLine,
            [string]$Inventory.Profile.TargetFramework,
            [string]$Inventory.Profile.Platform,
            [string]$Inventory.Profile.Architecture,
            [string]$Inventory.ProfileKey
    )
    $CanonicalRows.Add($ProfileRow)

    $Modules = @(Get-DLLPickleOrdinalSequence -InputObject @($Inventory.Modules) -KeySelector { param($Module) [string]$Module.Name })
    if ($Modules.Count -eq 0) {
        throw 'Prepared inventory contains no selected modules.'
    }
    $SeenModuleNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($Module in $Modules) {
        if (-not $SeenModuleNames.Add([string]$Module.Name)) {
            throw "Prepared inventory contains duplicate module '$($Module.Name)'."
        }
        $ModulePath = [System.IO.Path]::GetFullPath([string]$Module.ModulePath)
        $RelativeModulePath = [System.IO.Path]::GetRelativePath($ModuleCacheRoot, $ModulePath).Replace('\', '/')
        if ([System.IO.Path]::IsPathRooted($RelativeModulePath) -or
            $RelativeModulePath -eq '..' -or
            $RelativeModulePath.StartsWith('../', [System.StringComparison]::Ordinal)) {
            throw "Prepared module '$($Module.Name)' is outside its module cache."
        }
        if (-not (Test-Path -LiteralPath $ModulePath -PathType Container)) {
            throw "Prepared module '$($Module.Name)' was not found: $ModulePath"
        }
        $ModuleManifestPath = [System.IO.Path]::GetFullPath([string]$Module.ModuleManifestPath)
        $RelativeManifestPath = [System.IO.Path]::GetRelativePath($ModulePath, $ModuleManifestPath).Replace('\', '/')
        if ([System.IO.Path]::IsPathRooted($RelativeManifestPath) -or
            $RelativeManifestPath -eq '..' -or
            $RelativeManifestPath.StartsWith('../', [System.StringComparison]::Ordinal) -or
            -not (Test-Path -LiteralPath $ModuleManifestPath -PathType Leaf)) {
            throw "Prepared module '$($Module.Name)' manifest is outside its selected module root."
        }
        $ModuleRow = 'module|{0}|{1}|{2}|{3}|{4}' -f @(
                [string]$Module.Name,
                [string]$Module.Version,
                [string]$Module.LatestCompatibleVersion,
                (ConvertTo-DLLPickleCollapsedAssetPath -Path $RelativeModulePath),
                (ConvertTo-DLLPickleCollapsedAssetPath -Path $RelativeManifestPath)
        )
        $CanonicalRows.Add($ModuleRow)

        $ModuleEntries = @(Get-ChildItem -LiteralPath $ModulePath -Force -Recurse)
        foreach ($ModuleEntry in $ModuleEntries) {
            if (($ModuleEntry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Prepared module input must not be a symbolic link or reparse point: $($ModuleEntry.FullName)"
            }
        }
        $ModuleFileRows = @(
            foreach ($ModuleFile in @($ModuleEntries | Where-Object { -not $_.PSIsContainer })) {
                [pscustomobject]@{
                    RelativePath = [System.IO.Path]::GetRelativePath($ModulePath, $ModuleFile.FullName).Replace('\', '/')
                    FullName = [string]$ModuleFile.FullName
                    Length = [long]$ModuleFile.Length
                    Attributes = $ModuleFile.Attributes
                }
            }
        )
        $ModuleFiles = @(
            Get-DLLPickleOrdinalSequence -InputObject $ModuleFileRows -KeySelector { param($File) [string]$File.RelativePath } -Unique
        )
        if ($ModuleFiles.Count -eq 0) {
            throw "Prepared module '$($Module.Name)' contains no files."
        }
        foreach ($ModuleFile in $ModuleFiles) {
            $RelativeFilePath = [string]$ModuleFile.RelativePath
            $FileHash = (Get-FileHash -LiteralPath $ModuleFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $FileRow = 'file|{0}|{1}|{2}|{3}' -f @(
                [string]$Module.Name,
                $RelativeFilePath,
                $FileHash,
                [long]$ModuleFile.Length
            )
            $CanonicalRows.Add($FileRow)
        }
    }

    $CanonicalText = $CanonicalRows -join [char]10
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($CanonicalText)
    [System.BitConverter]::ToString(
        [System.Security.Cryptography.SHA256]::HashData($Bytes)
    ).Replace('-', '').ToLowerInvariant()
}

function Get-DLLPickleAuthenticatedCommand {
    <#
    .SYNOPSIS
    Resolves one hard-coded authenticated harness command from its exact module.

    .PARAMETER Name
    Command name.

    .PARAMETER Module
    Exact prepared module that must own the command.

    .OUTPUTS
    System.Management.Automation.CommandInfo
    #>

    [CmdletBinding()]
    [OutputType([System.Management.Automation.CommandInfo])]
    param (
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Module
    )

    $Commands = @(Get-Command -Name $Name -Module $Module -CommandType Function, Cmdlet -ErrorAction Stop)
    if ($Commands.Count -ne 1) {
        throw "Expected exactly one '$Name' command from prepared module '$Module'; found $($Commands.Count)."
    }
    $Commands[0]
}

function Invoke-DLLPickleAuthenticatedReadProbe {
    <#
    .SYNOPSIS
    Runs one hard-coded authenticated read probe and returns a sanitized result.

    .PARAMETER ProbeId
    Fixed probe identifier. No command text is accepted.

    .OUTPUTS
    System.Collections.Specialized.OrderedDictionary
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProbeId
    )

    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        switch ($ProbeId) {
            'graph-context' {
                $Command = Get-DLLPickleAuthenticatedCommand -Name 'Get-MgContext' -Module 'Microsoft.Graph.Authentication'
                if (-not (& $Command -ErrorAction Stop)) { throw 'Graph context was not established.' }
            }
            'graph-me-read' {
                $Command = Get-DLLPickleAuthenticatedCommand -Name 'Invoke-MgGraphRequest' -Module 'Microsoft.Graph.Authentication'
                & $Command -Method GET -Uri '/v1.0/me?$select=id' -ErrorAction Stop | Out-Null
            }
            'exo-mailbox-read' {
                $Command = Get-DLLPickleAuthenticatedCommand -Name 'Get-EXOMailbox' -Module 'ExchangeOnlineManagement'
                if (@(& $Command -ResultSize 1 -ErrorAction Stop).Count -eq 0) { throw 'Exchange mailbox read returned no object.' }
            }
            'az-context' {
                $Command = Get-DLLPickleAuthenticatedCommand -Name 'Get-AzContext' -Module 'Az.Accounts'
                if (-not (& $Command -ErrorAction Stop)) { throw 'Azure context was not established.' }
            }
            'az-resource-read' {
                $Command = Get-DLLPickleAuthenticatedCommand -Name 'Get-AzResource' -Module 'Az.Resources'
                if (@(& $Command -ErrorAction Stop | Select-Object -First 1).Count -eq 0) { throw 'Azure resource read returned no object.' }
            }
            'az-storage-account-read' {
                $Command = Get-DLLPickleAuthenticatedCommand -Name 'Get-AzStorageAccount' -Module 'Az.Storage'
                if (@(& $Command -ErrorAction Stop | Select-Object -First 1).Count -eq 0) { throw 'Azure storage-account read returned no object.' }
            }
            'teams-tenant-read' {
                $Command = Get-DLLPickleAuthenticatedCommand -Name 'Get-CsTenant' -Module 'MicrosoftTeams'
                if (-not (& $Command -ErrorAction Stop)) { throw 'Teams tenant read returned no object.' }
            }
            default { throw "Unsupported authenticated probe identifier '$ProbeId'." }
        }
        $Stopwatch.Stop()
        [ordered]@{
            probeId = $ProbeId
            executed = $true
            status = 'passed'
            durationMilliseconds = [long]$Stopwatch.ElapsedMilliseconds
            writesPerformed = $false
            errorType = $null
        }
    } catch {
        $Stopwatch.Stop()
        [ordered]@{
            probeId = $ProbeId
            executed = $true
            status = 'failed'
            durationMilliseconds = [long]$Stopwatch.ElapsedMilliseconds
            writesPerformed = $false
            errorType = $_.Exception.GetType().FullName
        }
    }
}
