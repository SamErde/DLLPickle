BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ProvisionerPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'tools/Install-DLLPickleTestPowerShell.ps1'
    $script:MatrixPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'build/powershell-test-matrix.json'
}

Describe 'Exact PowerShell runtime provisioning' -Tag 'Unit' {
    It 'validates an explicit stock executable without multi-pwsh' {
        $currentExecutable = (Get-Process -Id $PID).Path
        $currentVersion = $PSVersionTable.PSVersion.ToString()

        $result = & $script:ProvisionerPath -PowerShellExecutable $currentExecutable -PowerShellVersion $currentVersion -PassThru

        $result.Provider | Should -Be 'ExplicitExecutable'
        $result.PowerShellVersion | Should -Be $currentVersion
        $result.DotNetMajor | Should -Be ([Environment]::Version.Major)
        $result.TargetFramework | Should -Be ('net{0}.0' -f [Environment]::Version.Major)
        $result.ExecutablePath | Should -Be (Resolve-Path -LiteralPath $currentExecutable).Path
    }

    It 'rejects an explicit executable that reports a different servicing patch' {
        $currentExecutable = (Get-Process -Id $PID).Path
        $currentVersion = $PSVersionTable.PSVersion.ToString()
        $matrix = Get-Content -LiteralPath $script:MatrixPath -Raw | ConvertFrom-Json
        $differentDeclaredVersion = @($matrix.profiles.powerShellVersion | Where-Object { $_ -ne $currentVersion })[0]

        $differentDeclaredVersion | Should -Not -BeNullOrEmpty

        {
            & $script:ProvisionerPath -PowerShellExecutable $currentExecutable -PowerShellVersion $differentDeclaredVersion
        } | Should -Throw '*version mismatch*'
    }

    It 'contains no floating release selector or PATH mutation' {
        $source = Get-Content -LiteralPath $script:ProvisionerPath -Raw

        $source | Should -Not -Match 'install\s+(stable|lts|7\.4(?!\.18)|7\.5(?!\.9)|7\.6(?!\.4))'
        $source | Should -Not -Match '\$env:PATH\s*='
        $source | Should -Match ([regex]::Escape('--no-add-path'))
        $source | Should -Not -Match 'multi-pwsh\s+host|pwsh-7\.'
    }

    It 'derives official payload paths and validates provider checksums' {
        $source = Get-Content -LiteralPath $script:ProvisionerPath -Raw
        $matrix = Get-Content -LiteralPath $script:MatrixPath -Raw | ConvertFrom-Json

        $source | Should -Match ([regex]::Escape("Join-Path 'multi' $ExactVersion"))
        $source | Should -Match ([regex]::Escape('Test-PathWithinRoot'))
        @($matrix.archiveAssets) | Should -HaveCount 9
        @($matrix.provisioning.optionalProvider.assets) | Should -HaveCount 3
        @($matrix.archiveAssets.sha256 + $matrix.provisioning.optionalProvider.assets.sha256 | Where-Object { $_ -notmatch '^[a-f0-9]{64}$' }) | Should -BeNullOrEmpty
    }
}
