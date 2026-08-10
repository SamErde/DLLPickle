BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ScenarioHarness = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'tools\Invoke-DLLPickleManualAuthenticatedScenario.ps1') -Raw
    $script:Orchestrator = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'tools\Invoke-DLLPickleManualAuthenticatedCompatibility.ps1') -Raw
    $script:Initializer = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'tools\Initialize-DLLPickleManualAuthenticatedCompatibility.ps1') -Raw
    $script:SchemaPath = Join-Path $script:RepositoryRoot 'build\authenticated-evidence\manual-transition.schema.json'
}

Describe 'Manual authenticated compatibility harness guardrails' -Tag 'Unit' {
    It 'hard-codes interactive connections and real read probes without accepting command text' {
        $script:ScenarioHarness | Should -Match ([regex]::Escape("Connect-MgGraph -Scopes 'User.Read' -ContextScope Process"))
        $script:ScenarioHarness | Should -Match ([regex]::Escape("Invoke-MgGraphRequest -Method GET -Uri '/v1.0/me?`$select=id'"))
        $script:ScenarioHarness | Should -Match ([regex]::Escape('Get-EXOMailbox -ResultSize 1'))
        $script:ScenarioHarness | Should -Match ([regex]::Escape('Get-AzResource -ErrorAction Stop'))
        $script:ScenarioHarness | Should -Match ([regex]::Escape('Get-AzStorageAccount -ErrorAction Stop'))
        $script:ScenarioHarness | Should -Match ([regex]::Escape('Get-CsTenant -ErrorAction Stop'))
        $script:ScenarioHarness | Should -Not -Match 'Invoke-Expression|ScriptBlock|AccessToken|ClientSecret|Certificate'
    }

    It 'captures only sanitized error types and zero-write results' {
        $script:ScenarioHarness | Should -Match ([regex]::Escape('errorType = $_.Exception.GetType().FullName'))
        $script:ScenarioHarness | Should -Not -Match 'Exception\.Message|ErrorDetails|ScriptStackTrace'
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
        $script:ScenarioHarness | Should -Match ([regex]::Escape('profileKey = $ActualProfileKey'))
        $script:Orchestrator | Should -Match "status = 'pending'"
    }

    It 'prepares exact pinned runtimes and refreshes latest compatible modules without authenticating' {
        $script:Initializer | Should -Match ([regex]::Escape("Provider = 'DirectArchive'"))
        $script:Initializer | Should -Match ([regex]::Escape("Platform = 'windows'"))
        $script:Initializer | Should -Match ([regex]::Escape('Force = $true'))
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
        $Schema.'$defs'.profile.properties.scenarios.minItems | Should -Be 14
    }
}
