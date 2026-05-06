function Compare-DLLPickleScenarioResult {
    <#
    .SYNOPSIS
    Compares two DLLPickle scenario result files.

    .DESCRIPTION
    Reads two JSON scenario outputs and returns a compact comparison object that
    highlights changed scenario success, changed step success, and assemblies
    that changed by name, version, or location.

    .PARAMETER BaselinePath
    The JSON result file captured before a proposed fix.

    .PARAMETER CandidatePath
    The JSON result file captured after a proposed fix.

    .EXAMPLE
    Compare-DLLPickleScenarioResult -BaselinePath .\before.json -CandidatePath .\after.json

    .OUTPUTS
    PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$BaselinePath,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$CandidatePath
    )

    $Baseline = Get-Content -LiteralPath $BaselinePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $Candidate = Get-Content -LiteralPath $CandidatePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

    $StepComparisons = @(
        foreach ($CandidateStep in @($Candidate.Steps)) {
            $BaselineStep = @($Baseline.Steps | Where-Object { $_.Name -eq $CandidateStep.Name } | Select-Object -First 1)
            [PSCustomObject]@{
                Name             = $CandidateStep.Name
                BaselineSuccess  = if ($BaselineStep) { [bool]$BaselineStep.Success } else { $null }
                CandidateSuccess = [bool]$CandidateStep.Success
                Changed          = if ($BaselineStep) { [bool]$BaselineStep.Success -ne [bool]$CandidateStep.Success } else { $true }
                BaselineError    = if ($BaselineStep -and $BaselineStep.Error) { $BaselineStep.Error.Message } else { $null }
                CandidateError   = if ($CandidateStep.Error) { $CandidateStep.Error.Message } else { $null }
            }
        }
    )

    $BaselineFinalAssemblies = @($Baseline.Steps | Select-Object -Last 1 -ExpandProperty AssembliesAfter)
    $CandidateFinalAssemblies = @($Candidate.Steps | Select-Object -Last 1 -ExpandProperty AssembliesAfter)
    $AssemblyKeys = @(
        @($BaselineFinalAssemblies + $CandidateFinalAssemblies) |
            Where-Object { $_ } |
            ForEach-Object { $_.Name } |
            Sort-Object -Unique
    )

    $AssemblyComparisons = @(
        foreach ($AssemblyKey in $AssemblyKeys) {
            $BaselineAssembly = @($BaselineFinalAssemblies | Where-Object { $_.Name -eq $AssemblyKey } | Select-Object -First 1)
            $CandidateAssembly = @($CandidateFinalAssemblies | Where-Object { $_.Name -eq $AssemblyKey } | Select-Object -First 1)
            $BaselineIdentity = if ($BaselineAssembly) { '{0}|{1}' -f $BaselineAssembly.Version, $BaselineAssembly.Location } else { $null }
            $CandidateIdentity = if ($CandidateAssembly) { '{0}|{1}' -f $CandidateAssembly.Version, $CandidateAssembly.Location } else { $null }

            if ($BaselineIdentity -ne $CandidateIdentity) {
                [PSCustomObject]@{
                    Name              = $AssemblyKey
                    BaselineVersion   = if ($BaselineAssembly) { $BaselineAssembly.Version } else { $null }
                    BaselineLocation  = if ($BaselineAssembly) { $BaselineAssembly.Location } else { $null }
                    CandidateVersion  = if ($CandidateAssembly) { $CandidateAssembly.Version } else { $null }
                    CandidateLocation = if ($CandidateAssembly) { $CandidateAssembly.Location } else { $null }
                }
            }
        }
    )

    [PSCustomObject]@{
        PSTypeName             = 'DLLPickle.ScenarioComparison'
        BaselinePath           = $BaselinePath
        CandidatePath          = $CandidatePath
        BaselineSuccess        = [bool]$Baseline.Success
        CandidateSuccess       = [bool]$Candidate.Success
        ScenarioSuccessChanged = [bool]$Baseline.Success -ne [bool]$Candidate.Success
        StepComparisons        = $StepComparisons
        AssemblyChanges        = $AssemblyComparisons
    }
}

