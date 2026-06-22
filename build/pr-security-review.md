# DLLPickle PR Security & Quality Review

**Date:** 2026-03-24
**Scope:** GitHub Actions workflows, supply chain security, PowerShell code quality, and repository structure.

---

## Executive Summary

DLLPickle has a solid foundation: pinned action SHAs, OSSF Scorecard, Dependabot, Dependency Review, CODEOWNERS, and a `packages.lock.json`. This review records pipeline hardening implemented in the PowerShell 7.4+ migration, including **PSScriptAnalyzer SARIF upload to GitHub code scanning** and **NuGet lock-file enforcement during PR validation**. Remaining recommendations focus on preserving those controls and continuing to close validation gaps.

---

## Findings and Recommendations

### 1. PSScriptAnalyzer SARIF Upload (Implemented)

**Current state:** The Build Module workflow runs PSScriptAnalyzer, exports SARIF, and uploads the report to GitHub's Code Scanning dashboard. Analyzer findings are therefore available as build failures, PR annotations, and Security tab entries.

Implemented workflow permissions:

Required workflow permissions addition:

```yaml
permissions:
  contents: read
  security-events: write  # needed for SARIF upload
```

Implemented workflow pattern:

```yaml
- name: Run PSScriptAnalyzer and export SARIF
  shell: pwsh
  run: |
    $Results = Invoke-ScriptAnalyzer -Path ./src/DLLPickle -Recurse -Settings ./build/PSScriptAnalyzerSettings.psd1
    $SarifOutput = $Results | ConvertTo-Sarif
    $SarifOutput | ConvertTo-Json -Depth 20 | Set-Content -Path ./artifacts/psscriptanalyzer.sarif

- name: Upload PSScriptAnalyzer SARIF
  if: always()
  uses: github/codeql-action/upload-sarif@<pinned-sha>
  with:
    sarif_file: ./artifacts/psscriptanalyzer.sarif
    category: psscriptanalyzer
```

> Note: Keep the pinned PSScriptAnalyzer version on a release that supports SARIF output.

---

### 2. NuGet Lock File Enforcement During PR Validation (Implemented)

**Current state:** `DLLPickle.csproj` sets `<RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>`, the generated `packages.lock.json` is committed, and `Validate-Packages.yml` restores in locked mode during PR validation:

```yaml
run: dotnet restore src/DLLPickle.Build/DLLPickle.csproj --locked-mode
```

`--locked-mode` fails the build if the resolved package graph differs from the committed lock file, preventing accidental or malicious package reference drift from passing PR validation.

When intentionally updating dependencies, regenerate the lock file locally or in a controlled maintenance workflow with `--force-evaluate`, review the resulting lock-file diff, and commit it with the package reference change.

```yaml
- name: Restore dependencies in locked mode
  run: dotnet restore src/DLLPickle.Build/DLLPickle.csproj --locked-mode
```

With this behavior:

- **PR checks** -> `--locked-mode` fails the build if resolved packages differ from the committed lock file.
- **Dependency maintenance** -> `--force-evaluate` is used only when intentionally regenerating and reviewing the lock file.

---

### 3. Build Module PR Trigger Path Filter Is Too Narrow

**Current state:** `Build Module - Windows.yml` triggers on PRs only when files in `src/**` change:

```yaml
pull_request:
  paths:
    - "src/**"
    - ".github/workflows/Build Module - Windows.yml"
```

**Impact:** PRs that modify `build/`, `tests/`, or `.github/ci-scripts/` do not trigger the build. A contributor could change the Pester test harness, PSScriptAnalyzer settings, or CI bootstrap script without any automated validation.

**Recommendation:** Expand the `paths` filter to include these directories:

```yaml
pull_request:
  paths:
    - "src/**"
    - "build/**"
    - "tests/**"
    - ".github/ci-scripts/**"
    - ".github/workflows/Build Module - Windows.yml"
```

---

### 4. PSScriptAnalyzer Settings Do Not Enable Compatibility Rules

**Current state:** `build/PSScriptAnalyzerSettings.psd1` enables default rules at Error and Warning severity, but `PSUseCompatibleSyntax` and `PSUseCompatibleCmdlets` are commented out. The module explicitly targets PowerShell 7.4+.

**Recommendation:** Enable compatibility rules targeting the supported runtime versions. Add to `PSScriptAnalyzerSettings.psd1`:

```powershell
Rules = @{
    PSUseCompatibleSyntax = @{
        Enable         = $true
        TargetVersions = @('7.4')
    }
    PSUseCompatibleCmdlets = @{
        Compatibility = @(
            'core-7.4.0-windows'
        )
    }
    PSUseCompatibleCommands = @{
        Enable         = $true
        TargetProfiles = @(
            'win-8_x64_10.0.17763.0_7.4.0_x64_4.0.30319.42000_core'
        )
    }
}
```

This catches cases where syntax or cmdlets drift from the supported PowerShell 7.4+ baseline.

---

### 5. Pester Code Coverage Threshold Is Zero

**Current state:** The `Analyze` and `Test` tasks run PSScriptAnalyzer and Pester, but code coverage thresholds are configured at 0% (effectively disabled). This means the PR check passes regardless of how little of the module is tested.

**Recommendation:** Set a meaningful coverage threshold in the build configuration. A reasonable starting point for an established module is 50–70%. Raise it incrementally. In the Pester configuration within `DLLPickle.Build.ps1`, set:

```powershell
CodeCoverage       = @{
    Enabled          = $true
    CoveragePercentTarget = 60
}
```

Pair this with uploading the Pester coverage report (already done via artifact upload) so coverage trends are visible over time.

---

### 6. NuGet Package Version Ranges Are Broad

**Current state:** `DLLPickle.csproj` declares package references with major-version wildcards:

```xml
<PackageReference Include="Microsoft.Identity.Client" Version="4.*" />
<PackageReference Include="Microsoft.IdentityModel.Tokens" Version="8.*" />
```

**Impact:** While the lock file pins exact resolved versions at build time, the wildcard allows any new minor or patch version to be introduced when the lock file is regenerated. Combined with recommendation #2 (use `--locked-mode`), this risk is mitigated — but it is worth knowing that Dependabot auto-approval of patch/minor updates means new package versions merge without manual review.

**Recommendation:** This is an acceptable trade-off if `--locked-mode` is enforced (recommendation #2) and Dependabot is the only mechanism updating the lock file. Document this decision explicitly. If a higher trust level is required, pin to exact versions and require manual PR review for all dependency updates (remove auto-merge).

---

### 7. Branch Protection Rules Should Require Specific Status Checks

**Current state:** The repository has CODEOWNERS and workflows that run on PRs, but there is no evidence that GitHub branch protection rules enforce specific required status checks before merging to `main`. Without required checks, a maintainer (or collaborator) could merge a PR even if the build failed.

**Recommendation:** Configure branch protection on `main` with these required status checks:

- `Build and test module (Windows)` — from Build Module workflow
- `dependency-review` — from Dependency Review workflow
- `build-test` — from Validate Packages workflow

Additionally enable:

- Require PR reviews before merging (at least 1 reviewer)
- Dismiss stale reviews when new commits are pushed
- Require branches to be up to date before merging
- Do not allow bypassing the above settings (including for admins, if acceptable)

These cannot be configured via workflow files; they must be set in GitHub repository Settings → Branches.

> **Update (tag-driven versioning):** The release GitHub App has been removed from the "Protect Main" ruleset bypass list, since the release workflow no longer pushes directly to `main` (only the Admin role retains `always` bypass). Required status checks remain recommended — and are now load-bearing, since the App can no longer bypass them.

---

### 8. Dependabot Auto-Merge Scope

**Current state:** `Dependabot-Auto-Approve.yml` auto-approves and auto-merges Dependabot PRs for NuGet package updates classified as `patch` or `minor`. This means dependency updates merge without human review.

**Impact:** A compromised NuGet package (supply chain attack via a minor version bump) would pass through automatically. The Dependency Review workflow would need to catch it via known-vulnerability databases, which may lag behind a zero-day attack.

**Recommendation:** Consider restricting auto-merge to `patch` only, requiring manual review for minor version bumps of security-critical packages (MSAL, IdentityModel). Add a `deny-list` configuration to `Dependency-Review.yml` for packages known to be high-risk:

```yaml
- name: 'Dependency Review'
  uses: actions/dependency-review-action@<sha>
  with:
    comment-summary-in-pr: always
    fail-on-severity: moderate
    retry-on-snapshot-warnings: true
    # Optionally add deny-list for specific package ecosystems if needed
```

At minimum, ensure CODEOWNERS requires owner review for changes to `packages.lock.json` (already set) so the auto-merge path for Dependabot is the only one that bypasses human review.

---

### 9. No Explicit Secret Scanning Workflow

**Current state:** GitHub Advanced Security provides automatic secret scanning for public repositories, but there is no explicit workflow step that scans for accidentally committed secrets or credentials.

**Recommendation:** Add `trufflesecurity/trufflehog` or `gitleaks/gitleaks-action` to the PR check workflow to scan for secrets in changed files. Example:

```yaml
- name: Scan for secrets
  uses: gitleaks/gitleaks-action@<pinned-sha>
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

This provides a defense-in-depth layer on top of GitHub's native secret scanning, with results visible in the PR itself.

---

### 10. PR Template Checklist Should Reference Automated Checks

**Current state:** `PULL_REQUEST_TEMPLATE.md` has a manual checklist with items like "My code follows the code style of this project." This relies entirely on contributor self-reporting.

**Recommendation:** Add a section to the PR template that explicitly lists which automated checks must pass, so contributors know what to expect:

```markdown
## Automated Checks

The following checks must pass before this PR can be merged:
- [ ] Build Module (Windows) — compiles, passes PSScriptAnalyzer, and passes Pester tests
- [ ] Dependency Review — no known-vulnerable dependencies introduced
- [ ] Validate .NET Packages — NuGet lock file is consistent
```

This sets expectations and reduces confusion when checks fail.

---

## Current Strengths

The following practices are already well-implemented and should be maintained:

| Practice | Evidence |
| --- | --- |
| Pinned action SHAs | All `uses:` lines include `@<sha>` pins with version comments |
| OSSF Scorecard | `Supply-Chain-Security-Scorecards.yml` runs daily and uploads SARIF |
| Dependency Review | `Dependency-Review.yml` blocks PRs with moderate+ vulnerabilities |
| NuGet lock file generated | `RestorePackagesWithLockFile=true` in csproj |
| CODEOWNERS | Critical files (csproj, lock file, manifests, workflows) require `@SamErde` review |
| Least-privilege permissions | Most workflows declare `permissions: contents: read` |
| Dependabot configured | Updates github-actions, nuget, pip, devcontainers, docker |
| Conventional commits | `Get-VersionBump.ps1` enforces semantic versioning from commit messages |
| Rollback on failure | Release workflow deletes the tag and GitHub release on failure; tag-driven versioning makes no commits to `main`, so none need reverting |
| PSScriptAnalyzer | Runs during every build (Analyze task) at Error+Warning severity |

---

## Priority Order

| Priority | Recommendation | Effort |
| --- | --- | --- |
| 1 | Fix `--locked-mode` in Validate-Packages (#2) | Low |
| 2 | Upload PSScriptAnalyzer results as SARIF (#1) | Medium |
| 3 | Expand Build Module PR path filter (#3) | Low |
| 4 | Configure branch protection required checks (#7) | Low (UI config) |
| 5 | Enable PSScriptAnalyzer compatibility rules (#4) | Low |
| 6 | Set Pester coverage threshold > 0% (#5) | Low |
| 7 | Add secret scanning to PR workflow (#9) | Low |
| 8 | Update PR template with automated checks list (#10) | Low |
| 9 | Review Dependabot auto-merge scope (#8) | Medium (policy decision) |
| 10 | Document NuGet version range decision (#6) | Low |
