@{
    #________________________________________
    #IncludeDefaultRules
    IncludeDefaultRules = $true
    #________________________________________
    #Severity
    #Specify Severity when you want to limit generated diagnostic records to a specific subset: [ Error | Warning | Information ]
    Severity            = @('Error', 'Warning')
    #________________________________________
    #CustomRulePath
    #Specify CustomRulePath when you have a large set of custom rules you'd like to reference
    #CustomRulePath = "Module\InjectionHunter\1.0.0\InjectionHunter.psd1"
    #________________________________________
    #IncludeRules
    #Specify IncludeRules when you only want to run specific subset of rules instead of the default rule set.
    #IncludeRules = @('PSShouldProcess',
    #                 'PSUseApprovedVerbs')
    #________________________________________
    #ExcludeRules
    #Specify ExcludeRules when you want to exclude a certain rule from the the default set of rules.
    #ExcludeRules = @(
    #    'PSUseDeclaredVarsMoreThanAssignments'
    #)
    #________________________________________
    #Rules
    #Here you can specify customizations for particular rules. Several examples are included below:
    Rules = @{
        # Verify syntax is compatible with the minimum supported PowerShell versions (5.1 and 7.4).
        # Uses plain version strings — no profile path lookup required.
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.4')
        }
        # PSUseCompatibleCmdlets and PSUseCompatibleCommands require profile path strings that
        # are specific to the installed version of PSScriptAnalyzer. Uncomment and populate
        # after running: Get-ScriptAnalyzerRule -RuleName PSUseCompatibleCmdlets
        #PSUseCompatibleCmdlets = @{
        #    compatibility = @('desktop-5.1.14393.206-windows', 'core-7.4.0-windows')
        #}
        #PSUseCompatibleCommands = @{
        #    Enable         = $true
        #    TargetProfiles = @(
        #        'win-8_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework', # PS 5.1 on WinServer-2019
        #        'win-8_x64_10.0.17763.0_7.4.0_x64_4.0.30319.42000_core'               # PS 7.4 on WinServer-2019
        #    )
        #}
        #PSUseCompatibleTypes = @{
        #    Enable         = $true
        #    TargetProfiles = @(
        #        'win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework'
        #    )
        #}
    }
    #________________________________________
}
