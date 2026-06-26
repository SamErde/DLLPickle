<!-- markdownlint-disable MD024 -->
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.2.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

- Working on updates to replace PlatyPS documentation creation with the new Microsoft.PowerShell.PlatyPS module. (PRs and other help would be welcomed!)
- Added a structural gap-register guard (`tests/Unit/GapRegister.Tests.ps1`) that validates gap status values, index membership, index/frontmatter status agreement, and `resolution_pr`/`resolved_on` on resolved gaps; surfaced and fixed GAP-001's missing index row (GAP-011).

## [2.2.2] - 2026-06-22

> No functional PowerShell module behavior changes. This release hardens the dependency-update and release contract around the existing net8.0 module bundle.

### Added

- `tools/Test-DLLPickleTfmAlignment.ps1` — the explicit net8.0/netstandard2.0 TFM-alignment inspection (Architecture §8.2 Step 0b): it inspects each preload package's `lib/<tfm>/` assets and runs fail-closed in the scheduled Upstream-Compatibility candidate flow, complementing the `Build gate`.

### Changed

- The upstream-compatibility required check now distinguishes live freshness checks from deterministic guardrail changes, so workflow-only fixes can merge without pretending to refresh a stale conflict baseline.
- Dependabot's NuGet `deps:` commit prefix now publishes a **minor** module release: `Get-VersionBump.ps1` recognizes `deps:` as a minor release prefix, so an auto-merged minor/patch dependency bump fires the version gate on its own (decisions 3 & 4 / Architecture §8).
- Major dependency PRs are now converted to reviewed **draft PRs** with structured notes (version delta, NuGet link, TFM-alignment references, Build gate / CI links, conflict-surface / `dependency-policy.json` impact, and a maintainer checklist) instead of a generic comment; they stay excluded from auto-merge and auto-publish (decision 4).

### Internal

- Renormalize tracked files to a consistent LF-in-repo policy without changing module behavior.

## [2.2.1] - 2026-06-20

> Removes unsafe runtime assembly event callbacks, hardens the conflict-surface adjudication path, and records the refreshed issue #239 baseline.

### Changed

- Scheduled conflict-surface monitoring now runs daily, publishes compact JSON evidence and a job summary, and reports the exact monitored module versions.
- Dependabot auto-approval now rejects any PR containing files outside the NuGet project/lock-file allow-list.
- Upstream inventory capture now resolves every monitored module version before downloading any module, so the resulting inventory is an atomic version snapshot.
- The issue #239 conflict baseline now records the full version- and contributor-aware surface. Adjudication against the latest monitored modules confirmed that classifications and the bundled set are unchanged.
- Automatic future-load conflict watching has been removed. `Import-DPLibrary` still warns once for known conflicts that are already loaded; run `Test-DPLibraryConflict` after later module imports for the reliable on-demand check.

### Fixed

- `Compare-DLLPickleConflictMatrix.ps1` now treats version, contributor, removed-conflict, and ALC changes consistently with the version-aware fingerprint gate.
- Runtime ALC snapshots support strict adjudication mode, where module-import and probe-command failures are fatal instead of producing partial evidence.
- `Import-DPLibrary` no longer registers PowerShell script blocks as CLR `AssemblyResolve` or `AssemblyLoad` event handlers. Those events can run on threads without a PowerShell runspace and terminate the process with `PSInvalidOperationException` (#242).
- Dependency loading now relies on the supported-runtime dependency graph, deterministic fallback ordering, and retries. Synthetic transitive-dependency coverage confirmed that the legacy Windows PowerShell 5.1 resolver is not required on PowerShell 7.4+ / .NET 8.

## [2.2.0] - 2026-06-02

> Adds proactive detection of the Az.Storage + ExchangeOnlineManagement OData incompatibility (#174) and a public conflict check, plus release-pipeline and CI hardening. The bundled assemblies are **unchanged** from 2.1.2.

### Added

- **`Test-DPLibraryConflict`** — a public cmdlet that reports known-incompatible module combinations loaded in the current session (with the reason, the separate-process workaround, and the issue link) and returns the active conflicts.
- **`Import-DPLibrary` now warns** when a known-conflicting module pair is — or later becomes — co-loaded: immediately if both are already imported, otherwise via a best-effort, idempotent, self-unregistering `AssemblyLoad` handler that fires only once the whole pair is co-loaded (armed only when both modules are installed). Advisory: it never throws and is skipped under Constrained Language Mode.
- Data-driven conflict list in **`src/DLLPickle/KnownConflicts.json`** — a committed source file shipped verbatim with the module (adding a future conflict is a data edit, not a code change). Because it lives under `src/DLLPickle/`, a conflict-data edit correctly publishes a new release, while policy/CI-only edits do not.
- Runtime ALC-ownership probe tooling under `tools/` (`Get-DLLPickleLoadedTrackedAssembly.ps1`; `Get-DLLPickleRuntimeAssemblySnapshot` now sources its filter from `trackedAssemblies`, so it captures the OData stack) used to adjudicate #174.

### Changed

- **Release-and-Publish auto-triggers only on changes to the published bundle** (`src/DLLPickle/**`, `src/DLLPickle.Build/DLLPickle.csproj`, `src/DLLPickle.Build/packages.lock.json`). CI-, policy-, docs-, test-, and tooling-only changes no longer publish a new PowerShell Gallery version; release a genuine packaging-logic change via a manual `workflow_dispatch` run.
- The Upstream-Compatibility gate workflows now **always report** (a lightweight change-detection job skips the heavy work on non-bundle PRs), so they can be configured as **required status checks** without deadlocking docs-/CI-only PRs; the matrix build's required-check target is the always-present aggregate **`Build gate`**.

### Documentation

- Documented the **Az.Storage + ExchangeOnlineManagement known limitation** (#174): the two modules bundle incompatible strong-named `Microsoft.OData.Core` versions (7.6.4 vs 7.22.0) into the default `AssemblyLoadContext` and **cannot share one process** in either import order. DLLPickle cannot resolve this by preloading (preloading either version breaks the other), so the OData stack stays `block` — now runtime-confirmed. Use the two modules in separate PowerShell processes; #174 remains open as an upstream incompatibility.
- Synced `docs/Architecture.md` (ALC self-isolation model, preload/block taxonomy, the required-checks model, and the multi-TFM / Windows PowerShell 5.1 notes).

## [2.1.2] - 2026-06-01

> Follow-up Codex review of #223. Refines the 2.1.1 drift tooling and policy documentation — **no change to the published module bundle**.

### Fixed

- **Drift fingerprint is now contributor-aware.** `New-DLLPickleConflictMatrix` hashes each conflicting assembly's name, its versions, **and** the set of modules that ship it (`ShippedBy`), so a change in which modules contribute to a conflict (at the same version set) also trips drift for re-adjudication — not just name- or version-set changes. The recorded baseline is recomputed accordingly.
- **Dependency-PR gate documented as an upstream-freshness check.** Corrected the step name, comments, and messages to make clear it validates that the upstream conflict surface still matches the baseline — *not* the bumped bundle (a self-bump does not move the upstream fingerprint). The bundle is validated by the Build Module workflow (full build under `--locked-mode` + the #193 / Azure.Core repro guards, bounded by the csproj caps); those checks must be required status checks for auto-merge to wait on them.
- **Clarified `Microsoft.Extensions.*` tracking scope.** Recorded a `trackingScope` note on the blocked entries: Az.Resources (the observed #193 trigger) is not in `monitoredModules`, so its own copy is not inventoried; these assemblies are surfaced via the monitored Az.Accounts / Microsoft.Graph.Authentication that also bundle them.

## [2.1.1] - 2026-05-31

> Addresses the Codex review of 2.1.0. Repo-side hardening of the drift gate and dependency tooling — **no change to the published module bundle**.

### Fixed

- **Drift gate halts the candidate pipeline.** When the scheduled Upstream-Compatibility run detects a changed conflict surface, it now skips candidate-update generation and the automated dependency PR (flagging for human re-adjudication) instead of advancing preload changes against a stale baseline.
- **`maximumPackageVersion` caps are preserved.** A capped `minorPatchFloat` preload entry is now written as an exact `[x.y.z]` pinned at the cap, instead of an unbounded `N.*` that would let restore resolve above the maximum.
- **Versions-aware drift fingerprint.** The fingerprint is computed by `New-DLLPickleConflictMatrix` from each conflicting assembly's name **and** versions, so a within-major version move on a still-conflicting assembly is detected — not just name-set changes. (ALC-ownership drift remains the runtime-probe / maintainer tier.)
- **Drift gate runs on dependency PRs.** Dependabot lock/csproj bumps now recompute the conflict surface and block auto-merge if it drifted from the baseline, instead of the gate only running on the scheduled job.
- **Blocked `Microsoft.Extensions.*` transitives are tracked.** They are added to `trackedAssemblies` so the inventory/automation surfaces them; the drift baseline is recomputed accordingly.

## [2.1.0] - 2026-05-31

> The bundled assembly versions are **unchanged** from 2.0.2 (the floating ranges resolve to the same MSAL 4.84.1 / NativeInterop 0.20.6 — the current latest within their majors). This release is about **how dependencies are managed and validated going forward**, not a runtime change.

### Changed

- The MSAL/broker dependency pins are now **major-locked floating** (`Microsoft.Identity.Client` and friends `[4.84.1]` → `4.*`, `NativeInterop` `[0.20.6]` → `0.*`), so Dependabot manages minor/patch updates within the major (gated by the upstream-compatibility checks); major bumps remain a manual, reviewed edit.

### Added

- A **conflict-surface drift gate** in the Upstream-Compatibility workflow: it builds the cross-module conflict matrix, compares its fingerprint to a recorded baseline in `build/dependency-policy.json`, and opens an issue when the surface changes so the preload decision is re-adjudicated.
- New analysis tooling under `tools/` — `New-DLLPickleConflictMatrix`, `Compare-DLLPickleConflictMatrix`, and `Get-DLLPickleRuntimeAssemblySnapshot` (runtime AssemblyLoadContext probe) — plus unit tests.
- `docs/Architecture.md` — a durable, agent-oriented architecture blueprint (runtime/ALC model, preload/block taxonomy, invariants and their enforcing gates, source-of-truth map, and a Windows PowerShell 5.1 / net48 re-introduction checklist).

### Fixed

- The Release-and-Publish workflow now also triggers on `src/DLLPickle.Build/**` and `build/**` changes; previously a dependency-only change (like the 2.0.2 fix) would not auto-trigger a release on merge.

### Internal

- `build/dependency-policy.json` records the full, evidence-backed preload/block classification for every tracked assembly (Azure SDK stack and the `Microsoft.Extensions.*` transitives are `block`; the MSAL + IdentityModel stack is `preload`), the four-module target scenario, and the drift baseline. Documents the runtime finding that both Az.Accounts and Microsoft.Graph.Authentication now self-isolate their Azure SDK stack in private ALCs.

## [2.0.2] - 2026-05-31

### Fixed

- `Import-Module Az.Resources` (and other Az.* modules) failing with `Could not load file or assembly 'Microsoft.Extensions.DependencyInjection.Abstractions, Version=8.0.0.0 ...'. Assembly with same name is already loaded` after `Import-DPLibrary` (#193). DLLPickle was preloading the `Microsoft.Extensions.DependencyInjection.Abstractions` and `Microsoft.Extensions.Logging.Abstractions` BCL transitives (pulled by `Microsoft.IdentityModel.Tokens`) into the default load context, where they collided with the copies Az modules bundle. `Microsoft.IdentityModel.Tokens` still loads correctly without them preloaded.

### Removed

- `Microsoft.Extensions.DependencyInjection.Abstractions` and `Microsoft.Extensions.Logging.Abstractions` from the bundled preload set (via `ExcludeAssets="runtime"`). They are incidental transitives, not part of DLLPickle's identity-coordination purpose, and PowerShell does not host-provide them — so preloading DLLPickle's own copies only caused conflicts with consuming modules. The service modules that need them supply them at runtime.

## [2.0.1] - 2026-05-31

### Fixed

- `Connect-AzAccount` failing with `Method not found: '...Azure.Identity.InteractiveBrowserCredential.AuthenticateAsync(Azure.Core.TokenRequestContext, ...)'` after `Import-DPLibrary`. Az.Accounts 5.x isolates its Azure SDK stack in a private `AssemblyLoadContext`; preloading `Azure.Core` into the default load context split the identity of `Azure.Core.TokenRequestContext` across load contexts and broke Az's credential method binding. The `Azure.Core` preload was originally scoped to Windows PowerShell (net48) in #183 and was unintentionally promoted to the net8.0 preload during the 2.0.0 net48-removal refactor.

### Removed

- `Azure.Core` (and its `System.ClientModel` / `System.Memory.Data` / `Microsoft.Bcl.AsyncInterfaces` subgraph) from the bundled net8.0 preload set. Microsoft Graph, Exchange Online, and Teams resolve a compatible `Azure.Core` themselves on .NET 8, so the preload is unnecessary for them. Removing the dependency also retires the `Azure.Core` 1.50.0 cap, which existed only to keep that subgraph on the .NET 8 BCL.

### Internal

- Move `Azure.Core` to a report-only entry in `build/dependency-policy.json` and remove the now-moot Dependabot `Azure.Core` ignore.
- Rebase the #156 reproduction tests onto the still-active MSAL broker contract and add a regression guard asserting `Azure.Core` is not preloaded on the net8.0 profile.

## [2.0.0] - 2026-05-30

> **Breaking change:** DLLPickle 2.0 requires **PowerShell 7.4 or later** (running on .NET 8). Windows PowerShell 5.1 and .NET Framework 4.8 are not  supported yet on this major version.

### Added

- Deterministic dependency-aware DLL load ordering and scoped local assembly resolution fallback in `Import-DPLibrary` to reduce transient first-pass assembly load failures.
- PowerShell 7.4+ runtime baseline and net8.0-only dependency pipeline.

### Changed

- Replace manual DLL priority ordering in `Import-DPLibrary` with dependency-graph-based ordering and deterministic alphabetical fallback for unresolved graph nodes.
- Make runtime assembly detection lazy in `Import-DPLibrary` to avoid unnecessary work during import.
- Update `Import-DPLibrary` help to document load-order behavior and troubleshooting guidance for the PowerShell 7.4+ baseline.
- Simplify the build/test/workflow matrix and module metadata to remove Desktop/.NET Framework compatibility paths.

### Fixed

- Cap `Azure.Core` at 1.50.0 to keep the bundled dependency graph on the .NET 8 BCL. Azure.Core 1.51.0+ takes a dependency on the .NET 10 BCL (`System.Text.Json` / `System.Diagnostics.DiagnosticSource` / `Microsoft.Bcl.AsyncInterfaces` 10.x), which fails to load under PowerShell 7.4 (.NET 8).
- Harden module output refresh during builds so in-use binaries do not immediately break the prepare-and-validate workflow.

### Removed

- **Windows PowerShell 5.1 and .NET Framework (net48) support** — including the associated dependencies, conditional branching, validation tasks, and CI workflow paths.

### Dependencies

- Update `Microsoft.Identity.Client`, `Microsoft.Identity.Client.Broker`, and `Microsoft.Identity.Client.Extensions.Msal` to 4.84.1, and `Microsoft.Identity.Client.NativeInterop` to 0.20.6.
- Pin `Azure.Core` to 1.50.0 (capped for the PowerShell 7.4 / .NET 8 baseline — see Fixed).
- Refresh upstream compatibility dependency pins.

### Internal

- Move releases to a tag-driven versioning pipeline: the published version is derived from the Git tag and stamped into the build artifact, nothing is committed to `main`, and a failed release rolls back by deleting only the tag and GitHub release.
- Pin the .NET SDK to 8.0.x via `global.json` and install it explicitly in the build workflow.
- Harden the Dependabot auto-approve workflow (least-privilege GitHub App token, Dependabot-scoped secrets), group and schedule NuGet updates, and ignore `Azure.Core` updates that would cross the .NET 8 baseline.
- Remove the release GitHub App from the branch-protection bypass list.

## [1.3.1] - 2026-05-08

### Added

- Base profile preload helper supporting `Import-DPBaseProfile`.

### Fixed

- Surface base profile preload errors instead of failing silently.

### Dependencies

- Bump `Azure.Core` from 1.51.1 to 1.55.0 (#185).

## [1.3.0] - 2026-05-06

### Fixed

- Resolve a Microsoft Graph / `Azure.Core` assembly preload conflict (#183).

### Internal

- Improve the Dependabot workflow and add supporting documentation (#178); update the GitHub App token action and its identifier (#176).

## [1.2.0] - 2026-04-12

### Added

- Bundle MSAL (`Microsoft.Identity.Client`) packages and update the .NET restore strategy (#170).

### Changed

- Refine project documentation (#167).

### Security

- Workflow hardening: move permissions to the job level and add the `security-events` permission (#171); cross-platform security and validation improvements (#166).

## [1.1.2] - 2026-03-23

### Fixed

- Fix library import on Windows PowerShell 5.1 (#165), reverting the 1.1.1 `Resolve-DPDLLLoadOrder` refactor (#163) that introduced the regression.

## [1.1.1] - 2026-03-15

### Changed

- Streamline conditional logic in `Resolve-DPDLLLoadOrder` (#160). _(Reverted in 1.1.2 — it caused a Windows PowerShell 5.1 import regression.)_

## [1.1.0] - 2026-03-15

### Added

- Windows PowerShell 5.1 compatibility handling for `Import-DPLibrary` (#157).

## [1.0.0] - 2026-03-09

First stable release.

### Changed

- Documentation updates (#155).

## [0.19.0] - 2026-03-09

### Added

- Implement DLL Pickle settings functionality for configuration management
- Enhanced metadata handling in module operations

### Changed

- Removed `SkipProblematicAssemblies` parameter in favor of settings-based configuration
- Workflow hardening improvements including daily Dependabot runs and pinned GitHub app token

## [0.18.0] - 2026-03-03

### Added

- Retry logic for handling module dependencies in `Import-DPLibrary`

### Changed

- Updated `Import-DPLibrary` function with improved dependency handling and resilience

### Fixed

- Pinned checkout action to SHA of v4.2.2 for improved security

## [0.17.0] - 2026-02-23

### Fixed

- Added version sync step to module release workflow to prevent version mismatch issues

## [0.16.0] - 2026-02-22

### Changed

- CI/CD workflow and supply chain improvements for better build reliability

## [0.15.0] - 2026-02-16

### Added

- Binary files now included in module path for improved .NET assembly management

### Changed

- Enhanced Codacy workflow to support multiple analysis tools with unique SARIF outputs
- Updated documentation in README and Roadmap

## [0.10.2] - 2026-02-13

### Fixed

- Fixed module path variable in publish script
- Corrected path to publish script in release workflow

## [0.10.1] - 2026-02-13

### Changed

- Commented out local development imports in PSM1 for cleaner module loading

### Fixed

- Updated workflow permissions to enable GitHub release creation

## [0.10.0] - 2026-02-13

### Changed

- Transitioned to automated release workflow with improved version management

## [0.9.0]

This release contains major refactoring that brings it very close to a true 1.0 release!

### Changed

- Updates to multiple packaged DLLs since the last release.
- Replace `packages.json` with true dependency tracking in `DLLPickle.csproj` and `packages.lock.json`.
- Refactor the structure of the project to separate module source, dependency tracking, build artifacts, and build script.
- Replace manually codified dependency update workflow with Dependabot workflow(s).
- Improve the structural resiliency of the build script and build workflow.
- Improve repository configuration and project metadata file quality.
- Refactor and harden the dev container and docker container.

### Added

- Add proper support for TFM (target framework moniker) handling based on the PowerShell edition being used by the host.
- Add full support for Windows PowerShell 5.1 (.net48) and PowerShell 7.4+ (.net8).
- Add .NET restore, build, and test tasks to the project.

### Security

- Harden workflows with least privilege permissions and token configuration.
- Implement GitHub app for Dependabot updates that require automatic approval and merging.

## [0.2.7]

### Added

Microsoft.IdentityModel.Logging: 0.0.0 → 8.14.0; Microsoft.IdentityModel.Tokens: 0.0.0 → 8.14.0

This release includes new packages related to the Microsoft Identity libraries.

Full Changelog: [v0.2.6...v0.2.7](https://github.com/SamErde/DLLPickle/compare/v0.2.6...v0.2.7)

## [0.2.6]

### Added

Microsoft.Identity.Abstractions: 0.0.0 → 9.5.0
Microsoft.IdentityModel.Abstractions: 0.0.0 → 8.14.0
Microsoft.IdentityModel.JsonWebTokens: 0.0.0 → 8.14.0
System.IdentityModel.Tokens.Jwt: 0.0.0 → 8.14.0

This release includes new packages related to the Microsoft Identity libraries.

Full Changelog: [v0.2.5...v0.2.6](https://github.com/SamErde/DLLPickle/compare/v0.2.5...v0.2.6)

- Initial release.

[Unreleased]: https://github.com/SamErde/DLLPickle/compare/v2.2.2...HEAD
[2.2.2]: https://github.com/SamErde/DLLPickle/tag/v2.2.2
[2.2.1]: https://github.com/SamErde/DLLPickle/tag/v2.2.1
[2.2.0]: https://github.com/SamErde/DLLPickle/tag/v2.2.0
[2.1.2]: https://github.com/SamErde/DLLPickle/tag/v2.1.2
[2.1.1]: https://github.com/SamErde/DLLPickle/tag/v2.1.1
[2.1.0]: https://github.com/SamErde/DLLPickle/tag/v2.1.0
[2.0.2]: https://github.com/SamErde/DLLPickle/tag/v2.0.2
[2.0.1]: https://github.com/SamErde/DLLPickle/tag/v2.0.1
[2.0.0]: https://github.com/SamErde/DLLPickle/tag/v2.0.0
[1.3.1]: https://github.com/SamErde/DLLPickle/tag/v1.3.1
[1.3.0]: https://github.com/SamErde/DLLPickle/tag/v1.3.0
[1.2.0]: https://github.com/SamErde/DLLPickle/tag/v1.2.0
[1.1.2]: https://github.com/SamErde/DLLPickle/tag/v1.1.2
[1.1.1]: https://github.com/SamErde/DLLPickle/tag/v1.1.1
[1.1.0]: https://github.com/SamErde/DLLPickle/tag/v1.1.0
[1.0.0]: https://github.com/SamErde/DLLPickle/tag/v1.0.0
[0.19.0]: https://github.com/SamErde/DLLPickle/tag/v0.19.0
[0.18.0]: https://github.com/SamErde/DLLPickle/tag/v0.18.0
[0.17.0]: https://github.com/SamErde/DLLPickle/tag/v0.17.0
[0.16.0]: https://github.com/SamErde/DLLPickle/tag/v0.16.0
[0.15.0]: https://github.com/SamErde/DLLPickle/tag/v0.15.0
[0.10.2]: https://github.com/SamErde/DLLPickle/tag/v0.10.2
[0.10.1]: https://github.com/SamErde/DLLPickle/tag/v0.10.1
[0.10.0]: https://github.com/SamErde/DLLPickle/tag/v0.10.0
[0.9.0]: https://github.com/SamErde/DLLPickle/tag/v0.9.0
[0.2.7]: https://github.com/SamErde/DLLPickle/tag/v0.2.7
[0.2.6]: https://github.com/SamErde/DLLPickle/tag/v0.2.6
