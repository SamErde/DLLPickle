function Invoke-DLLPickleScenario {
    <#
    .SYNOPSIS
    Runs a DLLPickle scenario in an isolated PowerShell process.

    .DESCRIPTION
    Creates a temporary child script that runs ordered PowerShell steps in a
    fresh process, captures assembly snapshots before and after each step, and
    writes a structured JSON result file for issue reproduction diagnostics.

    .PARAMETER Name
    The scenario name recorded in the JSON result.

    .PARAMETER PowerShellExecutable
    The PowerShell executable to run, such as pwsh.

    .PARAMETER ModuleManifestPath
    Path to the DLLPickle module manifest to expose to scenario steps as
    $ScenarioModuleManifestPath.

    .PARAMETER AdditionalModulePath
    Additional module roots prepended to PSModulePath in the child process.

    .PARAMETER Step
    Ordered hashtables with Name and Script keys. Optional StopOnError stops
    later steps when a step fails.

    .PARAMETER OutputPath
    Destination JSON path. A temporary path is used when omitted.

    .PARAMETER TimeoutSeconds
    Optional maximum seconds to wait for the child process before terminating
    it. The default value of 0 waits indefinitely.

    .EXAMPLE
    Invoke-DLLPickleScenario -Name 'Import DLLPickle' -Step @(
        @{ Name = 'Import'; Script = 'Import-Module $ScenarioModuleManifestPath' }
    )

    .OUTPUTS
    PSCustomObject
    Returns the parsed scenario result object.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$PowerShellExecutable = [Environment]::ProcessPath,

        [Parameter()]
        [AllowNull()]
        [string]$ModuleManifestPath,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$AdditionalModulePath = @(),

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [hashtable[]]$Step,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath = (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('DLLPickleScenario-{0}.json' -f ([guid]::NewGuid()))),

        [Parameter()]
        [ValidateRange(0, 86400)]
        [int]$TimeoutSeconds = 0
    )

    $ExecutableCommand = Get-Command -Name $PowerShellExecutable -ErrorAction Stop
    $NormalizedSteps = @(
        foreach ($StepItem in $Step) {
            if (-not $StepItem.ContainsKey('Name') -or [string]::IsNullOrWhiteSpace([string]$StepItem.Name)) {
                throw 'Each scenario step must include a non-empty Name value.'
            }
            if (-not $StepItem.ContainsKey('Script') -or [string]::IsNullOrWhiteSpace([string]$StepItem.Script)) {
                throw "Scenario step '$($StepItem.Name)' must include a non-empty Script value."
            }

            [ordered]@{
                Name        = [string]$StepItem.Name
                Script      = [string]$StepItem.Script
                StopOnError = [bool]$StepItem.StopOnError
            }
        }
    )

    $Payload = [ordered]@{
        Name               = $Name
        ModuleManifestPath = $ModuleManifestPath
        AdditionalModulePath = @($AdditionalModulePath | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_)
            })
        Steps              = $NormalizedSteps
        OutputPath         = $OutputPath
    }

    $PayloadJson = $Payload | ConvertTo-Json -Depth 20
    $PayloadBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($PayloadJson))
    $ChildScriptTemplate = @'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$PayloadJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('__PAYLOAD__'))
$Payload = $PayloadJson | ConvertFrom-Json
$ScenarioAppDataRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('DLLPickleScenarioAppData-{0}' -f [guid]::NewGuid())
$null = New-Item -Path $ScenarioAppDataRoot -ItemType Directory -Force
$env:APPDATA = $ScenarioAppDataRoot
$env:XDG_CONFIG_HOME = $ScenarioAppDataRoot
$ScenarioConfigDirectory = Join-Path -Path $ScenarioAppDataRoot -ChildPath 'DLLPickle'
$null = New-Item -Path $ScenarioConfigDirectory -ItemType Directory -Force
$ScenarioConfig = [ordered]@{
    CheckForUpdates = $false
    ShowLogo = $false
    SkipLibraries = @()
}
$ScenarioConfig |
    ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path -Path $ScenarioConfigDirectory -ChildPath 'config.json') -Encoding UTF8

$OutputDirectory = Split-Path -Path $Payload.OutputPath -Parent
if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
}

$AdditionalModulePaths = @($Payload.AdditionalModulePath | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_)
    })
if ($AdditionalModulePaths.Count -gt 0) {
    $ExistingModulePaths = @($env:PSModulePath -split [System.IO.Path]::PathSeparator | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        })
    $env:PSModulePath = @($AdditionalModulePaths + $ExistingModulePaths) -join [System.IO.Path]::PathSeparator
}

function Get-DLLPickleScenarioAssemblySnapshot {
    [CmdletBinding()]
    param()

    [System.AppDomain]::CurrentDomain.GetAssemblies() |
        ForEach-Object {
            $AssemblyName = $_.GetName()
            $LoadContext = [System.Runtime.Loader.AssemblyLoadContext]::GetLoadContext($_)
            $Location = $null
            $GlobalAssemblyCache = $false
            try {
                $Location = $_.Location
            } catch {
                $Location = $null
            }
            try {
                $GlobalAssemblyCache = [bool]$_.GlobalAssemblyCache
            } catch {
                $GlobalAssemblyCache = $false
            }

            [PSCustomObject]@{
                Name                = $AssemblyName.Name
                Version             = if ($AssemblyName.Version) { $AssemblyName.Version.ToString() } else { $null }
                Location            = $Location
                GlobalAssemblyCache = $GlobalAssemblyCache
                FullName            = $_.FullName
                LoadContext         = if ($LoadContext -and $LoadContext.Name) { $LoadContext.Name } else { 'Default' }
                IsCollectible       = if ($LoadContext) { $LoadContext.IsCollectible } else { $false }
                Sha256              = if (-not [string]::IsNullOrWhiteSpace($Location) -and (Test-Path -LiteralPath $Location -PathType Leaf)) {
                    (Get-FileHash -LiteralPath $Location -Algorithm SHA256).Hash.ToLowerInvariant()
                } else {
                    $null
                }
            }
        } | Sort-Object -Property Name, Version, Location
}

function ConvertTo-DLLPickleScenarioText {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        [object]$InputObject
    )

    process {
        if ($null -eq $InputObject) {
            return $null
        }

        if ($InputObject -is [string]) {
            return $InputObject
        }

        if ($InputObject -is [System.Management.Automation.ErrorRecord]) {
            return ($InputObject | ConvertTo-DLLPickleScenarioError | ConvertTo-Json -Compress -Depth 4)
        }

        if ($InputObject -is [System.Exception]) {
            return ([PSCustomObject]@{
                    ExceptionType = $InputObject.GetType().FullName
                    Message       = $InputObject.Message
                } | ConvertTo-Json -Compress -Depth 4)
        }

        try {
            return ($InputObject | Select-Object -Property * | ConvertTo-Json -Compress -Depth 4)
        } catch {
            return $InputObject.ToString()
        }
    }
}

function ConvertTo-DLLPickleScenarioError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    [PSCustomObject]@{
        ExceptionType = $ErrorRecord.Exception.GetType().FullName
        Message       = $ErrorRecord.Exception.Message
        FullyQualifiedErrorId = $ErrorRecord.FullyQualifiedErrorId
        ScriptStackTrace = $ErrorRecord.ScriptStackTrace
    }
}

$ScenarioModuleManifestPath = [string]$Payload.ModuleManifestPath
$ScenarioOutputPath = [string]$Payload.OutputPath
$RuntimeProfile = $null
if (-not [string]::IsNullOrWhiteSpace($ScenarioModuleManifestPath)) {
    $RuntimePolicyPath = Join-Path -Path (Split-Path -Path $ScenarioModuleManifestPath -Parent) -ChildPath 'SupportedRuntimeProfiles.json'
    if (Test-Path -LiteralPath $RuntimePolicyPath -PathType Leaf) {
        $RuntimePolicy = Get-Content -LiteralPath $RuntimePolicyPath -Raw | ConvertFrom-Json
        $RuntimeProfile = @($RuntimePolicy.profiles | Where-Object {
                $_.powerShellMajor -eq $PSVersionTable.PSVersion.Major -and
                $_.powerShellMinor -eq $PSVersionTable.PSVersion.Minor -and
                $_.dotnetMajor -eq [Environment]::Version.Major
            }) | Select-Object -First 1
    }
}
$Scenario = [ordered]@{
    ScenarioName       = [string]$Payload.Name
    StartedAt          = [System.DateTimeOffset]::UtcNow.ToString('o')
    ModuleManifestPath = $ScenarioModuleManifestPath
    AdditionalModulePath = $AdditionalModulePaths
    Host               = [ordered]@{
        ProcessPath      = (Get-Process -Id $PID).Path
        PSVersion        = $PSVersionTable.PSVersion.ToString()
        PSEdition        = $PSVersionTable.PSEdition
        OS               = if ($PSVersionTable.ContainsKey('OS')) { $PSVersionTable.OS } else { [System.Environment]::OSVersion.VersionString }
        CLRVersion       = if ($PSVersionTable.ContainsKey('CLRVersion')) { $PSVersionTable.CLRVersion.ToString() } else { $null }
        RuntimeVersion   = [System.Environment]::Version.ToString()
        TargetFramework  = if ($RuntimeProfile) { [string]$RuntimeProfile.targetFramework } else { 'net{0}.0' -f [Environment]::Version.Major }
        SelectedBundlePath = if ($RuntimeProfile) {
            Join-Path -Path (Split-Path -Path $ScenarioModuleManifestPath -Parent) -ChildPath (Join-Path 'bin' $RuntimeProfile.targetFramework)
        } else {
            $null
        }
        PSHome           = $PSHOME
        Platform         = if ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)) { 'windows' } elseif ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::OSX)) { 'macos' } else { 'linux' }
        Architecture     = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLowerInvariant()
        PSModulePath     = $env:PSModulePath
        AppDataRoot      = $ScenarioAppDataRoot
    }
    InitialAssemblies  = @(Get-DLLPickleScenarioAssemblySnapshot)
    Steps              = [System.Collections.Generic.List[object]]::new()
}

$ScenarioFailed = $false
foreach ($Step in @($Payload.Steps)) {
    $AssembliesBefore = @(Get-DLLPickleScenarioAssemblySnapshot)
    $StepOutput = @()
    $StepError = $null
    $StepSucceeded = $true

    try {
        $ScriptBlock = [scriptblock]::Create([string]$Step.Script)
        $StepOutput = @(& $ScriptBlock 3>&1 4>&1 5>&1 6>&1)
    } catch {
        $StepSucceeded = $false
        $ScenarioFailed = $true
        $StepError = ConvertTo-DLLPickleScenarioError -ErrorRecord $_
    }

    $ImportResults = @(
        $StepOutput |
            Where-Object {
                $_ -and
                $_.PSObject.Properties.Name -contains 'Status' -and
                $_.PSObject.Properties.Name -contains 'DLLName'
            } |
            Select-Object -Property DLLName, AssemblyName, AssemblyVersion, Status, Error
    )

    $Scenario.Steps.Add([PSCustomObject]@{
            Name             = [string]$Step.Name
            Success          = $StepSucceeded
            Error            = $StepError
            Output           = @($StepOutput | ConvertTo-DLLPickleScenarioText)
            ImportResults    = $ImportResults
            AssembliesBefore = $AssembliesBefore
            AssembliesAfter  = @(Get-DLLPickleScenarioAssemblySnapshot)
        })

    if (-not $StepSucceeded -and [bool]$Step.StopOnError) {
        break
    }
}

$Scenario.CompletedAt = [System.DateTimeOffset]::UtcNow.ToString('o')
$Scenario.Success = -not $ScenarioFailed
$Scenario | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Payload.OutputPath -Encoding UTF8

if ($ScenarioFailed) {
    exit 1
}

exit 0
'@

    $ChildScriptContent = $ChildScriptTemplate.Replace('__PAYLOAD__', $PayloadBase64)
    $ChildScriptPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('DLLPickleScenario-{0}.ps1' -f ([guid]::NewGuid()))

    try {
        Set-Content -LiteralPath $ChildScriptPath -Value $ChildScriptContent -Encoding UTF8 -Force
        $StartInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $StartInfo.FileName = $ExecutableCommand.Source
        $StartInfo.UseShellExecute = $false
        $StartInfo.RedirectStandardOutput = $true
        $StartInfo.RedirectStandardError = $true
        $StartInfo.CreateNoWindow = $true
        [void]$StartInfo.ArgumentList.Add('-NoProfile')
        [void]$StartInfo.ArgumentList.Add('-File')
        [void]$StartInfo.ArgumentList.Add($ChildScriptPath)

        $Process = [System.Diagnostics.Process]::new()
        $Process.StartInfo = $StartInfo
        [void]$Process.Start()
        $StandardOutputTask = $Process.StandardOutput.ReadToEndAsync()
        $StandardErrorTask = $Process.StandardError.ReadToEndAsync()

        if ($TimeoutSeconds -gt 0) {
            if (-not $Process.WaitForExit($TimeoutSeconds * 1000)) {
                try {
                    $Process.Kill()
                } catch {
                    Write-Verbose "Failed to terminate timed-out scenario process $($Process.Id): $($_.Exception.Message)"
                }

                throw "Scenario '$Name' exceeded the $TimeoutSeconds second timeout."
            }
        } else {
            $Process.WaitForExit()
        }

        $Process.WaitForExit()
        $ProcessExitCode = $Process.ExitCode
        $ProcessOutput = @(
            if ($StandardOutputTask.Result) { $StandardOutputTask.Result }
            if ($StandardErrorTask.Result) { $StandardErrorTask.Result }
        )

        if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
            throw "Scenario '$Name' did not create an output file. Process output: $($ProcessOutput -join [Environment]::NewLine)"
        }

        $Result = Get-Content -LiteralPath $OutputPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $Result | Add-Member -MemberType NoteProperty -Name ProcessExitCode -Value $ProcessExitCode -Force
        $Result | Add-Member -MemberType NoteProperty -Name ProcessOutput -Value @($ProcessOutput | ForEach-Object { $_.ToString() }) -Force
        return $Result
    } finally {
        Remove-Item -LiteralPath $ChildScriptPath -Force -ErrorAction SilentlyContinue
    }
}
