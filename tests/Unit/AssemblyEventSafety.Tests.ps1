BeforeAll {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

Describe 'Assembly event safety' -Tag 'Unit' {
    It 'does not register PowerShell script blocks as CLR assembly event delegates' {
        $UnsafeSourceFiles = @(
            Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'src\DLLPickle') -Filter '*.ps1' -File -Recurse |
                Where-Object {
                    (Get-Content -LiteralPath $_.FullName -Raw) -match
                        '\[System\.(AssemblyLoadEventHandler|ResolveEventHandler)\]\s*\{'
                } |
                Select-Object -ExpandProperty FullName
        )

        $UnsafeSourceFiles | Should -BeNullOrEmpty
    }
}
