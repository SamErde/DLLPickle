BeforeAll {
    $script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ProvisionerPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'tools/Install-DLLPickleTestPowerShell.ps1'
    $script:MatrixPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'build/powershell-test-matrix.json'

    function Write-RuntimeProvisioningMatrixFixture {
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        [ordered]@{
            schemaVersion = 1
            profiles      = @(
                [ordered]@{
                    powerShellVersion = $PSVersionTable.PSVersion.ToString()
                    powerShellMajor   = $PSVersionTable.PSVersion.Major
                    powerShellMinor   = $PSVersionTable.PSVersion.Minor
                    dotnetMajor       = [Environment]::Version.Major
                    dotnetRuntimeVersion = [Environment]::Version.ToString()
                    targetFramework   = 'net{0}.0' -f [Environment]::Version.Major
                }
            )
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -Encoding UTF8

        return $Path
    }
}

Describe 'Exact PowerShell runtime provisioning' -Tag 'Unit' {
    It 'validates an explicit stock executable without multi-pwsh' {
        $currentExecutable = (Get-Process -Id $PID).Path
        $currentVersion = $PSVersionTable.PSVersion.ToString()
        $TestMatrixPath = Write-RuntimeProvisioningMatrixFixture -Path (Join-Path $TestDrive 'runtime-matrix.json')

        $result = & $script:ProvisionerPath -PowerShellExecutable $currentExecutable -PowerShellVersion $currentVersion -MatrixPath $TestMatrixPath -PassThru

        $result.Provider | Should -Be 'ExplicitExecutable'
        $result.PowerShellVersion | Should -Be $currentVersion
        $result.DotNetVersion | Should -Be ([Environment]::Version.ToString())
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

    It 'rejects a matrix entry with a different bundled .NET runtime patch' {
        $currentExecutable = (Get-Process -Id $PID).Path
        $currentVersion = $PSVersionTable.PSVersion.ToString()
        $TestMatrixPath = Write-RuntimeProvisioningMatrixFixture -Path (Join-Path $TestDrive 'runtime-version-mismatch.json')
        $matrix = Get-Content -LiteralPath $TestMatrixPath -Raw | ConvertFrom-Json
        $runtimeVersion = [Environment]::Version
        $matrix.profiles[0].dotnetRuntimeVersion = '{0}.{1}.{2}' -f $runtimeVersion.Major, $runtimeVersion.Minor, ($runtimeVersion.Build + 1)
        $matrix | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $TestMatrixPath -Encoding UTF8

        {
            & $script:ProvisionerPath -PowerShellExecutable $currentExecutable -PowerShellVersion $currentVersion -MatrixPath $TestMatrixPath
        } | Should -Throw '*CLR runtime version mismatch*'
    }

    It 'discovers the runtime patch for an explicitly pending lifecycle candidate' {
        $currentExecutable = (Get-Process -Id $PID).Path
        $currentVersion = $PSVersionTable.PSVersion.ToString()
        $TestMatrixPath = Write-RuntimeProvisioningMatrixFixture -Path (Join-Path $TestDrive 'pending-runtime-version.json')
        $matrix = Get-Content -LiteralPath $TestMatrixPath -Raw | ConvertFrom-Json
        $matrix.profiles[0].dotnetRuntimeVersion = $null
        $matrix | Add-Member -NotePropertyName candidateValidationPending -NotePropertyValue $true
        $matrix | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $TestMatrixPath -Encoding UTF8

        $result = & $script:ProvisionerPath -PowerShellExecutable $currentExecutable -PowerShellVersion $currentVersion -MatrixPath $TestMatrixPath -PassThru

        $result.DotNetVersion | Should -Be ([Environment]::Version.ToString())
        $result.DotNetMajor | Should -Be ([Environment]::Version.Major)
    }

    It 'rejects a missing runtime patch outside lifecycle candidate validation' {
        $currentExecutable = (Get-Process -Id $PID).Path
        $currentVersion = $PSVersionTable.PSVersion.ToString()
        $TestMatrixPath = Write-RuntimeProvisioningMatrixFixture -Path (Join-Path $TestDrive 'missing-runtime-version.json')
        $matrix = Get-Content -LiteralPath $TestMatrixPath -Raw | ConvertFrom-Json
        $matrix.profiles[0].dotnetRuntimeVersion = $null
        $matrix | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $TestMatrixPath -Encoding UTF8

        {
            & $script:ProvisionerPath -PowerShellExecutable $currentExecutable -PowerShellVersion $currentVersion -MatrixPath $TestMatrixPath
        } | Should -Throw '*has no dotnetRuntimeVersion*'
    }

    It 'still enforces the declared CLR major for a pending lifecycle candidate' {
        $currentExecutable = (Get-Process -Id $PID).Path
        $currentVersion = $PSVersionTable.PSVersion.ToString()
        $TestMatrixPath = Write-RuntimeProvisioningMatrixFixture -Path (Join-Path $TestDrive 'pending-runtime-major-mismatch.json')
        $matrix = Get-Content -LiteralPath $TestMatrixPath -Raw | ConvertFrom-Json
        $matrix.profiles[0].dotnetRuntimeVersion = $null
        $matrix.profiles[0].dotnetMajor = [Environment]::Version.Major + 1
        $matrix | Add-Member -NotePropertyName candidateValidationPending -NotePropertyValue $true
        $matrix | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $TestMatrixPath -Encoding UTF8

        {
            & $script:ProvisionerPath -PowerShellExecutable $currentExecutable -PowerShellVersion $currentVersion -MatrixPath $TestMatrixPath
        } | Should -Throw '*CLR mismatch*'
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
        $source | Should -Not -Match '(?ms)if \(-not \(Test-Path -LiteralPath \$ExpectedExecutable -PathType Leaf\)\) \{\s+Get-VerifiedDownload -Uri \$Archive\[0\]\.downloadUrl'
        $source | Should -Match '(?ms)Revalidate the immutable archive.*Get-VerifiedDownload -Uri \$Archive\[0\]\.downloadUrl.*Expand-TestRuntimeArchive -ArchivePath \$CachePath'
        @($matrix.archiveAssets) | Should -HaveCount 9
        @($matrix.provisioning.optionalProvider.assets) | Should -HaveCount 3
        @($matrix.archiveAssets.sha256 + $matrix.provisioning.optionalProvider.assets.sha256 | Where-Object { $_ -notmatch '^[a-f0-9]{64}$' }) | Should -BeNullOrEmpty
    }
}
