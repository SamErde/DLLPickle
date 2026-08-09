BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:GeneratorPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'tools/New-DLLPicklePowerShellTestMatrix.ps1'
}

Describe 'Generated exact PowerShell test matrix' -Tag 'Unit' {
    It 'generates exactly three supported patches across three operating systems' {
        $matrix = & $script:GeneratorPath -Compress | ConvertFrom-Json

        @($matrix.include) | Should -HaveCount 9
        @($matrix.include.powerShellVersion | Sort-Object -Unique) | Should -Be @('7.4.18', '7.5.9', '7.6.4')
        @($matrix.include.platform | Sort-Object -Unique) | Should -Be @('linux', 'macos', 'windows')
        @($matrix.include.targetFramework | Sort-Object -Unique) | Should -Be @('net10.0', 'net8.0', 'net9.0')
    }

    It 'uses only exact versions and the default official archive provider' {
        $matrix = & $script:GeneratorPath -Compress | ConvertFrom-Json

        @($matrix.include | Where-Object powerShellVersion -notmatch '^\d+\.\d+\.\d+$') | Should -BeNullOrEmpty
        @($matrix.include.provider | Sort-Object -Unique) | Should -Be @('DirectArchive')
    }

    It 'assigns one unique cell per version, platform, and architecture' {
        $matrix = & $script:GeneratorPath -Compress | ConvertFrom-Json
        $keys = @($matrix.include | ForEach-Object { '{0}|{1}|{2}' -f $_.powerShellVersion, $_.platform, $_.architecture })

        @($keys | Sort-Object -Unique) | Should -HaveCount 9
    }

    It 'uses an Intel runner for the macOS x64 archive lane' {
        $matrix = & $script:GeneratorPath -Compress | ConvertFrom-Json
        $macosCells = @($matrix.include | Where-Object platform -eq 'macos')

        $macosCells | Should -HaveCount 3
        @($macosCells.architecture | Sort-Object -Unique) | Should -Be @('x64')
        @($macosCells.runner | Sort-Object -Unique) | Should -Be @('macos-15-intel')
    }
}
