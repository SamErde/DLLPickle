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
    $PackageReferences = @($Project.Project.ItemGroup.PackageReference)
    $PackageReferenceByName = @{}

    foreach ($PackageReference in $PackageReferences) {
        $PackageReferenceByName[[string]$PackageReference.Include] = $PackageReference
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
        $BundledBlockedAssemblies = @(
            $BlockedAssemblyNames |
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
