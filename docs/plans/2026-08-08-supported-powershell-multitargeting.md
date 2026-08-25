# Microsoft-Supported PowerShell Multi-Targeting Implementation Plan

**Status:** Ready for implementation

**Date:** 2026-08-08

**Goal:** Replace DLLPickle's single optimistic PowerShell 7.4 / `net8.0` contract with explicitly built, selected, tested, and evidence-backed support for every PowerShell 7 release line that Microsoft still supports.

**Initial supported set:** PowerShell 7.4, 7.5, and 7.6, targeting `net8.0`, `net9.0`, and `net10.0` respectively.

**Architecture:** Build one isolated dependency bundle per supported PowerShell/.NET profile. Select the exact bundle from the running PowerShell and CLR versions. Generate CI jobs from a canonical support policy, execute each profile in its own stock `pwsh` process, and maintain conflict evidence independently per profile and operating system.

**Tech stack:** PowerShell, Pester, Invoke-Build, .NET SDK/MSBuild, NuGet locked restore, GitHub Actions, Dependabot, and optional `multi-pwsh`-assisted CI provisioning.

---

## 1. Settled decisions

These decisions are inputs to implementation and should not be silently re-adjudicated.

1. DLLPickle supports only PowerShell 7 release lines that Microsoft currently supports. Windows PowerShell 5.1 remains out of scope.
2. As of 2026-08-08, the supported profiles are:

   | PowerShell | Current documented patch | .NET runtime | TFM | Microsoft lifecycle state |
   | --- | --- | --- | --- | --- |
   | 7.4 LTS | 7.4.18 | .NET 8 | `net8.0` | Supported; retirement listed in November 2026 |
   | 7.5 | 7.5.9 | .NET 9 | `net9.0` | Supported; retirement listed in November 2026 |
   | 7.6 LTS | 7.6.4 | .NET 10 | `net10.0` | Supported through November 2028 |

3. Only the latest Microsoft-serviced patch in each supported release line is an authoritative test target. Exact patch pins are updated automatically after validation.
4. Adding a new PowerShell minor line or removing a retired line changes the distributed support contract and requires maintainer review. It must not auto-merge.
5. `multi-pwsh` is optional CI/test infrastructure only:

   - It is not shipped in the DLLPickle module.
   - It is not a module manifest dependency.
   - It is not a NuGet runtime or build-output dependency.
   - Production code does not invoke or reference it.
   - Building, installing, importing, and using DLLPickle do not require it.
   - CI may replace it with another official-runtime provisioning mechanism without changing DLLPickle's public or runtime contract.

6. When `multi-pwsh` provisions a test runtime, tests invoke the installed official `pwsh`/`pwsh.exe` directly. They do not use `pwsh-7.x` aliases, `multi-pwsh host`, native host shims, MCP mode, or virtual-environment startup hooks as evidence for the stock PowerShell host.
7. Routine Dependabot patch/minor dependency PRs may auto-approve and auto-merge only after all required build, test, dependency-review, and compatibility gates pass.
8. Major dependency PRs are tested, converted to draft, documented with per-TFM evidence, and left for maintainer review. They never auto-merge.
9. Conflict classifications are evidence-backed per PowerShell/TFM profile. A `net8.0` result must not be assumed valid for `net9.0` or `net10.0`.
10. Authentication-dependent or tenant-dependent tests do not perform writes and do not use real credentials without explicit approval. Missing credentials must be reported as an outstanding validation gate, not converted into a false success claim.

## 2. Evidence and references

Revalidate these sources at implementation start and immediately before release:

- [Microsoft PowerShell lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/powershell)
- [PowerShell 7.4 release documentation](https://learn.microsoft.com/en-us/powershell/scripting/whats-new/what-s-new-in-powershell-74?view=powershell-7.4)
- [PowerShell 7.5 release documentation](https://learn.microsoft.com/en-us/powershell/scripting/whats-new/what-s-new-in-powershell-75?view=powershell-7.5)
- [PowerShell 7.6 release documentation](https://learn.microsoft.com/en-us/powershell/scripting/whats-new/what-s-new-in-powershell-76?view=powershell-7.6)
- [`awakecoding/multi-pwsh` snapshot](https://github.com/awakecoding/multi-pwsh)
- [Maintained `Devolutions/multi-pwsh` repository](https://github.com/Devolutions/multi-pwsh)
- [`multi-pwsh` host and virtual-environment behavior](https://github.com/Devolutions/multi-pwsh/blob/master/docs/host-and-venv.md)

The implementation must also preserve lessons established in the repository history:

- [PR #215](https://github.com/SamErde/DLLPickle/pull/215): identical assembly versions loaded in different ALCs can still break authentication.
- [Issue #193](https://github.com/SamErde/DLLPickle/issues/193): preloading some `Microsoft.Extensions.*` assemblies can break downstream modules.
- [Issue #242](https://github.com/SamErde/DLLPickle/issues/242): PowerShell script-block assembly callbacks can crash the process.
- [Issue #174](https://github.com/SamErde/DLLPickle/issues/174): Az.Storage and ExchangeOnlineManagement can have a genuine OData conflict requiring process isolation.
- [Issue #169](https://github.com/SamErde/DLLPickle/issues/169): the VS Code/PowerShellEditorServices host surface remains unresolved.
- [Issue #273](https://github.com/SamErde/DLLPickle/issues/273): the upstream compatibility baseline is stale and drift reporting is noisy.

## 3. Current-state gaps

The current implementation is intentionally single-profile:

- `src/DLLPickle.Build/DLLPickle.csproj` targets only `net8.0`.
- `src/DLLPickle/Public/Import-DPLibrary.ps1` defaults to `bin/net8.0`.
- `src/DLLPickle/DLLPickle.psd1` and `build/DLLPickle.Settings.ps1` require PowerShell 7.4.
- `global.json` pins a .NET 8 SDK.
- Unit and integration tests contain `net8.0` assumptions.
- `Build Module.yml` tests hosted-runner operating systems but not exact PowerShell release lines.
- `dependency-policy.json` contains one global `net8.0` policy/baseline.
- Upstream inventory scans DLLs recursively without recording the asset TFM actually selected by a given runtime.
- The runtime snapshot tool launches a generic `pwsh` rather than an explicitly supplied executable.
- The TFM-alignment tool uses a partial handwritten compatibility model instead of NuGet's resolved asset graph.
- Current CI can load conflicting Pester versions in one process, obscuring dependency-specific results.

## 4. Target architecture

### 4.1 Shipped runtime support map

Add a small shipped data file such as `src/DLLPickle/SupportedRuntimeProfiles.json` containing only runtime behavior required by the module:

```json
{
  "schemaVersion": 1,
  "profiles": [
    {
      "powerShellMajor": 7,
      "powerShellMinor": 4,
      "dotnetMajor": 8,
      "targetFramework": "net8.0"
    },
    {
      "powerShellMajor": 7,
      "powerShellMinor": 5,
      "dotnetMajor": 9,
      "targetFramework": "net9.0"
    },
    {
      "powerShellMajor": 7,
      "powerShellMinor": 6,
      "dotnetMajor": 10,
      "targetFramework": "net10.0"
    }
  ]
}
```

Do not place `multi-pwsh` versions, URLs, paths, or test-only patch pins in this shipped file.

The loader must match both the PowerShell minor line and CLR major. It must fail clearly when:

- the PowerShell line is unsupported;
- the CLR major does not match the profile;
- the matching TFM directory or required bundle is missing; or
- the policy contains duplicate or malformed profiles.

### 4.2 CI support and test matrix

Add a non-shipped file such as `build/powershell-test-matrix.json` containing:

- exact current patch per supported line;
- Microsoft lifecycle end date and last verification timestamp;
- expected CLR and TFM;
- supported OS/architecture lanes;
- evidence freshness threshold;
- optional pinned `multi-pwsh` version and release checksum metadata.

Tests must verify that the shipped and CI profile sets agree, while allowing exact patch and CI-tool metadata to remain outside the package.

### 4.3 Build outputs

Change the build project to:

```xml
<TargetFrameworks>net8.0;net9.0;net10.0</TargetFrameworks>
```

The module artifact must contain isolated output directories for the three profiles. Do not deduplicate files across profiles merely because their hashes currently match; a shared physical load path can change assembly resolution and needs separate evidence.

## 5. Implementation tasks

Each task should finish with focused green tests before advancing. Preserve unrelated worktree changes. Do not commit, push, or open a PR unless the maintainer explicitly requests it.

### Task 0: Refresh live state and establish a clean baseline

**Primary files:** repository state, live lifecycle sources, current GitHub issues/PRs, current workflows.

- [ ] Fetch/prune repository metadata without rewriting local work.
- [ ] Confirm the current branch, worktree cleanliness, and divergence from `origin/main`.
- [ ] Revalidate Microsoft's currently supported PowerShell lines and exact current servicing patches.
- [ ] Revalidate the maintained canonical `multi-pwsh` project and current release before pinning it.
- [ ] Inspect open dependency PRs and issue #273 so existing drift is not mistaken for a new multi-TFM regression.
- [ ] Record any change from the initial 7.4/7.5/7.6 assumption and obtain maintainer direction before changing the settled support set.

### Task 1: Make the existing CI harness deterministic

**Likely files:** `.github/ci-scripts/Actions_Bootstrap.ps1`, `build/DLLPickle.Build.ps1`, workflow cache definitions, focused workflow tests.

- [ ] Pin Pester, InvokeBuild, and other build/test tools to explicit versions.
- [ ] Prevent multiple Pester assemblies from being imported into one process.
- [ ] Launch independent build/test stages in fresh `pwsh -NoProfile -NonInteractive` processes where necessary.
- [ ] Include exact tool version, OS, architecture, and PowerShell line in relevant cache keys.
- [ ] Add a regression that detects a mismatched already-loaded Pester assembly.
- [ ] Confirm current Dependabot PR failures report dependency behavior rather than bootstrap nondeterminism.

**Gate:** Existing single-profile tests are green and reproducible before multi-targeting begins.

### Task 2: Add support-policy data and validation

**Create:**

- `src/DLLPickle/SupportedRuntimeProfiles.json`
- `build/powershell-test-matrix.json`
- focused policy/schema tests under `tests/Unit/`

**Modify:** manifest/build settings and any package-copy allowlists needed for the small runtime profile file.

- [ ] Write failing schema, uniqueness, and cross-file-alignment tests.
- [ ] Add the shipped runtime profile and non-shipped CI matrix.
- [ ] Validate PowerShell minor, CLR major, TFM, supported OS, exact patch, lifecycle date, and evidence timestamp fields.
- [ ] Add a release-time lifecycle check that fails if the package still claims an expired Microsoft support line.
- [ ] Add a scheduled warning before an impending retirement.
- [ ] Ensure an exact patch-only CI matrix update does not alter the shipped runtime contract.

### Task 3: Multi-target the dependency bundle and loader

**Likely files:**

- `src/DLLPickle.Build/DLLPickle.csproj`
- `packages.lock.json`
- `global.json`
- `build/DLLPickle.Build.ps1`
- `build/DLLPickle.Settings.ps1`
- `src/DLLPickle/DLLPickle.psd1`
- `src/DLLPickle/Public/Import-DPLibrary.ps1`
- TFM and import unit/integration tests

- [ ] Write failing tests for all three profile mappings and mismatch cases.
- [ ] Target `net8.0`, `net9.0`, and `net10.0` with locked restore.
- [ ] Pin a suitable .NET 10 SDK capable of building all three TFMs.
- [ ] Make build/copy/pack tasks handle all declared TFMs without hardcoded `net8.0` paths.
- [ ] Make the loader select the exact profile from PowerShell and CLR versions.
- [ ] Set the manifest minimum to the oldest currently supported PowerShell line while enforcing the exact supported set in the loader.
- [ ] Keep common dependency versions initially; introduce conditional per-TFM versions only when evidence requires them.
- [ ] Verify every packaged TFM has the expected dependency set and no undeclared spillover.

### Task 4: Add optional exact-runtime provisioning

**Create or modify:** a CI helper such as `tools/Install-DLLPickleTestPowerShell.ps1` and focused tests.

The helper should accept an explicit provider or executable path so tests are not coupled to `multi-pwsh`:

```text
-PowerShellExecutable <path>     Use an already-provisioned stock executable
-Provider MultiPwsh             Optionally provision through multi-pwsh
-Provider DirectArchive         Provision from official PowerShell release archives
```

- [ ] Pin and checksum-verify any `multi-pwsh` release used in CI.
- [ ] Treat pre-1.0 `multi-pwsh` minor updates as reviewed toolchain changes.
- [ ] Install under a runner-temporary explicit root with no persistent PATH mutation.
- [ ] Derive the official executable path from the installation root/version, not from alias output.
- [ ] Invoke the real installed `pwsh`/`pwsh.exe` directly.
- [ ] Verify exact PowerShell version, CLR description/version, `$PSHOME`, process path, OS, architecture, and expected TFM before running product tests.
- [ ] Reject a `multi-pwsh` host shim or any executable path outside the expected official payload root.
- [ ] Cache official archives by provider version, OS, architecture, and exact PowerShell patch.
- [ ] Prove that the build and tests can run with an explicit executable path when `multi-pwsh` is absent.
- [ ] Add an artifact/package inspection asserting no `multi-pwsh` file, package, manifest dependency, or runtime reference is shipped.

### Task 5: Generate the exact PowerShell/OS CI matrix

**Likely files:** `.github/workflows/Build Module.yml`, reusable workflow/scripts, workflow guardrail tests.

Generate nine authoritative cells from `build/powershell-test-matrix.json`:

```text
PowerShell 7.4 × Windows, Linux, macOS
PowerShell 7.5 × Windows, Linux, macOS
PowerShell 7.6 × Windows, Linux, macOS
```

Each cell must:

- [ ] provision or receive one exact stock PowerShell executable;
- [ ] use an isolated `PSModulePath` and fresh process;
- [ ] verify runtime identity before testing;
- [ ] run unit, integration, packaging, loader-selection, and known-regression tests;
- [ ] capture assembly/ALC snapshots and the selected bundle path; and
- [ ] upload a structured result artifact.

Preserve stable required-check names:

- `Build gate` aggregates build/runtime matrix results.
- `Validate upstream compatibility tooling` aggregates policy, evidence, drift, and freshness results.
- `dependency-review` remains required.

The matrix must cover regressions represented by issues/PRs #34, #193, #215, and #242. Issue #174 should be represented as an expected conflict/limitation until fresh evidence proves otherwise. PowerShellEditorServices/VS Code coverage should address issue #169 or retain it as an explicit gap.

### Task 6: Make dependency and conflict evidence profile-aware

**Likely files:**

- `build/dependency-policy.json`
- `tools/Get-DLLPickleUpstreamInventory.ps1`
- `tools/Get-DLLPickleRuntimeAssemblySnapshot.ps1`
- `tools/Test-DLLPickleTfmAlignment.ps1`
- `tools/Update-DLLPickleDependencyPins.ps1`
- `tests/Integration/Invoke-DLLPickleScenario.ps1`
- upstream compatibility workflow and tests

- [ ] Key preload, block, and known-conflict decisions by PowerShell line, TFM, OS/platform, module set, and import order.
- [ ] Record umbrella module version and the constituent module that actually ships each assembly.
- [ ] Record module manifest PowerShell compatibility and the newest release compatible with each profile.
- [ ] Record the asset path/TFM actually selected by the tested runtime rather than recursively mixing every DLL in the module directory.
- [ ] Record assembly name, version, hash, path, ALC, OS, architecture, and probe command.
- [ ] Parameterize child-process tooling with an exact `-PowerShellExecutable`.
- [ ] Derive NuGet compatibility from restored `project.assets.json` instead of extending the handwritten regex model.
- [ ] Complete lazy-load probe commands for ExchangeOnlineManagement and MicrosoftTeams.
- [ ] Test both relevant import orders, with and without DLLPickle.
- [ ] Separate deterministic import/no-auth evidence from credential-dependent authenticated smoke evidence.
- [ ] Re-adjudicate current issue #273 drift once per profile.
- [ ] Deduplicate drift reporting by fingerprint so an unchanged finding does not generate repeated comments.

Initial monitored module families include:

- Microsoft.Graph.Authentication / Microsoft.Graph
- Az.Accounts, Az.Resources, Az.Storage / Az
- ExchangeOnlineManagement
- MicrosoftTeams

If the newest upstream release does not support a still-supported PowerShell line, test the newest compatible release and document the upstream limitation explicitly.

### Task 7: Preserve and extend dependency automation

**Likely files:** `.github/dependabot.yml`, `.github/workflows/Dependabot-Auto-Approve.yml`, workflow guardrail tests, dependency documentation.

- [ ] Preserve daily NuGet patch/minor grouping and the exact Dependabot actor/author checks.
- [ ] Expand the allowed dependency-file set only as needed for multi-target project/lock files.
- [ ] Require the complete TFM/runtime matrix, upstream-policy gate, build gate, and dependency review before auto-merge completes.
- [ ] Keep patch/minor auto-approval and auto-merge registration after all checks pass.
- [ ] Keep major updates draft-only and never auto-merged.
- [ ] Attach a per-TFM major-update report containing resolved graph, selected assets, added/removed assemblies, conflict-surface delta, and scenario outcomes.
- [ ] Require review for a preload/block classification change, a new conditional TFM pin, or a material size-budget breach even if the package version is nominally minor.
- [ ] Preserve `deps:` to minor module-release behavior and `breaking:` for maintainer-approved major dependency changes.

### Task 8: Generate documentation and enforce artifact size

**Likely files:** `README.md`, `docs/Architecture.md`, `docs/Deep-Dive.md`, `docs/DEPENDENCIES.md`, `docs/Troubleshooting.md`, `CHANGELOG.md`, generated compatibility artifacts.

- [ ] Replace single-`net8.0` claims with the current generated support matrix.
- [ ] Document Microsoft-supported versus upstream-module-supported combinations separately.
- [ ] Generate compatibility rows containing module/version, PowerShell, TFM, OS, selected asset, assembly/ALC result, verdict, evidence date, and run identifier.
- [ ] Document known process-isolation requirements rather than implying every module combination can coexist.
- [ ] Add documentation drift tests against the support/profile data.
- [ ] Generate unpacked and compressed size reports per TFM and for the full release artifact.
- [ ] Commit an approved size baseline and show deltas in dependency PRs.
- [ ] Route unexpected size growth to review instead of unattended merge.
- [ ] State explicitly that `multi-pwsh` is optional CI tooling and is absent from the published module.

### Task 9: Full validation and release-readiness review

- [ ] Run analyzer, unit tests, integration tests, issue reproductions, locked restore, complete build, and packaging checks.
- [ ] Run all available exact-runtime cells locally or through GitHub Actions.
- [ ] Confirm the package contains only `net8.0`, `net9.0`, and `net10.0` while those lines remain Microsoft-supported.
- [ ] Confirm no `multi-pwsh` executable, NuGet package, module dependency, code reference, or license payload is present in the artifact.
- [ ] Confirm every claimed runtime reports the expected PowerShell, CLR, TFM, `$PSHOME`, and process executable.
- [ ] Refresh Microsoft lifecycle state immediately before release.
- [ ] If credentials and approval are available, run the authenticated read-only validation tier; otherwise document the exact unexecuted scenarios as a release gate.
- [ ] Run `git diff --check`, review the complete diff, and verify no unrelated or generated temporary files remain.

## 6. Automation policy

### 6.1 PowerShell runtime patch updates

A scheduled job discovers the newest GA patch within each declared supported line and opens a PR updating only test-matrix/evidence pins. That PR may merge automatically after all supported profiles pass. The workflow must pin the discovered exact version in the PR; required CI must not use a floating `7.4`, `7.5`, or `7.6` selector whose result can change between reruns.

### 6.2 New or retired PowerShell lines

Detection is automatic; support-contract changes are reviewed.

- A new supported minor line opens a proposal PR or issue containing the PowerShell/.NET/TFM mapping, package-size estimate, build results, and initial upstream conflict evidence.
- An approaching retirement opens a warning before the lifecycle deadline.
- Removal of a retired line changes the loader, package contents, documentation, and support floor and therefore requires a reviewed release decision.
- The release workflow fails closed if the package still claims a line past the verified Microsoft support end.

### 6.3 Dependency updates

- Patch/minor: automatic PR, full multi-profile tests, auto-approval, auto-merge after all gates.
- Major: automatic draft PR, full multi-profile tests and structured evidence, maintainer review, no auto-merge.
- Policy/TFM/size change: manual review regardless of nominal dependency update type.

## 7. Definition of done

- [ ] PowerShell 7.3 and `net7.0` are absent from code, tests, artifacts, and support claims.
- [ ] The published module contains one isolated payload for every and only currently Microsoft-supported PowerShell 7 line in scope.
- [ ] The loader selects the exact TFM using both PowerShell and CLR versions and fails closed on mismatches.
- [ ] Every claimed PowerShell/OS cell executes the stock official `pwsh` binary for its exact pinned servicing patch.
- [ ] Test logs and artifacts record PowerShell, CLR, TFM, executable path, `$PSHOME`, OS, architecture, and selected bundle.
- [ ] Conflict evidence is profile-aware and does not use a TFM-blind global baseline.
- [ ] Graph, Az, ExchangeOnlineManagement, and MicrosoftTeams have current per-profile compatibility evidence or an explicit, evidenced limitation.
- [ ] Routine Dependabot patch/minor PRs merge unattended only after all required gates pass.
- [ ] Major updates remain draft until maintainer review.
- [ ] Runtime patch updates are proposed and validated automatically; new/retired support lines are reviewed.
- [ ] Documentation and artifact-size reports are generated and checked for drift.
- [ ] `multi-pwsh` is absent from the published artifact and every runtime/build dependency declaration.
- [ ] The project can build and test from explicit stock PowerShell executable paths with `multi-pwsh` unavailable.
- [ ] Any credential-dependent validation not executed is identified precisely and is not represented as passing.

## 8. Recommended PR sequence

1. CI tool determinism and Pester isolation.
2. Support-policy schemas and profile-alignment tests without runtime behavior changes.
3. Multi-TFM build outputs and exact loader selection.
4. Optional runtime provisioner and exact stock-executable validation.
5. Nine-cell PowerShell/OS matrix and stable aggregate gates.
6. Profile-aware upstream inventory, policy, evidence, and issue #273 re-adjudication.
7. Dependabot report/gate updates, documentation generation, and artifact-size policy.
8. Final lifecycle refresh, authenticated validation where authorized, and release preparation.

Keep these changes reviewable and independently green. Do not combine a support-contract change with unrelated feature work.
