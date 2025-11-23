<#
.SYNOPSIS
    Inventory installed PowerShell modules for DLLs, detect conflicts and redundancies, export CSV/JSON/HTML.
.DESCRIPTION
    See function Get-ModuleDllInventory for details.
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
        # -----------------------------------
        # Setup Defaults and Helper Functions
        # -----------------------------------
        # Locate the path to the report templates.
        if ($null -eq $TemplatePath) {
            $TemplatePath = [System.IO.Path]::Join( (Split-Path $PSScriptRoot -Parent), 'Templates', 'ModuleDllInventory.Template.html' )
            Write-Verbose "TemplatePath: $TemplatePath"
        }

        # Throttle default: use the number of processors, but cap parallel threads at 8.
        $AutoThrottle = [math]::Min([Environment]::ProcessorCount, 8)
        if ($ThrottleLimit -le 0) {
            $EffectiveThrottle = $AutoThrottle
            Write-Verbose "AutoThrottle: $AutoThrottle"
        } else {
            $EffectiveThrottle = $ThrottleLimit
            Write-Verbose "ThrottleLimit: $ThrottleLimit"
        }
        Write-Verbose "EffectiveThrottle: $EffectiveThrottle"

        function Convert-ForHtml {
            # Helper: HTML encode text.
            param(
                [string] $Text
            )
            if ($null -eq $Text) {
                return ''
            }
            return [System.Net.WebUtility]::HtmlEncode($Text)
        }

        function Resolve-PathIfRelative {
            # Helper: Resolve relative or absolute path to provider path or $null.
            [CmdletBinding()]
            param(
                [string] $Candidate,
                [string] $BaseDirectory
            )
            if ($null -eq $Candidate) { return $null }
            try {
                if ([System.IO.Path]::IsPathRooted($Candidate)) {
                    $ResolvedPath = Resolve-Path -LiteralPath $Candidate -ErrorAction SilentlyContinue
                    return if ($null -ne $ResolvedPath) { $ResolvedPath.ProviderPath } else { $null }
                } else {
                    $Joined = Join-Path -Path $BaseDirectory -ChildPath $Candidate
                    $ResolvedPath = Resolve-Path -LiteralPath $Joined -ErrorAction SilentlyContinue
                    return if ($null -ne $ResolvedPath) { $ResolvedPath.ProviderPath } else { $null }
                }
            } catch {
                Write-Warning "Failed to resolve the relative path.`nCandidate: '$Candidate'`nBaseDirectory: '$BaseDirectory'"
                return $null
            }
        }

        function Get-LibraryVersionInfo {
            # Helper: Read file version info (prefer ProductVersion and fail back to FileVersion).
            param([string] $Path)
            if ($null -eq $Path) { return $null }
            try {
                $FileInfo = Get-Item -LiteralPath $Path -ErrorAction Stop
                $Version = $FileInfo.VersionInfo.ProductVersion
                if ($null -eq $Version) { $Version = $FileInfo.VersionInfo.FileVersion }
                return $Version
            } catch {
                Write-Warning "No file version information found in ProductVersion or FileVersion for '$Path'."
                return $null
            }
        }

        function Import-ManifestData {
            # Helper: Safely import module manifest data (.psd1).
            param(
                [string] $ManifestPath
            )
            if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
                Write-Warning "Could not find a manifest at '$ManifestPath'. $_"
                return $null
            }
            try {
                return Import-PowerShellDataFile -Path $ManifestPath -ErrorAction Stop
            } catch {
                Write-Warning "Could not import the manifest at '$ManifestPath'."
                return $null
            }
        }

        function Get-DllReferencesFromContent {
            # Helper: Find dll-like references inside the contents of text (e.g., module manifest files).
            param(
                [string] $Content
            )
            $Found = [System.Collections.Generic.HashSet[string]]::new()
            if ($null -eq $Content) {
                return $Found
            }

            $Patterns = @(
                '(?i)["''](?<path>[^"''<>:]*?\.dll)["'']',
                '(?i)Add-Type\s+[^;]*?-Path\s+["'']?(?<path>[^"''\s;]+\.dll)["'']?',
                '(?i)Add-Type\s+[^;]*?-LiteralPath\s+["'']?(?<path>[^"''\s;]+\.dll)["'']?',
                '(?i)using\s+assembly\s+["'']?(?<path>[^"''\s;]+\.dll)["'']?',
                '(?i)Assembly\.LoadFrom\(\s*["'']?(?<path>[^"''\s\)]+\.dll)["'']?\s*\)',
                '(?i)Assembly\.LoadFile\(\s*["'']?(?<path>[^"''\s\)]+\.dll)["'']?\s*\)',
                '(?i)LoadFrom\(\s*["'']?(?<path>[^"''\s\)]+\.dll)["'']?\s*\)',
                '(?i)LoadFile\(\s*["'']?(?<path>[^"''\s\)]+\.dll)["'']?\s*\)'
            )

            foreach ($Pattern in $Patterns) {
                $Matches = [regex]::Matches($Content, $Pattern)
                foreach ($Match in $Matches) {
                    $Value = $Match.Groups['path'].Value
                    if ($Value) { [void]$Found.Add($Value) }
                }
            }

            $BareMatches = [regex]::Matches($Content, '(?i)([A-Za-z0-9_\-\.\\\/:]+?\.dll)')
            foreach ($BareMatch in $BareMatches) { [void]$Found.Add($BareMatch.Value) }

            return $Found
        }

        function Measure-ModuleFolder {
            # Helper: scan a single module folder for DLL references
            param(
                [string] $ModuleFolder,
                [string] $ModuleName,
                [string] $ModuleVersion,
                [string] $ModuleScope,
                [switch] $DoDeep
            )

            $LocalRecords = [System.Collections.Generic.List[object]]::new()

            # Scan for DLL files in module folder
            try { $DllFiles = Get-ChildItem -LiteralPath $ModuleFolder -Recurse -Filter '*.dll' -File -ErrorAction SilentlyContinue } catch { $DllFiles = @() }
            foreach ($File in $DllFiles) {
                $VersionRaw = Get-LibraryVersionInfo -Path $File.FullName
                $LocalRecords.Add([pscustomobject]@{
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

            # Scan manifest for RequiredAssemblies and NestedModules
            try { $Psd1 = Get-ChildItem -LiteralPath $ModuleFolder -Filter '*.psd1' -File -ErrorAction SilentlyContinue | Select-Object -First 1 } catch { $Psd1 = $null }
            if ($null -ne $Psd1) {
                $Manifest = Import-ManifestData -ManifestPath $Psd1.FullName
                if ($null -ne $Manifest) {
                    # RequiredAssemblies
                    if ($Manifest.ContainsKey('RequiredAssemblies') -and $Manifest.RequiredAssemblies) {
                        foreach ($RequiredAssembly in $Manifest.RequiredAssemblies) {
                            if ($null -eq $RequiredAssembly) { continue }
                            if ($RequiredAssembly -is [string] -and $RequiredAssembly.EndsWith('.dll', [System.StringComparison]::OrdinalIgnoreCase)) {
                                $Resolved = Resolve-PathIfRelative -Candidate $RequiredAssembly -BaseDirectory $ModuleFolder
                                $VersionRaw = Get-LibraryVersionInfo -Path $Resolved
                                $LocalRecords.Add([pscustomobject]@{
                                    LibraryName       = [System.IO.Path]::GetFileName($Resolved -or $RequiredAssembly)
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

                    # NestedModules
                    if ($Manifest.ContainsKey('NestedModules') -and $Manifest.NestedModules) {
                        foreach ($Nested in $Manifest.NestedModules) {
                            $PathCandidate = $null
                            if ($Nested -is [string]) { $PathCandidate = $Nested }
                            elseif ($Nested -is [hashtable] -and $Nested.ContainsKey('Module')) { $PathCandidate = $Nested.Module }
                            if ($PathCandidate -and $PathCandidate -is [string] -and $PathCandidate.EndsWith('.dll', [System.StringComparison]::OrdinalIgnoreCase)) {
                                $Resolved = Resolve-PathIfRelative -Candidate $PathCandidate -BaseDirectory $ModuleFolder
                                $VersionRaw = Get-LibraryVersionInfo -Path $Resolved
                                $LocalRecords.Add([pscustomobject]@{
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

            # Deep content scanning if requested
            if ($DoDeep) {
                try { $CodeFiles = Get-ChildItem -LiteralPath $ModuleFolder -Recurse -Include '*.ps1', '*.psm1', '*.cs', '*.ps1xml', '*.psd1' -File -ErrorAction SilentlyContinue } catch { $CodeFiles = @() }
                foreach ($CodeFile in $CodeFiles) {
                    try { $Content = Get-Content -LiteralPath $CodeFile.FullName -Raw -ErrorAction Stop } catch { continue }
                    $References = Get-DllReferencesFromContent -Content $Content
                    foreach ($Reference in $References) {
                        $Resolved = Resolve-PathIfRelative -Candidate $Reference -BaseDirectory $CodeFile.DirectoryName
                        $VersionRaw = Get-LibraryVersionInfo -Path $Resolved
                        $ContentLower = $Content.ToLower()
                        $ReferenceType = 'DeepScan'
                        if ($ContentLower -match 'add-type') { $ReferenceType = 'Add-Type' } elseif ($ContentLower -match 'using\s+assembly') { $ReferenceType = 'UsingAssembly' } elseif ($ContentLower -match 'loadfrom' -or $ContentLower -match 'loadfile' -or $ContentLower -match 'assembly\.load') { $ReferenceType = 'ReflectionLoad' }

                        $LocalRecords.Add([pscustomobject]@{
                            LibraryName       = [System.IO.Path]::GetFileName($Resolved -or $Reference)
                            LibraryFullPath   = $Resolved
                            LibraryVersionRaw = $VersionRaw
                            ModuleName        = $ModuleName
                            ModuleVersion     = $ModuleVersion
                            ModuleScope       = $ModuleScope
                            ModulePath        = $ModuleFolder
                            ReferenceType     = $ReferenceType
                            DiscoveredBy      = 'DeepContent'
                        })
                    }
                }
            }

            return $LocalRecords
        }

        function Get-ScopeFromPath {
            # Helper: Decide actual module scope based on path.
            param(
                # The path to check module scope.
                [Parameter()]
                [ValidateNotNullOrEmpty]
                [string] $Path
            )

            try {
                $FullPath = [System.IO.Path]::GetFullPath($Path)
            } catch {
                return $null
            }
            $FullLower = $FullPath.ToLowerInvariant()

            $ProgramFiles = (($env:ProgramFiles -as [string]) -replace '\\$', '').ToLowerInvariant()
            $ProgramFilesX86 = (("$env:ProgramFiles(x86)" -as [string]) -replace '\\$', '').ToLowerInvariant()
            $ProgramData = (("$env:ProgramData" -as [string]) -replace '\\$', '').ToLowerInvariant()
            $WinDir = (($env:windir -as [string]) -replace '\\$', '').ToLowerInvariant()

            # Would this be cleaner as a switch statement?
            if ($null -ne $ProgramFiles -and $FullLower.StartsWith($ProgramFiles)) { return 'AllUsers' }
            if ($null -ne $ProgramFilesX86 -and $FullLower.StartsWith($ProgramFilesX86)) { return 'AllUsers' }
            if ($null -ne $ProgramData -and $FullLower.StartsWith($ProgramData)) { return 'AllUsers' }
            if ($null -ne $WinDir -and $FullLower.StartsWith($WinDir)) { return 'AllUsers' }
            # If none of the above comparisons match, return 'CurrentUser.'
            return 'CurrentUser'
        }

        function Get-InstalledModuleFolders {
            # Discover Installed module folders from providers and file system
            param(
                [string] $ScopeSelection
            )

            $Folders = [System.Collections.Generic.List[object]]::new()
            $Seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

            # Provider: Get-InstalledModule
            if (Get-Command -Name Get-InstalledModule -ErrorAction SilentlyContinue) {
                try {
                    $Installed = Get-InstalledModule -ErrorAction SilentlyContinue
                    foreach ($InstalledModule in $Installed) {
                        $Base = $null
                        try { $Base = $InstalledModule.InstalledLocation } catch {}
                        if ($null -eq $Base -and $InstalledModule.ModuleBase) { $Base = $InstalledModule.ModuleBase }
                        if ($null -ne $Base) {
                            $Resolved = (Resolve-Path -LiteralPath $Base -ErrorAction SilentlyContinue)
                            $ProviderPath = if ($null -ne $Resolved) { $Resolved.ProviderPath } else { $null }
                            if ($null -ne $ProviderPath) {
                                $ActualScope = Get-ScopeFromPath -Path $ProviderPath
                                if ($ScopeSelection -in @($ActualScope, 'Both')) {
                                    if ($Seen.Add($ProviderPath)) {
                                        $Folders.Add([pscustomobject]@{
                                                ModuleName    = $InstalledModule.Name
                                                ModuleVersion = ($InstalledModule.Version -as [string])
                                                ModulePath    = $ProviderPath
                                                Source        = 'Get-InstalledModule'
                                                Scope         = $ActualScope
                                            })
                                    }
                                }
                            }
                        }
                    }
                } catch {}
            }

            # Provider: Get-InstalledPSResource
            if (Get-Command -Name Get-InstalledPSResource -ErrorAction SilentlyContinue) {
                try {
                    $Resources = Get-InstalledPSResource -ErrorAction SilentlyContinue
                    foreach ($Resource in $Resources) {
                        $Base = $null
                        try { $Base = $Resource.Destination } catch {}
                        if ($null -ne $Base) {
                            $Resolved = (Resolve-Path -LiteralPath $Base -ErrorAction SilentlyContinue)
                            $ProviderPath = if ($null -ne $Resolved) { $Resolved.ProviderPath } else { $null }
                            if ($null -ne $ProviderPath) {
                                $ActualScope = Get-ScopeFromPath -Path $ProviderPath
                                if ($ScopeSelection -in @($ActualScope, 'Both')) {
                                    if ($Seen.Add($ProviderPath)) {
                                        $Folders.Add([pscustomobject]@{
                                                ModuleName    = $Resource.Name
                                                ModuleVersion = ($Resource.Version -as [string])
                                                ModulePath    = $ProviderPath
                                                Source        = 'Get-InstalledPSResource'
                                                Scope         = $ActualScope
                                            })
                                    }
                                }
                            }
                        }
                    }
                } catch {}
            }

            # Filesystem conventional module locations
            $ModuleDirs = [System.Collections.Generic.List[string]]::new()
            if ($ScopeSelection -in @('CurrentUser', 'Both')) {
                $ModuleDirs.Add("$env:USERPROFILE\Documents\PowerShell\Modules")
                $ModuleDirs.Add("$env:USERPROFILE\Documents\WindowsPowerShell\Modules")
            }
            if ($ScopeSelection -in @('AllUsers', 'Both')) {
                $ModuleDirs.Add("$env:ProgramFiles\PowerShell\Modules")
                $ModuleDirs.Add("$env:ProgramFiles\WindowsPowerShell\Modules")
                if ($env:ProgramFiles -ne "$env:ProgramFiles(x86)") { $ModuleDirs.Add("$env:ProgramFiles(x86)\WindowsPowerShell\Modules") }
            }

            $ModuleDirs = $ModuleDirs | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
            Write-Verbose -Message ("Retrieving directories in the path '{0}'" -f ($ModuleDirs -join "', '"))

            foreach ($BasePath in $ModuleDirs) {
                try { $TopChild = Get-ChildItem -LiteralPath $BasePath -Directory -ErrorAction SilentlyContinue } catch { $TopChild = @() }
                foreach ($Top in $TopChild) {
                    # If module folder contains version subfolders, pick newest version folder
                    try { $VersionFolders = Get-ChildItem -LiteralPath $Top.FullName -Directory -ErrorAction SilentlyContinue } catch { $VersionFolders = @() }
                    if ($VersionFolders.Count -gt 0) {
                        $Newest = $VersionFolders | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                        $Full = (Resolve-Path -LiteralPath $Newest.FullName -ErrorAction SilentlyContinue).ProviderPath
                        if ($null -ne $Full -and $Seen.Add($Full)) {
                            $ActualScope = Get-ScopeFromPath -Path $Full
                            if ($ScopeSelection -in @($ActualScope, 'Both')) {
                                $Folders.Add([pscustomobject]@{
                                        ModuleName    = $Top.Name
                                        ModuleVersion = ($Newest.BaseName -as [string])
                                        ModulePath    = $Full
                                        Source        = 'FileSystemScan'
                                        Scope         = $ActualScope
                                    })
                            }
                        }
                    } else {
                        $Full = (Resolve-Path -LiteralPath $Top.FullName -ErrorAction SilentlyContinue).ProviderPath
                        if ($null -ne $Full -and $Seen.Add($Full)) {
                            $ActualScope = Get-ScopeFromPath -Path $Full
                            if ($ScopeSelection -in @($ActualScope, 'Both')) {
                                $Folders.Add([pscustomobject]@{
                                        ModuleName    = $Top.Name
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

        # ------------------------
        # Collect folders for requested scopes
        # ------------------------
        $AllModuleFolders = [System.Collections.Generic.List[object]]::new()
        if ($Scope -in @('CurrentUser', 'Both')) {
            $Folders = Get-InstalledModuleFolders -ScopeSelection 'CurrentUser'
            foreach ($Folder in $Folders) { $AllModuleFolders.Add($Folder) }
        }
        if ($Scope -in @('AllUsers', 'Both')) {
            $Folders = Get-InstalledModuleFolders -ScopeSelection 'AllUsers'
            foreach ($Folder in $Folders) { $AllModuleFolders.Add($Folder) }
        }

        Write-Verbose -Message ("All paths to search: '{0}'" -f (($AllModuleFolders | ForEach-Object { $_.ModulePath } | Select-Object -Unique) -join "', '"))

        # ------------------------
        # Deduplicate newest version per module per scope
        # ------------------------
        $ByModule = $AllModuleFolders | Group-Object -Property ModuleName, Scope

        $SelectedModuleFolders = [System.Collections.Generic.List[object]]::new()
        foreach ($GroupKey in $ByModule) {
            # GroupKey.Name looks like: "ModuleName, Scope"
            # Build filter from group's Values collection (Values holds ModuleName and Scope)
            $Vals = $GroupKey.Values
            $ModuleNameKey = $Vals[0]
            $ScopeKey = $Vals[1]

            $IfMatches = $AllModuleFolders | Where-Object { $_.ModuleName -eq $ModuleNameKey -and $_.Scope -eq $ScopeKey }

            if ($IfMatches.Count -eq 1) {
                $SelectedModuleFolders.Add($IfMatches[0])
            } else {
                # Try parse semver-ish version, else pick newest by folder write time
                $Parsed = $IfMatches | ForEach-Object {
                    $ParsedVersion = $null
                    try { $ParsedVersion = [version]::Parse($_.ModuleVersion) } catch { $ParsedVersion = $null }
                    [pscustomobject]@{ Entry = $_; ParsedVersion = $ParsedVersion }
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
        # ------------------------
        # Scanning (parallel or serial)
        # ------------------------
        if ($UseParallel) {
            try {
                $ParallelResults = $SelectedModuleFolders | ForEach-Object -Parallel {
                    param($ModuleDescriptor, $DeepFlag)

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

                    # Manifest scanning
                    try { $Psd1 = Get-ChildItem -LiteralPath $ModuleFolder -Filter '*.psd1' -File -ErrorAction SilentlyContinue | Select-Object -First 1 } catch { $Psd1 = $null }
                    if ($null -ne $Psd1) {
                        try { $Manifest = Import-PowerShellDataFile -Path $Psd1.FullName -ErrorAction Stop } catch { $Manifest = $null }
                        if ($null -ne $Manifest) {
                            if ($Manifest.ContainsKey('RequiredAssemblies') -and $Manifest.RequiredAssemblies) {
                                foreach ($RequiredAssembly in $Manifest.RequiredAssemblies) {
                                    if ($null -eq $RequiredAssembly) { continue }
                                    if ($RequiredAssembly -is [string] -and $RequiredAssembly.EndsWith('.dll', [System.StringComparison]::OrdinalIgnoreCase)) {
                                        $Resolved = $null
                                        try {
                                            if ([System.IO.Path]::IsPathRooted($RequiredAssembly)) { $Resolved = (Resolve-Path -LiteralPath $RequiredAssembly -ErrorAction SilentlyContinue).ProviderPath } else { $Resolved = (Resolve-Path -LiteralPath (Join-Path -Path $ModuleFolder -ChildPath $RequiredAssembly) -ErrorAction SilentlyContinue).ProviderPath }
                                        } catch {}
                                        $VersionRaw = $null
                                        if ($null -ne $Resolved) {
                                            try { $VersionRaw = (Get-Item -LiteralPath $Resolved -ErrorAction SilentlyContinue).VersionInfo.ProductVersion } catch {}
                                            if ($null -eq $VersionRaw) { try { $VersionRaw = (Get-Item -LiteralPath $Resolved -ErrorAction SilentlyContinue).VersionInfo.FileVersion } catch {} }
                                        }
                                        $LocalRecords += [pscustomobject]@{
                                            LibraryName       = [System.IO.Path]::GetFileName($Resolved -or $RequiredAssembly)
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

                    # Deep content scanning
                    if ($using:DeepInspection.IsPresent) {
                        try { $CodeFiles = Get-ChildItem -LiteralPath $ModuleFolder -Recurse -Include '*.ps1', '*.psm1', '*.cs', '*.ps1xml', '*.psd1' -File -ErrorAction SilentlyContinue } catch { $CodeFiles = @() }
                        foreach ($CodeFile in $CodeFiles) {
                            try { $Content = Get-Content -LiteralPath $CodeFile.FullName -Raw -ErrorAction Stop } catch { continue }
                            $References = @()
                            $Patterns = @(
                                '(?i)["''](?<path>[^"''<>:]*?\.dll)["'']',
                                '(?i)Add-Type\s+[^;]*?-Path\s+["'']?(?<path>[^"''\s;]+\.dll)["'']?',
                                '(?i)Add-Type\s+[^;]*?-LiteralPath\s+["'']?(?<path>[^"''\s;]+\.dll)["'']?',
                                '(?i)using\s+assembly\s+["'']?(?<path>[^"''\s;]+\.dll)["'']?',
                                '(?i)LoadFrom\(\s*["'']?(?<path>[^"''\s\)]+\.dll)["'']?\s*\)',
                                '(?i)LoadFile\(\s*["'']?(?<path>[^"''\s\)]+\.dll)["'']?\s*\)'
                            )
                            foreach ($Pattern in $Patterns) {
                                $Matches = [regex]::Matches($Content, $Pattern)
                                foreach ($Match in $Matches) { if ($Match.Groups['path'].Value) { $References += $Match.Groups['path'].Value } }
                            }
                            $BareMatches = [regex]::Matches($Content, '(?i)([A-Za-z0-9_\-\.\\\/:]+?\.dll)')
                            foreach ($BareMatch in $BareMatches) { $References += $BareMatch.Value }
                            $References = $References | Select-Object -Unique
                            foreach ($Reference in $References) {
                                $Resolved = $null
                                try {
                                    if ([System.IO.Path]::IsPathRooted($Reference)) { $Resolved = (Resolve-Path -LiteralPath $Reference -ErrorAction SilentlyContinue).ProviderPath } else { $Resolved = (Resolve-Path -LiteralPath (Join-Path -Path $CodeFile.DirectoryName -ChildPath $Reference) -ErrorAction SilentlyContinue).ProviderPath }
                                } catch {}
                                $VersionRaw = $null
                                if ($null -ne $Resolved) {
                                    try { $VersionRaw = (Get-Item -LiteralPath $Resolved -ErrorAction SilentlyContinue).VersionInfo.ProductVersion } catch {}
                                    if ($null -eq $VersionRaw) { try { $VersionRaw = (Get-Item -LiteralPath $Resolved -ErrorAction SilentlyContinue).VersionInfo.FileVersion } catch {} }
                                }
                                $ContentLower = $Content.ToLower()
                                $ReferenceType = 'DeepScan'
                                if ($ContentLower -match 'add-type') { $ReferenceType = 'Add-Type' } elseif ($ContentLower -match 'using\s+assembly') { $ReferenceType = 'UsingAssembly' } elseif ($ContentLower -match 'loadfrom' -or $ContentLower -match 'loadfile' -or $ContentLower -match 'assembly\.load') { $ReferenceType = 'ReflectionLoad' }

                                $LocalRecords += [pscustomobject]@{
                                    LibraryName       = [System.IO.Path]::GetFileName($Resolved -or $Reference)
                                    LibraryFullPath   = $Resolved
                                    LibraryVersionRaw = $VersionRaw
                                    ModuleName        = $ModuleName
                                    ModuleVersion     = $ModuleVersion
                                    ModuleScope       = $ModuleScope
                                    ModulePath        = $ModuleFolder
                                    ReferenceType     = $ReferenceType
                                    DiscoveredBy      = 'DeepContent'
                                }
                            }
                        }
                    }

                    return $LocalRecords
                } -ArgumentList $DeepInspection -ThrottleLimit $EffectiveThrottle
            } catch {
                Write-Verbose -Message ('Parallel scan error: {0}; falling back to serial.' -f $_.Exception.Message)
                $UseParallel = $false
            }

            if ($UseParallel -and $ParallelResults) {
                foreach ($Set in $ParallelResults) { foreach ($Item in $Set) { $InventoryRecords.Add($Item) } }
            }
        }

        if (-not $UseParallel) {
            foreach ($ModuleDescriptor in $SelectedModuleFolders) {
                $Results = Measure-ModuleFolder -ModuleFolder $ModuleDescriptor.ModulePath -ModuleName $ModuleDescriptor.ModuleName -ModuleVersion $ModuleDescriptor.ModuleVersion -ModuleScope $ModuleDescriptor.Scope -DoDeep:$DeepInspection
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

        foreach ($Group in $Groups) {
            $DistinctVersions = $Group.Group | Select-Object -Property LibraryVersionRaw -Unique
            $VersionCount = ($DistinctVersions | Where-Object { $null -ne $_.LibraryVersionRaw }).Count
            if ($VersionCount -gt 1) {
                $Entries = $Group.Group | Select-Object ModuleName, ModuleVersion, ModuleScope, ModulePath, LibraryName, LibraryVersionRaw, LibraryFullPath, ReferenceType, DiscoveredBy
                $ConflictList.Add([pscustomobject]@{
                        LibraryName = $Group.Name
                        Type        = 'Conflict'
                        Instances   = $Entries
                    })
            } else {
                $NonNullVersion = ($Group.Group | Where-Object { $null -ne $_.LibraryVersionRaw } | Select-Object -First 1).LibraryVersionRaw
                if ($null -ne $NonNullVersion) {
                    $ModulesWithSame = $Group.Group | Where-Object { $_.LibraryVersionRaw -eq $NonNullVersion } | Select-Object ModuleName, ModuleVersion, ModuleScope, ModulePath, LibraryFullPath, ReferenceType, DiscoveredBy
                    if (($ModulesWithSame | Measure-Object).Count -gt 1) {
                        $RedundancyList.Add([pscustomobject]@{
                                LibraryName = $Group.Name
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

        # Console grouped list (Option A) - show full module list (robust version)
        try {
            $GroupSummary = $Normalized |
                Group-Object -Property LibraryName, LibraryVersionRaw |
                    ForEach-Object {
                        if (-not $_.Group -or $_.Group.Count -eq 0) {
                            return
                        }

                        $Representative = $_.Group | Select-Object -First 1
                        $LibName = $Representative.LibraryName
                        $LibVersion = $Representative.LibraryVersionRaw

                        # Build module list (unique names, comma-separated)
                        $Modules = ($_.Group |
                                Select-Object -ExpandProperty ModuleName -Unique) -join ', '

                            $Obj = [pscustomobject]@{
                                LibraryName    = $LibName
                                LibraryVersion = $LibVersion
                                Modules        = $Modules
                            }

                            # Add custom typename so the ps1xml formatting applies cleanly
                            $Obj.PSObject.TypeNames.Insert(0, 'ModuleDll.Inventory.Group')
                            $Obj
                        }
        } catch {
            Write-Warning "A non-fatal display error occurred: $($_.Exception.Message)"
        }

        Write-Host ''
        Write-Host 'Module DLL Inventory (grouped)' -ForegroundColor Cyan
        $GroupSummary | Format-Table -Property LibraryName, LibraryVersion, Modules -AutoSize

        # Export CSV
        if ($ExportCsv) {
            try {
                $Normalized | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
                Write-Verbose -Message ('Exported CSV to {0}' -f $ExportCsv)
            } catch { Write-Warning -Message ('Failed to export CSV: {0}' -f $_.Exception.Message) }
        }

        # Export JSON
        if ($ExportJson) {
            try {
                $Report | ConvertTo-Json -Depth 8 | Set-Content -Path $ExportJson -Encoding UTF8
                Write-Verbose -Message ('Exported JSON to {0}' -f $ExportJson)
            } catch { Write-Warning -Message ('Failed to export JSON: {0}' -f $_.Exception.Message) }
        }

        # Export HTML with external template
        if ($ExportHtml) {
            try {
                if (-not (Test-Path -LiteralPath $TemplatePath)) { throw "Template not found: $TemplatePath" }
                $Template = Get-Content -LiteralPath $TemplatePath -Raw -ErrorAction Stop

                # Build Conflict HTML fragment
                $ConflictHtml = ''
                if ($Report.Conflicts.Count -gt 0) {
                    foreach ($Conflict in $Report.Conflicts) {
                        $ConflictHtml += "<div class='panel'><h3>" + (Convert-ForHtml $Conflict.LibraryName) + "</h3><table class='table'><thead><tr><th>Module</th><th>ModuleVer</th><th>DllVer</th><th>Scope</th><th>ModulePath</th><th>DllPath</th><th>Ref</th></tr></thead><tbody>"
                        foreach ($Instance in $Conflict.Instances) {
                            $ConflictHtml += '<tr><td>' + (Convert-ForHtml ($Instance.ModuleName -as [string])) + '</td><td>' + (Convert-ForHtml $Instance.ModuleVersion) + '</td><td>' + (Convert-ForHtml $Instance.LibraryVersionRaw) + '</td><td>' + (Convert-ForHtml $Instance.ModuleScope) + "</td><td><code class='code'>" + (Convert-ForHtml $Instance.ModulePath) + "</code></td><td><code class='code'>" + (Convert-ForHtml $Instance.LibraryFullPath) + '</code></td><td>' + (Convert-ForHtml $Instance.ReferenceType) + '</td></tr>'
                        }
                        $ConflictHtml += '</tbody></table></div>'
                    }
                } else {
                    $ConflictHtml = "<div class='small'>No conflicts detected.</div>"
                }

                # Build Redundancy HTML fragment
                $RedHtml = ''
                if ($Report.Redundancies.Count -gt 0) {
                    foreach ($Redundancy in $Report.Redundancies) {
                        $RedHtml += "<div class='panel'><h3>" + (Convert-ForHtml $Redundancy.LibraryName) + ' - version ' + (Convert-ForHtml $Redundancy.Version) + "</h3><table class='table'><thead><tr><th>Module</th><th>ModuleVer</th><th>Scope</th><th>ModulePath</th><th>DllPath</th><th>Ref</th></tr></thead><tbody>"
                        foreach ($Instance in $Redundancy.Instances) {
                            $RedHtml += '<tr><td>' + (Convert-ForHtml ($Instance.ModuleName -as [string])) + '</td><td>' + (Convert-ForHtml $Instance.ModuleVersion) + '</td><td>' + (Convert-ForHtml $Instance.ModuleScope) + "</td><td><code class='code'>" + (Convert-ForHtml $Instance.ModulePath) + "</code></td><td><code class='code'>" + (Convert-ForHtml $Instance.LibraryFullPath) + '</code></td><td>' + (Convert-ForHtml $Instance.ReferenceType) + '</td></tr>'
                        }
                        $RedHtml += '</tbody></table></div>'
                    }
                } else {
                    $RedHtml = "<div class='small'>No redundancies detected.</div>"
                }

                # Build Inventory by scope HTML fragment
                $InvHtml = ''
                $ByScope = $Report.Inventory | Group-Object -Property ModuleScope
                foreach ($ScopeGroup in $ByScope) {
                    $InvHtml += '<h3>Scope: ' + (Convert-ForHtml $ScopeGroup.Name) + ' - Items: ' + ($ScopeGroup.Count) + "</h3><table class='table'><thead><tr><th>Module</th><th>ModuleVer</th><th>DLL</th><th>DllVer</th><th>DllPath</th><th>Ref</th></tr></thead><tbody>"
                    foreach ($Row in $ScopeGroup.Group) {
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
                Write-Verbose -Message ('Exported HTML to {0}' -f $ExportHtml)
            } catch { Write-Warning -Message ('Failed to export HTML: {0}' -f $_.Exception.Message) }
        }

        # Return structured objects
        if ($PassThru.IsPresent) { return , $Report, $Report.Inventory } else { return $Report }
    }
}
