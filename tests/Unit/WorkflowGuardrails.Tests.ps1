BeforeAll {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $UpstreamWorkflow = Get-Content -LiteralPath (Join-Path $ProjectRoot '.github\workflows\Upstream-Compatibility.yml') -Raw
    $DependabotWorkflow = Get-Content -LiteralPath (Join-Path $ProjectRoot '.github\workflows\Dependabot-Auto-Approve.yml') -Raw
    $DependabotConfig = Get-Content -LiteralPath (Join-Path $ProjectRoot '.github\dependabot.yml') -Raw
    $ReleaseWorkflow = Get-Content -LiteralPath (Join-Path $ProjectRoot '.github\workflows\Release-and-Publish.yml') -Raw
    $LifecycleWorkflowPath = Join-Path $ProjectRoot '.github\workflows\PowerShell-Support-Lifecycle.yml'
    $BuildWorkflow = Get-Content -LiteralPath (Join-Path $ProjectRoot '.github\workflows\Build Module.yml') -Raw
}

Describe 'Upstream compatibility workflow guardrails' -Tag 'Unit' {
    It 'runs the scheduled drift detector daily' {
        $UpstreamWorkflow | Should -Match 'cron:\s*["'']34 8 \* \* \*["'']'
    }

    It 'exposes an always-reported aggregate required check' {
        $UpstreamWorkflow | Should -Match '(?ms)^  pr-gate:\s+name: Validate upstream compatibility tooling\s+needs: \[pr-changes, pr-smoke-validation, profile-evidence-gate\]\s+if: \$\{\{ always\(\) \}\}'
    }

    It 'routes policy and fingerprint-generator changes through live validation' {
        $UpstreamWorkflow | Should -Match 'live_validation'
        $UpstreamWorkflow | Should -Match ([regex]::Escape('build/dependency-policy.json'))
        $UpstreamWorkflow | Should -Match ([regex]::Escape('tools/Get-DLLPickleUpstreamInventory.ps1'))
        $UpstreamWorkflow | Should -Match ([regex]::Escape("'^tools/Get-DLLPickleLoadedTrackedAssembly\.ps1$'"))
        $UpstreamWorkflow | Should -Match ([regex]::Escape('tools/New-DLLPickleConflictMatrix.ps1'))
        $UpstreamWorkflow | Should -Match ([regex]::Escape('tools/New-DLLPickleUpstreamScenarioEvidence.ps1'))
        $UpstreamWorkflow | Should -Match ([regex]::Escape("'^src/DLLPickle/'"))
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

    It 'publishes profile-aware findings once per stable fingerprint' {
        $UpstreamWorkflow | Should -Match ([regex]::Escape('tools/New-DLLPickleProfileEvidenceSummary.ps1'))
        $UpstreamWorkflow | Should -Match ([regex]::Escape('tools/Test-DLLPickleFindingFingerprintReported.ps1'))
        $UpstreamWorkflow | Should -Match ([regex]::Escape('$Summary.FindingMarker'))
        $UpstreamWorkflow | Should -Match 'issues: write'
        $UpstreamWorkflow | Should -Match ([regex]::Escape('suppressing a duplicate comment'))
    }

    It 'uses exact-profile baselines and fingerprint-derived candidate branches for scheduled writes' {
        $UpstreamWorkflow | Should -Match ([regex]::Escape('$ProfilePolicy[0].baselines.windows'))
        $UpstreamWorkflow | Should -Not -Match ([regex]::Escape('$policy.baseline.conflictSurfaceFingerprint'))
        $UpstreamWorkflow | Should -Match ([regex]::Escape('automation/upstream-compatibility-$($Fingerprint.Substring(0, 16))'))
        $UpstreamWorkflow | Should -Match ([regex]::Escape('publication_fingerprint='))
        $UpstreamWorkflow | Should -Not -Match ([regex]::Escape('automation/upstream-compatibility-${{ github.run_id }}'))
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

    It 'routes a newly introduced conditional TFM pin to maintainer review' {
        $DependabotWorkflow | Should -Match ([regex]::Escape('CONDITIONAL_TFM_ADDITION'))
        $DependabotWorkflow | Should -Match 'PackageReference.*Condition=.*TargetFramework'
    }

    It 'keeps runtime NuGet updates separate from CI toolchain updates' {
        $DependabotConfig | Should -Match 'runtime-bundle-minor-patch'
        $DependabotConfig | Should -Match 'ci-tooling-actions'
        $DependabotConfig | Should -Match 'multi-pwsh.*CI provisioning policy'
    }
}

Describe 'Dependabot major-version draft-PR flow' -Tag 'Unit' {
    It 'converts a major-version PR to a draft for mandatory review' {
        $DependabotWorkflow | Should -Match ([regex]::Escape('gh pr ready --undo'))
    }

    It 'gates the draft conversion on the major update type' {
        $DependabotWorkflow | Should -Match ([regex]::Escape("update-type == 'version-update:semver-major'"))
    }

    It 'posts a per-TFM evidence index covering graph, assets, assembly and conflict deltas, size, scenarios, and maintainer review' {
        $DependabotWorkflow | Should -Match 'Version change'
        $DependabotWorkflow | Should -Match 'Resolved graph \+ selected assets'
        $DependabotWorkflow | Should -Match 'Added/removed/changed assemblies'
        $DependabotWorkflow | Should -Match 'Conflict-surface delta'
        $DependabotWorkflow | Should -Match 'Scenario outcomes'
        $DependabotWorkflow | Should -Match ([regex]::Escape('artifact-size-baseline.json'))
        $DependabotWorkflow | Should -Match ([regex]::Escape('Compatibility-Evidence.md'))
        $DependabotWorkflow | Should -Match 'Maintainer checklist'
    }

    It 'keeps major updates excluded from auto-merge' {
        # Auto-merge is invoked exactly once -- in the patch/minor step, never on the major path.
        ([regex]::Matches($DependabotWorkflow, [regex]::Escape('gh pr merge --auto'))).Count | Should -Be 1
        $DependabotWorkflow | Should -Match ([regex]::Escape("update-type != 'version-update:semver-major'"))
    }
}

Describe 'Release publish gating guardrails' -Tag 'Unit' {
    It 'requires exact-commit authenticated evidence before version analysis or publication' {
        $ReleaseWorkflow | Should -Match '(?ms)^  authenticated-release-gate:\s+name: Require Authenticated Compatibility'
        $ReleaseWorkflow | Should -Match '(?ms)^  authenticated-release-gate:.*?permissions:\s+actions: read\s+contents: read'
        $ReleaseWorkflow | Should -Match '(?m)^    needs: authenticated-release-gate$'
        $ReleaseWorkflow | Should -Match ([regex]::Escape('Authenticated-Compatibility.yml'))
        $ReleaseWorkflow | Should -Match ([regex]::Escape('authenticated-compatibility-evidence'))
        $ReleaseWorkflow | Should -Match ([regex]::Escape("'--commit', `$EvidenceSha"))
        $ReleaseWorkflow | Should -Match ([regex]::Escape('steps.release-candidate.outputs.release_sha'))
        $ReleaseWorkflow | Should -Match ([regex]::Escape('needs.authenticated-release-gate.outputs.release_sha'))
        $ReleaseWorkflow | Should -Not -Match ([regex]::Escape('github.event.pull_request.head.sha'))
        $ReleaseWorkflow | Should -Match ([regex]::Escape('requiredBeforeRelease'))
        $ReleaseWorkflow | Should -Match ([regex]::Escape('writesAllowed -ne $false'))
    }

    It 'fails closed on the runtime lifecycle policy before version analysis' {
        $ReleaseWorkflow | Should -Match ([regex]::Escape('tools/Test-DLLPickleRuntimeProfilePolicy.ps1'))
        $ReleaseWorkflow | Should -Match ([regex]::Escape('-Mode Release'))
        $ReleaseWorkflow | Should -Match ([regex]::Escape('tools/Get-DLLPicklePowerShellSupportUpdate.ps1'))
        $ReleaseWorkflow | Should -Match ([regex]::Escape('-RequireCurrent'))
    }

    It 'runs profile-aware evidence and fail-closed baselines across the exact runtime matrix' {
        $UpstreamWorkflow | Should -Match ([regex]::Escape('tools/New-DLLPicklePowerShellTestMatrix.ps1'))
        $UpstreamWorkflow | Should -Match ([regex]::Escape('tools/Install-DLLPickleTestPowerShell.ps1'))
        $UpstreamWorkflow | Should -Match ([regex]::Escape('tools/Test-DLLPickleProfileConflictBaseline.ps1'))
        $UpstreamWorkflow | Should -Match ([regex]::Escape('tools/New-DLLPickleUpstreamScenarioEvidence.ps1'))
        $UpstreamWorkflow | Should -Match ([regex]::Escape('ScenarioEvidencePath'))
        $UpstreamWorkflow | Should -Match 'executed-two-orders-with-and-without-dllpickle'
        $UpstreamWorkflow | Should -Match ([regex]::Escape('-PowerShellExecutable'))
        $UpstreamWorkflow | Should -Match ([regex]::Escape('fromJson(needs.profile-matrix.outputs.matrix)'))
        $UpstreamWorkflow | Should -Match ([regex]::Escape('not-run-no-approved-credentials'))
        $UpstreamWorkflow | Should -Match ([regex]::Escape('writesPerformed = $false'))
    }

    It 'revalidates composition and size after stamping the release artifact' {
        $ReleaseWorkflow | Should -Match ([regex]::Escape('Test-DLLPicklePackageArtifact.ps1'))
        $ReleaseWorkflow | Should -Match ([regex]::Escape('New-DLLPickleArtifactSizeReport.ps1'))
        $ReleaseWorkflow | Should -Match ([regex]::Escape('SkipBuildOutputComparison'))
        $ReleaseWorkflow | Should -Match ([regex]::Escape('stamped-release-policy-reports'))
    }

    It 'auto-triggers only on closed pull requests to main' {
        $ReleaseWorkflow | Should -Match '(?ms)on:\s+pull_request:\s+types:\s*\[closed\]'
        $ReleaseWorkflow | Should -Match '(?ms)branches:\s+- main'
    }

    It 'path-gates auto-publish to EXACTLY the three bundle-affecting inputs' {
        # Parse the pull_request paths: allow-list and assert it is EXACTLY the three bundle inputs.
        # A presence-only check would still pass if an accidental auto-publish path (e.g. "docs/**",
        # "*.md", ".github/**") were added later -- the precise CI/docs release-trigger regression
        # GAP-006 is closed to prevent. The list must therefore have no entries beyond the allow-list.
        $pathsMatch = [regex]::Match(
            $ReleaseWorkflow,
            '(?m)^  pull_request:[\s\S]*?^    paths:\r?\n(?<list>(?:[^\S\r\n]+-[^\S\r\n][^\r\n]*\r?\n?)+)')
        $pathsMatch.Success | Should -BeTrue -Because 'the pull_request trigger must declare a paths allow-list'

        # Extract every YAML sequence item under paths: regardless of quote style (double-quoted,
        # single-quoted, or unquoted) so an extra entry like - docs/** or - 'docs/**' is still
        # captured and trips the EXACTLY-three assertion instead of being silently ignored.
        $declaredPaths = @(
            $pathsMatch.Groups['list'].Value -split '\r?\n' |
                ForEach-Object {
                    $item = [regex]::Match($_, '^[^\S\r\n]*-[^\S\r\n]+(?<path>\S.*?)[^\S\r\n]*$')
                    if ($item.Success) {
                        # Strip one matching pair of surrounding double or single quotes, if present.
                        $item.Groups['path'].Value -replace '^"(.*)"$', '$1' -replace "^'(.*)'`$", '$1'
                    }
                } |
                Where-Object { $_ }
        )
        $allowedPaths = @(
            'src/DLLPickle/**'
            'src/DLLPickle.Build/DLLPickle.csproj'
            'src/DLLPickle.Build/packages.lock.json'
        )
        $declaredPaths | Should -Be $allowedPaths
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

Describe 'PowerShell support lifecycle workflow guardrails' -Tag 'Unit' {
    It 'runs a scheduled and manually dispatchable lifecycle check' {
        $LifecycleWorkflowPath | Should -Exist
        $lifecycleWorkflow = Get-Content -LiteralPath $LifecycleWorkflowPath -Raw

        $lifecycleWorkflow | Should -Match '(?m)^\s+schedule:'
        $lifecycleWorkflow | Should -Match '(?m)^\s+workflow_dispatch:'
        $lifecycleWorkflow | Should -Match ([regex]::Escape('tools/Test-DLLPickleRuntimeProfilePolicy.ps1'))
        $lifecycleWorkflow | Should -Match ([regex]::Escape('-Mode Scheduled'))
        $lifecycleWorkflow | Should -Match ([regex]::Escape('tools/Get-DLLPicklePowerShellSupportUpdate.ps1'))
        $lifecycleWorkflow | Should -Match ([regex]::Escape('powershell-support-update.json'))
        $lifecycleWorkflow | Should -Match ([regex]::Escape('tools/Update-DLLPicklePowerShellTestMatrix.ps1'))
        $lifecycleWorkflow | Should -Match ([regex]::Escape('tools/Install-DLLPickleTestPowerShell.ps1'))
        $lifecycleWorkflow | Should -Match ([regex]::Escape('fromJson(needs.discover.outputs.runtime_matrix)'))
        $lifecycleWorkflow | Should -Match ([regex]::Escape('PatchProposalFingerprint'))
        $lifecycleWorkflow | Should -Match ([regex]::Escape('SupportContractFingerprint'))
    }

    It 'keeps discovery read-only and scopes repository writes to fingerprinted publication jobs' {
        $lifecycleWorkflow = Get-Content -LiteralPath $LifecycleWorkflowPath -Raw

        $lifecycleWorkflow | Should -Match '(?ms)^permissions:\s+contents: read\s*$'
        $lifecycleWorkflow | Should -Match '(?ms)^  finalize-patch-proposal:.*?permissions:\s+contents: write\s+pull-requests: write'
        $lifecycleWorkflow | Should -Match '(?ms)^  support-contract-warning:.*?permissions:\s+contents: read\s+issues: write'
        $lifecycleWorkflow | Should -Match ([regex]::Escape('automation/powershell-patch-$($Fingerprint.Substring(0, 16))'))
        $lifecycleWorkflow | Should -Match ([regex]::Escape('tools/Test-DLLPickleFindingFingerprintReported.ps1'))
        $lifecycleWorkflow | Should -Match 'gh\s+pr\s+create|@\(''pr'', ''create'''
        $lifecycleWorkflow | Should -Match 'gh\s+issue\s+(create|comment)'
        $lifecycleWorkflow | Should -Not -Match 'gh\s+pr\s+merge|git\s+push\s+--force'
    }

    It 'treats runtime policy and SDK changes as build relevant' {
        $BuildWorkflow | Should -Match ([regex]::Escape("'^global\.json$'"))
        $BuildWorkflow | Should -Match ([regex]::Escape("'^build/powershell-test-matrix\.json$'"))
    }
}

Describe 'Exact PowerShell runtime matrix workflow guardrails' -Tag 'Unit' {
    It 'generates the authoritative matrix from policy rather than a handwritten version list' {
        $BuildWorkflow | Should -Match ([regex]::Escape('tools/New-DLLPicklePowerShellTestMatrix.ps1'))
        $BuildWorkflow | Should -Match ([regex]::Escape('fromJson(needs.runtime-matrix.outputs.matrix)'))
    }

    It 'provisions and directly invokes each exact stock executable in fresh processes' {
        $BuildWorkflow | Should -Match ([regex]::Escape('tools/Install-DLLPickleTestPowerShell.ps1'))
        $BuildWorkflow | Should -Match ([regex]::Escape('$env:DLLPICKLE_TEST_PWSH -NoLogo -NoProfile -NonInteractive'))
        $BuildWorkflow | Should -Not -Match 'multi-pwsh\s+host|pwsh-7\.'
    }

    It 'captures structured selected-bundle and assembly load-context evidence' {
        $BuildWorkflow | Should -Match ([regex]::Escape('tools/New-DLLPickleRuntimeProfileEvidence.ps1'))
        $BuildWorkflow | Should -Match ([regex]::Escape('runtime-evidence-'))
        $BuildWorkflow | Should -Match 'upload-artifact@'
    }

    It 'runs strict package composition and resolved-TFM checks in every exact-runtime cell' {
        $RuntimeJob = [regex]::Match($BuildWorkflow, '(?ms)^  runtime-tests:.*?(?=^  dependency-change-report:)').Value
        $RuntimeJob | Should -Match ([regex]::Escape('tools/Test-DLLPicklePackageArtifact.ps1 -Strict'))
        $RuntimeJob | Should -Match ([regex]::Escape('tools/Test-DLLPickleTfmAlignment.ps1 -Strict'))
    }

    It 'keeps Build gate stable and aggregates both hosted and exact-runtime jobs' {
        $BuildWorkflow | Should -Match '(?m)^\s+name: Build gate\s*$'
        $BuildWorkflow | Should -Match 'needs: \[changes, runtime-matrix, build, runtime-tests, dependency-change-report\]'
        $BuildWorkflow | Should -Match ([regex]::Escape("foreach (`$RequiredJob in @('runtimeMatrix', 'build', 'runtimeTests'))"))
        $BuildWorkflow | Should -Match ([regex]::Escape('needs.runtime-matrix.result'))
        $BuildWorkflow | Should -Match ([regex]::Escape('runtimeTests ='))
        $BuildWorkflow | Should -Match ([regex]::Escape('needs.runtime-tests.result'))
        $BuildWorkflow | Should -Match ([regex]::Escape('needs.dependency-change-report.result'))
    }

    It 'requires successful profile-matrix generation whenever live upstream evidence is required' {
        $UpstreamWorkflow | Should -Match 'needs: \[pr-changes, profile-matrix, profile-evidence\]'
        $UpstreamWorkflow | Should -Match ([regex]::Escape("if (`$MatrixResult -ne 'success')"))
        $UpstreamWorkflow | Should -Match ([regex]::Escape('Required exact profile matrix generation did not succeed'))
    }

    It 'enforces artifact composition and material size growth in the hosted build gate' {
        $BuildWorkflow | Should -Match ([regex]::Escape('Test-DLLPicklePackageArtifact.ps1'))
        $BuildWorkflow | Should -Match ([regex]::Escape('New-DLLPickleArtifactSizeReport.ps1'))
        $BuildWorkflow | Should -Match ([regex]::Escape('package-policy-reports'))
    }

    It 'attaches a base-versus-candidate per-TFM report for Dependabot changes' {
        $BuildWorkflow | Should -Match ([regex]::Escape('tools/New-DLLPickleDependencyChangeReport.ps1'))
        $BuildWorkflow | Should -Match ([regex]::Escape('dependency-change-report.json'))
        $BuildWorkflow | Should -Match ([regex]::Escape('BaselineProjectAssetsPath'))
        $BuildWorkflow | Should -Match ([regex]::Escape('ScenarioEvidencePath'))
    }
}
