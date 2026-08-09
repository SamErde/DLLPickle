BeforeAll {
    Set-Location -Path $PSScriptRoot
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:GeneratorPath = Join-Path $ProjectRoot 'tools\New-DLLPickleSupportDocumentation.ps1'
    $script:ReadmePath = Join-Path $ProjectRoot 'README.md'
    $script:ArchitecturePath = Join-Path $ProjectRoot 'docs\Architecture.md'
    $script:DependencyDocPath = Join-Path $ProjectRoot 'docs\DEPENDENCIES.md'
}

Describe 'Generated support documentation' -Tag 'Unit' {
    It 'matches the canonical support and dependency policies' {
        { & $script:GeneratorPath -Check } | Should -Not -Throw
    }

    It 'renders repository-canonical CRLF endings on every host' {
        $OutputDirectory = Join-Path $TestDrive 'generated'

        $null = & $script:GeneratorPath -OutputDirectory $OutputDirectory

        foreach ($DocumentName in @('Support-Matrix.md', 'Compatibility-Evidence.md')) {
            $Document = [System.IO.File]::ReadAllText((Join-Path $OutputDirectory $DocumentName))
            $Document | Should -Match "`r`n"
            ($Document -replace "`r`n", '') | Should -Not -Match "`n"
        }
    }

    It 'keeps the primary documentation linked to the generated support contract' {
        Get-Content -LiteralPath $script:ReadmePath -Raw | Should -Match 'generated/Support-Matrix\.md'
        Get-Content -LiteralPath $script:ArchitecturePath -Raw | Should -Match 'generated/Support-Matrix\.md'
        Get-Content -LiteralPath $script:DependencyDocPath -Raw | Should -Match 'generated/Compatibility-Evidence\.md'
    }

    It 'separates Microsoft support, upstream evidence, and optional CI tooling claims' {
        $SupportMatrix = Get-Content -LiteralPath (Join-Path $ProjectRoot 'docs\generated\Support-Matrix.md') -Raw
        $Compatibility = Get-Content -LiteralPath (Join-Path $ProjectRoot 'docs\generated\Compatibility-Evidence.md') -Raw
        $SupportMatrix | Should -Match 'Microsoft-supported runtime contract'
        $SupportMatrix | Should -Match 'multi-pwsh.*optional'
        $Compatibility | Should -Match 'release-gating gaps'
        $Compatibility | Should -Match 'process-isolation requirement'
        $Compatibility | Should -Match 'Issue #34'
        $Compatibility | Should -Match 'PR #215'
        $Compatibility | Should -Match 'Issue #242'
        $Compatibility | Should -Match 'not executed without approved credentials'
    }
}
