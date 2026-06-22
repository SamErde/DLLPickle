BeforeAll {
    $ProjectRoot = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
    $PolicyPath = Join-Path -Path (Join-Path -Path $ProjectRoot -ChildPath 'build') -ChildPath 'dependency-policy.json'
    $ProjectPath = Join-Path -Path (Join-Path -Path (Join-Path -Path $ProjectRoot -ChildPath 'src') -ChildPath 'DLLPickle.Build') -ChildPath 'DLLPickle.csproj'
    $BuiltModuleRoot = Join-Path -Path (Join-Path -Path $ProjectRoot -ChildPath 'module') -ChildPath 'DLLPickle'
    $BuiltBinPath = Join-Path -Path (Join-Path -Path $BuiltModuleRoot -ChildPath 'bin') -ChildPath 'net8.0'
}

Describe 'Dependency policy realization' -Tag 'Integration' {
    It 'keeps the dependency policy, project references, and built bin output aligned' {
        Test-Path -LiteralPath $PolicyPath | Should -BeTrue
        Test-Path -LiteralPath $ProjectPath | Should -BeTrue
        Test-Path -LiteralPath $BuiltBinPath | Should -BeTrue

        $Policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
        $Project = [xml](Get-Content -LiteralPath $ProjectPath -Raw)
        $PackageReferences = @($Project.Project.ItemGroup.PackageReference)
        $PackageReferenceByName = @{}

        foreach ($PackageReference in $PackageReferences) {
            $PackageReferenceByName[[string]$PackageReference.Include] = $PackageReference
        }

        $PreloadPackages = @(
            $Policy.preload |
                ForEach-Object { [string]$_.packageName } |
                Sort-Object -Unique
        )
        $PreloadAssemblyNames = @(
            $Policy.preload |
                ForEach-Object { [string]$_.assemblyName } |
                Sort-Object -Unique
        )
        $BlockedPackages = @(
            $Policy.blockedPreloadAssemblies |
                ForEach-Object { [string]$_.packageName } |
                Sort-Object -Unique
        )
        $BlockedAssemblyNames = @(
            $Policy.blockedPreloadAssemblies |
                ForEach-Object { [string]$_.assemblyName } |
                Sort-Object -Unique
        )

        $MissingPreloadReferences = @(
            $PreloadPackages |
                Where-Object { -not $PackageReferenceByName.ContainsKey($_) }
        )
        $MissingPreloadReferences | Should -BeNullOrEmpty

        $RuntimeExcludedPreloadReferences = @(
            foreach ($PackageName in $PreloadPackages) {
                $PackageReference = $PackageReferenceByName[$PackageName]
                $ExcludeAssets = @(
                    [string]$PackageReference.ExcludeAssets -split ';' |
                        ForEach-Object { $_.Trim() } |
                        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                )

                if ($ExcludeAssets -contains 'runtime' -or $ExcludeAssets -contains 'all') {
                    $PackageName
                }
            }
        )
        $RuntimeExcludedPreloadReferences | Should -BeNullOrEmpty

        $BlockedReferencesWithoutRuntimeExclusion = @(
            foreach ($PackageName in $BlockedPackages) {
                if (-not $PackageReferenceByName.ContainsKey($PackageName)) {
                    continue
                }

                $PackageReference = $PackageReferenceByName[$PackageName]
                $ExcludeAssets = @(
                    [string]$PackageReference.ExcludeAssets -split ';' |
                        ForEach-Object { $_.Trim() } |
                        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                )

                if ($ExcludeAssets -notcontains 'runtime' -and $ExcludeAssets -notcontains 'all') {
                    $PackageName
                }
            }
        )
        $BlockedReferencesWithoutRuntimeExclusion | Should -BeNullOrEmpty

        $BuiltAssemblyNames = @(
            Get-ChildItem -LiteralPath $BuiltBinPath -Filter '*.dll' -File -ErrorAction Stop |
                ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } |
                Sort-Object -Unique
        )

        $MissingPreloadAssemblies = @(
            $PreloadAssemblyNames |
                Where-Object { $_ -notin $BuiltAssemblyNames }
        )
        $MissingPreloadAssemblies | Should -BeNullOrEmpty

        $BundledBlockedAssemblies = @(
            $BlockedAssemblyNames |
                Where-Object { $_ -in $BuiltAssemblyNames }
        )
        $BundledBlockedAssemblies | Should -BeNullOrEmpty

        $UnexpectedBundledAssemblies = @(
            $BuiltAssemblyNames |
                Where-Object { $_ -notin $PreloadAssemblyNames }
        )
        $UnexpectedBundledAssemblies | Should -BeNullOrEmpty
    }
}
