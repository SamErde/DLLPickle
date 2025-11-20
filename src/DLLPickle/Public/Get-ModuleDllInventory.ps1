function Get-ModuleDllInventory {
    [CmdletBinding()]
    param(
        [ValidateSet('CurrentUser', 'AllUsers', 'Both')]
        [string] $Scope = 'Both',

        [switch] $DeepInspection,

        [string] $ExportCsv,

        [string] $ExportJson,

        [string] $ExportHtml,

        [switch] $Parallel,

        [int] $ThrottleLimit = 8,

        [switch] $PassThru
    )

    begin {
        # -----------------------
        # Helpers
        # -----------------------
        function Resolve-IfRelative {
            param(
                [string] $Candidate,
                [string] $BaseDirectory
            )
            if (-not $Candidate) { return $null }
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

        function Get-LibraryVersionInfo {
            param([string] $Path)
            if (-not $Path) { return $null }
            try {
                $Item = Get-Item -LiteralPath $Path -ErrorAction Stop
                $Version = $Item.VersionInfo.ProductVersion
                if (-not $Version) { $Version = $Item.VersionInfo.FileVersion }
                return $Version
            } catch {
                return $null
            }
        }

        function Get-ManifestData {
            param([string] $ManifestPath)
            if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { return $null }
            try {
                return Import-PowerShellDataFile -Path $ManifestPath -ErrorAction Stop
            } catch {
                return $null
            }
        }

        function Get-DllReferencesFromContent {
            param(
                [string] $Content,
                [string] $FileDirectory
            )

            $Found = [System.Collections.Generic.HashSet[string]]::new()
            if (-not $Content) { return $Found }

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
                foreach ($M in $Matches) {
                    $Raw = $M.Groups['path'].Value
                    if ($Raw) { [void]$Found.Add($Raw) }
                }
            }

            $BareMatches = [regex]::Matches($Content, '(?i)([A-Za-z0-9_\-\.\\\/:]+?\.dll)')
            foreach ($B in $BareMatches) { [void]$Found.Add($B.Value) }

            return $Found
        }

        # Scan logic (single-module folder)
        function Scan-ModuleFolder {
            param(
                [string] $ModuleFolder,
                [string] $ModuleName,
                [string] $ModuleVersion,
                [string] $ModuleScope,
                [switch] $DoDeep
            )

            $Records = [System.Collections.Generic.List[object]]::new()

            try {
                $DllFiles = Get-ChildItem -LiteralPath $ModuleFolder -Recurse -Filter '*.dll' -File -ErrorAction SilentlyContinue
            } catch {
                $DllFiles = @()
            }

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

            # Manifest parsing
            $Psd1 = Get-ChildItem -LiteralPath $ModuleFolder -Filter '*.psd1' -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($Psd1) {
                $Manifest = Get-ManifestData -ManifestPath $Psd1.FullName
                if ($Manifest) {
                    if ($Manifest.ContainsKey('RequiredAssemblies') -and $Manifest.RequiredAssemblies) {
                        foreach ($Req in $Manifest.RequiredAssemblies) {
                            if (-not $Req) { continue }
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

            # Deep inspection
            if ($DoDeep.IsPresent) {
                $FilePatterns = @('*.ps1', '*.psm1', '*.cs', '*.ps1xml', '*.psd1')
                try {
                    $CodeFiles = Get-ChildItem -LiteralPath $ModuleFolder -Recurse -Include $FilePatterns -File -ErrorAction SilentlyContinue
                } catch {
                    $CodeFiles = @()
                }

                foreach ($Cf in $CodeFiles) {
                    try {
                        $Content = Get-Content -LiteralPath $Cf.FullName -Raw -ErrorAction Stop
                    } catch {
                        continue
                    }

                    $Refs = Get-DllReferencesFromContent -Content $Content -FileDirectory $Cf.DirectoryName
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

        # -----------------------
        # Get installed module folders (tries providers then filesystem)
        # -----------------------
        function Get-InstalledModuleFolders {
            param([string] $ScopeSelection)

            $Folders = [System.Collections.Generic.List[object]]::new()

            if (Get-Command -Name Get-InstalledModule -ErrorAction SilentlyContinue) {
                try {
                    $Installed = Get-InstalledModule -ErrorAction SilentlyContinue
                    foreach ($I in $Installed) {
                        $Base = $null
                        try { $Base = $I.InstalledLocation } catch {}
                        if (-not $Base -and $I.ModuleBase) { $Base = $I.ModuleBase }
                        if ($Base) {
                            $Folders.Add([pscustomobject]@{
                                    ModuleName    = $I.Name
                                    ModuleVersion = $I.Version.ToString()
                                    ModulePath    = $Base
                                    Source        = 'Get-InstalledModule'
                                    Scope         = $ScopeSelection
                                })
                        }
                    }
                } catch {}
            }

            if (Get-Command -Name Get-InstalledPSResource -ErrorAction SilentlyContinue) {
                try {
                    $Resources = Get-InstalledPSResource -ErrorAction SilentlyContinue
                    foreach ($R in $Resources) {
                        $Base = $null
                        try { $Base = $R.Destination } catch {}
                        if ($Base) {
                            $Folders.Add([pscustomobject]@{
                                    ModuleName    = $R.Name
                                    ModuleVersion = $R.Version.ToString()
                                    ModulePath    = $Base
                                    Source        = 'Get-InstalledPSResource'
                                    Scope         = $ScopeSelection
                                })
                        }
                    }
                } catch {}
            }

            $ModuleDirs = @()
            if ($ScopeSelection -in @('CurrentUser', 'Both')) {
                $ModuleDirs += "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"
                $ModuleDirs += "$env:USERPROFILE\Documents\PowerShell\Modules"
            }
            if ($ScopeSelection -in @('AllUsers', 'Both')) {
                $ModuleDirs += "$env:ProgramFiles\WindowsPowerShell\Modules"
                $ModuleDirs += "$env:ProgramFiles\PowerShell\Modules"
                if ($env:ProgramFiles -ne "$env:ProgramFiles(x86)") { $ModuleDirs += "$env:ProgramFiles(x86)\WindowsPowerShell\Modules" }
            }

            foreach ($BasePath in ($ModuleDirs | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)) {
                try {
                    $Child = Get-ChildItem -LiteralPath $BasePath -Directory -ErrorAction SilentlyContinue
                } catch {
                    $Child = @()
                }

                foreach ($C in $Child) {
                    try {
                        $VersionFolders = Get-ChildItem -LiteralPath $C.FullName -Directory -ErrorAction SilentlyContinue
                    } catch {
                        $VersionFolders = @()
                    }

                    if ($VersionFolders.Count -gt 0) {
                        $Newest = $VersionFolders | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                        $Folders.Add([pscustomobject]@{
                                ModuleName    = $C.Name
                                ModuleVersion = ($Newest.BaseName -as [string])
                                ModulePath    = $Newest.FullName
                                Source        = 'FileSystemScan'
                                Scope         = $ScopeSelection
                            })
                    } else {
                        $Folders.Add([pscustomobject]@{
                                ModuleName    = $C.Name
                                ModuleVersion = ''
                                ModulePath    = $C.FullName
                                Source        = 'FileSystemScan'
                                Scope         = $ScopeSelection
                            })
                    }
                }
            }

            return $Folders
        }

        # collection containers
        $AllModuleFolders = [System.Collections.Generic.List[object]]::new()

        if ($Scope -in @('CurrentUser', 'Both')) {
            $Folders = Get-InstalledModuleFolders -ScopeSelection 'CurrentUser'
            foreach ($F in $Folders) { $AllModuleFolders.Add($F) }
        }
        if ($Scope -in @('AllUsers', 'Both')) {
            $Folders = Get-InstalledModuleFolders -ScopeSelection 'AllUsers'
            foreach ($F in $Folders) { $AllModuleFolders.Add($F) }
        }

        # dedupe: newest version per module per scope
        $ByModule = $AllModuleFolders | Group-Object -Property @{Expression = { $_.ModuleName }; Label = 'Name' }, @{Expression = { $_.Scope }; Label = 'Scope' } -NoElement
        $SelectedModuleFolders = [System.Collections.Generic.List[object]]::new()
        foreach ($GroupKey in $ByModule) {
            $Matches = $AllModuleFolders | Where-Object { $_.ModuleName -eq $GroupKey.Name -and $_.Scope -eq $GroupKey.Scope }
            if ($Matches.Count -eq 1) {
                $SelectedModuleFolders.Add($Matches[0])
            } else {
                $Parsed = $Matches | ForEach-Object {
                    $v = $null
                    try { $v = [version]::Parse($_.ModuleVersion) } catch { $v = $null }
                    [pscustomobject]@{ Entry = $_; ParsedVersion = $v }
                }
                $WithParsed = $Parsed | Where-Object { $null -ne $_.ParsedVersion }
                if ($WithParsed.Count -gt 0) {
                    $Chosen = $WithParsed | Sort-Object -Property { $_.ParsedVersion } -Descending | Select-Object -First 1
                    $SelectedModuleFolders.Add($Chosen.Entry)
                } else {
                    $Chosen = $Matches | Sort-Object @{Expression = { (Get-Item -LiteralPath $_.ModulePath -ErrorAction SilentlyContinue).LastWriteTime } } -Descending | Select-Object -First 1
                    $SelectedModuleFolders.Add($Chosen)
                }
            }
        }

        $InventoryRecords = [System.Collections.Generic.List[object]]::new()
        $UseParallel = $Parallel.IsPresent -and ($PSVersionTable.PSVersion.Major -ge 7)
    }

    process {
        if ($UseParallel) {
            # Parallel scan with ForEach-Object -Parallel (PowerShell 7+)
            try {
                $ParallelResults = $SelectedModuleFolders | ForEach-Object -Parallel {
                    param($ModuleDescriptor, $DeepFlag)
                    # Inline copy of the scanning logic for compatibility in parallel runspaces
                    $ModuleFolder = $ModuleDescriptor.ModulePath
                    $ModuleName = $ModuleDescriptor.ModuleName
                    $ModuleVersion = $ModuleDescriptor.ModuleVersion
                    $ModuleScope = $ModuleDescriptor.Scope

                    $LocalRecords = @()

                    try { $DllFiles = Get-ChildItem -LiteralPath $ModuleFolder -Recurse -Filter '*.dll' -File -ErrorAction SilentlyContinue } catch { $DllFiles = @() }
                    foreach ($File in $DllFiles) {
                        $VersionRaw = $null
                        try { $VersionRaw = (Get-Item -LiteralPath $File.FullName -ErrorAction SilentlyContinue).VersionInfo.ProductVersion } catch {}
                        if (-not $VersionRaw) {
                            try { $VersionRaw = (Get-Item -LiteralPath $File.FullName -ErrorAction SilentlyContinue).VersionInfo.FileVersion } catch {}
                        }
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

                    # Manifest
                    try { $Psd1 = Get-ChildItem -LiteralPath $ModuleFolder -Filter '*.psd1' -File -ErrorAction SilentlyContinue | Select-Object -First 1 } catch { $Psd1 = $null }
                    if ($Psd1) {
                        try { $Manifest = Import-PowerShellDataFile -Path $Psd1.FullName -ErrorAction Stop } catch { $Manifest = $null }
                        if ($Manifest) {
                            if ($Manifest.ContainsKey('RequiredAssemblies') -and $Manifest.RequiredAssemblies) {
                                foreach ($Req in $Manifest.RequiredAssemblies) {
                                    if (-not $Req) { continue }
                                    if ($Req -is [string] -and $Req.EndsWith('.dll', [System.StringComparison]::OrdinalIgnoreCase)) {
                                        $Resolved = $null
                                        try {
                                            if ([System.IO.Path]::IsPathRooted($Req)) { $Resolved = (Resolve-Path -LiteralPath $Req -ErrorAction SilentlyContinue).ProviderPath }
                                            else { $Resolved = (Resolve-Path -LiteralPath (Join-Path -Path $ModuleFolder -ChildPath $Req) -ErrorAction SilentlyContinue).ProviderPath }
                                        } catch {}
                                        $VersionRaw = $null
                                        if ($Resolved) {
                                            try { $VersionRaw = (Get-Item -LiteralPath $Resolved -ErrorAction SilentlyContinue).VersionInfo.ProductVersion } catch {}
                                            if (-not $VersionRaw) { try { $VersionRaw = (Get-Item -LiteralPath $Resolved -ErrorAction SilentlyContinue).VersionInfo.FileVersion } catch {} }
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
                                        if ($Resolved) {
                                            try { $VersionRaw = (Get-Item -LiteralPath $Resolved -ErrorAction SilentlyContinue).VersionInfo.ProductVersion } catch {}
                                            if (-not $VersionRaw) { try { $VersionRaw = (Get-Item -LiteralPath $Resolved -ErrorAction SilentlyContinue).VersionInfo.FileVersion } catch {} }
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

                    # DeepContent
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
                                if ($Resolved) {
                                    try { $VersionRaw = (Get-Item -LiteralPath $Resolved -ErrorAction SilentlyContinue).VersionInfo.ProductVersion } catch {}
                                    if (-not $VersionRaw) { try { $VersionRaw = (Get-Item -LiteralPath $Resolved -ErrorAction SilentlyContinue).VersionInfo.FileVersion } catch {} }
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
                } -ArgumentList $DeepInspection -ThrottleLimit $ThrottleLimit
            } catch {
                Write-Verbose "Parallel scan error: $($_.Exception.Message); fallback to serial."
                $UseParallel = $false
            }

            if ($UseParallel -and $ParallelResults) {
                foreach ($Set in $ParallelResults) { foreach ($Item in $Set) { $InventoryRecords.Add($Item) } }
            }
        }

        if (-not $UseParallel) {
            foreach ($ModuleDescriptor in $SelectedModuleFolders) {
                $Results = Scan-ModuleFolder -ModuleFolder $ModuleDescriptor.ModulePath -ModuleName $ModuleDescriptor.ModuleName -ModuleVersion $ModuleDescriptor.ModuleVersion -ModuleScope $ModuleDescriptor.Scope -DoDeep:$DeepInspection
                foreach ($Rec in $Results) { $InventoryRecords.Add($Rec) }
            }
        }
    }

    end {
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
                if ($NonNullVersion) {
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

        # Console: grouped-list view (Option A, show full module lists)
        $GroupSummary = $Normalized |
            Group-Object -Property LibraryName, LibraryVersionRaw |
                ForEach-Object {
                    $Modules = ($_.Group | Select-Object -Property ModuleName -Unique | ForEach-Object { $_.ModuleName }) -join ', '
                    $Obj = [pscustomobject]@{
                        LibraryName    = $_.Name.Split(',')[0].Trim()
                        LibraryVersion = ($_.Name.Split(',')[1].Trim() -replace '^LibraryVersionRaw=', '')
                        Modules        = $Modules
                    }
                    # Tag object for optional formatting file usage
                    $Obj.PSObject.TypeNames.Insert(0, 'ModuleDll.Inventory.Group')
                    $Obj
                }

        # Print the console table (use Format-Table for good default)
        Write-Host ''
        Write-Host 'Module DLL Inventory (grouped)' -ForegroundColor Cyan
        $GroupSummary | Format-Table -Property LibraryName, LibraryVersion, Modules -AutoSize

        # Export CSV/JSON/HTML if requested
        if ($ExportCsv) {
            try {
                $Normalized | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
                Write-Verbose "Exported CSV to $ExportCsv"
            } catch {
                Write-Warning "Failed to export CSV: $($_.Exception.Message)"
            }
        }

        if ($ExportJson) {
            try {
                $Report | ConvertTo-Json -Depth 8 | Set-Content -Path $ExportJson -Encoding UTF8
                Write-Verbose "Exported JSON to $ExportJson"
            } catch {
                Write-Warning "Failed to export JSON: $($_.Exception.Message)"
            }
        }

        if ($ExportHtml) {
            try {
                # Minimal embedded HTML/CSS/JS template with collapsible sections and color coding
                $Html = @"
<!doctype html>
<html>
<head>
<meta charset='utf-8'/>
<title>PowerShell Module DLL Inventory Report</title>
<style>
body{font-family:Segoe UI,Arial,Helvetica,sans-serif;margin:20px;background:#f8f9fb;color:#222}
h1{color:#1f4e79}
.panel{background:#fff;border-radius:8px;padding:12px;margin-bottom:12px;box-shadow:0 1px 3px rgba(0,0,0,.08)}
.badge{display:inline-block;padding:4px 8px;border-radius:12px;font-size:0.85em}
.badge-ok{background:#dff0d8;color:#2c662d}
.badge-warn{background:#fff3cd;color:#856404}
.badge-bad{background:#f8d7da;color:#721c24}
.table{width:100%;border-collapse:collapse;margin-top:8px}
.table th,.table td{padding:6px 8px;border-bottom:1px solid #eee;text-align:left}
.collapsible{cursor:pointer}
.small{font-size:0.9em;color:#555}
.code{font-family:Consolas,monospace;background:#f4f6f8;padding:6px;border-radius:4px}
</style>
</head>
<body>
<h1>PowerShell Module DLL Inventory Report</h1>
<div class='panel'>
  <strong>Generated:</strong> $($Report.GeneratedOn) <br/>
  <strong>Scope:</strong> $($Report.ScopeSearched) &nbsp; <strong>DeepInspection:</strong> $($Report.DeepInspection)
  <br/><span class='small'>Modules scanned: $($Report.ModuleCount) - DLL references: $($Report.InventoryCount)</span>
</div>

<div class='panel'>
  <h2 class='collapsible' onclick="toggle('conflicts')">Conflicts <span id='conflictsBadge' class='badge'></span></h2>
  <div id='conflicts'>
"@

                # Build conflict HTML
                $ConflictHtml = ''
                if ($Report.Conflicts.Count -gt 0) {
                    foreach ($C in $Report.Conflicts) {
                        $ConflictHtml += "<div class='panel'><h3>$($C.LibraryName)</h3><table class='table'><thead><tr><th>Module</th><th>ModuleVer</th><th>DllVer</th><th>Scope</th><th>ModulePath</th><th>DllPath</th><th>Ref</th></tr></thead><tbody>"
                        foreach ($I in $C.Instances) {
                            $ConflictHtml += "<tr><td>$($I.ModuleName)</td><td>$($I.ModuleVersion)</td><td>$($I.LibraryVersionRaw)</td><td>$($I.ModuleScope)</td><td><code class='code'>$([System.Web.HttpUtility]::HtmlEncode($I.ModulePath))</code></td><td><code class='code'>$([System.Web.HttpUtility]::HtmlEncode($I.LibraryFullPath))</code></td><td>$($I.ReferenceType)</td></tr>"
                        }
                        $ConflictHtml += '</tbody></table></div>'
                    }
                } else {
                    $ConflictHtml = "<div class='small'>No conflicts detected.</div>"
                }

                $Html += $ConflictHtml
                $Html += '</div></div>'

                # Redundancies
                $Html += "<div class='panel'><h2 class='collapsible' onclick=\"toggle('redundancies')\">Redundancies <span id='redundBadge' class='badge'></span></h2><div id='redundancies'>"
                $RedHtml = ''
                if ($Report.Redundancies.Count -gt 0) {
                    foreach ($R in $Report.Redundancies) {
                        $RedHtml += "<div class='panel'><h3>$($R.LibraryName) - version $($R.Version)</h3><table class='table'><thead><tr><th>Module</th><th>ModuleVer</th><th>Scope</th><th>ModulePath</th><th>DllPath</th><th>Ref</th></tr></thead><tbody>"
                        foreach ($I in $R.Instances) {
                            $RedHtml += "<tr><td>$($I.ModuleName)</td><td>$($I.ModuleVersion)</td><td>$($I.ModuleScope)</td><td><code class='code'>$([System.Web.HttpUtility]::HtmlEncode($I.ModulePath))</code></td><td><code class='code'>$([System.Web.HttpUtility]::HtmlEncode($I.LibraryFullPath))</code></td><td>$($I.ReferenceType)</td></tr>"
                        }
                        $RedHtml += '</tbody></table></div>'
                    }
                } else {
                    $RedHtml = "<div class='small'>No redundancies detected.</div>"
                }
                $Html += $RedHtml
                $Html += '</div></div>'

                # Inventory by scope
                $Html += "<div class='panel'><h2 class='collapsible' onclick=\"toggle('inventory')\">Inventory (by scope)</h2><div id='inventory'>"
                $ByScope = $Report.Inventory | Group-Object -Property ModuleScope
                foreach ($S in $ByScope) {
                    $Html += "<h3>Scope: $($S.Name) - Items: $($S.Count)</h3><table class='table'><thead><tr><th>Module</th><th>ModuleVer</th><th>DLL</th><th>DllVer</th><th>DllPath</th><th>Ref</th></tr></thead><tbody>"
                    foreach ($Row in $S.Group) {
                        $Html += "<tr><td>$($Row.ModuleName)</td><td>$($Row.ModuleVersion)</td><td>$($Row.LibraryName)</td><td>$($Row.LibraryVersionRaw)</td><td><code class='code'>$([System.Web.HttpUtility]::HtmlEncode($Row.LibraryFullPath))</code></td><td>$($Row.ReferenceType)</td></tr>"
                    }
                    $Html += '</tbody></table>'
                }
                $Html += '</div></div>'

                # Footer with script parameters
                $Html += "<div class='panel'><h2>Context</h2><div class='small'><pre>Scope: $($Report.ScopeSearched)`nDeepInspection: $($Report.DeepInspection)`nGenerated: $($Report.GeneratedOn)</pre></div></div>"

                # Script for collapsible and badges
                $Html += @"
<script>
function toggle(id){ var el=document.getElementById(id); if(!el) return; el.style.display=(el.style.display==='none') ? 'block' : 'none'; }
document.getElementById('conflicts').style.display='block';
document.getElementById('redundancies').style.display='block';
document.getElementById('inventory').style.display='block';
document.getElementById('conflictsBadge').innerText = '${($Report.Conflicts.Count)}';
document.getElementById('redundBadge').innerText = '${($Report.Redundancies.Count)}';
</script>
</body></html>
"@

                $Html += ''
                # Write to file
                $Html | Set-Content -Path $ExportHtml -Encoding UTF8
                Write-Verbose "Exported HTML to $ExportHtml"
            } catch {
                Write-Warning "Failed to export HTML: $($_.Exception.Message)"
            }
        }

        # Return structured objects
        if ($PassThru.IsPresent) {
            return , $Report, $Report.Inventory
        } else {
            return $Report
        }
    }
}
