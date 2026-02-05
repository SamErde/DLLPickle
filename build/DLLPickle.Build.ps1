<#
.SYNOPSIS
    An Invoke-Build Build file.
.DESCRIPTION
    Build steps can include:
        - ValidateRequirements
        - ImportModuleManifest
        - Clean
        - Analyze
        - FormattingCheck
        - Test
        - DevCC
        - CreateHelpStart
        - Build
        - IntegrationTest
        - Archive
.EXAMPLE
    Invoke-Build

    This will perform the default build Add-BuildTasks: see below for the default Add-BuildTask execution
.EXAMPLE
    Invoke-Build -Add-BuildTask Analyze,Test

    This will perform only the Analyze and Test Add-BuildTasks.
.NOTES
    This build file by Catesta will pull in configurations from the "<module>.Settings.ps1" file as well, where users can more easily customize the build process if required.
    https://github.com/nightroman/Invoke-Build
    https://github.com/nightroman/Invoke-Build/wiki/Build-Scripts-Guidelines

    If using VSCode you can use the generated tasks.json to execute the various tasks in this build file.
        Ctrl + P | then type task (add space) - you will then be presented with a list of available tasks to run

    The 'InstallDependencies' Add-BuildTask isn't present here.
        Module dependencies are installed at a previous step in the pipeline.
        If your manifest has module dependencies include all required modules in your CI/CD bootstrap file:
            AWS            - install_modules.ps1
            Azure          - Actions_Bootstrap.ps1
            GitHub Actions - Actions_Bootstrap.ps1
            AppVeyor       - Actions_Bootstrap.ps1
#>

#Include: Settings
. "$(Join-Path -Path $PSScriptRoot -ChildPath "$ModuleName.Settings.ps1")"

function Test-ManifestBool ($Path) {
    # Validate the module manifest file
    Get-ChildItem $Path | Test-ModuleManifest -ErrorAction SilentlyContinue | Out-Null; $?
}

#Default Build
[string[]]$str = 'Clean', 'ValidateRequirements', 'ImportModuleManifest'
$str += 'FormattingCheck'
$str += 'Analyze', 'Test'
$str += 'CreateHelpStart'
[string[]]$str2 = $str # str2: Full build without integration tests
$str2 += 'Build', 'Archive'
$str += 'Build', 'IntegrationTest', 'Archive' # str: Full build
Add-BuildTask -Name . -Jobs $str

#Local testing build process
Add-BuildTask TestLocal Clean, ImportModuleManifest, Analyze, Test

#Local help file creation process
Add-BuildTask HelpLocal Clean, ImportModuleManifest, CreateHelpStart

#Full build without integration tests
Add-BuildTask BuildNoIntegration -Jobs $str2


# Pre-build variables to be used by other portions of the script
Enter-Build {
    $script:ProjectRoot = Split-Path -Path $PSScriptRoot -Parent

    ### QUESTION: Is the $BuildFile variable created by Invoke-Build automatically?
    $script:ModuleName = [regex]::Match((Get-Item $BuildFile).Name, '^(.*)\.Build\.ps1$').Groups[1].Value

    # Identify other required paths
    ### QUESTION: Is the $BuildRoot variable created by Invoke-Build automatically?
    $script:ModuleSourcePath = [System.IO.Path]::Join($ProjectRoot, 'src', $script:ModuleName)
    $script:ModuleFiles = Join-Path -Path $script:ModuleSourcePath -ChildPath '*'

    $script:ModuleManifestFile = Join-Path -Path $script:ModuleSourcePath -ChildPath "$($script:ModuleName).psd1"

    $ManifestInfo = Import-PowerShellDataFile -Path $script:ModuleManifestFile
    $script:ModuleVersion = $ManifestInfo.ModuleVersion
    $script:ModuleDescription = $ManifestInfo.Description
    $script:FunctionsToExport = $ManifestInfo.FunctionsToExport

    $script:TestsPath = Join-Path -Path $ProjectRoot -ChildPath 'tests'
    $script:UnitTestsPath = Join-Path -Path $script:TestsPath -ChildPath 'Unit'
    $script:IntegrationTestsPath = Join-Path -Path $script:TestsPath -ChildPath 'Integration'

    $script:ArtifactsPath = Join-Path -Path $ProjectRoot -ChildPath 'artifacts'
    $script:ArchivePath = Join-Path -Path $ProjectRoot -ChildPath 'archive'

    $script:BuildModuleRootFile = Join-Path -Path $script:ArtifactsPath -ChildPath "$($script:ModuleName).psm1"

    # SET: Ensure our builds fail until if below a minimum defined code test coverage threshold
    $script:CoverageThreshold = 0

    [version]$script:MinPesterVersion = '5.2.2'
    [version]$script:MaxPesterVersion = '5.99.99'
    $script:TestOutputFormat = 'NUnitXML'
} #Enter-Build


# Define headers as separator, task path, synopsis, and location, e.g. for Ctrl+Click in VSCode.
# Also change the default color to Green. If you need task start times, use `$Task.Started`.
Set-BuildHeader {
    param ($Path)
    # Separator line
    Write-Build DarkMagenta ('=' * 79)
    # Default header + synopsis
    Write-Build DarkGray "Task $Path : $(Get-BuildSynopsis $Task)"
    # Task location in a script
    Write-Build DarkGray "At $($Task.InvocationInfo.ScriptName):$($Task.InvocationInfo.ScriptLineNumber)"
    Write-Build Yellow "Manifest File: $script:ModuleManifestFile"
    Write-Build Yellow "Manifest Version: $($ManifestInfo.ModuleVersion)"
} #Set-BuildHeader


# Define footers similar to default but change the color to DarkGray.
Set-BuildFooter {
    param ($Path)
    Write-Build DarkGray "Done $Path, $($Task.Elapsed)"
    # Separator line
    Write-Build Gray ('=' * 79)
} #Set-BuildFooter


#Synopsis: Validate system requirements are met
Add-BuildTask ValidateRequirements {
    # This setting comes from the *.Settings.ps1
    Write-Build White "      Verifying at least PowerShell $script:requiredPSVersion..."
    Assert-Build ($PSVersionTable.PSVersion -ge $script:requiredPSVersion) "At least Powershell $script:requiredPSVersion is required for this build to function properly"
    Write-Build Green '      ...Verification Complete!'
} #ValidateRequirements


# Synopsis: Import the current module manifest file for processing
Add-BuildTask TestModuleManifest -Before ImportModuleManifest {
    Write-Build White '      Running module manifest tests...'
    Assert-Build (Test-Path $script:ModuleManifestFile) 'Unable to locate the module manifest file.'
    Assert-Build (Test-ManifestBool -Path $script:ModuleManifestFile) 'Module Manifest test did not pass verification.'
    Write-Build Green '      ...Module Manifest Verification Complete!'
}


# Synopsis: Load the module project
Add-BuildTask ImportModuleManifest {
    Write-Build White '      Attempting to load the project module.'
    try {
        Import-Module $script:ModuleManifestFile -Force -PassThru -ErrorAction Stop
    }
    catch {
        Write-Build Red "      ...$_`n"
        throw "Unable to load the project module. $_"
    }
    Write-Build Green "      ...$script:ModuleName imported successfully"
}


#Synopsis: Clean and reset Artifacts/Archive Directory
Add-BuildTask Clean {
    Write-Build White '      Clean up our Artifacts/Archive directory...'
    $null = Remove-Item $script:ArtifactsPath -Force -Recurse -ErrorAction SilentlyContinue
    $null = New-Item $script:ArtifactsPath -ItemType:Directory
    $null = Remove-Item $script:ArchivePath -Force -Recurse -ErrorAction SilentlyContinue
    $null = New-Item $script:ArchivePath -ItemType:Directory
    Write-Build Green '      ...Clean Complete!'
} #Clean


#Synopsis: Invoke PSScriptAnalyzer against the Module source path
Add-BuildTask Analyze {
    $ScriptAnalyzerParams = @{
        Path    = $script:ModuleSourcePath
        Setting = 'PSScriptAnalyzerSettings.psd1'
        Recurse = $true
        Verbose = $false
    }
    Write-Build White '      Performing Module ScriptAnalyzer checks...'
    $ScriptAnalyzerResults = Invoke-ScriptAnalyzer @ScriptAnalyzerParams
    if ($ScriptAnalyzerResults) {
        $ScriptAnalyzerResults | Format-Table
        throw '      One or more PSScriptAnalyzer errors/warnings where found.'
    }
    else {
        Write-Build Green '      ...Module Analyze Complete!'
    }
} #Analyze


#Synopsis: Invoke Script Analyzer against the Tests path if it exists
Add-BuildTask AnalyzeTests -After Analyze {
    if (Test-Path -Path $script:TestsPath) {
        $ScriptAnalyzerParams = @{
            Path        = $script:TestsPath
            Setting     = 'PSScriptAnalyzerSettings.psd1'
            ExcludeRule = 'PSUseDeclaredVarsMoreThanAssignments'
            Recurse     = $true
            Verbose     = $false
        }
        Write-Build White '      Performing Test ScriptAnalyzer checks...'
        $ScriptAnalyzerResults = Invoke-ScriptAnalyzer @ScriptAnalyzerParams
        if ($ScriptAnalyzerResults) {
            $ScriptAnalyzerResults | Format-Table
            throw '      One or more PSScriptAnalyzer errors/warnings where found.'
        }
        else {
            Write-Build Green '      ...Test Analyze Complete!'
        }
    }
} #AnalyzeTests


#Synopsis: Analyze scripts to verify if they adhere to desired coding format (Stroustrup / OTBS / Allman)
Add-BuildTask FormattingCheck {
    $ScriptAnalyzerParams = @{
        Setting     = 'CodeFormattingOTBS'
        ExcludeRule = 'PSUseConsistentWhitespace'
        Recurse     = $true
        Verbose     = $false
    }
    Write-Build White '      Performing script formatting checks...'
    $ScriptAnalyzerResults = Get-ChildItem -Path $script:ModuleSourcePath -Exclude "*.psd1" | Invoke-ScriptAnalyzer @ScriptAnalyzerParams
    if ($ScriptAnalyzerResults) {
        $ScriptAnalyzerResults | Format-Table
        throw '      PSScriptAnalyzer code formatting check did not adhere to {0} standards' -f $ScriptAnalyzerParams.Setting
    }
    else {
        Write-Build Green '      ...Formatting Analyze Complete!'
    }
} #FormattingCheck


#Synopsis: Invoke all Pester Unit Tests in the Tests\Unit folder (if it exists)
Add-BuildTask Test {

    Write-Build White "      Importing desired Pester version. Min: $script:MinPesterVersion Max: $script:MaxPesterVersion"
    Remove-Module -Name Pester -Force -ErrorAction 'SilentlyContinue' # there are instances where some containers have Pester already in the session
    Import-Module -Name Pester -MinimumVersion $script:MinPesterVersion -MaximumVersion $script:MaxPesterVersion -ErrorAction 'Stop'

    $CodeCovPath = "$script:ArtifactsPath\ccReport\"
    $TestOutputPath = "$script:ArtifactsPath\testOutput\"
    if (-not(Test-Path $CodeCovPath)) {
        New-Item -Path $CodeCovPath -ItemType Directory | Out-Null
    }
    if (-not(Test-Path $TestOutputPath)) {
        New-Item -Path $TestOutputPath -ItemType Directory | Out-Null
    }
    if (Test-Path -Path $script:UnitTestsPath) {
        $PesterConfiguration = New-PesterConfiguration
        $PesterConfiguration.run.Path = $script:UnitTestsPath
        $PesterConfiguration.Run.PassThru = $true
        $PesterConfiguration.Run.Exit = $false
        $PesterConfiguration.CodeCoverage.Enabled = $true
        $PesterConfiguration.CodeCoverage.Path = "$ProjectRoot\src\$ModuleName\*\*.ps1"
        $PesterConfiguration.CodeCoverage.CoveragePercentTarget = $script:CoverageThreshold
        $PesterConfiguration.CodeCoverage.OutputPath = "$CodeCovPath\CodeCoverage.xml"
        $PesterConfiguration.CodeCoverage.OutputFormat = 'JaCoCo'
        $PesterConfiguration.TestResult.Enabled = $true
        $PesterConfiguration.TestResult.OutputPath = "$TestOutputPath\PesterTests.xml"
        $PesterConfiguration.TestResult.OutputFormat = $script:TestOutputFormat
        $PesterConfiguration.Output.Verbosity = 'Detailed'

        Write-Build White '      Performing Pester Unit Tests...'
        # Publish Test Results
        $TestResults = Invoke-Pester -Configuration $PesterConfiguration

        # This will output a nice json for each failed test (if running in CodeBuild)
        if ($env:CODEBUILD_BUILD_ARN) {
            $TestResults.TestResult | ForEach-Object {
                if ($_.Result -ne 'Passed') {
                    ConvertTo-Json -InputObject $_ -Compress
                }
            }
        }

        $NumberFails = $TestResults.FailedCount
        Assert-Build($NumberFails -eq 0) ('Failed "{0}" unit tests.' -f $NumberFails)

        Write-Build Gray ('      ...CODE COVERAGE - CommandsExecutedCount: {0}' -f $TestResults.CodeCoverage.CommandsExecutedCount)
        Write-Build Gray ('      ...CODE COVERAGE - CommandsAnalyzedCount: {0}' -f $TestResults.CodeCoverage.CommandsAnalyzedCount)

        if ($TestResults.CodeCoverage.NumberOfCommandsExecuted -ne 0) {
            $CoveragePercent = '{0:N2}' -f ($TestResults.CodeCoverage.CommandsExecutedCount / $TestResults.CodeCoverage.CommandsAnalyzedCount * 100)

            if ($TestResults.CodeCoverage.NumberOfCommandsMissed -gt 0) {
                'Failed to analyze "{0}" commands' -f $TestResults.CodeCoverage.NumberOfCommandsMissed
            }
            Write-Host "PowerShell Commands not tested:`n$(ConvertTo-Json -InputObject $TestResults.CodeCoverage.MissedCommands)"

            if ([Int]$CoveragePercent -lt $CoverageThreshold) {
                throw ('Failed to meet code coverage threshold of {0}% with only {1}% coverage' -f $CoverageThreshold, $CoveragePercent)
            }
            else {
                Write-Build Cyan "      $('Covered {0}% of {1} analyzed commands in {2} files.' -f $CoveragePercent, $TestResults.CodeCoverage.CommandsAnalyzedCount, $TestResults.CodeCoverage.FilesAnalyzedCount)"
                Write-Build Green '      ...Pester Unit Tests Complete!'
            }
        }
        else {
            # account for new module build condition
            Write-Build Yellow '      Code coverage check skipped. No commands to execute...'
        }

    }
} #Test


#Synopsis: Used primarily during active development to generate XML file to graphically display code coverage in VSCode using Coverage Gutters
Add-BuildTask DevCC {
    Write-Build White '      Generating code coverage report at root...'
    Write-Build White "      Importing desired Pester version. Min: $script:MinPesterVersion Max: $script:MaxPesterVersion"
    Remove-Module -Name Pester -Force -ErrorAction SilentlyContinue # there are instances where some containers have Pester already in the session
    Import-Module -Name Pester -MinimumVersion $script:MinPesterVersion -MaximumVersion $script:MaxPesterVersion -ErrorAction 'Stop'
    $PesterConfiguration = New-PesterConfiguration
    $PesterConfiguration.run.Path = $script:UnitTestsPath
    $PesterConfiguration.CodeCoverage.Enabled = $true
    $PesterConfiguration.CodeCoverage.Path = "$PSScriptRoot\$ModuleName\*\*.ps1" # ############## VERIFY THIS PATH ###############
    $PesterConfiguration.CodeCoverage.CoveragePercentTarget = $script:CoverageThreshold
    $PesterConfiguration.CodeCoverage.OutputPath = '..\..\cov.xml'
    $PesterConfiguration.CodeCoverage.OutputFormat = 'CoverageGutters'

    Invoke-Pester -Configuration $PesterConfiguration
    Write-Build Green '      ...Code Coverage report generated!'
} #DevCC


# Synopsis: Build help for module
Add-BuildTask CreateHelpStart {
    Write-Build White '      Performing all help related actions.'

    Write-Build Gray '           Importing Microsoft.PowerShell.PlatyPS ...'
    Import-Module Microsoft.PowerShell.PlatyPS -ErrorAction Stop
    Write-Build Gray '           ...Microsoft.PowerShell.PlatyPS imported successfully.'
} #CreateHelpStart


# Synopsis: Build markdown help files for module and fail if help information is missing
Add-BuildTask CreateMarkdownHelp -After CreateHelpStart {
    $ModulePage = "$script:ProjectRoot\docs\$($ModuleName).md"

    $markdownParams = @{
        #Module         = $ModuleName
        OutputFolder   = "$script:ProjectRoot\docs\"
        Force          = $true
        WithModulePage = $true
        Locale         = 'en-US'
        #FwLink         = "NA"
        HelpVersion    = $script:ModuleVersion
    }

    Write-Build Gray '           Generating markdown files...'
    $null = New-MarkdownCommandHelp @markdownParams
    Write-Build Gray '           ...Markdown generation completed.'
    Write-Build Gray '           Replacing markdown elements...'
    Write-Build DarkGray '             Replace multi-line EXAMPLES'
    $OutputDir = "$script:ProjectRoot\docs\"

    $OutputDir | Get-ChildItem -File | ForEach-Object {
        # Fix formatting in multiline examples
        $Content = Get-Content $_.FullName -Raw
        $NewContent = $Content -replace '(## EXAMPLE [^`]+?```\r\n[^`\r\n]+?\r\n)(```\r\n\r\n)([^#]+?\r\n)(\r\n)([^#]+)(#)', '$1$3$2$4$5$6'
        if ($NewContent -ne $Content) {
            Set-Content -Path $_.FullName -Value $NewContent -Force
        }
    }

    Write-Build DarkGray '             Replace each missing element we need for a proper generic module page .md file'
    $ModulePageFileContent = Get-Content -Raw $ModulePage
    $ModulePageFileContent = $ModulePageFileContent -replace '{{Manually Enter Description Here}}', $script:ModuleDescription
    $script:FunctionsToExport | ForEach-Object {
        Write-Build DarkGray "             Updating definition for the following function: $($_)"
        $TextToReplace = "{{Manually Enter $($_) Description Here}}"
        $ReplacementText = (Get-Help -Detailed $_).Synopsis
        $ModulePageFileContent = $ModulePageFileContent -replace $TextToReplace, $ReplacementText
    }

    Write-Build DarkGray '             Evaluating if running 7.4.0 or higher...'
    # https://github.com/PowerShell/platyPS/issues/595
    if ($PSVersionTable.PSVersion -ge [version]'7.4.0') {
        Write-Build DarkGray '                Performing Markdown repair'
        # Dot-source markdown repair
        . $BuildRoot\MarkdownRepair.ps1
        $OutputDir | Get-ChildItem -File | ForEach-Object {
            Repair-PlatyPSMarkdown -Path $_.FullName
        }
    }

    Write-Build DarkGray '             Add blank line after headers.'
    # *NOTE: it is not possible to adjust fenced code block at this location because conversion to MAML does not support language tags.
    $OutputDir | Get-ChildItem -File | ForEach-Object {
        $Content = Get-Content $_.FullName -Raw
        $NewContent = $Content -replace '(?m)^(#{1,6}\s+.*)$\r?\n(?!\r?\n)', "`$1`r`n"
        # $newContent = $content -replace '(?m)^(#{1,6}\s+.+?)$\r?\n(?!\r?\n)', "`$1`n"
        # $newContent = $content -replace '(?m)^(#{1,6}\s+.*)$\r?\n(?!\r?\n)', "`$1`n"
        if ($NewContent -ne $Content) {
            Set-Content -Path $_.FullName -Value $NewContent -Force
        }
    }
    $ModulePageFileContent | Out-File $ModulePage -Force -Encoding:utf8
    Write-Build Gray '           ...Markdown replacements complete.'


    Write-Build Gray '           Verifying GUID...'
    $MissingGUID = Select-String -Path "$script:ProjectRoot\docs\*.md" -Pattern "(00000000-0000-0000-0000-000000000000)"
    if ($MissingGUID.Count -gt 0) {
        Write-Build Yellow '             The documentation that got generated resulted in a generic GUID. Check the GUID entry of your module manifest.'
        throw 'Missing GUID in manifest. Please review and rebuild.'
    }


    Write-Build Gray '           Checking for missing documentation in md files...'
    $MissingDocumentation = Select-String -Path "$script:ProjectRoot\docs\*.md" -Pattern "({{.*}})"
    if ($MissingDocumentation.Count -gt 0) {
        Write-Build Yellow '             The documentation that got generated resulted in missing sections which should be filled out.'
        Write-Build Yellow '             Please review the following sections in your comment based help, fill out missing information and rerun this build:'
        Write-Build Yellow '             (Note: This can happen if the .EXTERNALHELP CBH is defined for a function before running this build.)'
        Write-Build Yellow "             Path of files with issues: $script:ProjectRoot\docs\"
        $MissingDocumentation | Select-Object FileName, LineNumber, Line | Format-Table -AutoSize
        throw 'Missing documentation. Please review and rebuild.'
    }


    Write-Build Gray '           Checking for missing SYNOPSIS in md files...'
    $fSynopsisOutput = @()
    # $SynopsisEval = Select-String -Path "$script:ProjectRoot\docs\*.md" -Pattern "^## SYNOPSIS$" -Context 0, 1
    $SynopsisEval = Select-String -Path "$script:ProjectRoot\docs\*.md" -Pattern "^## SYNOPSIS$\r?\n$" -Context 0, 2
    $SynopsisEval | ForEach-Object {
        $chAC = $_.Context.DisplayPostContext.ToCharArray()
        if ($null -eq $chAC) {
            $fSynopsisOutput += $_.FileName
        }
    }
    if ($fSynopsisOutput) {
        Write-Build Yellow "             The following files are missing SYNOPSIS:"
        $fSynopsisOutput
        throw 'SYNOPSIS information missing. Please review.'
    }

    Write-Build Gray '           ...Markdown generation complete.'
} #CreateMarkdownHelp


# Synopsis: Build the external XML help file from markdown help files with PlatyPS
Add-BuildTask CreateExternalHelp -After CreateMarkdownHelp {
    Write-Build Gray '           Creating external XML help file...'
    #$null = New-ExternalHelp "$script:ProjectRoot\docs" -OutputPath "$script:ProjectRoot\en-US\" -Force
    Write-Verbose "Need to update for the new PlatyPS module."
    Write-Build Gray '           ...External XML help file created!'
} #CreateExternalHelp

Add-BuildTask CreateHelpComplete -After CreateExternalHelp {
    Write-Build Gray '           Finalizing markdown documentation now that external help has been created...'
    Write-Build DarkGray '             Add powershell language to unspecified fenced code blocks.'

    $OutputDir = "$script:ProjectRoot\docs\"

    Get-ChildItem -Path $OutputDir -File | ForEach-Object {
        $lines = Get-Content -Path $_.FullName
        $insideCodeBlock = $false

        for ($i = 0; $i -lt $lines.Count; $i++) {
            # Regex captures everything after triple backticks (if present).
            # e.g. ```yaml => captured group = "yaml"
            #      ```    => captured group = ""
            if ($lines[$i] -match '^\s*```(\S*)\s*$') {
                $lang = $Matches[1]

                if (-not $insideCodeBlock) {
                    # We found an opening fence
                    if ([string]::IsNullOrWhiteSpace($lang)) {
                        # Bare triple backticks => add powershell
                        $lines[$i] = '```powershell'
                    }
                    # Toggle "inside code block" on
                    $insideCodeBlock = $true
                }
                else {
                    # We found the closing fence -> set $insideCodeBlock off
                    $insideCodeBlock = $false
                    # Do *not* modify closing fence, leave it exactly as it is
                }
            }
        }

        Set-Content -Path $_.FullName -Value $lines
    }
    Write-Build DarkGray '             Ensuring exactly one trailing newline in final markdown file.'
    Get-ChildItem -Path $OutputDir -File -Filter *.md | ForEach-Object {
        # Read the file as an array of lines
        $lines = Get-Content -Path $_.FullName

        # Remove all blank lines at the end, but do not remove actual content
        while ($lines.Count -gt 0 -and $lines[-1] -match '^\s*$') {
            $lines = $lines[0..($lines.Count - 2)]
        }

        # Re-join with Windows line endings and add exactly one trailing newline
        $content = ($lines -join "`r`n")
        Set-Content -Path $_.FullName -Value $content -Force
    }
    Write-Build Gray '           ...Markdown documentation finalized.'
    Write-Build Green '      ...CreateHelp Complete!'
} #CreateHelpStart


# Synopsis: Replace comment based help (CBH) with external help in all public functions for this project
Add-BuildTask UpdateCBH -After AssetCopy {
    $ExternalHelp = @"
<#
.EXTERNALHELP $($ModuleName)-help.xml
#>
"@
    Write-Output "$ExternalHelp"
    # $CBHPattern = "(?ms)(\<#.*\.SYNOPSIS.*?#>)"
    <#
    Get-ChildItem -Path "$script:ProjectRoot\src\$ModuleName\Public\*.ps1" -File | ForEach-Object {
        $FormattedOutFile = $_.FullName
        Write-Output "      Replacing CBH in file: $($FormattedOutFile)"
        $UpdatedFile = (Get-Content  $FormattedOutFile -raw) -replace $CBHPattern, $ExternalHelp
        $UpdatedFile | Out-File -FilePath $FormattedOutFile -Force -Encoding:utf8
    }
    #>
} #UpdateCBH


# Synopsis: Copies module assets to Artifacts folder
Add-BuildTask AssetCopy -Before Build {
    Write-Build Gray '        Copying assets to Artifacts...'
    #Copy-Item -Path "$script:ModuleSourcePath\*" -Destination $script:ArtifactsPath -Exclude *.psd1, *.psm1 -Recurse -ErrorAction Stop
    Write-Build Gray '        ...Assets copy complete.'
} #AssetCopy


# Synopsis: Builds the Module to the Artifacts folder
Add-BuildTask Build {
    Write-Build White '      Performing Module Build'

    Write-Build Gray '        Copying manifest file to Artifacts...'
    #Copy-Item -Path $script:ModuleManifestFile -Destination $script:ArtifactsPath -Recurse -ErrorAction Stop
    #Copy-Item -Path $script:ModuleSourcePath\bin -Destination $script:ArtifactsPath -Recurse -ErrorAction Stop
    Write-Build Gray '        ...manifest copy complete.'

    Write-Build Gray '        Merging Public and Private functions to one module file...'
    #$Private = "$script:ModuleSourcePath\Private"
    $ScriptContent = [System.Text.StringBuilder]::new()
    $PowerShellScripts = Get-ChildItem -Path $script:ModuleSourcePath -Filter '*.ps1' -Recurse
    foreach ($script in $PowerShellScripts) {
        $null = $ScriptContent.Append((Get-Content -Path $script.FullName -Raw))
        $null = $ScriptContent.AppendLine('')
        $null = $ScriptContent.AppendLine('')
    }
    $ScriptContent.ToString() | Out-File -FilePath $script:BuildModuleRootFile -Encoding utf8 -Force
    # Cleanup the combined root module and remove extra trailing lines at the end of the file.
    Invoke-Formatter $script:BuildModuleRootFile -ErrorAction SilentlyContinue
    Write-Build Gray '        ...Module creation complete.'

    <#
    Write-Build Gray '        Cleaning up leftover artifacts...'
    # Cleanup artifacts that are no longer required
    if (Test-Path "$script:ArtifactsPath\Public") {
        Remove-Item "$script:ArtifactsPath\Public" -Recurse -Force -ErrorAction Stop
    }
    if (Test-Path "$script:ArtifactsPath\Private") {
        Remove-Item "$script:ArtifactsPath\Private" -Recurse -Force -ErrorAction Stop
    }
    if (Test-Path "$script:ArtifactsPath\Imports.ps1") {
        Remove-Item "$script:ArtifactsPath\Imports.ps1" -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path "$script:ArtifactsPath\docs") {
        # Here we update the parent level docs. If you would prefer not to update them, comment out this section.
        Write-Build Gray '        Overwriting docs output...'
        if (-not (Test-Path '..\docs\')) {
            New-Item -Path '..\docs\' -ItemType Directory -Force | Out-Null
        }
        Move-Item "$script:ArtifactsPath\docs\*.md" -Destination '..\docs\' -Force
        Remove-Item "$script:ArtifactsPath\docs" -Recurse -Force -ErrorAction Stop
        Write-Build Gray '        ...Docs output completed.'
    }
    #>

    Write-Build Green '      ...Build Complete!'
} #Build


#Synopsis: Invokes all Pester Integration Tests in the Tests\Integration folder (if it exists)
Add-BuildTask IntegrationTest {
    if (Test-Path -Path $script:IntegrationTestsPath) {
        Write-Build White "      Importing desired Pester version. Min: $script:MinPesterVersion Max: $script:MaxPesterVersion"
        Remove-Module -Name Pester -Force -ErrorAction SilentlyContinue # There are instances where some containers have Pester already in the session
        Import-Module -Name Pester -MinimumVersion $script:MinPesterVersion -MaximumVersion $script:MaxPesterVersion -ErrorAction 'Stop'

        Write-Build White "      Performing Pester Integration Tests in $($invokePesterParams.path)"

        $PesterConfiguration = New-PesterConfiguration
        $PesterConfiguration.run.Path = $script:IntegrationTestsPath
        $PesterConfiguration.Run.PassThru = $true
        $PesterConfiguration.Run.Exit = $false
        $PesterConfiguration.CodeCoverage.Enabled = $false
        $PesterConfiguration.TestResult.Enabled = $false
        $PesterConfiguration.Output.Verbosity = 'Detailed'

        $TestResults = Invoke-Pester -Configuration $PesterConfiguration
        # This will output a nice json for each failed test (if running in CodeBuild)
        if ($env:CODEBUILD_BUILD_ARN) {
            $TestResults.TestResult | ForEach-Object {
                if ($_.Result -ne 'Passed') {
                    ConvertTo-Json -InputObject $_ -Compress
                }
            }
        }

        $NumberFails = $TestResults.FailedCount
        Assert-Build($NumberFails -eq 0) ('Failed "{0}" unit tests.' -f $NumberFails)
        Write-Build Green '      ...Pester Integration Tests Complete!'
    }
} #IntegrationTest


#Synopsis: Creates an archive of the built Module
Add-BuildTask Archive {
    Write-Build White '        Performing Archive...'

    $ArchivePath = Join-Path -Path $ProjectRoot -ChildPath 'archive'
    if (Test-Path -Path $ArchivePath) {
        # $null = Remove-Item -Path $ArchivePath -Recurse -Force
    }

    # $null = New-Item -Path $ArchivePath -ItemType Directory -Force

    #$ZipFileName = '{0}_{1}_{2}.{3}.zip' -f $script:ModuleName, $script:ModuleVersion, ([DateTime]::UtcNow.ToString("yyyyMMdd")), ([DateTime]::UtcNow.ToString("HHmmss"))
    #$ZipFile = Join-Path -Path $ArchivePath -ChildPath $ZipFileName

    if ($PSEdition -eq 'Desktop') {
        Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
    }
    #[System.IO.Compression.ZipFile]::CreateFromDirectory($script:ArtifactsPath, $ZipFile)

    Write-Build Green '        ...Archive Complete!'
} #Archive
