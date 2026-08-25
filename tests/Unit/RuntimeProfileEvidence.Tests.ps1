BeforeAll {
    $script:ToolPath = Join-Path $PSScriptRoot '..\..\tools\New-DLLPickleRuntimeProfileEvidence.ps1'
}

Describe 'Runtime profile evidence compatibility' -Tag 'Unit' {
    It 'imports an absolute manifest path with the cross-version Name parameter' {
        $Source = Get-Content -LiteralPath $script:ToolPath -Raw

        $Source | Should -Match ([regex]::Escape('Import-Module -Name $Payload.manifestPath -Force'))
        $Source | Should -Not -Match ([regex]::Escape('Import-Module -LiteralPath $Payload.manifestPath'))
    }
}
