BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ScenarioHarness = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'tools\Invoke-DLLPickleManualAuthenticatedScenario.ps1') -Raw
    $script:Orchestrator = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'tools\Invoke-DLLPickleManualAuthenticatedCompatibility.ps1') -Raw
    $script:Initializer = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'tools\Initialize-DLLPickleManualAuthenticatedCompatibility.ps1') -Raw
    $script:SharedHelpers = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'tools\DLLPickle.ManualAuthenticatedEvidence.ps1') -Raw
    $script:SchemaPath = Join-Path $script:RepositoryRoot 'build\authenticated-evidence\manual-transition.schema.json'
}

Describe 'Manual authenticated compatibility harness guardrails' -Tag 'Unit' {
    It 'hard-codes interactive connections and real read probes without accepting command text' {
        $script:ScenarioHarness | Should -Match ([regex]::Escape("-Name 'Connect-MgGraph' -Module 'Microsoft.Graph.Authentication'"))
        $script:ScenarioHarness | Should -Match ([regex]::Escape("& `$Command -Scopes 'User.Read' -ContextScope Process"))
        $script:SharedHelpers | Should -Match ([regex]::Escape("-Name 'Invoke-MgGraphRequest' -Module 'Microsoft.Graph.Authentication'"))
        $script:SharedHelpers | Should -Match ([regex]::Escape("& `$Command -Method GET -Uri '/v1.0/me?`$select=id'"))
        $script:SharedHelpers | Should -Match ([regex]::Escape("-Name 'Get-EXOMailbox' -Module 'ExchangeOnlineManagement'"))
        $script:SharedHelpers | Should -Match ([regex]::Escape("-Name 'Get-AzResource' -Module 'Az.Resources'"))
        $script:SharedHelpers | Should -Match ([regex]::Escape("-Name 'Get-AzStorageAccount' -Module 'Az.Storage'"))
        $script:SharedHelpers | Should -Match ([regex]::Escape("-Name 'Get-CsTenant' -Module 'MicrosoftTeams'"))
        $script:ScenarioHarness | Should -Match ([regex]::Escape('& $Command -Scope Process -UseDeviceAuthentication -ErrorAction Stop'))
        $script:ScenarioHarness | Should -Not -Match 'Update-AzConfig'
        ($script:ScenarioHarness + $script:SharedHelpers) | Should -Not -Match 'Invoke-Expression|ScriptBlock|AccessToken|ClientSecret|Certificate'
    }

    It 'captures only sanitized error types and zero-write results' {
        $script:SharedHelpers | Should -Match ([regex]::Escape('errorType = $_.Exception.GetType().FullName'))
        ($script:ScenarioHarness + $script:SharedHelpers) | Should -Not -Match 'Exception\.Message|ErrorDetails|ScriptStackTrace'
        $script:ScenarioHarness | Should -Match ([regex]::Escape('writesPerformed = $false'))
        $script:ScenarioHarness | Should -Match 'before-authentication'
        $script:ScenarioHarness | Should -Match 'after-connection'
        $script:ScenarioHarness | Should -Match 'after-read-probe'
    }

    It 'runs every scenario in a fresh exact interactive process and supports safe resume' {
        $script:Orchestrator | Should -Match ([regex]::Escape("'-NoLogo', '-NoProfile', '-File', `$ChildHarnessPath"))
        $script:Orchestrator | Should -Not -Match ([regex]::Escape("'-NonInteractive'"))
        ([regex]::Matches($script:Orchestrator, "'[a-z]+-(?:module-only|dllpickle-first|module-first)'" )).Count | Should -Be 12
        $script:Orchestrator | Should -Match 'cross-import-order-1'
        $script:Orchestrator | Should -Match 'cross-import-order-2'
        $script:Orchestrator | Should -Match 'Reusing passing checkpoint'
        $script:Orchestrator | Should -Match ([regex]::Escape("'-ExpectedProfileKey', `$CurrentProfileKey"))
        $script:Orchestrator | Should -Match ([regex]::Escape("'-ExpectedInventoryFingerprint', [string]`$PreparedProfile.InventoryFingerprint"))
        $script:ScenarioHarness | Should -Match ([regex]::Escape('profileKey = $ActualProfileKey'))
        $script:ScenarioHarness | Should -Match ([regex]::Escape('inventoryFingerprint = $InventoryFingerprint'))
        $script:Orchestrator | Should -Match "status = 'pending'"
    }

    It 'imports DLLPickle in module-first scenarios before authentication begins' {
        $ModuleFirstImport = $script:ScenarioHarness.IndexOf("if (`$Definition.timing -eq 'module-first') { Import-DLLPickleBundle }", [System.StringComparison]::Ordinal)
        $BeforeAuthentication = $script:ScenarioHarness.IndexOf("stage = 'before-authentication'", [System.StringComparison]::Ordinal)
        $ConnectLoop = $script:ScenarioHarness.IndexOf('Connect-Provider -Provider', [System.StringComparison]::Ordinal)

        $ModuleFirstImport | Should -BeGreaterThan -1
        $ModuleFirstImport | Should -BeLessThan $BeforeAuthentication
        $ModuleFirstImport | Should -BeLessThan $ConnectLoop
    }

    It 'fails authenticated scenarios when DLLPickle reports a failed preload row' {
        $script:ScenarioHarness | Should -Match ([regex]::Escape('$ImportResults = @(Import-DPLibrary -SuppressLogo -ErrorAction Stop)'))
        $script:ScenarioHarness | Should -Match ([regex]::Escape("Where-Object { [string]`$_.Status -eq 'Failed' }"))
        $script:ScenarioHarness | Should -Match ([regex]::Escape('DLLPickle preload reported'))
        $script:ScenarioHarness | Should -Not -Match ([regex]::Escape('Import-DPLibrary -SuppressLogo -ErrorAction Stop | Out-Null'))
    }

    It 'prepares exact pinned runtimes and refreshes latest compatible modules without authenticating' {
        $script:Initializer | Should -Match ([regex]::Escape("Provider = 'DirectArchive'"))
        $script:Initializer | Should -Match ([regex]::Escape("Platform = 'windows'"))
        $script:Initializer | Should -Match ([regex]::Escape('Force = $true'))
        $script:Initializer | Should -Match ([regex]::Escape('Where-Object {'))
        $script:Initializer | Should -Match ([regex]::Escape('[string]$_.Version -ne [string]$_.LatestCompatibleVersion'))
        $script:Initializer | Should -Match ([regex]::Escape('Get-DLLPicklePreparedInventoryFingerprint'))
        $script:Initializer | Should -Match 'AuthenticationPerformed = \$false'
        $script:Initializer | Should -Not -Match 'Connect-MgGraph|Connect-ExchangeOnline|Connect-AzAccount|Connect-MicrosoftTeams'
    }

    It 'ships a parseable schema fixed to one release and no credential-bearing content' {
        $Schema = Get-Content -LiteralPath $script:SchemaPath -Raw | ConvertFrom-Json -ErrorAction Stop
        $Schema.properties.content.properties.bridge.properties.allowedReleaseVersion.const | Should -Be '3.0.0'
        $Schema.properties.content.properties.credentialMaterialCaptured.const | Should -BeFalse
        $Schema.properties.content.properties.writesPerformed.const | Should -BeFalse
        $Schema.properties.content.properties.platformScope.const | Should -Be 'windows-x64-only'
        $Schema.'$defs'.scenario.additionalProperties | Should -BeFalse
        $Schema.'$defs'.scenario.required | Should -Contain 'profileKey'
        $Schema.'$defs'.scenario.required | Should -Contain 'inventoryFingerprint'
        $Schema.'$defs'.profile.required | Should -Contain 'inventoryFingerprint'
        $Schema.'$defs'.profile.properties.scenarios.minItems | Should -Be 14
        $AcceptedRule = @($Schema.properties.acceptance.allOf)[0].then.properties
        $AcceptedRule.acceptedAtUtc.type | Should -Be 'string'
        $AcceptedRule.acceptedBy.minLength | Should -Be 1
        @($AcceptedRule.confidence.enum) | Should -Be @('low', 'medium', 'high')
    }
}
