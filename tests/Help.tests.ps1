# Taken with love from @juneb_get_help (https://raw.githubusercontent.com/juneb/PesterTDD/master/Module.Help.Tests.ps1)

BeforeDiscovery {

    function global:FilterOutCommonParams {
        param ($Params)
        $CommonParams = @(
            'Debug', 'ErrorAction', 'ErrorVariable', 'InformationAction', 'InformationVariable',
            'OutBuffer', 'OutVariable', 'PipelineVariable', 'Verbose', 'WarningAction',
            'WarningVariable', 'Confirm', 'WhatIf'
        )
        $Params | Where-Object { $_.Name -notin $CommonParams } | Sort-Object -Property Name -Unique
    }

    $Manifest = Import-PowerShellDataFile -Path $env:BHPSModuleManifest
    $OutputDir = Join-Path -Path $env:BHProjectPath -ChildPath 'Output'
    $OutputModDir = Join-Path -Path $OutputDir -ChildPath $env:BHProjectName
    $OutputModVerDir = Join-Path -Path $OutputModDir -ChildPath $Manifest.ModuleVersion
    $OutputModVerManifest = Join-Path -Path $OutputModVerDir -ChildPath "$( $env:BHProjectName ).psd1"

    # Get module commands
    # Remove all versions of the module from the session. Pester can't handle multiple versions.
    Get-Module $env:BHProjectName | Remove-Module -Force -ErrorAction Ignore
    Import-Module -Name $OutputModVerManifest -Verbose:$false -ErrorAction Stop
    $CommandQueryParams = @{
        Module      = (Get-Module $env:BHProjectName)
        CommandType = [System.Management.Automation.CommandTypes[]]'Cmdlet, Function' # Not alias
    }
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        $CommandQueryParams.CommandType[0] += 'Workflow'
    }
    $Commands = Get-Command @CommandQueryParams

    ## When testing help, remember that help is cached at the beginning of each session.
    ## To test, restart session.
}

Describe 'Test help for <_.Name>' -ForEach $Commands {

    BeforeDiscovery {
        # Get command help, parameters, and links
        $Command = $_
        $CommandHelp = Get-Help $Command.Name -ErrorAction SilentlyContinue
        $CommandParameters = global:FilterOutCommonParams -Params $Command.ParameterSets.Parameters
        $CommandParameterNames = $CommandParameters.Name
        $HelpLinks = $CommandHelp.relatedLinks.navigationLink.uri
    }

    BeforeAll {
        # These vars are needed in both discovery and test phases so we need to duplicate them here
        $Command = $_
        $CommandName = $_.Name
        $CommandHelp = Get-Help $Command.Name -ErrorAction SilentlyContinue
        $CommandParameters = global:FilterOutCommonParams -Params $Command.ParameterSets.Parameters
        $CommandParameterNames = $CommandParameters.Name
        $HelpParameters = global:FilterOutCommonParams -Params $CommandHelp.Parameters.Parameter
        $HelpParameterNames = $HelpParameters.Name
    }

    # If help is not found, synopsis in auto-generated help is the syntax diagram
    It 'Help is not auto-generated' {
        $CommandHelp.Synopsis | Should -Not -BeLike '*`[`<CommonParameters`>`]*'
    }

    # Should be a description for every function
    It 'Has description' {
        $CommandHelp.Description | Should -Not -BeNullOrEmpty
    }

    # Should be at least one example
    It 'Has example code' {
        ($CommandHelp.Examples.Example | Select-Object -First 1).Code | Should -Not -BeNullOrEmpty
    }

    # Should be at least one example description
    It 'Has example help' {
        ($CommandHelp.Examples.Example.Remarks | Select-Object -First 1).Text | Should -Not -BeNullOrEmpty
    }

    It 'Help link <_> is valid' -ForEach $HelpLinks {
        (Invoke-WebRequest -Uri $_ -UseBasicParsing).StatusCode | Should -Be '200'
    }

    Context 'Parameter <_.Name>' -ForEach $CommandParameters {

        BeforeAll {
            $Parameter = $_
            $ParameterName = $Parameter.Name
            $ParameterHelp = $CommandHelp.parameters.parameter | Where-Object Name -EQ $ParameterName
            $ParameterHelpType = if ($ParameterHelp.ParameterValue) { $ParameterHelp.ParameterValue.Trim() }
        }

        # Should be a description for every parameter
        It 'Has description' {
            $ParameterHelp.Description.Text | Should -Not -BeNullOrEmpty
        }

        # Required value in Help should match IsMandatory property of parameter
        It 'Has correct [mandatory] value' {
            $CodeMandatory = $_.IsMandatory.ToString()
            $ParameterHelp.Required | Should -Be $CodeMandatory
        }

        # Parameter type in help should match code
        It 'Has correct parameter type' {
            $ParameterHelpType | Should -Be $Parameter.ParameterType.Name
        }
    }

    Context 'Test <_> help parameter help for <commandName>' -ForEach $HelpParameterNames {

        # Shouldn't find extra parameters in help.
        It 'finds help parameter in code: <_>' {
            $_ -in $CommandParameterNames | Should -Be $true
        }
    }
}
