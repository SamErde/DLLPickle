#region Check During Module Import
$AlreadyLoaded = [AppDomain]::CurrentDomain.GetAssemblies() |
    Where-Object { $_.GetName().Name -eq 'Microsoft.IdentityModel.Tokens' }

if ($AlreadyLoaded) {
    Write-Warning "Microsoft.IdentityModel.Tokens already loaded: $($AlreadyLoaded.GetName().Version)"
}



if ($PSVersionTable.PSEdition -eq 'Desktop') {
    $Tfm = 'net48'
} else {
    $Tfm = 'net8.0'
}
#endregion Check During Module Import



#region BaseModule Example
$basePath = Join-Path $PSScriptRoot 'bin'

if ($PSVersionTable.PSVersion.Major -eq 5) {
    $tfm = 'net48'
} else {
    $tfm = 'net8.0'
}

$assemblyPath = Join-Path $basePath $tfm

Get-ChildItem -Path $assemblyPath -Filter *.dll |
    ForEach-Object {
        try {
            [System.Reflection.Assembly]::LoadFrom($_.FullName) | Out-Null
        } catch {
            # Ignore already-loaded assemblies
            continue
        }
    }

function Get-LoadedAssembly {
    param(
        [Parameter(Mandatory)]
        [string]$SimpleName
    )

    [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq $SimpleName }
}

function Test-CompatibleAssembly {
    param(
        [Version]$Loaded,
        [Version]$Expected
    )

    return $Loaded.Major -eq $Expected.Major
}

$expected = @{
    'Microsoft.Identity.Client'      = [Version]'4.0.0.0'
    'Microsoft.IdentityModel.Tokens' = [Version]'8.0.0.0'
}

foreach ($name in $expected.Keys) {
    $loaded = Get-LoadedAssembly -SimpleName $name

    if ($loaded) {
        $loadedVersion = $loaded.GetName().Version

        if (-not (Test-CompatibleAssembly $loadedVersion $expected[$name])) {
            Write-Warning "Incompatible $name already loaded: $loadedVersion"
            return
        }
    }
}

if ($script:DllPickleInitialized) {
    return
}

$script:DllPickleInitialized = $true


foreach ($dll in Get-ChildItem $assemblyPath -Filter *.dll) {
    $name = [System.Reflection.AssemblyName]::GetAssemblyName($dll.FullName)

    if (Get-LoadedAssembly -SimpleName $name.Name) {
        continue
    }

    [System.Reflection.Assembly]::LoadFrom($dll.FullName) | Out-Null
}
#endregion BaseModule Example



#region Preloader
# ----------------------------------
# DLLPickle - Identity DLL Preloader
# ----------------------------------

# Guardrail: idempotency
if ($script:DllPickleInitialized) {
    return
}
$script:DllPickleInitialized = $true

# -------------------------------
# Helper: get loaded assembly by simple name
# -------------------------------
function Get-LoadedAssembly {
    param(
        [Parameter(Mandatory)]
        [string]$SimpleName
    )

    [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object {
            try {
                $_.GetName().Name -eq $SimpleName
            } catch {
                $false
            }
        }
}
#endregion Preloader



# -------------------------------
# Helper: compatibility check (major version only)
# -------------------------------
function Test-CompatibleAssembly {
    param(
        [Parameter(Mandatory)]
        [Version]$LoadedVersion,

        [Parameter(Mandatory)]
        [Version]$ExpectedVersion
    )

    return $LoadedVersion.Major -eq $ExpectedVersion.Major
}

# -------------------------------
# Expected assembly major versions
# -------------------------------
$ExpectedAssemblies = @{
    'Microsoft.Identity.Client'             = [Version]'4.0.0.0'
    'Microsoft.IdentityModel.Abstractions'  = [Version]'8.0.0.0'
    'Microsoft.IdentityModel.Logging'       = [Version]'8.0.0.0'
    'Microsoft.IdentityModel.JsonWebTokens' = [Version]'8.0.0.0'
    'Microsoft.IdentityModel.Tokens'        = [Version]'8.0.0.0'
    'System.IdentityModel.Tokens.Jwt'       = [Version]'8.0.0.0'
}

# -------------------------------
# Preflight guardrail: detect incompatible assemblies
# -------------------------------
foreach ($name in $ExpectedAssemblies.Keys) {
    $loaded = Get-LoadedAssembly -SimpleName $name

    if ($loaded) {
        $loadedVersion = $loaded.GetName().Version
        $expectedVersion = $ExpectedAssemblies[$name]

        if (-not (Test-CompatibleAssembly -LoadedVersion $loadedVersion -ExpectedVersion $expectedVersion)) {
            Write-Warning (
                "DLLPickle detected incompatible assembly already loaded:`n" +
                "  $name`n" +
                "  Loaded version:  $loadedVersion`n" +
                "  Expected major:  $($expectedVersion.Major)`n" +
                'DLLPickle will not attempt to override loaded assemblies.'
            )
            return
        }
    }
}

# -------------------------------
# Determine runtime + TFM
# -------------------------------
$basePath = Join-Path $PSScriptRoot 'bin'

if ($PSVersionTable.PSVersion.Major -eq 5) {
    $tfm = 'net48'
} else {
    $tfm = 'net8.0'
}

$assemblyPath = Join-Path $basePath $tfm

if (-not (Test-Path $assemblyPath)) {
    Write-Warning "DLLPickle assembly path not found: $assemblyPath"
    return
}

# -------------------------------
# Load assemblies (deterministically)
# -------------------------------
Get-ChildItem -Path $assemblyPath -Filter '*.dll' |
    Sort-Object Name |
        ForEach-Object {

            try {
                $assemblyName = [System.Reflection.AssemblyName]::GetAssemblyName($_.FullName)
            } catch {
                return
            }

            # Skip if already loaded (idempotency + safety)
            if (Get-LoadedAssembly -SimpleName $assemblyName.Name) {
                return
            }

            try {
                [System.Reflection.Assembly]::LoadFrom($_.FullName) | Out-Null
            } catch {
                Write-Warning "DLLPickle failed to load $($_.Name): $_"
            }
        }

