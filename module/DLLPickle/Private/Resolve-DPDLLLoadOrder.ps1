function Get-DPDLLReferenceName {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string[]]$LocalAssemblyNames
    )

    $LocalAssemblyLookup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Name in $LocalAssemblyNames) {
        [void]$LocalAssemblyLookup.Add($Name)
    }

    $DirectoryPath = Split-Path -Path $Path -Parent
    $References = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Prefer MetadataLoadContext when available to inspect references without runtime load side effects.
    $MetadataLoadContextType = [type]::GetType('System.Reflection.MetadataLoadContext, System.Reflection.MetadataLoadContext', $false)
    if ($MetadataLoadContextType) {
        try {
            $ResolverPaths = [System.Collections.Generic.List[string]]::new()
            foreach ($File in (Get-ChildItem -Path $DirectoryPath -Filter '*.dll' -File -ErrorAction SilentlyContinue)) {
                [void]$ResolverPaths.Add($File.FullName)
            }

            $TrustedPlatformAssemblies = [System.AppContext]::GetData('TRUSTED_PLATFORM_ASSEMBLIES')
            if ($TrustedPlatformAssemblies) {
                $PathSeparatorPattern = [regex]::Escape([System.IO.Path]::PathSeparator.ToString())
                foreach ($AssemblyPath in ($TrustedPlatformAssemblies -split $PathSeparatorPattern)) {
                    if (-not [string]::IsNullOrWhiteSpace($AssemblyPath)) {
                        [void]$ResolverPaths.Add($AssemblyPath)
                    }
                }
            }

            $PathResolver = [System.Reflection.PathAssemblyResolver]::new($ResolverPaths)
            $MetadataContext = [System.Reflection.MetadataLoadContext]::new($PathResolver)

            try {
                $Assembly = $MetadataContext.LoadFromAssemblyPath($Path)
                foreach ($Reference in $Assembly.GetReferencedAssemblies()) {
                    if ($LocalAssemblyLookup.Contains($Reference.Name)) {
                        [void]$References.Add($Reference.Name)
                    }
                }
            } finally {
                $MetadataContext.Dispose()
            }

            return @($References)
        } catch {
            Write-Verbose "MetadataLoadContext reference discovery failed for '$Path'. Falling back to ReflectionOnly APIs when available."
        }
    }

    # Windows PowerShell fallback for reference inspection on .NET Framework.
    if ([System.Reflection.Assembly].GetMethods().Name -contains 'ReflectionOnlyLoadFrom') {
        $ReflectionOnlyResolveHandler = [System.ResolveEventHandler] {
            param ($ResolveSender, $ResolveArgs)

            [void]$ResolveSender

            try {
                $RequestedName = ([System.Reflection.AssemblyName]::new($ResolveArgs.Name)).Name
                $CandidatePath = Join-Path -Path $DirectoryPath -ChildPath "$RequestedName.dll"
                if (Test-Path -Path $CandidatePath) {
                    return [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($CandidatePath)
                }
            } catch {
                return $null
            }

            return $null
        }

        try {
            [System.AppDomain]::CurrentDomain.add_ReflectionOnlyAssemblyResolve($ReflectionOnlyResolveHandler)
            $Assembly = [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($Path)
            foreach ($Reference in $Assembly.GetReferencedAssemblies()) {
                if ($LocalAssemblyLookup.Contains($Reference.Name)) {
                    [void]$References.Add($Reference.Name)
                }
            }

            return @($References)
        } catch {
            Write-Verbose "ReflectionOnly reference discovery failed for '$Path'."
            return @()
        } finally {
            [System.AppDomain]::CurrentDomain.remove_ReflectionOnlyAssemblyResolve($ReflectionOnlyResolveHandler)
        }
    }

    return @()
}


function Resolve-DPDLLLoadOrder {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$DLLFiles
    )

    if (-not $DLLFiles -or $DLLFiles.Count -eq 0) {
        return @()
    }

    $AssemblyNameToFile = @{}
    foreach ($DLLFile in $DLLFiles) {
        $AssemblySimpleName = $DLLFile.BaseName

        try {
            $AssemblySimpleName = [System.Reflection.AssemblyName]::GetAssemblyName($DLLFile.FullName).Name
        } catch {
            Write-Verbose "Unable to read assembly metadata from '$($DLLFile.Name)'. Falling back to base filename for graph ordering."
        }

        if (-not $AssemblyNameToFile.ContainsKey($AssemblySimpleName)) {
            $AssemblyNameToFile[$AssemblySimpleName] = $DLLFile
            continue
        }

        if ([System.StringComparer]::OrdinalIgnoreCase.Compare(
                $DLLFile.FullName,
                $AssemblyNameToFile[$AssemblySimpleName].FullName) -lt 0) {
            $AssemblyNameToFile[$AssemblySimpleName] = $DLLFile
        }

        Write-Verbose "Duplicate assembly simple name '$AssemblySimpleName' detected. Using deterministic lexical path ordering."
    }

    $AssemblyNames = @($AssemblyNameToFile.Keys)
    $DependentsByDependency = @{}
    $InDegreeByAssembly = @{}

    foreach ($AssemblyName in $AssemblyNames) {
        $DependentsByDependency[$AssemblyName] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $InDegreeByAssembly[$AssemblyName] = 0
    }

    foreach ($AssemblyName in $AssemblyNames) {
        $File = $AssemblyNameToFile[$AssemblyName]
        $References = @(Get-DPDLLReferenceName -Path $File.FullName -LocalAssemblyNames $AssemblyNames)

        foreach ($DependencyName in $References) {
            if (-not $AssemblyNameToFile.ContainsKey($DependencyName)) {
                continue
            }

            if ($DependentsByDependency[$DependencyName].Add($AssemblyName)) {
                $InDegreeByAssembly[$AssemblyName]++
            }
        }
    }

    $OrderedAssemblyNames = [System.Collections.Generic.List[string]]::new()
    $ProcessedAssemblyNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    while ($OrderedAssemblyNames.Count -lt $AssemblyNames.Count) {
        $ReadyAssemblies = @(
            $AssemblyNames |
                Where-Object {
                    -not $ProcessedAssemblyNames.Contains($_) -and
                    $InDegreeByAssembly[$_] -eq 0
                } | Sort-Object
        )

        if ($ReadyAssemblies.Count -eq 0) {
            break
        }

        foreach ($ReadyAssembly in $ReadyAssemblies) {
            [void]$OrderedAssemblyNames.Add($ReadyAssembly)
            [void]$ProcessedAssemblyNames.Add($ReadyAssembly)

            foreach ($DependentAssembly in ($DependentsByDependency[$ReadyAssembly] | Sort-Object)) {
                $InDegreeByAssembly[$DependentAssembly]--
            }
        }
    }

    if ($OrderedAssemblyNames.Count -lt $AssemblyNames.Count) {
        $RemainingAssemblies = @(
            $AssemblyNames |
                Where-Object { -not $ProcessedAssemblyNames.Contains($_) } | Sort-Object
        )

        Write-Verbose "Dependency graph did not fully resolve for $($RemainingAssemblies.Count) assemblies. Appending unresolved nodes alphabetically."
        foreach ($RemainingAssembly in $RemainingAssemblies) {
            [void]$OrderedAssemblyNames.Add($RemainingAssembly)
        }
    }

    return @($OrderedAssemblyNames | ForEach-Object { $AssemblyNameToFile[$_] })
}
