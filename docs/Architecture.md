<!-- markdownlint-disable MD013 MD024 -->
# DLLPickle Architecture Blueprint

> **Audience:** maintainers and **agentic workstreams**. This is the durable, living source of truth for how DLLPickle is built and why. Read it before changing the preload contract; update it after. For the point-in-time design rationale, see [the needs-analysis design spec](superpowers/specs/2026-05-31-dll-needs-analysis-design.md). For user-facing guidance, see [Deep-Dive.md](Deep-Dive.md) and [DEPENDENCIES.md](DEPENDENCIES.md). Open maintenance traps and follow-ups are tracked in the [gap register](gaps/README.md).

## 1. What DLLPickle does

A single PowerShell process can load only one assembly of a given identity at a time. When several Microsoft service modules each bundle a different version of the same dependency DLL, the first one loaded "wins" and the others can fail with type-load or missing-method errors. DLLPickle **preloads a curated set of identity-stack assemblies into the default `AssemblyLoadContext` (ALC) before those modules load**, so default-ALC consumers share one coherent version.

### 1.1 Two tiers of functionality (and two different scopes)

DLLPickle ships two distinct kinds of capability, and they have **different runtime requirements**. Keeping them separate is a load-bearing design decision — conflating them is the most common way to misread the platform-support contract.

| Tier | Functions | Runtime requirement | What it does |
| --- | --- | --- | --- |
| **Preloader (automated fix)** | `Import-DPLibrary`, `Import-DPBaseProfile` | **PowerShell 7.4+ / .NET 8 (`net8.0`) only.** Depends on `AssemblyLoadContext`. | Loads the bundled `bin/net8.0` identity stack into the default ALC so later module loads reuse one coherent version. |
| **Inspection / diagnostics (manual aid)** | `Find-DLLInPSModulePath`, `Get-ModuleImportCandidate`, `Get-ModulesWithDependency`, `Get-ModulesWithVersionSortedIdentityClient`, `Test-DPLibraryConflict` (plus `Get-DPConfig`/`Set-DPConfig`) | **Cross-edition by design.** Deliberately also scans Windows PowerShell module roots. | Reports which installed module ships the newest identity DLL, so a user can decide which service to connect to first. |

The inspection tier exists to serve the project charter even for environments the preloader cannot reach: a **Windows PowerShell 5.1** user who hits the same version-conflict problem can run the inspection helpers to discover which module to load first and apply that **manual** "first-one-wins" workaround. See §1.2 for the precise platform-support contract.

### 1.2 Platform-support contract (decisions 1 & 2)

- **The automated preloader targets PowerShell 7.4+ on the `net8.0` runtime profile, and only that.** This is the supported way to *fix* the conflict automatically. It is enforced top to bottom: the manifest declares `PowerShellVersion = '7.4'` and `CompatiblePSEditions = @('Core')` (`src/DLLPickle/DLLPickle.psd1`); the build sets `RequiredPSVersion = '7.4.0'` (`build/DLLPickle.Settings.ps1`); the build project is single-target `<TargetFramework>net8.0</TargetFramework>` (`src/DLLPickle.Build/DLLPickle.csproj`); and `Import-DPLibrary` hard-codes `bin/net8.0` and throws if that directory is missing.
- **Windows PowerShell 5.1 / .NET Framework 4.8 is not a supported runtime for the preloader, by design.** The whole self-isolation reasoning in §2 depends on `AssemblyLoadContext`, which does not exist on .NET Framework 4.8. The module manifest is `Core`-only, so DLLPickle is not intended to be *imported and run* under Windows PowerShell 5.1.
- **The inspection/diagnostic tier is deliberately cross-edition.** Its functions are written to run on both editions and to scan the **Windows PowerShell module roots** (e.g. `Documents\WindowsPowerShell\Modules`) as well as the PowerShell 7 roots. This is intentional: a 5.1 user who needs a *manual* solution to the version-conflict problem can use these helpers to identify which module to connect to first. The supported way to do this today is to run the helpers **from a PowerShell 7.4+ session** while they inspect a machine's full set of installed modules (see the §10 note on the manifest edition declaration).
- **Multi-TFM (net9.0/net10.0) is a deferred goal**, not current scope (§10). The methodology is TFM-parameterizable; the runtime profile is single-target `net8.0` today.

## 2. The runtime model that drives every decision (read this first)

There are two kinds of assembly load context in play:

- **Default ALC** — the shared session context. Assemblies here have one identity for everyone.
- **Module-private ALCs** — some modules ship a bootstrap that loads *their* bundled dependencies into a **private** context so their versions never collide with the rest of the session.

**Key finding (runtime-measured, 2026-05-31):** the two heaviest Azure-SDK consumers now **self-isolate**:

| Module | Private ALC | Azure-SDK assemblies observed in it |
| --- | --- | --- |
| `Az.Accounts` (5.x) | `AzSharedAssemblyLoadContext` | `Azure.Core`, `Azure.Identity`, `Microsoft.Identity.Client.Extensions.Msal` |
| `Microsoft.Graph.Authentication` | `msgraph-load-context` | `Azure.Core`, `System.ClientModel` |

They even run **different `Azure.Core` versions side-by-side** (Az `1.50`, Graph `1.51.1`) in the same process without conflict — which is only possible *because* each is isolated.

**Consequences:**

1. DLLPickle must **not** preload the Azure SDK stack. Preloading `Azure.Core` into the default ALC splits the identity of `Azure.Core.TokenRequestContext` across the module's private ALC boundary and breaks `Connect-AzAccount` with a `MissingMethodException` (shipped fix: 2.0.1).
2. As more modules self-isolate, **DLLPickle's necessary scope shrinks** on PS 7.4+. Its remaining value is the **MSAL + IdentityModel** stack, which default-ALC consumers (Exchange Online, Teams) still share.

> **Windows PowerShell 5.1 caveat — no ALC.** Everything above depends on `AssemblyLoadContext`, which exists only on .NET (Core) 5+. **Windows PowerShell 5.1 runs on .NET Framework 4.8, which has no ALC**, so modules **cannot** self-isolate there — every dependency lands in one shared load context. This is *why* the preloader does not support 5.1 (§1.2): the "modules manage the Azure SDK themselves" premise does not hold. If net48 / WinPS 5.1 support is ever re-added, the Azure SDK stack (`Azure.Core`, `Azure.Identity`, `Azure.Identity.Broker`, `System.ClientModel`) would need to be **preloaded again — conditionally, per-TFM (net48 only)** — exactly as #183 originally did before the 2.0 refactor over-generalized it. In other words: the `block` verdicts in §3 are correct **because** the runtime is ALC-capable; they are not universal. See §10 for the full re-introduction checklist.

## 3. The preload decision model

Every tracked assembly is classified into exactly one of:

| Class | Meaning | What earns it |
| --- | --- | --- |
| **preload** | Bundled in DLLPickle; loaded early into the default ALC | Shared by ≥2 default-ALC consumers at diverging versions, **and** preloading one coherent version is observed to help without breaking a self-isolating module. |
| **block** | Never bundled | A self-isolating module owns it in a private ALC **and** preloading it is observed to break a scenario; or it is harmful to preload (OData/#174). |
| **ignore** | No action | No cross-module divergence, not harmful. |

**Static narrows, runtime decides.** ALC ownership (from the runtime probe) flags *candidates*; the with/without runtime differential makes the *call*. This distinction is load-bearing: `Microsoft.Identity.Client.Extensions.Msal` is owned by Az's private ALC (a block *candidate*), yet preloading the MSAL/IdentityModel stack is **proven safe and beneficial** (2.0.1 four-module connect), so it is `preload`. Only the Azure SDK stack is `block`.

**Current classification (net8.0 profile):**

| Assemblies | Class | Basis |
| --- | --- | --- |
| `Microsoft.Identity.Client` (+ `.Broker`, `.Extensions.Msal`, `.NativeInterop`); `Microsoft.IdentityModel.*`; `System.IdentityModel.Tokens.Jwt` | **preload** | Default-ALC consumers (EXO/Teams) + the #156 broker fix; 2.0.1-validated. |
| `Azure.Core`, `Azure.Identity`, `Azure.Identity.Broker`, `System.ClientModel` | **block** | Az + Graph self-isolate these privately; preloading splits type identity (the `Connect-AzAccount` break). **ALC-capable runtimes only** — would flip to `preload` on net48 (see §2 caveat / §10). |
| `Microsoft.OData.Core`, `Microsoft.OData.Edm`, `Microsoft.Spatial` | **block** (report-only) | #174 — preloading breaks Az.Storage. |
| `Microsoft.Extensions.DependencyInjection.Abstractions`, `Microsoft.Extensions.Logging.Abstractions` | **block** | #193 — incidental `Microsoft.IdentityModel.Tokens` transitives, not host-provided. Preloading DLLPickle's own copies into the default ALC collided with the copies `Az.Resources` bundles (`assembly with same name is already loaded`). Excluded via `ExcludeAssets="runtime"` (shipped 2.0.2); `Microsoft.IdentityModel.Tokens` still loads without them. |

## 4. Component map (authoritative paths)

| Component | Path | Responsibility |
| --- | --- | --- |
| Module source | `src/DLLPickle/` | The shipped PowerShell module (public/private functions, manifest). |
| Loader | `src/DLLPickle/Public/Import-DPLibrary.ps1` | Loads the bundled `bin/net8.0` DLLs into the default ALC with dependency-ordered, retrying loads. |
| Build project | `src/DLLPickle.Build/DLLPickle.csproj` | **Realizes** the policy — preload packages are direct runtime references; blocked transitives that need suppression are direct references with `ExcludeAssets="runtime"`. `packages.lock.json` pins resolved versions. |
| Dependency policy | `build/dependency-policy.json` | **Decision source of truth** — per-assembly classification + evidence, monitored modules, target scenario, drift baseline. |
| Analysis tools | `tools/Get-DLLPickleLoadedTrackedAssembly.ps1`, `New-DLLPickleConflictMatrix.ps1`, `Compare-DLLPickleConflictMatrix.ps1`, `Get-DLLPickleRuntimeAssemblySnapshot.ps1`, `Get-DLLPickleUpstreamInventory.ps1`, `Update-DLLPickleDependencyPins.ps1` | Inventory upstream modules, build the conflict matrix, probe runtime ALC ownership (filter sourced from `trackedAssemblies`), detect drift, and apply policy pins. |
| Build script | `build/DLLPickle.Build.ps1` | Invoke-Build tasks: Analyze, AnalyzeTests, AnalyzeTools, Test, RestoreDependencies, PrepareModuleOutput, IntegrationTest. |
| Release scripts | `.github/ci-scripts/Get-VersionBump.ps1` | Decides the semantic-version bump (and whether to release at all) from Conventional Commit prefixes since the last tag. The publish-decision logic behind §8.1. |
| CI | `.github/workflows/` | Build/test matrix, Upstream-Compatibility (inventory + drift), Dependabot auto-approve, path+commit-gated `Release-and-Publish`. |
| Build output | `module/DLLPickle/` | **Generated** (gitignored). Rebuilt by `PrepareModuleOutput`; never hand-edited. |
| Gap register | `docs/gaps/` | Repo-local status tracking for maintenance traps, automation gaps, deferred follow-ups, and agent-resolvable work items. |

## 5. Source-of-truth map

| Question | Authoritative source |
| --- | --- |
| Which assemblies are preloaded/blocked, and why? | `build/dependency-policy.json` (classification + evidence) |
| What is actually bundled? | `src/DLLPickle.Build/DLLPickle.csproj` (+ `packages.lock.json`) — must match the policy's `preload` set |
| How does the loader behave? | `src/DLLPickle/Public/Import-DPLibrary.ps1` |
| Which runtime/edition is supported? | §1.2 (platform-support contract) + `src/DLLPickle/DLLPickle.psd1` |
| When does a merged PR publish a new version? | §8.1 + `.github/workflows/Release-and-Publish.yml` + `.github/ci-scripts/Get-VersionBump.ps1` |
| How is a dependency update adjudicated and shipped? | §8.2 + `build/dependency-policy.json` + `.github/workflows/Dependabot-Auto-Approve.yml` |
| What maintenance traps and follow-up gaps remain? | `docs/gaps/README.md` and the individual `docs/gaps/GAP-*.md` files |
| User guidance | `docs/Deep-Dive.md` |
| Dependency/update policy | `docs/DEPENDENCIES.md`, `.github/dependabot.yml` |
| Design rationale (point-in-time) | `docs/superpowers/specs/2026-05-31-dll-needs-analysis-design.md` |
| Architecture (living) | this file |

## 6. Invariants (and the gate that enforces each)

- **No `block` assembly appears in `module/DLLPickle/bin/net8.0`.** → policy-driven `tests/Integration/DependencyPolicyRealization.Tests.ps1` plus scenario-specific guards in `tests/Integration/DLLPickle.IntegrationTest.Tests.ps1`.
- **No preloaded assembly is loaded into two ALCs at once** in the four-module scenario. → integration ALC-split guard (runtime tier; maintainer-run with real modules).
- **The bundled `preload` set equals `dependency-policy.json`'s `preload` entries.** → `tests/Integration/DependencyPolicyRealization.Tests.ps1`.
- **Runtime-provided BCL assemblies are never preloaded.** Some assemblies are platform-scoped: `System.Security.Cryptography.ProtectedData` is provided by PowerShell only on Windows; on Linux/macOS it is bundled (not excluded). See `build/dependency-policy.json` for platform-specific block scopes. → policy block classification + `tests/Integration/DependencyPolicyRealization.Tests.ps1` with platform-aware filtering.
- **Analysis tooling is correct.** → `tests/Unit/ConflictMatrix.Tests.ps1`, `tests/Unit/ConflictMatrixDrift.Tests.ps1`.
- **`tests/` and `tools/` stay analyzer-clean.** → `AnalyzeTests` / `AnalyzeTools` build tasks (throw on any finding; `tests/` excludes only `PSUseDeclaredVarsMoreThanAssignments`).

## 7. Validation gates

- **Unit + analyzer:** `Invoke-Build -Task Analyze,Test` (the PR-smoke gate). Must be green.
- **Issue reproduction + composition:** `Invoke-Build -Task IssueReproTest` (synthetic modules; deterministic).
- **Runtime adjudication — non-auth tier (CI-capable):** strict per-module ALC snapshots (module/probe failures are fatal) + the four-module import/composition smoke.
- **Runtime adjudication — auth tier (maintainer-run; future Stage 2b automatable via GitHub OIDC + Entra federated credential):** real `Connect-*` to a dev tenant. This is the sign-off for any change to the bundled set.
- **Publish trigger:** `Release-and-Publish` publishes a merged PR only when it passes **both** the bundle-affecting **path gate** and the Conventional-Commit **version gate** — see §8.1 for the full contract (including how a Dependabot `deps:` commit maps to a **minor** release). CI-, policy-, docs-, test-, and tooling-only changes do **not** publish a new gallery version; `workflow_dispatch` is the deliberate-release escape hatch.
- **Dependency PRs (Dependabot):** the bumped *bundle* is validated by **Build Module** (full build under `--locked-mode` + the #193/Azure.Core repro guards), bounded by the csproj floating-with-cap constraints. The Upstream-Compatibility `pr-smoke` adds an upstream-latest freshness check for policy/tooling changes, and the scheduled candidate flow performs live inventory, drift detection, TFM alignment, and candidate PR generation.

## 8. Release & dependency-update contract

This section is the source of truth for **when a merged change publishes a new PowerShell Gallery version** (decision 3) and **how a tracked-dependency release is adjudicated, tested, and shipped** (decision 4). It documents the **intended contract**; where today's automation does not yet fully implement it, the delta is recorded in §10. No behavior here is changed by simply updating this document.

### 8.1 What publishes a new version (decision 3)

The published artifact is the **module bundle**: the module source under `src/DLLPickle/**` and the bundled DLL set realized by `src/DLLPickle.Build/DLLPickle.csproj` + `packages.lock.json`. A change that alters that bundle should produce a new gallery version; CI-, policy-, docs-, test-, and tooling-only changes should not.

`Release-and-Publish` auto-publishes a merged PR **only when both gates pass**:

1. **Path gate** — the merge touches a bundle-affecting path: `src/DLLPickle/**`, `src/DLLPickle.Build/DLLPickle.csproj`, or `src/DLLPickle.Build/packages.lock.json` (the workflow `paths:` filter).
2. **Version gate** — `.github/ci-scripts/Get-VersionBump.ps1` finds a release-worthy Conventional Commit prefix among the commits since the last tag. Recognized prefixes:

   | Bump | Prefixes |
   | --- | --- |
   | **major** | `BREAKING CHANGE:`, `breaking:`, `major-release` |
   | **minor** | `feat:`, `minor:`, **`deps:`** (Dependabot's NuGet bumps — see §8.2) |
   | **patch** | `fix:`, `perf:`, `refactor:`, `security:`, `chore:` |

   Any other prefix (`docs:`, `style:`, `ci:`, …) yields `ShouldRelease = false` → **no publish**.

Versioning is **tag-driven**: the in-source manifest stays at the `0.0.0` placeholder, the Git tag `vX.Y.Z` is the source of truth, and the real version is stamped into the built artifact at publish time. A failed publish rolls back by deleting the tag and release; `main` is never committed to. `workflow_dispatch` is the deliberate-release escape hatch (e.g. to ship a packaging-logic change that does not move a bundle path).

> **Both gates matter for dependency PRs.** A Dependabot NuGet bump touches `DLLPickle.csproj` + `packages.lock.json` (path gate ✔) and its commit prefix is `deps:`, which `Get-VersionBump.ps1` recognizes as a **minor** release prefix (version gate ✔) — so an auto-merged minor/patch dependency bump publishes a **minor** module release. See §8.2 for the full lifecycle.

### 8.2 Tracked-dependency release lifecycle (decision 4)

A "tracked dependency" is one of the NuGet packages bundled into the preload set (the MSAL + IdentityModel families in `DLLPickle.csproj`; see §3). When a new release of one is detected — by Dependabot or the scheduled Upstream-Compatibility candidate flow — it is adjudicated by the **severity of the version jump**.

**Step 0 — TFM-alignment check (precondition for both paths).** Before any merge, confirm the new release aligns with the supported target framework moniker(s). "TFM-aligned" means **both**:

- **(a) Build-gate proof** — the project still restores under `--locked-mode` and builds + passes Pester/CI green on `net8.0` (the `Build gate` required check); **and**
- **(b) Explicit TFM inspection** — the package actually ships an assembly compatible with the supported TFM(s) (`net8.0`, or a `netstandard2.0` asset that loads on net8.0), rather than appearing to work only by luck of transitive resolution. Enforced by `tools/Test-DLLPickleTfmAlignment.ps1`, which inspects each preload package's `lib/<tfm>/` assets and runs fail-closed in the scheduled Upstream-Compatibility candidate flow.

A release that fails either half is not TFM-aligned and must not be merged on the automated path.

**Minor / patch release** → run Step 0 (TFM alignment) + Pester + CI, then **approve and merge with a detailed PR comment** recording what moved, the alignment evidence, and the conflict-surface result. Because identity-library bumps are the module's core deliverable, a minor/patch dependency bump produces a **minor** module release: Dependabot's `deps:` commit prefix is a recognized minor release prefix (§8.1), so an auto-merged bump fires the version gate on its own.

**Major release** → still **fully tested** (Pester + CI) and **verified for architecture alignment** (Step 0, plus a re-adjudication of the §3 preload/block classifications, since a major upstream jump can move the conflict surface), **but it lands as a draft PR with fully detailed notes** — never auto-merged and never auto-published. The notes should cover: the version delta and an upstream changelog / breaking-change summary, the TFM-alignment result, the Pester/CI outcome, and the conflict-surface / `dependency-policy.json` impact. A maintainer promotes the draft to ready and merges after review; the merge then publishes a **major** module release (carried as `breaking:`). This is implemented in `Dependabot-Auto-Approve.yml` (draft conversion + the structured-notes scaffold).

This mirrors the **hard gate** in §9: bundle-set changes are behavior-changing and require the auth-tier real-environment sign-off; they are not auto-merged blindly.

## 9. Agent workstream conventions

When changing the preload contract, follow this loop:

1. **Inventory** the monitored modules (`Get-DLLPickleUpstreamInventory.ps1`).
2. **Build and compare the conflict matrix** (`New-DLLPickleConflictMatrix.ps1`, then `Compare-DLLPickleConflictMatrix.ps1`) to find candidates and structured new/removed conflict, version, and contributor changes. The matrix also emits the drift `Fingerprint` — a SHA-256 over each diverging assembly's name, sorted versions, **and** contributing-module set (`ShippedBy`) — which the Upstream-Compatibility gate compares to `baseline.conflictSurfaceFingerprint`. Any structured change trips drift.
3. **Probe runtime ALC ownership** (`Get-DLLPickleRuntimeAssemblySnapshot.ps1`) — private-ALC ownership is a `block` *candidate*, not an automatic verdict.
4. **Adjudicate** with the runtime differential (does preloading help without breaking?). Record the verdict + evidence in `build/dependency-policy.json`.
5. **Realize** in `DLLPickle.csproj` (preload = bundled reference; block = excluded, incl. `ExcludeAssets` for blocked transitives), regenerate `packages.lock.json`.
6. **Validate** (non-auth gates always; auth tier for any bundled-set change).
7. **Update this blueprint** if the contract or invariants changed.
8. **Update the gap register** if the work opens, advances, resolves, blocks, supersedes, or intentionally accepts a tracked gap.

The baseline is a reproducible snapshot, not just a hash: `baseline.conflictSurface` stores every diverging assembly's `name`, sorted `versions`, and sorted `shippedBy` contributors alongside the module versions and fingerprint. Baseline refreshes must resolve all monitored versions before downloading any module, then prove that the stored rows recompute to the recorded fingerprint. Version-only moves are material drift and require adjudication; they do not pass silently.

Issue #239 was adjudicated on 2026-06-20 against Microsoft.Graph.Authentication 2.38.0, ExchangeOnlineManagement 3.10.0, Az.Storage 9.7.0, Az.Accounts 5.5.0, and MicrosoftTeams 7.8.0. The 16 conflict names and their contributors were unchanged. Strict probes of both configured import orders, with and without DLLPickle preloading, confirmed the existing preload/block classifications, so only the structured policy baseline changed; the bundled set and public module behavior did not.

**Hard gates (non-negotiable):**

- A design must be approved before implementation (see the spec/plan workflow under `docs/superpowers/`).
- Changes to the **bundled set** are behavior-changing and require the auth-tier real-environment sign-off before merge (the 2.0.1 precedent). They are **not** auto-merged.
- Commit/push only when the maintainer asks.
- Never hand-edit `module/` (generated). Never weaken analyzer settings to silence a finding — fix the code or scope a justified suppression.
- Do not mark a `docs/gaps/GAP-*.md` item `resolved` unless the implementation, tests or explicit test rationale, and documentation updates are complete and linked.

## 10. Known gaps / follow-ups

Detailed status for open and in-progress maintenance traps is tracked in the [gap register](gaps/README.md). Keep this section focused on architecture context; keep item state, checklists, and resolution links in the individual gap files.

| Gap | Status | Architecture note |
| --- | --- | --- |
| [GAP-002](gaps/GAP-002-az-resources-monitoring.md) | open | `Az.Resources` is the observed #193 collision source but is not currently in `monitoredModules`. |
| [GAP-003](gaps/GAP-003-exo-teams-probe-commands.md) | open | EXO/Teams ALC ownership is not yet captured because bare `Import-Module` does not eagerly load their identity assemblies. |
| [GAP-004](gaps/GAP-004-vscode-powershelleditorservices-host.md) | open | VS Code / PowerShellEditorServices host behavior is not yet modeled for issue #169. |
| [GAP-005](gaps/GAP-005-odata-conflict-expectation-management.md) | open | OData/#174 remains a known unsolved single-process incompatibility; guard expectations and user docs must stay current. |
| [GAP-006](gaps/GAP-006-release-dispatch-process-trap.md) | open | Packaging/release-logic changes may require deliberate `workflow_dispatch` because non-bundle paths do not auto-publish. |
| [GAP-007](gaps/GAP-007-required-status-check-ruleset-audit.md) | open | Required status-check ruleset configuration lives partly outside the repository and needs an auditable repo-local snapshot or procedure. |
| [GAP-008](gaps/GAP-008-manifest-export-drift.md) | open | Manifest `FunctionsToExport` should be guarded against drift from intended public functions. |

Historical/resolved notes remain below when they explain the current architecture or release contract.

- **Dependency bumps publish on their own — `deps → minor` (decisions 3 & 4).** *Resolved.* `Get-VersionBump.ps1` now recognizes Dependabot's NuGet `deps:` commit prefix (`.github/dependabot.yml`) as a **minor** release prefix (§8.1), so an auto-approved, squash-merged minor/patch dependency bump satisfies both the path gate and the version gate and publishes a **minor** module release. (A maintainer-promoted major dependency PR still carries `breaking:`.) Covered by `tests/Unit/GetVersionBump.Tests.ps1`.
- **Major-dependency draft-PR flow.** *Resolved.* `Dependabot-Auto-Approve.yml` converts a `version-update:semver-major` PR to a **draft** (`gh pr ready --undo`) and posts structured notes (version delta, NuGet package link, TFM-alignment references, Build gate / CI links, conflict-surface / `dependency-policy.json` impact, and a maintainer checklist) instead of the former generic comment. Majors remain excluded from `gh pr merge --auto`. Guarded by `tests/Unit/WorkflowGuardrails.Tests.ps1`.
- **Explicit TFM-alignment inspection (Step 0b).** *Resolved.* `tools/Test-DLLPickleTfmAlignment.ps1` inspects each preload package's `lib/<tfm>/` assets (or a legacy flat `lib/`) and asserts a net8.0/netstandard2.0-compatible asset is present, complementing the `Build gate` (Step 0a). It runs fail-closed in the scheduled Upstream-Compatibility candidate flow and is referenced from the major-dependency draft-PR notes. (`Get-DLLPickleUpstreamInventory.ps1` still captures only assembly `Name`/`Version`/`FullName`; the TFM assertion lives in the dedicated tool, which inspects the restored NuGet package layout.) Covered by `tests/Unit/TfmAlignment.Tests.ps1`.
- **Platform-support contract vs. manifest edition (decision 2).** The inspection/diagnostic tier is intended to be cross-edition (§1.2), but the manifest declares `CompatiblePSEditions = @('Core')`, so *importing* the module under Windows PowerShell 5.1 surfaces a compatibility warning. The supported manual-remediation path is therefore to run the inspection helpers **from a PowerShell 7.4+ session** while they scan the Windows PowerShell module roots — not to import DLLPickle under 5.1. Two code paths back this cross-edition intent on purpose: `Set-DPConfig` keeps a `$PSEdition`-aware encoding fallback, and `Find-DLLInPSModulePath` seeds the `WindowsPowerShell\Modules` roots (the all-users WinPS root only when actually running on 5.1). These are intentional, not residual dead code; recorded here so the contract is explicit.
- **Multi-TFM (net9.0/net10.0):** deferred; the methodology is TFM-parameterizable. net9.0/net10.0 are ALC-capable, so the `block` verdicts in §3 carry over to them. The `net8.0` bundle is confirmed to load on **PS 7.6 / .NET 10 via roll-forward** (Az.Resources import verified, no #193 regression) — a positive signal that multi-TFM is mostly a packaging exercise, not a behavioral one, on ALC-capable runtimes. When it lands, `dependency-policy.json` preload entries (currently a single `targetFramework: net8.0` each) and the `Update-DLLPickleDependencyPins` tooling will need a per-TFM representation; the `RestoreDependencies` task already parses both `TargetFramework` and `TargetFrameworks` in anticipation.
- **Re-introducing Windows PowerShell 5.1 / net48 (no ALC) — checklist if attempted:** because net48 has no `AssemblyLoadContext`, modules cannot self-isolate and the §3 `block` verdicts for the Azure SDK stack **invert**. Re-support would require: (1) multi-targeting the build to `net48` alongside `net8.0`; (2) **conditionally preloading the Azure SDK stack** (`Azure.Core` + `Azure.Identity`/`Broker` + `System.ClientModel`) for net48 only — pinned to the highest version the WinPS-supported module set agrees on, as #183 did; (3) restoring net48-specific dependency conditions in `DLLPickle.csproj` (e.g. `Condition="'$(TargetFramework)' == 'net48'"`); (4) restoring `CompatiblePSEditions = @('Core','Desktop')` and lowering the manifest `PowerShellVersion`, plus per-edition guards in `Import-DPLibrary`; (5) adding WinPS 5.1 to the CI test matrix and re-validating the #156/#165-class scenarios. The 2.0 refactor's mistake was applying the net48-era Azure.Core preload to net8 unconditionally — any re-introduction must keep it **strictly TFM-conditional**.
- **Planned feature enhancements (backlog).** Forward-looking ideas consolidated from the former root `Roadmap.md`; not yet scheduled, order is not guaranteed, and large dependency/platform shifts may change priority. (Released and in-progress work lives in [CHANGELOG.md](../CHANGELOG.md) — for example the `Microsoft.PowerShell.PlatyPS` help-generation migration is already tracked there, and the broader PowerShell 7.4+ compatibility and supply-chain hardening work is the ongoing subject of §3, §8, and §9.)
  - Import a specific version of MSAL (`Microsoft.Identity.Client`) on demand, rather than only the bundled pin.
  - Verify a package's hash/signature against the original source (e.g. NuGet) metadata before preload — a supply-chain integrity check extending the dependency-update work in §8.
  - Option to preload additional common (non-identity) assemblies beyond the default identity stack.
  - Option to inspect and preload only the newest version of relevant assemblies already present among the modules installed on the current system. The inspection side already exists (`Get-ModuleImportCandidate`, `Get-ModulesWithVersionSortedIdentityClient`, `Find-DLLInPSModulePath`); this would add the preload-from-installed mode.
  - A function to import a specific named set of assemblies — a targeted alternative to the full `Import-DPLibrary` set or `Import-DPBaseProfile`.
  - A function to clean up older installed DLLPickle module versions.
