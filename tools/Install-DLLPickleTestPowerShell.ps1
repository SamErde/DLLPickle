<#
.SYNOPSIS
Provision or validate an exact stock PowerShell executable for DLLPickle tests.

.DESCRIPTION
Uses either an explicit executable, a checksum-verified official PowerShell archive,
or the pinned optional multi-pwsh CI provider. The returned executable is always the
official payload pwsh/pwsh.exe, never an alias, shim, hosted process, or PATH lookup.

.PARAMETER PowerShellExecutable
An already-provisioned stock PowerShell executable to validate and return.

.PARAMETER Provider
The provisioning provider. DirectArchive downloads the official Microsoft release
archive. MultiPwsh uses the separately pinned CI-only provider.

.PARAMETER PowerShellVersion
The exact servicing patch required by the CI support matrix.

.PARAMETER InstallRoot
Runner-temporary installation and cache root. No persistent PATH changes are made.

.PARAMETER MatrixPath
Path to build/powershell-test-matrix.json.

.PARAMETER Platform
Target platform. Defaults to the current process platform.

.PARAMETER Architecture
Target process architecture. Defaults to the current process architecture.

.PARAMETER PassThru
Return structured runtime identity details instead of only the executable path.

.OUTPUTS
System.String or System.Management.Automation.PSCustomObject
#>

[CmdletBinding(DefaultParameterSetName = 'Provider')]
[OutputType([string], [pscustomobject])]
param (
    [Parameter(Mandatory, ParameterSetName = 'Executable')]
    [ValidateNotNullOrEmpty()]
    [string]$PowerShellExecutable,

    [Parameter(Mandatory, ParameterSetName = 'Provider')]
    [ValidateSet('DirectArchive', 'MultiPwsh')]
    [string]$Provider,

    [Parameter(Mandatory)]
    [version]$PowerShellVersion,

    [Parameter(ParameterSetName = 'Provider')]
    [string]$InstallRoot,

    [Parameter()]
    [string]$MatrixPath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'build/powershell-test-matrix.json'),

    [Parameter(ParameterSetName = 'Provider')]
    [ValidateSet('windows', 'linux', 'macos')]
    [string]$Platform,

    [Parameter(ParameterSetName = 'Provider')]
    [ValidateSet('x64', 'x86', 'arm64', 'arm32')]
    [string]$Architecture,

    [Parameter()]
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CurrentPlatformName {
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
        return 'windows'
    }
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) {
        return 'macos'
    }
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)) {
        return 'linux'
    }

    throw 'The current operating system is not supported by the DLLPickle test matrix.'
}

function Get-VerifiedDownload {
    param (
        [Parameter(Mandatory)]
        [uri]$Uri,

        [Parameter(Mandatory)]
        [string]$DestinationPath,

        [Parameter(Mandatory)]
        [ValidatePattern('^[a-fA-F0-9]{64}$')]
        [string]$Sha256
    )

    $DestinationDirectory = Split-Path -Path $DestinationPath -Parent
    if (-not (Test-Path -LiteralPath $DestinationDirectory -PathType Container)) {
        $null = New-Item -Path $DestinationDirectory -ItemType Directory -Force
    }

    if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) {
        $ExistingHash = (Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256).Hash
        if ($ExistingHash -ieq $Sha256) {
            return
        }

        Remove-Item -LiteralPath $DestinationPath -Force
    }

    $DownloadParameters = @{
        Uri                      = $Uri
        OutFile                  = $DestinationPath
        UseBasicParsing          = $true
        ConnectionTimeoutSeconds = 60
        OperationTimeoutSeconds  = 300
        MaximumRetryCount        = 3
        RetryIntervalSec         = 5
    }
    Invoke-WebRequest @DownloadParameters
    $ActualHash = (Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256).Hash
    if ($ActualHash -ine $Sha256) {
        Remove-Item -LiteralPath $DestinationPath -Force
        throw "Checksum validation failed for '$Uri'. Expected $Sha256 but received $ActualHash."
    }
}

function Expand-TestRuntimeArchive {
    param (
        [Parameter(Mandatory)]
        [string]$ArchivePath,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    if (Test-Path -LiteralPath $DestinationPath) {
        Remove-Item -LiteralPath $DestinationPath -Recurse -Force
    }

    $StagingPath = '{0}.staging-{1}-{2}' -f $DestinationPath, $PID, ([System.Guid]::NewGuid().ToString('n'))
    $null = New-Item -Path $StagingPath -ItemType Directory -Force
    try {
        if ([System.IO.Path]::GetExtension($ArchivePath) -eq '.zip') {
            Expand-Archive -LiteralPath $ArchivePath -DestinationPath $StagingPath -Force
        } else {
            $TarOutput = @(& tar -xzf $ArchivePath -C $StagingPath 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to extract '$ArchivePath': $($TarOutput -join [Environment]::NewLine)"
            }
        }

        Move-Item -LiteralPath $StagingPath -Destination $DestinationPath
    } finally {
        if (Test-Path -LiteralPath $StagingPath) {
            Remove-Item -LiteralPath $StagingPath -Recurse -Force
        }
    }
}

function Test-PathWithinRoot {
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Root
    )

    $RelativePath = [System.IO.Path]::GetRelativePath(
        [System.IO.Path]::GetFullPath($Root),
        [System.IO.Path]::GetFullPath($Path)
    )
    -not $RelativePath.StartsWith('..', [System.StringComparison]::Ordinal) -and
        -not [System.IO.Path]::IsPathRooted($RelativePath)
}

function Get-StockPowerShellIdentity {
    param (
        [Parameter(Mandatory)]
        [string]$ExecutablePath
    )

    $IdentityProbe = @'
$Platform = if ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)) {
    'windows'
} elseif ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::OSX)) {
    'macos'
} elseif ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Linux)) {
    'linux'
} else {
    'unknown'
}
[ordered]@{
    powerShellVersion = $PSVersionTable.PSVersion.ToString()
    dotNetVersion = [Environment]::Version.ToString()
    dotNetMajor = [Environment]::Version.Major
    psHome = $PSHOME
    processPath = [Environment]::ProcessPath
    platform = $Platform
    architecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLowerInvariant()
} | ConvertTo-Json -Compress
'@

    $ProbeOutput = @(& $ExecutablePath -NoLogo -NoProfile -NonInteractive -Command $IdentityProbe 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Stock PowerShell identity probe failed for '$ExecutablePath': $($ProbeOutput -join [Environment]::NewLine)"
    }

    try {
        $ProbeOutput -join [Environment]::NewLine | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Stock PowerShell identity probe returned malformed output for '$ExecutablePath': $($ProbeOutput -join [Environment]::NewLine)"
    }
}

if (-not (Test-Path -LiteralPath $MatrixPath -PathType Leaf)) {
    throw "PowerShell test matrix not found: $MatrixPath"
}

try {
    $Matrix = Get-Content -LiteralPath $MatrixPath -Raw | ConvertFrom-Json -ErrorAction Stop
} catch {
    throw "PowerShell test matrix is malformed: $($_.Exception.Message)"
}

$ExactVersion = $PowerShellVersion.ToString()
$Profiles = @($Matrix.profiles | Where-Object powerShellVersion -eq $ExactVersion)
if ($Profiles.Count -ne 1) {
    throw "PowerShell $ExactVersion is not an exact, unique servicing patch in the DLLPickle test matrix."
}
$ExpectedProfile = $Profiles[0]

$ExpectedPayloadRoot = $null
if ($PSCmdlet.ParameterSetName -eq 'Executable') {
    if (-not (Test-Path -LiteralPath $PowerShellExecutable -PathType Leaf)) {
        throw "Explicit PowerShell executable not found: $PowerShellExecutable"
    }
    $ResolvedExecutable = (Resolve-Path -LiteralPath $PowerShellExecutable).Path
    $EffectiveProvider = 'ExplicitExecutable'
} else {
    if ([string]::IsNullOrWhiteSpace($Platform)) {
        $Platform = Get-CurrentPlatformName
    }
    if ([string]::IsNullOrWhiteSpace($Architecture)) {
        $Architecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLowerInvariant()
    }
    if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
        $TemporaryRoot = if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
            $env:RUNNER_TEMP
        } else {
            [System.IO.Path]::GetTempPath()
        }
        $InstallRoot = Join-Path -Path $TemporaryRoot -ChildPath 'DLLPickle/TestPowerShell'
    }
    $InstallRoot = [System.IO.Path]::GetFullPath($InstallRoot)

    $Lane = @($Matrix.lanes | Where-Object { $_.platform -eq $Platform -and $_.architecture -eq $Architecture })
    if ($Lane.Count -ne 1) {
        throw "The DLLPickle test matrix does not declare exactly one $Platform/$Architecture lane."
    }
    $ExecutableName = [string]$Lane[0].executableName

    if ($Provider -eq 'DirectArchive') {
        $Archive = @($Matrix.archiveAssets | Where-Object {
                $_.powerShellVersion -eq $ExactVersion -and $_.platform -eq $Platform -and $_.architecture -eq $Architecture
            })
        if ($Archive.Count -ne 1) {
            throw "The DLLPickle test matrix does not declare exactly one official archive for PowerShell $ExactVersion on $Platform/$Architecture."
        }

        $ProviderRoot = Join-Path -Path $InstallRoot -ChildPath ([System.IO.Path]::Combine('DirectArchive', $ExactVersion, "$Platform-$Architecture"))
        $CachePath = Join-Path -Path $ProviderRoot -ChildPath (Join-Path 'cache' $Archive[0].fileName)
        $ExpectedPayloadRoot = Join-Path -Path $ProviderRoot -ChildPath 'payload'
        $ExpectedExecutable = Join-Path -Path $ExpectedPayloadRoot -ChildPath $ExecutableName

        if (-not (Test-Path -LiteralPath $ExpectedExecutable -PathType Leaf)) {
            Get-VerifiedDownload -Uri $Archive[0].downloadUrl -DestinationPath $CachePath -Sha256 $Archive[0].sha256
            Expand-TestRuntimeArchive -ArchivePath $CachePath -DestinationPath $ExpectedPayloadRoot
            if ($Platform -ne 'windows') {
                $ChmodOutput = @(& chmod u+x $ExpectedExecutable 2>&1)
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to mark the stock PowerShell executable as executable: $($ChmodOutput -join [Environment]::NewLine)"
                }
            }
        }
    } else {
        $OptionalProvider = $Matrix.provisioning.optionalProvider
        if (-not $OptionalProvider.ciOnly -or $OptionalProvider.name -ne 'MultiPwsh') {
            throw 'The optional provider policy must identify MultiPwsh as CI-only.'
        }
        $ProviderAsset = @($OptionalProvider.assets | Where-Object {
                $_.platform -eq $Platform -and $_.architecture -eq $Architecture
            })
        if ($ProviderAsset.Count -ne 1) {
            throw "The DLLPickle test matrix does not declare exactly one MultiPwsh asset for $Platform/$Architecture."
        }

        $ProviderRoot = Join-Path -Path $InstallRoot -ChildPath ([System.IO.Path]::Combine('MultiPwsh', "v$($OptionalProvider.version)", "$Platform-$Architecture", $ExactVersion))
        $ToolCachePath = Join-Path -Path $ProviderRoot -ChildPath (Join-Path 'cache' $ProviderAsset[0].fileName)
        $ToolPayloadRoot = Join-Path -Path $ProviderRoot -ChildPath 'tool'
        $ToolExecutableName = if ($Platform -eq 'windows') { 'multi-pwsh.exe' } else { 'multi-pwsh' }
        $MultiPwshExecutable = Join-Path -Path $ToolPayloadRoot -ChildPath $ToolExecutableName
        $MultiPwshInstallRoot = Join-Path -Path $ProviderRoot -ChildPath 'payload'
        $ExpectedPayloadRoot = Join-Path -Path $MultiPwshInstallRoot -ChildPath (Join-Path 'multi' $ExactVersion)
        $ExpectedExecutable = Join-Path -Path $ExpectedPayloadRoot -ChildPath $ExecutableName

        if (-not (Test-Path -LiteralPath $ExpectedExecutable -PathType Leaf)) {
            if (-not (Test-Path -LiteralPath $MultiPwshExecutable -PathType Leaf)) {
                Get-VerifiedDownload -Uri $ProviderAsset[0].downloadUrl -DestinationPath $ToolCachePath -Sha256 $ProviderAsset[0].sha256
                Expand-TestRuntimeArchive -ArchivePath $ToolCachePath -DestinationPath $ToolPayloadRoot
                if ($Platform -ne 'windows') {
                    $ChmodOutput = @(& chmod u+x $MultiPwshExecutable 2>&1)
                    if ($LASTEXITCODE -ne 0) {
                        throw "Failed to mark multi-pwsh as executable: $($ChmodOutput -join [Environment]::NewLine)"
                    }
                }
            }

            $InstallOutput = @(& $MultiPwshExecutable install $ExactVersion --scope user --root $MultiPwshInstallRoot --arch $Architecture --no-add-path 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "MultiPwsh failed to install PowerShell ${ExactVersion}: $($InstallOutput -join [Environment]::NewLine)"
            }
        }
    }

    if (-not (Test-Path -LiteralPath $ExpectedExecutable -PathType Leaf)) {
        throw "$Provider did not produce the expected official PowerShell executable: $ExpectedExecutable"
    }
    $ResolvedExecutable = (Resolve-Path -LiteralPath $ExpectedExecutable).Path
    if (-not (Test-PathWithinRoot -Path $ResolvedExecutable -Root $ExpectedPayloadRoot)) {
        throw "Rejected provider executable outside the expected official payload root: $ResolvedExecutable"
    }
    $EffectiveProvider = $Provider
}

$Identity = Get-StockPowerShellIdentity -ExecutablePath $ResolvedExecutable
if ([version]$Identity.powerShellVersion -ne $PowerShellVersion) {
    throw "PowerShell version mismatch. Expected $ExactVersion but '$ResolvedExecutable' reported $($Identity.powerShellVersion)."
}
if ([int]$Identity.dotNetMajor -ne [int]$ExpectedProfile.dotnetMajor) {
    throw "CLR mismatch for PowerShell $ExactVersion. Expected CLR $($ExpectedProfile.dotnetMajor) but '$ResolvedExecutable' reported CLR $($Identity.dotNetMajor)."
}
if ($PSCmdlet.ParameterSetName -eq 'Provider') {
    if ($Identity.platform -ne $Platform -or $Identity.architecture -ne $Architecture) {
        throw "Runtime identity mismatch. Expected $Platform/$Architecture but '$ResolvedExecutable' reported $($Identity.platform)/$($Identity.architecture)."
    }
    if (-not (Test-PathWithinRoot -Path $Identity.psHome -Root $ExpectedPayloadRoot)) {
        throw "Rejected PowerShell host whose PSHOME is outside the expected official payload root: $($Identity.psHome)"
    }
    if (-not (Test-PathWithinRoot -Path $Identity.processPath -Root $ExpectedPayloadRoot)) {
        throw "Rejected PowerShell host shim whose process path is outside the expected official payload root: $($Identity.processPath)"
    }
}

$Result = [pscustomobject]@{
    Provider          = $EffectiveProvider
    PowerShellVersion = [string]$Identity.powerShellVersion
    DotNetVersion     = [string]$Identity.dotNetVersion
    DotNetMajor       = [int]$Identity.dotNetMajor
    TargetFramework   = [string]$ExpectedProfile.targetFramework
    ExecutablePath    = [string]$ResolvedExecutable
    PSHome            = [string]$Identity.psHome
    ProcessPath       = [string]$Identity.processPath
    Platform          = [string]$Identity.platform
    Architecture      = [string]$Identity.architecture
}

if ($PassThru) {
    $Result
} else {
    $Result.ExecutablePath
}
