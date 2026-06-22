BeforeAll {
    $script:ScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..\..\.github\ci-scripts\Get-VersionBump.ps1')).Path

    # Named Get-* (not New-*): the AnalyzeTests task only excludes PSUseDeclaredVarsMoreThanAssignments,
    # so a New-*/Set-* helper would trip PSUseShouldProcessForStateChangingFunctions and fail the gate.
    function Get-SyntheticVersionBumpResult {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [string[]]$CommitMessage,

            [string]$ManifestVersion = '0.0.0'
        )

        $RepoPath = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('n'))
        $null = New-Item -Path $RepoPath -ItemType Directory -Force
        $HooksPath = Join-Path $RepoPath '.disabled-hooks'
        $null = New-Item -Path $HooksPath -ItemType Directory -Force
        $ManifestPath = Join-Path $RepoPath 'DLLPickle.psd1'
        "@{ ModuleVersion = '$ManifestVersion' }" | Set-Content -LiteralPath $ManifestPath -Encoding utf8

        Push-Location -LiteralPath $RepoPath
        try {
            git init --quiet 2>&1 | Out-Null
            # Neutralize any global signing/hooks so these throwaway TestDrive commits stay hermetic
            # and deterministic; these are ephemeral test-repo commits, not repository commits.
            git config commit.gpgsign false 2>&1 | Out-Null
            git config tag.gpgsign false 2>&1 | Out-Null
            git config core.hooksPath $HooksPath 2>&1 | Out-Null
            git config user.email 'test@dllpickle.invalid' 2>&1 | Out-Null
            git config user.name 'DLLPickle Test' 2>&1 | Out-Null

            # The root commit is excluded from the analyzed range (root..HEAD), so its prefix never
            # influences the bump; the commits under test are added on top of it.
            git add DLLPickle.psd1 2>&1 | Out-Null
            git commit --quiet -m 'chore: seed repository' 2>&1 | Out-Null

            foreach ($Message in $CommitMessage) {
                git commit --quiet --allow-empty -m $Message 2>&1 | Out-Null
            }

            & $script:ScriptPath -ManifestPath $ManifestPath
        } finally {
            Pop-Location
        }
    }
}

Describe 'Get-VersionBump deps-prefix release gate' -Tag 'Unit' {
    It 'treats a Dependabot deps: commit as a minor release (deps -> minor)' {
        $Result = Get-SyntheticVersionBumpResult -CommitMessage @('deps: bump Microsoft.Identity.Client from 4.83.1 to 4.84.1')
        $Result.ShouldRelease | Should -BeTrue
        $Result.NewVersionType | Should -Be 'minor'
        $Result.NewVersion.ToString() | Should -Be '0.1.0'
    }

    It 'treats a scoped deps(scope): commit as a minor release' {
        $Result = Get-SyntheticVersionBumpResult -CommitMessage @('deps(nuget): bump the nuget-minor-patch group')
        $Result.ShouldRelease | Should -BeTrue
        $Result.NewVersionType | Should -Be 'minor'
    }

    It 'does not release for a <Prefix>: commit' -ForEach @(
        @{ Prefix = 'docs' }
        @{ Prefix = 'ci' }
        @{ Prefix = 'style' }
    ) {
        $Result = Get-SyntheticVersionBumpResult -CommitMessage @("${Prefix}: routine non-publishing change")
        $Result.ShouldRelease | Should -BeFalse
        $Result.NewVersionType | Should -Be 'none'
    }
}

Describe 'Get-VersionBump existing prefix behavior is preserved' -Tag 'Unit' {
    It 'maps a <Prefix>: commit to a <Expected> bump' -ForEach @(
        @{ Prefix = 'feat'; Expected = 'minor' }
        @{ Prefix = 'fix'; Expected = 'patch' }
        @{ Prefix = 'perf'; Expected = 'patch' }
        @{ Prefix = 'breaking'; Expected = 'major' }
    ) {
        $Result = Get-SyntheticVersionBumpResult -CommitMessage @("${Prefix}: representative change")
        $Result.NewVersionType | Should -Be $Expected
        $Result.ShouldRelease | Should -BeTrue
    }

    It 'lets a major breaking: commit win over a deps: minor in the same range' {
        $Result = Get-SyntheticVersionBumpResult -CommitMessage @(
            'deps: bump a dependency'
            'breaking: drop a runtime'
        )
        $Result.NewVersionType | Should -Be 'major'
        $Result.ShouldRelease | Should -BeTrue
    }
}
