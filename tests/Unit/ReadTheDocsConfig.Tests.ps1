BeforeAll {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $ReadTheDocsConfig = Get-Content -LiteralPath (Join-Path $ProjectRoot '.readthedocs.yaml') -Raw
}

Describe 'Read the Docs MkDocs configuration' -Tag 'Unit' {
    It 'uses a repository-relative MkDocs config path' {
        $ReadTheDocsConfig | Should -Match ([regex]::Escape('configuration: mkdocs.yml'))
        $ReadTheDocsConfig | Should -Not -Match ([regex]::Escape('configuration: /mkdocs.yml'))
    }

    It 'does not request unsupported extra formats for MkDocs builds' {
        $ReadTheDocsConfig | Should -Not -Match '(?m)^formats:\s+'
    }
}
