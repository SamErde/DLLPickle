BeforeAll {
    $ProjectRoot = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
    $PolicyPath = Join-Path -Path (Join-Path -Path $ProjectRoot -ChildPath 'build') -ChildPath 'dependency-policy.json'
    $ProjectPath = Join-Path -Path (Join-Path -Path (Join-Path -Path $ProjectRoot -ChildPath 'src') -ChildPath 'DLLPickle.Build') -ChildPath 'DLLPickle.csproj'
    $BuiltModuleRoot = Join-Path -Path (Join-Path -Path $ProjectRoot -ChildPath 'module') -ChildPath 'DLLPickle'
    $BuiltBinPath = Join-Path -Path (Join-Path -Path $BuiltModuleRoot -ChildPath 'bin') -ChildPath 'net8.0'

    if (-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)) {
        throw "Dependency policy not found: $PolicyPath"
    }
    if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) {
        throw "Build project not found: $ProjectPath"
    }
    if (-not (Test-Path -LiteralPath $BuiltBinPath -PathType Container)) {
        throw "Built module bin path not found. Run the PrepareModuleOutput build task first: $BuiltBinPath"
    }

    $Policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
    $Project = [xml](Get-Content -LiteralPath $ProjectPath -Raw)
    
    # Helper to evaluate MSBuild conditions
    function Test-MSBuildCondition {
        param([string]$Condition)
        
        if ([string]::IsNullOrWhiteSpace($Condition)) {
            return $true
        }

        # Replace common MSBuild properties with their runtime values
        $EvaluatedCondition = $Condition
        $EvaluatedCondition = $EvaluatedCondition -replace '\$\(OS\)', "'$([environment]::OSVersion.Platform -eq 'Win32NT' ? 'Windows_NT' : 'Unix')'"
        
        # Simple evaluation for the OS conditions we use
        if ($EvaluatedCondition -match "'\$\(OS\)'\s*==\s*'Windows_NT'") {
            return [environment]::OSVersion.Platform -eq 'Win32NT'
        } elseif ($EvaluatedCondition -match "'\$\(OS\)'\s*!=\s*'Windows_NT'") {
            return [environment]::OSVersion.Platform -ne 'Win32NT'
        }

        return $true  # If we can't evaluate, assume it applies
    }
    
    $PackageReferences = @($Project.Project.ItemGroup.PackageReference)
    $PackageReferenceByName = @{}

    foreach ($PackageReference in $PackageReferences) {
        $PackageName = [string]$PackageReference.Include
        $Condition = [string]$PackageReference.Condition
        
        # Skip this reference if the condition doesn't apply
        if (-not (Test-MSBuildCondition -Condition $Condition)) {
            continue
        }

        # If we already have this package, keep the one with the more specific metadata
        # (prefer the one with ExcludeAssets over the one without)
        if ($PackageReferenceByName.ContainsKey($PackageName)) {
            $Existing = $PackageReferenceByName[$PackageName]
            $CurrentHasExclusion = -not [string]::IsNullOrWhiteSpace([string]$PackageReference.ExcludeAssets)
            $ExistingHasExclusion = -not [string]::IsNullOrWhiteSpace([string]$Existing.ExcludeAssets)
            
            # If current has more restrictions (exclusions), keep current; otherwise keep existing
            if (-not $CurrentHasExclusion -and $ExistingHasExclusion) {
                continue
            }
        }

        $PackageReferenceByName[$PackageName] = $PackageReference
    }

    $PreloadPackages = @($Policy.preload.packageName | Sort-Object -Unique)
    $PreloadAssemblyNames = @($Policy.preload.assemblyName | Sort-Object -Unique)
    $BlockedPackages = @($Policy.blockedPreloadAssemblies.packageName | Sort-Object -Unique)
    $BlockedAssemblyNames = @($Policy.blockedPreloadAssemblies.assemblyName | Sort-Object -Unique)
    $ClassifiedPackages = @($PreloadPackages + $BlockedPackages | Sort-Object -Unique)
    $BuiltAssemblyNames = @(
        Get-ChildItem -LiteralPath $BuiltBinPath -Filter '*.dll' -File -ErrorAction Stop |
            ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } |
            Sort-Object -Unique
    )

    # Build a hashtable of blocked packages with their policy entries for platform checking
    $BlockedPoliciesByPackageName = @{}
    foreach ($BlockedPolicy in $Policy.blockedPreloadAssemblies) {
        $BlockedPoliciesByPackageName[$BlockedPolicy.packageName] = $BlockedPolicy
    }

    # Determine current platform
    $CurrentPlatform = if ([Environment]::OSVersion.Platform -eq 'Win32NT') { 'Windows' } else { 'Unix' }

    function Get-ExcludedAssetName {
        param(
            [Parameter(Mandatory)]
            [System.Xml.XmlElement]$PackageReference
        )

        @(
            [string]$PackageReference.ExcludeAssets -split ';' |
                ForEach-Object { $_.Trim().ToLowerInvariant() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
    }

    function Test-PackageApplicableToCurrentPlatform {
        param(
            [Parameter(Mandatory)]
            [string]$PackageName
        )

        $PolicyEntry = $BlockedPoliciesByPackageName[$PackageName]
        if (-not $PolicyEntry) {
            return $true # If no policy entry, assume it applies
        }

        # If no platforms field, it applies to all platforms
        if (-not $PolicyEntry.platforms) {
            return $true
        }

        # Check if current platform is in the list
        return $CurrentPlatform -in $PolicyEntry.platforms
    }
}

Describe 'Dependency policy realization' -Tag 'Integration' {
    It 'classifies every direct package reference in dependency policy' {
        $UnclassifiedDirectPackages = @(
            $PackageReferenceByName.Keys |
                Where-Object { $_ -notin $ClassifiedPackages } |
                Sort-Object
        )

        $UnclassifiedDirectPackages | Should -BeNullOrEmpty
    }

    It 'directly references every preload package' {
        $MissingPreloadReferences = @(
            $PreloadPackages |
                Where-Object { -not $PackageReferenceByName.ContainsKey($_) }
        )

        $MissingPreloadReferences | Should -BeNullOrEmpty
    }

    It 'does not exclude runtime assets from preload references' {
        $RuntimeExcludedPreloadReferences = @(
            foreach ($PackageName in $PreloadPackages) {
                if (-not $PackageReferenceByName.ContainsKey($PackageName)) {
                    continue
                }

                $ExcludeAssets = @(Get-ExcludedAssetName -PackageReference $PackageReferenceByName[$PackageName])
                if ($ExcludeAssets -contains 'runtime' -or $ExcludeAssets -contains 'all') {
                    $PackageName
                }
            }
        )

        $RuntimeExcludedPreloadReferences | Should -BeNullOrEmpty
    }

    It 'excludes runtime assets from directly referenced blocked packages' {
        $BlockedReferencesWithoutRuntimeExclusion = @(
            foreach ($PackageName in $BlockedPackages) {
                # Skip packages that are not applicable to the current platform
                if (-not (Test-PackageApplicableToCurrentPlatform -PackageName $PackageName)) {
                    continue
                }

                if (-not $PackageReferenceByName.ContainsKey($PackageName)) {
                    continue
                }

                $ExcludeAssets = @(Get-ExcludedAssetName -PackageReference $PackageReferenceByName[$PackageName])
                if ($ExcludeAssets -notcontains 'runtime' -and $ExcludeAssets -notcontains 'all') {
                    $PackageName
                }
            }
        )

        $BlockedReferencesWithoutRuntimeExclusion | Should -BeNullOrEmpty
    }

    It 'bundles every preload assembly' {
        $MissingPreloadAssemblies = @(
            $PreloadAssemblyNames |
                Where-Object { $_ -notin $BuiltAssemblyNames }
        )

        $MissingPreloadAssemblies | Should -BeNullOrEmpty
    }

    It 'does not bundle blocked assemblies' {
        # Filter blocked assemblies to only those applicable to the current platform
        $ApplicableBlockedAssemblyNames = @(
            $Policy.blockedPreloadAssemblies |
                Where-Object { Test-PackageApplicableToCurrentPlatform -PackageName $_.packageName } |
                ForEach-Object { $_.assemblyName } |
                Sort-Object -Unique
        )

        $BundledBlockedAssemblies = @(
            $ApplicableBlockedAssemblyNames |
                Where-Object { $_ -in $BuiltAssemblyNames }
        )

        $BundledBlockedAssemblies | Should -BeNullOrEmpty
    }

    It 'does not bundle assemblies absent from the preload policy' {
        $UnexpectedBundledAssemblies = @(
            $BuiltAssemblyNames |
                Where-Object { $_ -notin $PreloadAssemblyNames }
        )

        $UnexpectedBundledAssemblies | Should -BeNullOrEmpty
    }
}
