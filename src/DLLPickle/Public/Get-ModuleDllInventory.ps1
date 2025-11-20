<#
.SYNOPSIS
    Inventory installed PowerShell modules for DLLs, detect conflicts and redundancies, export CSV/JSON/HTML.

.DESCRIPTION
    Scans installed modules (newest per scope) for DLLs via fast directory scanning and optional deep content inspection.
    Exports results and builds an HTML report from an external template with Mustache-style placeholders.
#>

function Get-ModuleDllInventory {
    [CmdletBinding()]
    param(
        [ValidateSet('CurrentUser', 'AllUsers', 'Both')]
        [string] $Scope = 'Both',

        [switch] $DeepInspection,

        [string] $ExportCsv,

        [string] $ExportJson,

        [string] $ExportHtml,

        [string] $TemplatePath = $null,

        [switch] $Parallel,

        [int] $ThrottleLimit = 0,

        [switch] $PassThru
    )

    begin {
        # Determine default template path (script directory)
        if ($null -eq $TemplatePath) {
            try {
                if ($PSCommandPath) {
                    $ScriptDir = Split-Path -Parent $PSCommandPath
                } elseif ($PSScriptRoot) {
                    $ScriptDir = $PSScriptRoot
                } else {
                    $ScriptDir = (Get-Location).ProviderPath
                }
            } catch {
                $ScriptDir = (Get-Location).ProviderPath
            }
            $TemplatePath = Join-Path -Path $ScriptDir -ChildPath 'templates\ModuleDLLInventory.Template.html'
        }

        # Automatic throttle: min(processorCount, 8) if ThrottleLimit not provided or <= 0
        $AutoThrottle = [math]::Min([Environment]::ProcessorCount, 8)
        if ($ThrottleLimit -le 0) { $EffectiveThrottle = $AutoThrottle } else { $EffectiveThrottle = $ThrottleLimit }

        # Helper: HTML encode
        function Convert-ForHtml {
            param([string] $Text)
            if ($null -eq $Text) { return '' }
            return [System.Net.WebUtility]::HtmlEncode($Text)
        }

        # Helper: resolve relative path (returns provider path) or $null
        function Resolve-IfRelative {
            param([string] $Candidate, [string] $BaseDirectory)
            if ($null -eq $Candidate) { return $null }
            try {
                if ([System.IO.Path]::IsPathRooted($Candidate)) {
                    return (Resolve-Path -LiteralPath $Candidate -ErrorAction SilentlyContinue).ProviderPath
                } else {
                    $Joined = Join-Path -Path $BaseDirectory -ChildPath $Candidate
                    return (Resolve-Path -LiteralPath $Joined -ErrorAction SilentlyContinue).ProviderPath
                }
            } catch {
                return $null
            }
        }

        # Helper: get ProductVersion or FileVersion for a file
        function Get-LibraryVersionInfo {
            param([string] $Path)
            if ($null -eq $Path) { return $null }
            try {
                $Item = Get-Item -LiteralPath $Path -ErrorAction Stop
                $Version = $Item.VersionInfo.ProductVersion
                if ($null -eq $Version) { $Version = $Item.VersionInfo.FileVersion }
                return $Version
            } catch {
                return $null
            }
        }

        # Helper: import psd1 manifest safely
        function Get-ManifestData {
            param([string] $ManifestPath)
            if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { return $null }
            try {
                return Import-PowerShellDataFile -Path $ManifestPath -ErrorAction Stop
            } catch {
                return $null
            }
        }

        # Helper: find DLL-like references inside text content
        function Get-DllReferencesFromContent {
            param([string] $Content)
            $Found = [System.Collections.Generic.HashSet[string]]::new()
            if ($null -eq $Content) { return $Found }

            $Patterns = @(
                '(?i)["''](?<path>[^"''<>:]*?\.dll)["'']',
                '(?i)Add-Type\s+[^;]*?-Path\s+["'']?(?<path>[^"''\s;]+\.dll)["'']?',
                '(?i)Add-Type\s+[^;]*?-LiteralPath\s+["'']?(?<path>[^"''\s;]+\.dll)["'']?',
                '(?i)using\s+assembly\s+["'']?(?<path>[^"''\s;]+\.dll)["'']?',
                '(?i)LoadFrom\(\s*["'']?(?<path>[^"''\s\)]+\.dll)["'']?\s*\)',
                '(?i)LoadFile\(\s*["'']?(?<path>[^"''\s\)]+\.dll)["'']?\s*\)'
            )

            foreach ($Pattern in $Patterns) {
                $MatchResults = [regex]::Matches($Content, $Pattern)
                foreach ($M in $MatchResults) {
                    $Raw = $M.Groups['path'].Value
                    if ($Raw) { [void]$Found.Add($Raw) }
                }
            }

            $BareMatches = [regex]::Matches($Content, '(?i)([A-Za-z0-9_\-\.\\\/:]+?\.dll)')
            foreach ($B in $BareMatches) { [void]$Found.Add($B.Value) }

            return $Found
        }

        # Single-module folder scanner (fast + optional deep)
        function Measure-ModuleFOlder {
            param(
                [string] $ModuleFolder,
                [string] $ModuleName,
                [string] $ModuleVersion,
                [string] $ModuleScope,
                [switch] $DoDeep
            )

            $Records = [System.Collections.Generic.List[object]]::new()

            try { $DllFiles = Get-ChildItem -LiteralPath $ModuleFolder -Recurse -Filter '*.dll' -File -ErrorAction SilentlyContinue } catch { $DllFiles = @() }
            foreach ($File in $DllFiles) {
                $VersionRaw = Get-LibraryVersionInfo -Path $File.FullName
                $Records.Add([pscustomobject]@{
                        LibraryName       = $File.Name
                        LibraryFullPath   = $File.FullName
                        LibraryVersionRaw = $VersionRaw
                        ModuleName        = $ModuleName
                        ModuleVersion     = $ModuleVersion
                        ModuleScope       = $ModuleScope
                        ModulePath        = $ModuleFolder
                        ReferenceType     = 'FileScan'
                        DiscoveredBy      = 'Directory'
                    })
            }

            # Manifest (.psd1)
            try { $Psd1 = Get-ChildItem -LiteralPath $ModuleFolder -Filter '*.psd1' -File -ErrorAction SilentlyContinue | Select-Object -First 1 } catch { $Psd1 = $null }
            if ($null -ne $Psd1) {
                $Manifest = Get-ManifestData -ManifestPath $Psd1.FullName
                if ($null -ne $Manifest) {
                    if ($Manifest.ContainsKey('RequiredAssemblies') -and $Manifest.RequiredAssemblies) {
                        foreach ($Req in $Manifest.RequiredAssemblies) {
                            if ($null -eq $Req) { continue }
                            if ($Req -is [string] -and $Req.EndsWith('.dll', [System.StringComparison]::OrdinalIgnoreCase)) {
                                $Resolved = Resolve-IfRelative -Candidate $Req -BaseDirectory $ModuleFolder
                                $VersionRaw = Get-LibraryVersionInfo -Path $Resolved
                                $Records.Add([pscustomobject]@{
                                        LibraryName       = [System.IO.Path]::GetFileName($Resolved -or $Req)
                                        LibraryFullPath   = $Resolved
                                        LibraryVersionRaw = $VersionRaw
                                        ModuleName        = $ModuleName
                                        ModuleVersion     = $ModuleVersion
                                        ModuleScope       = $ModuleScope
                                        ModulePath        = $ModuleFolder
                                        ReferenceType     = 'RequiredAssembly'
                                        DiscoveredBy      = 'Manifest'
                                    })
                            }
                        }
                    }

                    if ($Manifest.ContainsKey('NestedModules') -and $Manifest.NestedModules) {
                        foreach ($Nested in $Manifest.NestedModules) {
                            $PathCandidate = $null
                            if ($Nested -is [string]) { $PathCandidate = $Nested }
                            elseif ($Nested -is [hashtable] -and $Nested.ContainsKey('Module')) { $PathCandidate = $Nested.Module }
                            if ($PathCandidate -and $PathCandidate -is [string] -and $PathCandidate.EndsWith('.dll', [System.StringComparison]::OrdinalIgnoreCase)) {
                                $Resolved = Resolve-IfRelative -Candidate $PathCandidate -BaseDirectory $ModuleFolder
                                $VersionRaw = Get-LibraryVersionInfo -Path $Resolved
                                $Records.Add([pscustomobject]@{
                                        LibraryName       = [System.IO.Path]::GetFileName($Resolved -or $PathCandidate)
                                        LibraryFullPath   = $Resolved
                                        LibraryVersionRaw = $VersionRaw
                                        ModuleName        = $ModuleName
                                        ModuleVersion     = $ModuleVersion
                                        ModuleScope       = $ModuleScope
                                        ModulePath        = $ModuleFolder
                                        ReferenceType     = 'NestedModule'
                                        DiscoveredBy      = 'Manifest'
                                    })
                            }
                        }
                    }
                }
            }

            if ($DoDeep.IsPresent) {
                $FilePatterns = @('*.ps1', '*.psm1', '*.cs', '*.ps1xml', '*.psd1')
                try { $CodeFiles = Get-ChildItem -LiteralPath $ModuleFolder -Recurse -Include $FilePatterns -File -ErrorAction SilentlyContinue } catch { $CodeFiles = @() }
                foreach ($Cf in $CodeFiles) {
                    try { $Content = Get-Content -LiteralPath $Cf.FullName -Raw -ErrorAction Stop } catch { continue }
                    $Refs = Get-DllReferencesFromContent -Content $Content
                    foreach ($Ref in $Refs) {
                        $Resolved = Resolve-IfRelative -Candidate $Ref -BaseDirectory $Cf.DirectoryName
                        $VersionRaw = Get-LibraryVersionInfo -Path $Resolved
                        $Lower = $Content.ToLower()
                        $RefType = 'DeepScan'
                        if ($Lower -match 'add-type') { $RefType = 'Add-Type' }
                        elseif ($Lower -match 'using\s+assembly') { $RefType = 'UsingAssembly' }
                        elseif ($Lower -match 'loadfrom' -or $Lower -match 'loadfile' -or $Lower -match 'assembly\.load') { $RefType = 'ReflectionLoad' }

                        $Records.Add([pscustomobject]@{
                                LibraryName       = [System.IO.Path]::GetFileName($Resolved -or $Ref)
                                LibraryFullPath   = $Resolved
                                LibraryVersionRaw = $VersionRaw
                                ModuleName        = $ModuleName
                                ModuleVersion     = $ModuleVersion
                                ModuleScope       = $ModuleScope
                                ModulePath        = $ModuleFolder
                                ReferenceType     = $RefType
                                DiscoveredBy      = 'DeepContent'
                            })
                    }
                }
            }

            return $Records
        }

        # Get installed module folders (providers then filesystem)
        function Get-InstalledModuleFolders {
            param([string] $ScopeSelection)

            # Helper: normalize path and decide scope by location
            function Get-ScopeFromPath {
                param([string] $Path)
                if ($null -eq $Path) { return $null }

                try {
                    $Full = [System.IO.Path]::GetFullPath($Path)
                } catch {
                    return $null
                }

                # Normalize for comparison
                $FullLower = $Full.ToLowerInvariant()

                $ProgramFiles = ("$env:ProgramFiles" -as [string]) -replace '\\$', ''
                $ProgramFilesX86 = ("$env:ProgramFiles(x86)" -as [string]) -replace '\\$', ''
                $ProgramData = ($env:ProgramData -as [string]) -replace '\\$', ''
                $WinDir = ($env:windir -as [string]) -replace '\\$', ''

                # Make safe-lower versions
                if ($null -ne $ProgramFiles) { $ProgramFiles = $ProgramFiles.ToLowerInvariant() }
                if ($null -ne $ProgramFilesX86) { $ProgramFilesX86 = $ProgramFilesX86.ToLowerInvariant() }
                if ($null -ne $ProgramData) { $ProgramData = $ProgramData.ToLowerInvariant() }
                if ($null -ne $WinDir) { $WinDir = $WinDir.ToLowerInvariant() }

                # If path is inside any system-wide folder -> AllUsers
                if ($null -ne $ProgramFiles -and $FullLower.StartsWith($ProgramFiles)) { return 'AllUsers' }
                if ($null -ne $ProgramFilesX86 -and $FullLower.StartsWith($ProgramFilesX86)) { return 'AllUsers' }
                if ($null -ne $ProgramData -and $FullLower.StartsWith($ProgramData)) { return 'AllUsers' }
                if ($null -ne $WinDir -and $FullLower.StartsWith($WinDir)) { return 'AllUsers' }

                # Otherwise, treat as CurrentUser
                return 'CurrentUser'
            }

            $Folders = [System.Collections.Generic.List[object]]::new()
            $SeenPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

            # 1) Provider: Get-InstalledModule (PowerShellGet)
            if (Get-Command -Name Get-InstalledModule -ErrorAction SilentlyContinue) {
                try {
                    $Installed = Get-InstalledModule -ErrorAction SilentlyContinue
                    foreach ($I in $Installed) {
                        $Base = $null
                        try { $Base = $I.InstalledLocation } catch {}
                        if ($null -eq $Base -and $I.ModuleBase) { $Base = $I.ModuleBase }

                        if ($null -ne $Base) {
                            $ActualScope = Get-ScopeFromPath -Path $Base
                            if ($null -eq $ActualScope) { $ActualScope = $ScopeSelection }

                            # Respect caller intent: add only if caller asked for this scope (or asked for Both)
                            if ($ScopeSelection -in @($ActualScope, 'Both')) {
                                $Full = (Resolve-Path -LiteralPath $Base -ErrorAction SilentlyContinue).ProviderPath
                                if ($null -ne $Full -and $SeenPaths.Add($Full)) {
                                    $Folders.Add([pscustomobject]@{
                                            ModuleName    = $I.Name
                                            ModuleVersion = $I.Version.ToString()
                                            ModulePath    = $Full
                                            Source        = 'Get-InstalledModule'
                                            Scope         = $ActualScope
                                        })
                                }
                            }
                        }
                    }
                } catch {}
            }

            # 2) Provider: Get-InstalledPSResource (PowerShellGet v3 / PowerShellGet.Core)
            if (Get-Command -Name Get-InstalledPSResource -ErrorAction SilentlyContinue) {
                try {
                    $Resources = Get-InstalledPSResource -ErrorAction SilentlyContinue
                    foreach ($R in $Resources) {
                        $Base = $null
                        try { $Base = $R.Destination } catch {}
                        if ($null -ne $Base) {
                            $ActualScope = Get-ScopeFromPath -Path $Base
                            if ($null -eq $ActualScope) { $ActualScope = $ScopeSelection }

                            if ($ScopeSelection -in @($ActualScope, 'Both')) {
                                $Full = (Resolve-Path -LiteralPath $Base -ErrorAction SilentlyContinue).ProviderPath
                                if ($null -ne $Full -and $SeenPaths.Add($Full)) {
                                    $Folders.Add([pscustomobject]@{
                                            ModuleName    = $R.Name
                                            ModuleVersion = $R.Version.ToString()
                                            ModulePath    = $Full
                                            Source        = 'Get-InstalledPSResource'
                                            Scope         = $ActualScope
                                        })
                                }
                            }
                        }
                    }
                } catch {}
            }

            # 3) Filesystem scan of conventional module install locations
            $ModuleDirs = [System.Collections.Generic.List[string]]::new()
            if ($ScopeSelection -in @('CurrentUser', 'Both')) {
                $ModuleDirs.Add("$env:USERPROFILE\Documents\WindowsPowerShell\Modules")
                $ModuleDirs.Add("$env:USERPROFILE\Documents\PowerShell\Modules")
            }
            if ($ScopeSelection -in @('AllUsers', 'Both')) {
                $ModuleDirs.Add("$env:ProgramFiles\WindowsPowerShell\Modules")
                $ModuleDirs.Add("$env:ProgramFiles\PowerShell\Modules")
                if ($env:ProgramFiles -ne "$env:ProgramFiles(x86)") { $ModuleDirs.Add("$env:ProgramFiles(x86)\WindowsPowerShell\Modules") }
            }

            foreach ($BasePath in ($ModuleDirs | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)) {
                try { $Child = Get-ChildItem -LiteralPath $BasePath -Directory -ErrorAction SilentlyContinue } catch { $Child = @() }
                foreach ($C in $Child) {
                    try { $VersionFolders = Get-ChildItem -LiteralPath $C.FullName -Directory -ErrorAction SilentlyContinue } catch { $VersionFolders = @() }
                    if ($VersionFolders.Count -gt 0) {
                        $Newest = $VersionFolders | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                        $Full = (Resolve-Path -LiteralPath $Newest.FullName -ErrorAction SilentlyContinue).ProviderPath
                        if ($null -ne $Full -and $SeenPaths.Add($Full)) {
                            $ActualScope = Get-ScopeFromPath -Path $Full
                            if ($ScopeSelection -in @($ActualScope, 'Both')) {
                                $Folders.Add([pscustomobject]@{
                                        ModuleName    = $C.Name
                                        ModuleVersion = ($Newest.BaseName -as [string])
                                        ModulePath    = $Full
                                        Source        = 'FileSystemScan'
                                        Scope         = $ActualScope
                                    })
                            }
                        }
                    } else {
                        $Full = (Resolve-Path -LiteralPath $C.FullName -ErrorAction SilentlyContinue).ProviderPath
                        if ($null -ne $Full -and $SeenPaths.Add($Full)) {
                            $ActualScope = Get-ScopeFromPath -Path $Full
                            if ($ScopeSelection -in @($ActualScope, 'Both')) {
                                $Folders.Add([pscustomobject]@{
                                        ModuleName    = $C.Name
                                        ModuleVersion = ''
                                        ModulePath    = $Full
                                        Source        = 'FileSystemScan'
                                        Scope         = $ActualScope
                                    })
                            }
                        }
                    }
                }
            }
            return $Folders
        }

        # Collect folders for requested scopes
        $AllModuleFolders = [System.Collections.Generic.List[object]]::new()
        if ($Scope -in @('CurrentUser', 'Both')) {
            $Folders = Get-InstalledModuleFolders -ScopeSelection 'CurrentUser'
            foreach ($F in $Folders) { $AllModuleFolders.Add($F) }
        }
        if ($Scope -in @('AllUsers', 'Both')) {
            $Folders = Get-InstalledModuleFolders -ScopeSelection 'AllUsers'
            foreach ($F in $Folders) { $AllModuleFolders.Add($F) }
        }

        # Deduplicate: newest version per module per scope
        $ByModule = $AllModuleFolders | Group-Object -Property ModuleName, Scope

        $SelectedModuleFolders = [System.Collections.Generic.List[object]]::new()
        foreach ($GroupKey in $ByModule) {
            $IfMatches = $AllModuleFolders | Where-Object { $_.ModuleName -eq $GroupKey.Name -and $_.Scope -eq $GroupKey.Scope }
            if ($IfMatches.Count -eq 1) { $SelectedModuleFolders.Add($IfMatches[0]) }
            else {
                $Parsed = $IfMatches | ForEach-Object {
                    $v = $null
                    try { $v = [version]::Parse($_.ModuleVersion) } catch { $v = $null }
                    [pscustomobject]@{ Entry = $_; ParsedVersion = $v }
                }
                $WithParsed = $Parsed | Where-Object { $null -ne $_.ParsedVersion }
                if ($WithParsed.Count -gt 0) {
                    $Chosen = $WithParsed | Sort-Object -Property { $_.ParsedVersion } -Descending | Select-Object -First 1
                    $SelectedModuleFolders.Add($Chosen.Entry)
                } else {
                    $Chosen = $IfMatches | Sort-Object @{Expression = { (Get-Item -LiteralPath $_.ModulePath -ErrorAction SilentlyContinue).LastWriteTime } } -Descending | Select-Object -First 1
                    $SelectedModuleFolders.Add($Chosen)
                }
            }
        }

        $InventoryRecords = [System.Collections.Generic.List[object]]::new()
        $UseParallel = $Parallel.IsPresent -and ($PSVersionTable.PSVersion.Major -ge 7)
    }

    process {
        if ($UseParallel) {
            try {
                $ParallelResults = $SelectedModuleFolders | ForEach-Object -Parallel {
                    param($ModuleDescriptor, $DeepFlag)
                    # Recreate minimal scanning in the parallel runspace
                    $ModuleFolder = $ModuleDescriptor.ModulePath
                    $ModuleName = $ModuleDescriptor.ModuleName
                    $ModuleVersion = $ModuleDescriptor.ModuleVersion
                    $ModuleScope = $ModuleDescriptor.Scope

                    $LocalRecords = @()

                    try { $DllFiles = Get-ChildItem -LiteralPath $ModuleFolder -Recurse -Filter '*.dll' -File -ErrorAction SilentlyContinue } catch { $DllFiles = @() }
                    foreach ($File in $DllFiles) {
                        $VersionRaw = $null
                        try { $VersionRaw = (Get-Item -LiteralPath $File.FullName -ErrorAction SilentlyContinue).VersionInfo.ProductVersion } catch {}
                        if ($null -eq $VersionRaw) { try { $VersionRaw = (Get-Item -LiteralPath $File.FullName -ErrorAction SilentlyContinue).VersionInfo.FileVersion } catch {} }
                        $LocalRecords += [pscustomobject]@{
                            LibraryName       = $File.Name
                            LibraryFullPath   = $File.FullName
                            LibraryVersionRaw = $VersionRaw
                            ModuleName        = $ModuleName
                            ModuleVersion     = $ModuleVersion
                            ModuleScope       = $ModuleScope
                            ModulePath        = $ModuleFolder
                            ReferenceType     = 'FileScan'
                            DiscoveredBy      = 'Directory'
                        }
                    }

                    # Manifests
                    try { $Psd1 = Get-ChildItem -LiteralPath $ModuleFolder -Filter '*.psd1' -File -ErrorAction SilentlyContinue | Select-Object -First 1 } catch { $Psd1 = $null }
                    if ($null -ne $Psd1) {
                        try { $Manifest = Import-PowerShellDataFile -Path $Psd1.FullName -ErrorAction Stop } catch { $Manifest = $null }
                        if ($null -ne $Manifest) {
                            if ($Manifest.ContainsKey('RequiredAssemblies') -and $Manifest.RequiredAssemblies) {
                                foreach ($Req in $Manifest.RequiredAssemblies) {
                                    if ($null -eq $Req) { continue }
                                    if ($Req -is [string] -and $Req.EndsWith('.dll', [System.StringComparison]::OrdinalIgnoreCase)) {
                                        $Resolved = $null
                                        try {
                                            if ([System.IO.Path]::IsPathRooted($Req)) { $Resolved = (Resolve-Path -LiteralPath $Req -ErrorAction SilentlyContinue).ProviderPath }
                                            else { $Resolved = (Resolve-Path -LiteralPath (Join-Path -Path $ModuleFolder -ChildPath $Req) -ErrorAction SilentlyContinue).ProviderPath }
                                        } catch {}
                                        $VersionRaw = $null
                                        if ($null -ne $Resolved) {
                                            try { $VersionRaw = (Get-Item -LiteralPath $Resolved -ErrorAction SilentlyContinue).VersionInfo.ProductVersion } catch {}
                                            if ($null -eq $VersionRaw) { try { $VersionRaw = (Get-Item -LiteralPath $Resolved -ErrorAction SilentlyContinue).VersionInfo.FileVersion } catch {} }
                                        }
                                        $LocalRecords += [pscustomobject]@{
                                            LibraryName       = [System.IO.Path]::GetFileName($Resolved -or $Req)
                                            LibraryFullPath   = $Resolved
                                            LibraryVersionRaw = $VersionRaw
                                            ModuleName        = $ModuleName
                                            ModuleVersion     = $ModuleVersion
                                            ModuleScope       = $ModuleScope
                                            ModulePath        = $ModuleFolder
                                            ReferenceType     = 'RequiredAssembly'
                                            DiscoveredBy      = 'Manifest'
                                        }
                                    }
                                }
                            }

                            if ($Manifest.ContainsKey('NestedModules') -and $Manifest.NestedModules) {
                                foreach ($Nested in $Manifest.NestedModules) {
                                    $PathCandidate = $null
                                    if ($Nested -is [string]) { $PathCandidate = $Nested }
                                    elseif ($Nested -is [hashtable] -and $Nested.ContainsKey('Module')) { $PathCandidate = $Nested.Module }
                                    if ($PathCandidate -and $PathCandidate -is [string] -and $PathCandidate.EndsWith('.dll', [System.StringComparison]::OrdinalIgnoreCase)) {
                                        $Resolved = $null
                                        try {
                                            if ([System.IO.Path]::IsPathRooted($PathCandidate)) { $Resolved = (Resolve-Path -LiteralPath $PathCandidate -ErrorAction SilentlyContinue).ProviderPath }
                                            else { $Resolved = (Resolve-Path -LiteralPath (Join-Path -Path $ModuleFolder -ChildPath $PathCandidate) -ErrorAction SilentlyContinue).ProviderPath }
                                        } catch {}
                                        $VersionRaw = $null
                                        if ($null -ne $Resolved) {
                                            try { $VersionRaw = (Get-Item -LiteralPath $Resolved -ErrorAction SilentlyContinue).VersionInfo.ProductVersion } catch {}
                                            if ($null -eq $VersionRaw) { try { $VersionRaw = (Get-Item -LiteralPath $Resolved -ErrorAction SilentlyContinue).VersionInfo.FileVersion } catch {} }
                                        }
                                        $LocalRecords += [pscustomobject]@{
                                            LibraryName       = [System.IO.Path]::GetFileName($Resolved -or $PathCandidate)
                                            LibraryFullPath   = $Resolved
                                            LibraryVersionRaw = $VersionRaw
                                            ModuleName        = $ModuleName
                                            ModuleVersion     = $ModuleVersion
                                            ModuleScope       = $ModuleScope
                                            ModulePath        = $ModuleFolder
                                            ReferenceType     = 'NestedModule'
                                            DiscoveredBy      = 'Manifest'
                                        }
                                    }
                                }
                            }
                        }
                    }

                    # DeepContent (regex)
                    if ($using:DeepInspection.IsPresent) {
                        try { $CodeFiles = Get-ChildItem -LiteralPath $ModuleFolder -Recurse -Include '*.ps1', '*.psm1', '*.cs', '*.ps1xml', '*.psd1' -File -ErrorAction SilentlyContinue } catch { $CodeFiles = @() }
                        foreach ($Cf in $CodeFiles) {
                            try { $Content = Get-Content -LiteralPath $Cf.FullName -Raw -ErrorAction Stop } catch { continue }
                            $Refs = @()
                            $Patterns = @(
                                '(?i)["''](?<path>[^"''<>:]*?\.dll)["'']',
                                '(?i)Add-Type\s+[^;]*?-Path\s+["'']?(?<path>[^"''\s;]+\.dll)["'']?',
                                '(?i)Add-Type\s+[^;]*?-LiteralPath\s+["'']?(?<path>[^"''\s;]+\.dll)["'']?',
                                '(?i)using\s+assembly\s+["'']?(?<path>[^"''\s;]+\.dll)["'']?',
                                '(?i)LoadFrom\(\s*["'']?(?<path>[^"''\s\)]+\.dll)["'']?\s*\)',
                                '(?i)LoadFile\(\s*["'']?(?<path>[^"''\s\)]+\.dll)["'']?\s*\)'
                            )
                            foreach ($P in $Patterns) {
                                $M = [regex]::Matches($Content, $P)
                                foreach ($m in $M) { if ($m.Groups['path'].Value) { $Refs += $m.Groups['path'].Value } }
                            }
                            $Bare = [regex]::Matches($Content, '(?i)([A-Za-z0-9_\-\.\\\/:]+?\.dll)')
                            foreach ($b in $Bare) { $Refs += $b.Value }
                            $Refs = $Refs | Select-Object -Unique
                            foreach ($Ref in $Refs) {
                                $Resolved = $null
                                try {
                                    if ([System.IO.Path]::IsPathRooted($Ref)) { $Resolved = (Resolve-Path -LiteralPath $Ref -ErrorAction SilentlyContinue).ProviderPath }
                                    else { $Resolved = (Resolve-Path -LiteralPath (Join-Path -Path $Cf.DirectoryName -ChildPath $Ref) -ErrorAction SilentlyContinue).ProviderPath }
                                } catch {}
                                $VersionRaw = $null
                                if ($null -ne $Resolved) {
                                    try { $VersionRaw = (Get-Item -LiteralPath $Resolved -ErrorAction SilentlyContinue).VersionInfo.ProductVersion } catch {}
                                    if ($null -eq $VersionRaw) { try { $VersionRaw = (Get-Item -LiteralPath $Resolved -ErrorAction SilentlyContinue).VersionInfo.FileVersion } catch {} }
                                }
                                $Lower = $Content.ToLower()
                                $RefType = 'DeepScan'
                                if ($Lower -match 'add-type') { $RefType = 'Add-Type' }
                                elseif ($Lower -match 'using\s+assembly') { $RefType = 'UsingAssembly' }
                                elseif ($Lower -match 'loadfrom' -or $Lower -match 'loadfile' -or $Lower -match 'assembly\.load') { $RefType = 'ReflectionLoad' }

                                $LocalRecords += [pscustomobject]@{
                                    LibraryName       = [System.IO.Path]::GetFileName($Resolved -or $Ref)
                                    LibraryFullPath   = $Resolved
                                    LibraryVersionRaw = $VersionRaw
                                    ModuleName        = $ModuleName
                                    ModuleVersion     = $ModuleVersion
                                    ModuleScope       = $ModuleScope
                                    ModulePath        = $ModuleFolder
                                    ReferenceType     = $RefType
                                    DiscoveredBy      = 'DeepContent'
                                }
                            }
                        }
                    }

                    return $LocalRecords
                } -ArgumentList $DeepInspection -ThrottleLimit $EffectiveThrottle
            } catch {
                Write-Verbose "Parallel scan error: $($_.Exception.Message); falling back to serial."
                $UseParallel = $false
            }

            if ($UseParallel -and $ParallelResults) {
                foreach ($Set in $ParallelResults) { foreach ($Item in $Set) { $InventoryRecords.Add($Item) } }
            }
        }

        if (-not $UseParallel) {
            foreach ($ModuleDescriptor in $SelectedModuleFolders) {
                $Results = Measure-ModuleFOlder -ModuleFolder $ModuleDescriptor.ModulePath -ModuleName $ModuleDescriptor.ModuleName -ModuleVersion $ModuleDescriptor.ModuleVersion -ModuleScope $ModuleDescriptor.Scope -DoDeep:$DeepInspection
                foreach ($Rec in $Results) { $InventoryRecords.Add($Rec) }
            }
        }
    }

    end {
        # Normalize unique rows
        $Normalized = $InventoryRecords | Sort-Object ModuleName, LibraryName, LibraryFullPath -Unique

        # Group & detect conflicts/redundancies
        $Groups = $Normalized | Group-Object -Property LibraryName
        $ConflictList = [System.Collections.Generic.List[object]]::new()
        $RedundancyList = [System.Collections.Generic.List[object]]::new()

        foreach ($G in $Groups) {
            $DistinctVersions = $G.Group | Select-Object -Property LibraryVersionRaw -Unique
            $VersionCount = ($DistinctVersions | Where-Object { $null -ne $_.LibraryVersionRaw }).Count
            if ($VersionCount -gt 1) {
                $Entries = $G.Group | Select-Object ModuleName, ModuleVersion, ModuleScope, ModulePath, LibraryName, LibraryVersionRaw, LibraryFullPath, ReferenceType, DiscoveredBy
                $ConflictList.Add([pscustomobject]@{
                        LibraryName = $G.Name
                        Type        = 'Conflict'
                        Instances   = $Entries
                    })
            } else {
                $NonNullVersion = ($G.Group | Where-Object { $null -ne $_.LibraryVersionRaw } | Select-Object -First 1).LibraryVersionRaw
                if ($null -ne $NonNullVersion) {
                    $ModulesWithSame = $G.Group | Where-Object { $_.LibraryVersionRaw -eq $NonNullVersion } | Select-Object ModuleName, ModuleVersion, ModuleScope, ModulePath, LibraryFullPath, ReferenceType, DiscoveredBy
                    if (($ModulesWithSame | Measure-Object).Count -gt 1) {
                        $RedundancyList.Add([pscustomobject]@{
                                LibraryName = $G.Name
                                Type        = 'Redundancy'
                                Version     = $NonNullVersion
                                Instances   = $ModulesWithSame
                            })
                    }
                }
            }
        }

        $Report = [pscustomobject]@{
            GeneratedOn    = (Get-Date)
            ScopeSearched  = $Scope
            DeepInspection = $DeepInspection.IsPresent
            ModuleCount    = ($SelectedModuleFolders | Measure-Object).Count
            InventoryCount = ($Normalized | Measure-Object).Count
            Conflicts      = $ConflictList
            Redundancies   = $RedundancyList
            Inventory      = $Normalized
        }

        # Console grouped list (Option A) - show full module list
        $GroupSummary = $Normalized |
            Group-Object -Property LibraryName, LibraryVersionRaw |
                ForEach-Object {
                    $Modules = ($_.Group | Select-Object -Property ModuleName -Unique | ForEach-Object { $_.ModuleName }) -join ', '
                    $Version = ($_.Name.Split(',')[1].Trim() -replace '^LibraryVersionRaw=', '') -replace '^\s*', ''
                    $Obj = [pscustomobject]@{
                        LibraryName    = $_.Name.Split(',')[0].Trim()
                        LibraryVersion = $Version
                        Modules        = $Modules
                    }
                    $Obj.PSObject.TypeNames.Insert(0, 'ModuleDll.Inventory.Group')
                    $Obj
                }

        Write-Host ''
        Write-Host 'Module DLL Inventory (grouped)' -ForegroundColor Cyan
        $GroupSummary | Format-Table -Property LibraryName, LibraryVersion, Modules -AutoSize

        # Export CSV
        if ($ExportCsv) {
            try {
                $Normalized | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
                Write-Verbose "Exported CSV to $ExportCsv"
            } catch {
                Write-Warning "Failed to export CSV: $($_.Exception.Message)"
            }
        }

        # Export JSON
        if ($ExportJson) {
            try {
                $Report | ConvertTo-Json -Depth 8 | Set-Content -Path $ExportJson -Encoding UTF8
                Write-Verbose "Exported JSON to $ExportJson"
            } catch {
                Write-Warning "Failed to export JSON: $($_.Exception.Message)"
            }
        }

        # Export HTML with external template
        if ($ExportHtml) {
            try {
                if (-not (Test-Path -LiteralPath $TemplatePath)) { throw "Template not found: $TemplatePath" }
                $Template = Get-Content -LiteralPath $TemplatePath -Raw -ErrorAction Stop

                # Build Conflict HTML fragment
                $ConflictHtml = ''
                if ($Report.Conflicts.Count -gt 0) {
                    foreach ($C in $Report.Conflicts) {
                        $ConflictHtml += "<div class='panel'><h3>" + (Convert-ForHtml $C.LibraryName) + "</h3><table class='table'><thead><tr><th>Module</th><th>ModuleVer</th><th>DllVer</th><th>Scope</th><th>ModulePath</th><th>DllPath</th><th>Ref</th></tr></thead><tbody>"
                        foreach ($I in $C.Instances) {
                            $ConflictHtml += '<tr><td>' + (Convert-ForHtml $I.ModuleName) + '</td><td>' + (Convert-ForHtml $I.ModuleVersion) + '</td><td>' + (Convert-ForHtml $I.LibraryVersionRaw) + '</td><td>' + (Convert-ForHtml $I.ModuleScope) + "</td><td><code class='code'>" + (Convert-ForHtml $I.ModulePath) + "</code></td><td><code class='code'>" + (Convert-ForHtml $I.LibraryFullPath) + '</code></td><td>' + (Convert-ForHtml $I.ReferenceType) + '</td></tr>'
                        }
                        $ConflictHtml += '</tbody></table></div>'
                    }
                } else {
                    $ConflictHtml = "<div class='small'>No conflicts detected.</div>"
                }

                # Build Redundancy HTML fragment
                $RedHtml = ''
                if ($Report.Redundancies.Count -gt 0) {
                    foreach ($R in $Report.Redundancies) {
                        $RedHtml += "<div class='panel'><h3>" + (Convert-ForHtml $R.LibraryName) + ' - version ' + (Convert-ForHtml $R.Version) + "</h3><table class='table'><thead><tr><th>Module</th><th>ModuleVer</th><th>Scope</th><th>ModulePath</th><th>DllPath</th><th>Ref</th></tr></thead><tbody>"
                        foreach ($I in $R.Instances) {
                            $RedHtml += '<tr><td>' + (Convert-ForHtml $I.ModuleName) + '</td><td>' + (Convert-ForHtml $I.ModuleVersion) + '</td><td>' + (Convert-ForHtml $I.ModuleScope) + "</td><td><code class='code'>" + (Convert-ForHtml $I.ModulePath) + "</code></td><td><code class='code'>" + (Convert-ForHtml $I.LibraryFullPath) + '</code></td><td>' + (Convert-ForHtml $I.ReferenceType) + '</td></tr>'
                        }
                        $RedHtml += '</tbody></table></div>'
                    }
                } else {
                    $RedHtml = "<div class='small'>No redundancies detected.</div>"
                }

                # Build Inventory by scope HTML fragment
                $InvHtml = ''
                $ByScope = $Report.Inventory | Group-Object -Property ModuleScope
                foreach ($S in $ByScope) {
                    $InvHtml += '<h3>Scope: ' + (Convert-ForHtml $S.Name) + ' - Items: ' + ($S.Count) + "</h3><table class='table'><thead><tr><th>Module</th><th>ModuleVer</th><th>DLL</th><th>DllVer</th><th>DllPath</th><th>Ref</th></tr></thead><tbody>"
                    foreach ($Row in $S.Group) {
                        $InvHtml += '<tr><td>' + (Convert-ForHtml $Row.ModuleName) + '</td><td>' + (Convert-ForHtml $Row.ModuleVersion) + '</td><td>' + (Convert-ForHtml $Row.LibraryName) + '</td><td>' + (Convert-ForHtml $Row.LibraryVersionRaw) + "</td><td><code class='code'>" + (Convert-ForHtml $Row.LibraryFullPath) + '</code></td><td>' + (Convert-ForHtml $Row.ReferenceType) + '</td></tr>'
                    }
                    $InvHtml += '</tbody></table>'
                }

                $SummaryHtml = "<div class='small'><strong>Modules scanned:</strong> " + ($Report.ModuleCount) + ' &nbsp; <strong>DLL references:</strong> ' + ($Report.InventoryCount) + '</div>'

                # Replace placeholders in template
                $Out = $Template
                $Out = $Out -replace '\{\{ReportTitle\}\}', (Convert-ForHtml 'PowerShell Module DLL Inventory Report')
                $Out = $Out -replace '\{\{GeneratedOn\}\}', (Convert-ForHtml ($Report.GeneratedOn.ToString()))
                $Out = $Out -replace '\{\{SummarySection\}\}', $SummaryHtml
                $Out = $Out -replace '\{\{ConflictTable\}\}', $ConflictHtml
                $Out = $Out -replace '\{\{RedundancyTable\}\}', $RedHtml
                $Out = $Out -replace '\{\{ScopeBreakdown\}\}', ''
                $Out = $Out -replace '\{\{InventoryTable\}\}', $InvHtml
                $Out = $Out -replace '\{\{ModuleDetails\}\}', ''

                $Out | Set-Content -Path $ExportHtml -Encoding UTF8
                Write-Verbose "Exported HTML to $ExportHtml"
            } catch {
                Write-Warning "Failed to export HTML: $($_.Exception.Message)"
            }
        }

        # Return structured objects
        if ($PassThru.IsPresent) { return , $Report, $Report.Inventory } else { return $Report }
    }
}
