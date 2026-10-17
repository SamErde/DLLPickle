[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TestPath,

    [Parameter(Mandatory)]
    [string]$SummaryPath,

    [Parameter(Mandatory)]
    [string]$TestResultPath,

    [string]$CoverageSourcePathsJson,

    [string]$CodeCoverageOutputPath,

    [ValidateSet('JaCoCo', 'CoverageGutters')]
    [string]$CodeCoverageOutputFormat = 'JaCoCo',

    [int]$CoveragePercentTarget = 0,

    [string]$TestResultFormat = 'NUnitXML',

    [version]$MinimumPesterVersion = '5.2.2',

    [version]$MaximumPesterVersion = '5.99.99',

    [switch]$EnableCodeCoverage,

    [switch]$ExcludeLiveRepro
)

$ErrorActionPreference = 'Stop'

try {
    $PesterModule = Get-Module Pester -ListAvailable |
        Where-Object {
            $_.Version -ge $MinimumPesterVersion -and $_.Version -le $MaximumPesterVersion
        } |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $PesterModule) {
        throw "No Pester module was found between versions $MinimumPesterVersion and $MaximumPesterVersion."
    }

    # This script is intentionally executed by a fresh pwsh process. Importing the
    # selected module by path avoids PowerShell resolving a second installed copy.
    Import-Module -Name $PesterModule.Path -ErrorAction Stop

    $PesterConfiguration = New-PesterConfiguration
    $PesterConfiguration.Run.Path = $TestPath
    $PesterConfiguration.Run.PassThru = $true
    $PesterConfiguration.Run.Exit = $false
    $PesterConfiguration.Output.Verbosity = 'Detailed'
    $PesterConfiguration.TestResult.Enabled = $true
    $PesterConfiguration.TestResult.OutputPath = $TestResultPath
    $PesterConfiguration.TestResult.OutputFormat = $TestResultFormat

    if ($EnableCodeCoverage) {
        $CoverageSourcePath = @($CoverageSourcePathsJson | ConvertFrom-Json)
        $PesterConfiguration.CodeCoverage.Enabled = $true
        $PesterConfiguration.CodeCoverage.Path = $CoverageSourcePath
        $PesterConfiguration.CodeCoverage.CoveragePercentTarget = $CoveragePercentTarget
        $PesterConfiguration.CodeCoverage.OutputPath = $CodeCoverageOutputPath
        $PesterConfiguration.CodeCoverage.OutputFormat = $CodeCoverageOutputFormat
    }

    if ($ExcludeLiveRepro) {
        $PesterConfiguration.Filter.ExcludeTag = @('LiveRepro')
        Write-Host 'Excluding LiveRepro tests. Set DLLPICKLE_RUN_LIVE_REPRO=1 to include them.'
    }

    $TestResults = Invoke-Pester -Configuration $PesterConfiguration
    $FailedTests = @($TestResults.TestResult | Where-Object { $_ -and $_.Result -ne 'Passed' })
    $CommandsExecutedCount = [int]$TestResults.CodeCoverage.CommandsExecutedCount
    $CommandsAnalyzedCount = [int]$TestResults.CodeCoverage.CommandsAnalyzedCount
    $MissedCommands = @($TestResults.CodeCoverage.MissedCommands | Where-Object { $_ })

    $Summary = [ordered]@{
        FailedCount = [int]$TestResults.FailedCount
        CodeCoverage = [ordered]@{
            CommandsExecutedCount = $CommandsExecutedCount
            CommandsAnalyzedCount = $CommandsAnalyzedCount
            CommandsMissedCount = [Math]::Max(0, $CommandsAnalyzedCount - $CommandsExecutedCount)
            FilesAnalyzedCount = [int]$TestResults.CodeCoverage.FilesAnalyzedCount
            MissedCommands = $MissedCommands
        }
        FailedTests = @($FailedTests | ForEach-Object {
                [ordered]@{
                    Name = $_.Name
                    Result = $_.Result
                    ErrorRecord = $_.ErrorRecord
                }
            })
    }

    $Summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $SummaryPath -Encoding utf8NoBOM
} catch {
    Write-Error $_
    exit 1
}
