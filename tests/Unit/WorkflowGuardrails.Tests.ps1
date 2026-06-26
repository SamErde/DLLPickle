BeforeAll {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $UpstreamWorkflow = Get-Content -LiteralPath (Join-Path $ProjectRoot '.github\workflows\Upstream-Compatibility.yml') -Raw
    $DependabotWorkflow = Get-Content -LiteralPath (Join-Path $ProjectRoot '.github\workflows\Dependabot-Auto-Approve.yml') -Raw
    $ReleaseWorkflow = Get-Content -LiteralPath (Join-Path $ProjectRoot '.github\workflows\Release-and-Publish.yml') -Raw
}

Describe 'Upstream compatibility workflow guardrails' -Tag 'Unit' {
    It 'runs the scheduled drift detector daily' {
        $UpstreamWorkflow | Should -Match 'cron:\s*["'']34 8 \* \* \*["'']'
    }

    It 'exposes an always-reported aggregate required check' {
        $UpstreamWorkflow | Should -Match '(?ms)^  pr-gate:\s+name: Validate upstream compatibility tooling\s+needs: \[pr-changes, pr-smoke-validation\]\s+if: \$\{\{ always\(\) \}\}'
    }

    It 'routes policy and fingerprint-generator changes through live validation' {
        $UpstreamWorkflow | Should -Match 'live_validation'
        $UpstreamWorkflow | Should -Match ([regex]::Escape('build/dependency-policy.json'))
        $UpstreamWorkflow | Should -Match ([regex]::Escape('tools/Get-DLLPickleUpstreamInventory.ps1'))
        $UpstreamWorkflow | Should -Match ([regex]::Escape('tools/New-DLLPickleConflictMatrix.ps1'))
    }

    It 'uploads compact JSON evidence and writes a job summary' {
        $UpstreamWorkflow | Should -Match ([regex]::Escape('upstream-inventory.json'))
        $UpstreamWorkflow | Should -Match ([regex]::Escape('conflict-matrix.json'))
        $UpstreamWorkflow | Should -Match 'retention-days:'
        $UpstreamWorkflow | Should -Match 'GITHUB_STEP_SUMMARY'
        $UpstreamWorkflow | Should -Not -Match '(?m)^\s+path: \.\/artifacts\/upstreamCompatibility\s*$'
    }

    It 'runs the explicit TFM-alignment check (Step 0b) in the candidate flow and uploads its report' {
        $UpstreamWorkflow | Should -Match ([regex]::Escape('tools/Test-DLLPickleTfmAlignment.ps1'))
        $UpstreamWorkflow | Should -Match ([regex]::Escape('tfm-alignment.json'))
    }
}

Describe 'Dependabot auto-merge guardrails' -Tag 'Unit' {
    It 'requires every changed file to be in the NuGet allow-list' {
        $DependabotWorkflow | Should -Match 'UNEXPECTED_FILES'
        $DependabotWorkflow | Should -Match 'is_exact_nuget_update'
    }

    It 'documents every required merge check by its exact context name' {
        $DependabotWorkflow | Should -Match ([regex]::Escape('Build gate'))
        $DependabotWorkflow | Should -Match ([regex]::Escape('Validate upstream compatibility tooling'))
        $DependabotWorkflow | Should -Match ([regex]::Escape('dependency-review'))
    }
}

Describe 'Dependabot major-version draft-PR flow' -Tag 'Unit' {
    It 'converts a major-version PR to a draft for mandatory review' {
        $DependabotWorkflow | Should -Match ([regex]::Escape('gh pr ready --undo'))
    }

    It 'gates the draft conversion on the major update type' {
        $DependabotWorkflow | Should -Match ([regex]::Escape("update-type == 'version-update:semver-major'"))
    }

    It 'posts structured notes covering the version delta, TFM alignment, conflict surface, and a maintainer checklist' {
        $DependabotWorkflow | Should -Match 'Version change'
        $DependabotWorkflow | Should -Match 'TFM alignment'
        $DependabotWorkflow | Should -Match ([regex]::Escape('Test-DLLPickleTfmAlignment.ps1'))
        $DependabotWorkflow | Should -Match ([regex]::Escape('dependency-policy.json'))
        $DependabotWorkflow | Should -Match 'Maintainer checklist'
    }

    It 'keeps major updates excluded from auto-merge' {
        # Auto-merge is invoked exactly once -- in the patch/minor step, never on the major path.
        ([regex]::Matches($DependabotWorkflow, [regex]::Escape('gh pr merge --auto'))).Count | Should -Be 1
        $DependabotWorkflow | Should -Match ([regex]::Escape("update-type != 'version-update:semver-major'"))
    }
}

Describe 'Release publish gating guardrails' -Tag 'Unit' {
    It 'auto-triggers only on closed pull requests to main' {
        $ReleaseWorkflow | Should -Match '(?ms)on:\s+pull_request:\s+types:\s*\[closed\]'
        $ReleaseWorkflow | Should -Match '(?ms)branches:\s+- main'
    }

    It 'path-gates auto-publish to the three bundle-affecting inputs' {
        $ReleaseWorkflow | Should -Match ([regex]::Escape('- "src/DLLPickle/**"'))
        $ReleaseWorkflow | Should -Match ([regex]::Escape('- "src/DLLPickle.Build/DLLPickle.csproj"'))
        $ReleaseWorkflow | Should -Match ([regex]::Escape('- "src/DLLPickle.Build/packages.lock.json"'))
    }

    It 'does not path-gate on non-bundle inputs that must never auto-publish' {
        # docs/test/tooling/policy/CI-only changes leave the shipped bundle byte-identical.
        $ReleaseWorkflow | Should -Not -Match '(?m)^\s+- "docs/\*\*"'
        $ReleaseWorkflow | Should -Not -Match '(?m)^\s+- "tests/\*\*"'
        $ReleaseWorkflow | Should -Not -Match '(?m)^\s+- "tools/\*\*"'
        $ReleaseWorkflow | Should -Not -Match '(?m)^\s+- "build/\*\*"'
    }

    It 'exposes workflow_dispatch as the deliberate-release escape hatch with an explicit bump choice' {
        $ReleaseWorkflow | Should -Match '(?m)^\s+workflow_dispatch:'
        $ReleaseWorkflow | Should -Match ([regex]::Escape('version_bump'))
        $ReleaseWorkflow | Should -Match '(?ms)options:\s+- auto\s+- major\s+- minor\s+- patch'
    }
}
