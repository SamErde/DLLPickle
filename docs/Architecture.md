<!-- markdownlint-disable MD013 MD024 -->
# DLLPickle Architecture Blueprint

> **Audience:** maintainers and **agentic workstreams**. This is the durable, living source of truth for how DLLPickle is built and why. Read it before changing the preload contract; update it after. For the point-in-time design rationale, see [the needs-analysis design spec](superpowers/specs/2026-05-31-dll-needs-analysis-design.md). For user-facing guidance, see [Deep-Dive.md](Deep-Dive.md) and [DEPENDENCIES.md](DEPENDENCIES.md). Open maintenance traps and follow-ups are tracked in the [gap register](gaps/README.md).

## 1. What DLLPickle does

A single PowerShell process can load only one assembly of a given identity at a time. When several Microsoft service modules each bundle a different version of the same dependency DLL, the first one loaded "wins" and the others can fail with type-load or missing-method errors. DLLPickle **preloads a curated set of identity-stack assemblies into the default `AssemblyLoadContext` (ALC) before those modules load**, so default-ALC consumers share one coherent version.

### 1.1 Two tiers of functionality (and two different scopes)

DLLPickle ships two distinct kinds of capability, and they have **different runtime requirements**. Keeping them separate is a load-bearing design decision — conflating them is the most common way to misread the platform-support contract.

| Tier | Functions | Runtime requirement | What it does |
| --- | --- | --- | --- |
| **Preloader (automated fix)** | `Import-DPLibrary`, `Import-DPBaseProfile` | The exact Microsoft-supported profiles in the [generated support matrix](generated/Support-Matrix.md): PowerShell 7.4 / `net8.0`, 7.5 / `net9.0`, and 7.6 / `net10.0`. Depends on `AssemblyLoadContext`. | Selects the isolated bundle using both the PowerShell minor and CLR major, then loads it into the default ALC so later module loads reuse one coherent version. |
| **Inspection / diagnostics (manual aid)** | `Find-DLLInPSModulePath`, `Get-ModuleImportCandidate`, `Get-ModulesWithDependency`, `Get-ModulesWithVersionSortedIdentityClient`, `Test-DPLibraryConflict` (plus `Get-DPConfig`/`Set-DPConfig`) | **Cross-edition by design.** Deliberately also inspects Windows PowerShell module roots, including `Documents\WindowsPowerShell\Modules`; the all-users WinPS root is auto-seeded only when actually running on 5.1. | Reports which installed module ships the newest identity DLL, so a user can decide which service to connect to first. |

The inspection tier exists to serve the project charter even for environments the preloader cannot reach: a **Windows PowerShell 5.1** user who hits the same version-conflict problem can run the inspection helpers to discover which module to load first and apply that **manual** "first-one-wins" workaround. See §1.2 for the precise platform-support contract.

### 1.2 Platform-support contract (decisions 1 & 2)

- **The automated preloader supports exactly the declared PowerShell/CLR profiles, not a floating “7.4 or later” range.** `src/DLLPickle/SupportedRuntimeProfiles.json` is the shipped behavior map; `build/powershell-test-matrix.json` supplies exact servicing patches and lifecycle evidence for CI. The project targets `net8.0;net9.0;net10.0`, and `Get-DPRuntimeProfile` requires the PowerShell minor, CLR major, and target framework to agree before `Import-DPLibrary` loads the matching `bin/<tfm>` directory. Unknown, duplicate, malformed, or mismatched profiles fail closed.
- **Servicing patches and support-contract changes have different automation.** A newer patch within a declared line is checksum- and runtime-validated across the exact OS matrix, then published once on a fingerprint-derived automation branch. A new minor line, lifecycle-date change, impending retirement, or expired line opens or updates a deduplicated review issue; it never silently adds or removes a shipped TFM. Release publication fails closed while an expired line remains claimed.
- **Windows PowerShell 5.1 / .NET Framework 4.8 is not a supported runtime for the preloader, by design.** The whole self-isolation reasoning in §2 depends on `AssemblyLoadContext`, which does not exist on .NET Framework 4.8. The module manifest is `Core`-only, so DLLPickle is not intended to be *imported and run* under Windows PowerShell 5.1.
- **The inspection/diagnostic tier is deliberately cross-edition.** Its functions are written to run on both editions and to scan the **Windows PowerShell module roots** that the current session can identify (for example `Documents\WindowsPowerShell\Modules`, plus the all-users WinPS root when actually running on 5.1) as well as the PowerShell 7 roots. This is intentional: a 5.1 user who needs a *manual* solution to the version-conflict problem can use these helpers to identify which module to connect to first. The supported way to do this today is to run the helpers **from a declared supported PowerShell session** while they inspect a machine's installed modules, understanding that the all-users WinPS root is only auto-seeded when the helper itself runs on 5.1 (see the §10 note on the manifest edition declaration).
- **Multi-targeting is a shipped isolation boundary.** `net8.0`, `net9.0`, and `net10.0` have separate physical payload directories even when individual files currently hash identically. The package-composition gate rejects missing or extra profile directories and verifies that optional CI provisioning tooling is absent.

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
2. As more modules self-isolate, **DLLPickle's necessary scope shrinks** on the supported ALC-capable profiles. Its remaining value is the **MSAL + IdentityModel** stack, which default-ALC consumers (Exchange Online, Teams) still share.

> **Windows PowerShell 5.1 caveat — no ALC.** Everything above depends on `AssemblyLoadContext`, which exists only on .NET (Core) 5+. **Windows PowerShell 5.1 runs on .NET Framework 4.8, which has no ALC**, so modules **cannot** self-isolate there — every dependency lands in one shared load context. This is *why* the preloader does not support 5.1 (§1.2): the "modules manage the Azure SDK themselves" premise does not hold. If net48 / WinPS 5.1 support is ever re-added, the Azure SDK stack (`Azure.Core`, `Azure.Identity`, `Azure.Identity.Broker`, `System.ClientModel`) would need to be **preloaded again — conditionally, per-TFM (net48 only)** — exactly as #183 originally did before the 2.0 refactor over-generalized it. In other words: the `block` verdicts in §3 are correct **because** the runtime is ALC-capable; they are not universal. See §10 for the full re-introduction checklist.

## 3. The preload decision model

Every tracked assembly is classified into exactly one of:

| Class | Meaning | What earns it |
| --- | --- | --- |
| **preload** | Bundled in DLLPickle; loaded early into the default ALC | Shared by ≥2 default-ALC consumers at diverging versions, **and** preloading one coherent version is observed to help without breaking a self-isolating module. |
| **block** | Never preloaded on the policy scope; normally excluded from the bundle | A self-isolating module owns it in a private ALC and preloading it breaks a scenario, or the host already provides it. A platform-scoped runtime dependency may remain in the single universal artifact for other operating systems, but the loader must filter it on the blocked platform. |
| **ignore** | No action | No cross-module divergence, not harmful. |

**Static narrows, runtime decides.** ALC ownership (from the runtime probe) flags *candidates*; the with/without runtime differential makes the *call*. This distinction is load-bearing: `Microsoft.Identity.Client.Extensions.Msal` is owned by Az's private ALC (a block *candidate*), yet preloading the MSAL/IdentityModel stack is **proven safe and beneficial** (2.0.1 four-module connect), so it is `preload`. Only the Azure SDK stack is `block`.

**Current classification (all three ALC-capable profiles):**

| Assemblies | Class | Basis |
| --- | --- | --- |
| `Microsoft.Identity.Client` (+ `.Broker`, `.Extensions.Msal`, `.NativeInterop`); `Microsoft.IdentityModel.*`; `System.IdentityModel.Tokens.Jwt` | **preload** | Default-ALC consumers (EXO/Teams) + the #156 broker fix; 2.0.1-validated. |
| `Azure.Core`, `Azure.Identity`, `Azure.Identity.Broker`, `System.ClientModel` | **block** | Az + Graph self-isolate these privately; preloading splits type identity (the `Connect-AzAccount` break). **ALC-capable runtimes only** — would flip to `preload` on net48 (see §2 caveat / §10). |
| `Microsoft.OData.Core`, `Microsoft.OData.Edm`, `Microsoft.Spatial` | **block** (report-only) | #174 — preloading breaks Az.Storage. Any future change requires runtime re-adjudication in both import orders, not static package updates alone. |
| `Microsoft.Extensions.DependencyInjection.Abstractions`, `Microsoft.Extensions.Logging.Abstractions` | **block** | #193 — incidental `Microsoft.IdentityModel.Tokens` transitives, not host-provided. Preloading DLLPickle's own copies into the default ALC collided with the copies `Az.Resources` bundles (`assembly with same name is already loaded`). Excluded via `ExcludeAssets="runtime"` (shipped 2.0.2); `Microsoft.IdentityModel.Tokens` still loads without them. `Az.Resources` is now explicitly monitored so drift inventory sees that collision source directly. |

## 4. Component map (authoritative paths)

| Component | Path | Responsibility |
| --- | --- | --- |
| Module source | `src/DLLPickle/` | The shipped PowerShell module (public/private functions, manifest). |
| Runtime policy and loader | `src/DLLPickle/SupportedRuntimeProfiles.json`, `src/DLLPickle/Private/Get-DPRuntimeProfile.ps1`, `src/DLLPickle/Public/Import-DPLibrary.ps1` | Maps the running PowerShell/CLR pair to one exact TFM and loads that isolated bundle with dependency-ordered, retrying loads. |
| Build project | `src/DLLPickle.Build/DLLPickle.csproj` | **Realizes** the policy — preload packages are direct runtime references; blocked transitives that must never ship use `ExcludeAssets="runtime"`; platform-scoped host assemblies needed elsewhere remain in the universal payload and are filtered by `SupportedRuntimeProfiles.json`. `packages.lock.json` pins resolved versions. |
| Dependency policy | `build/dependency-policy.json` | **Decision source of truth** — per-profile and per-platform classifications, monitored modules, import orders, validation tiers, and conflict baselines. |
| Profile evidence | `build/profile-evidence/` | Durable normalized snapshots for each accepted PowerShell/TFM/OS/architecture cell. Policy baselines bind the committed snapshot path and content fingerprint. |
| Analysis tools | `tools/Get-DLLPickleLoadedTrackedAssembly.ps1`, `New-DLLPickleConflictMatrix.ps1`, `Compare-DLLPickleConflictMatrix.ps1`, `Get-DLLPickleRuntimeAssemblySnapshot.ps1`, `Get-DLLPickleUpstreamInventory.ps1`, `New-DLLPickleNormalizedProfileEvidence.ps1`, `Update-DLLPickleDependencyPins.ps1` | Inventory upstream modules, build the conflict matrix, normalize durable evidence, probe runtime ALC ownership (filter sourced from `trackedAssemblies`), detect drift, and apply policy pins. |
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
| What are the current exact patches and lifecycle dates? | `build/powershell-test-matrix.json` + [generated support matrix](generated/Support-Matrix.md) |
| When does a merged PR publish a new version? | §8.1 + `.github/workflows/Release-and-Publish.yml` + `.github/ci-scripts/Get-VersionBump.ps1` |
| How is a dependency update adjudicated and shipped? | §8.2 + `build/dependency-policy.json` + `.github/workflows/Dependabot-Auto-Approve.yml` |
| What maintenance traps and follow-up gaps remain? | `docs/gaps/README.md` and the individual `docs/gaps/GAP-*.md` files |
| User guidance | `docs/Deep-Dive.md` |
| Dependency/update policy | `docs/DEPENDENCIES.md`, `.github/dependabot.yml` |
| Design rationale (point-in-time) | `docs/superpowers/specs/2026-05-31-dll-needs-analysis-design.md` |
| Architecture (living) | this file |

## 6. Invariants (and the gate that enforces each)

- **No `block` assembly appears in any supported TFM payload.** → policy-driven `tests/Integration/DependencyPolicyRealization.Tests.ps1` plus scenario-specific guards in `tests/Integration/DLLPickle.IntegrationTest.Tests.ps1`.
- **No preloaded assembly is loaded into two ALCs at once** in the four-module scenario. → integration ALC-split guard (runtime tier; maintainer-run with real modules).
- **The bundled `preload` set equals `dependency-policy.json`'s `preload` entries.** → `tests/Integration/DependencyPolicyRealization.Tests.ps1`.
- **Runtime-provided BCL assemblies are never preloaded.** `System.Security.Cryptography.ProtectedData` is provided by PowerShell only on Windows, but the published module is one cross-platform artifact assembled on Windows. It is therefore bundled for Linux/macOS, while `SupportedRuntimeProfiles.json` makes the Windows loader skip the bundled copy. See `build/dependency-policy.json` for the platform-specific block scope. → policy realization + exact-runtime integration coverage.
- **Analysis tooling is correct.** → `tests/Unit/ConflictMatrix.Tests.ps1`, `tests/Unit/ConflictMatrixDrift.Tests.ps1`.
- **Only the three declared TFM directories ship, and multi-pwsh never ships.** → `tools/Test-DLLPicklePackageArtifact.ps1` + `tests/Unit/ArtifactPolicy.Tests.ps1`.
- **Material artifact growth requires review.** → `tools/New-DLLPickleArtifactSizeReport.ps1` against `build/artifact-size-baseline.json`. A captured baseline also fails strict validation until a maintainer sets `approvalStatus` to `accepted` with an approval timestamp; capture time is not approval.
- **`tests/` and `tools/` stay analyzer-clean.** → `AnalyzeTests` / `AnalyzeTools` build tasks (throw on any finding; `tests/` excludes only `PSUseDeclaredVarsMoreThanAssignments`).

## 7. Validation gates

- **Unit + analyzer:** `tools/Invoke-DLLPickleBuild.ps1 -Task Analyze,Test` imports the exact pinned tool versions in a fresh no-profile process. Must be green.
- **Issue reproduction + composition:** `Invoke-Build -Task IssueReproTest` (synthetic modules; deterministic).
- **Runtime adjudication — deterministic no-auth tier:** nine exact stock-host cells (three PowerShell/.NET/TFM profiles × Windows/Linux/macOS), strict per-module ALC snapshots, both relevant import orders, structured runtime identity, and fail-closed profile/platform baselines.
- **Runtime adjudication — authenticated read-only tier:** maintainer-approved credentials only. The exact unexecuted commands and status are generated in [Compatibility-Evidence.md](generated/Compatibility-Evidence.md); they are release gates and are never inferred from deterministic results. `Release-and-Publish` prefers a successful `Authenticated-Compatibility.yml` run for the exact reviewed candidate commit and one unexpired `authenticated-compatibility-evidence` artifact. Until that protected workflow and environment exist, a temporary manual record can authorize only release `3.0.0`, only for its exact bundle-source fingerprint, only after all fixed three-profile Windows read scenarios pass with zero writes, and for no more than 30 days. `Test-DLLPickleManualAuthenticatedEvidence.ps1` rejects any other release, bundle, profile set, skipped probe, expired record, missing maintainer acceptance, or credential-bearing evidence; absence of either valid route fails closed.
- **Publish trigger:** `Release-and-Publish` publishes a merged PR only when it passes **both** the bundle-affecting **path gate** and the Conventional-Commit **version gate** — see §8.1 for the full contract (including how a Dependabot `deps:` commit maps to a **minor** release). CI-, policy-, docs-, test-, and tooling-only changes do **not** publish a new gallery version; `workflow_dispatch` is the deliberate-release escape hatch.
- **Dependency PRs (Dependabot):** the bumped *bundle* is validated by **Build Module** (locked restore, all TFMs, exact runtime matrix, composition, size, and issue-repro guards). The Upstream-Compatibility gate records profile-aware selected assets, hashes, ALCs, import orders, deterministic probes, and conflict fingerprints. A conditional TFM pin, policy/classification edit, or material size increase routes to maintainer review.

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

- **(a) Build-gate proof** — the project still restores under `--locked-mode`, builds all three target frameworks, and passes Pester plus every exact runtime/OS cell (the stable `Build gate` required check); **and**
- **(b) Explicit TFM inspection** — NuGet's restored `project.assets.json` selects a managed asset for every preload package on `net8.0`, `net9.0`, and `net10.0`. Enforced by `tools/Test-DLLPickleTfmAlignment.ps1`; the report names each resolved graph and selected asset rather than approximating compatibility with a handwritten regex.

A release that fails either half is not TFM-aligned and must not be merged on the automated path.

**Minor / patch release** → run Step 0 (TFM alignment) + Pester + CI, then **approve and merge with a detailed PR comment** recording what moved, the alignment evidence, and the conflict-surface result. Because identity-library bumps are the module's core deliverable, a minor/patch dependency bump produces a **minor** module release: Dependabot's `deps:` commit prefix is a recognized minor release prefix (§8.1), so an auto-merged bump fires the version gate on its own.

**Major release** → still **fully tested** (Pester + CI) and **verified for architecture alignment** (Step 0, plus a re-adjudication of the §3 preload/block classifications), **but it lands as a draft PR with per-TFM resolved graphs, selected assets, assembly delta, conflict-surface delta, size delta, and scenario outcomes** — never auto-merged and never auto-published. A maintainer promotes the draft to ready and merges after review; the merge then publishes a **major** module release (carried as `breaking:`).

This mirrors the **hard gate** in §9: bundle-set changes are behavior-changing and require the auth-tier real-environment sign-off; they are not auto-merged blindly.

### 8.3 Manual release dispatch (maintainer runbook)

The path gate in §8.1 is deliberate: a merge only auto-publishes when it changes the **published bundle** (`src/DLLPickle/**`, `src/DLLPickle.Build/DLLPickle.csproj`, or `src/DLLPickle.Build/packages.lock.json`). This protects the gallery from docs/CI/test/tooling churn, but it creates a **process trap**: a change that is *about* releasing or packaging — yet does not touch a bundle path — will merge without ever publishing. A maintainer (or agent) can reasonably but wrongly assume "merged" means "shipped".

**Does this merge auto-publish?**

| Change | Auto-publishes? | Why |
| --- | --- | --- |
| Edit a public/private function under `src/DLLPickle/**` | ✅ Yes (with a release-worthy commit prefix) | Hits the path gate; the version gate fires on `feat:`/`fix:`/etc. |
| Dependabot NuGet bump (`DLLPickle.csproj` + `packages.lock.json`, `deps:` prefix) | ✅ Yes → **minor** | Path gate ✔ + `deps:` is a recognized minor prefix (§8.1/§8.2). |
| Edit `build/DLLPickle.Build.ps1` packaging/release logic | ❌ No | `build/**` is excluded from the `paths:` filter — bundle bytes are unchanged. |
| Edit `.github/workflows/Release-and-Publish.yml` | ❌ No | `.github/**` is excluded. |
| Edit `build/dependency-policy.json`, tests, tooling, or docs only | ❌ No | None of these change the shipped DLLs or module source. |
| Any bundle-path change whose commits are all `docs:`/`ci:`/`style:` | ❌ No | Path gate ✔ but the version gate finds no release-worthy prefix. |

**When `workflow_dispatch` is the correct tool.** Use the manual **Run workflow** button on `Release-and-Publish` (the deliberate-release escape hatch) when **all** of the following hold:

1. The change should ship a new gallery version, **and**
2. It does **not** move a bundle path (so the automatic path gate will never fire) — for example a packaging/release-logic fix in `build/DLLPickle.Build.ps1`, **or**
3. You need to re-release after a transient publish failure (the failed run rolls back by deleting the tag/release; `main` is never committed to), **or**
4. You are cutting a release whose bump type you want to set explicitly (`major`/`minor`/`patch`) rather than inferring from commit prefixes (`auto`).

**When *not* to use it.** Do not use `workflow_dispatch` to bypass the version gate for ordinary code changes — fix the commit prefix instead. Do not manually dispatch a release for docs/CI/test/tooling-only changes; by design they do not ship a new module version.

> **Agent guidance:** never report that a non-bundle change (build script, workflow, policy, tests, tooling, docs) has "shipped" or "published" simply because its PR merged. State that it merged and, if a release is intended, that a deliberate `workflow_dispatch` run is required. The path gate and version gate are guarded by `tests/Unit/WorkflowGuardrails.Tests.ps1`.

## 9. Agent workstream conventions

When changing the preload contract, follow this loop:

1. **Inventory** the monitored modules (`Get-DLLPickleUpstreamInventory.ps1`).
2. **Build and compare the conflict matrix in every exact runtime profile** (`New-DLLPickleConflictMatrix.ps1`, then `Compare-DLLPickleConflictMatrix.ps1`) to find candidates and structured new/removed conflict, version, contributor, and ALC-owner changes. The matrix emits a profile-keyed `Fingerprint`; `Test-DLLPickleProfileConflictBaseline.ps1` compares it only with the matching PowerShell line, TFM, platform, module-set, and import-order baseline under `runtimeProfiles[].baselines`. Missing, unaccepted, or changed profile evidence fails closed. The top-level `baseline` and each `legacyUnscopedBaseline` are retained only as historical #239/#273 evidence and are not authoritative for a supported profile.
3. **Probe runtime ALC ownership** (`Get-DLLPickleRuntimeAssemblySnapshot.ps1`) — private-ALC ownership is a `block` *candidate*, not an automatic verdict.
4. **Adjudicate** with the runtime differential (does preloading help without breaking?). Record the verdict + evidence in `build/dependency-policy.json`.
5. **Realize** in `DLLPickle.csproj` (preload = bundled reference; ordinary block = excluded; a platform-scoped block needed by another OS remains bundled and is filtered by the shipped runtime policy), regenerate `packages.lock.json`.
6. **Validate** (non-auth gates always; auth tier for any bundled-set change).
7. **Update this blueprint** if the contract or invariants changed.
8. **Update the gap register** if the work opens, advances, resolves, blocks, supersedes, or intentionally accepts a tracked gap.

Each accepted profile baseline is a reproducible snapshot, not just a hash. `New-DLLPickleNormalizedProfileEvidence.ps1` converts runner-specific paths to stable `upstream:`, `dllpickle:`, or exact-host `runtime:` asset identifiers and writes the selected module version, assembly name/version/hash/path, contributor, import order, operating system, architecture, and AssemblyLoadContext. Volatile run ID, URL, commit, timestamp, and observed OS description remain reviewable provenance but are excluded from the content fingerprint. Each `runtimeProfiles[].baselines` entry names the committed snapshot under `build/profile-evidence/` and its content fingerprint; the baseline gate recomputes that snapshot and requires current evidence to match it. Baseline refreshes resolve all monitored versions before downloading any module, then prove that the stored rows recompute to the recorded fingerprint. Version-only, contributor, selected-asset, or ALC-owner moves are material drift and require adjudication; they do not pass silently. `New-DLLPickleProfileEvidenceSummary.ps1` combines the nine comparisons into one stable finding marker so unchanged scheduled results can be deduplicated without falling back to the legacy global hash.

Issue #239 was adjudicated on 2026-06-20 against Microsoft.Graph.Authentication 2.38.0, ExchangeOnlineManagement 3.10.0, Az.Storage 9.7.0, Az.Accounts 5.5.0, and MicrosoftTeams 7.8.0. That snapshot remains useful historical context, but it predates the nine-profile evidence contract and cannot be carried forward as a current net8/net9/net10 or cross-platform verdict.

**Hard gates (non-negotiable):**

- A design must be approved before implementation (see the spec/plan workflow under `docs/superpowers/`).
- Changes to the **bundled set** are behavior-changing and require the auth-tier real-environment sign-off before merge (the 2.0.1 precedent). They are **not** auto-merged.
- Commit/push only when the maintainer asks.
- Never hand-edit `module/` (generated). Never weaken analyzer settings to silence a finding — fix the code or scope a justified suppression.
- Do not mark a `docs/gaps/GAP-*.md` item `resolved` unless the implementation, tests or explicit test rationale, and documentation updates are complete and linked.
- Do not resolve a pull-request review thread as a substitute for code, test, or documentation changes (see §9.1).

### 9.1 Review-thread maintenance workflow

The `Protect Main` ruleset expects review-thread resolution before merge (this is the conversation-resolution half of GAP-007's required-status posture). That gate is only meaningful if threads are resolved because the underlying concern was addressed — not to clear a merge blocker. This workflow is intentionally kept **separate** from GAP-007: GAP-007 audits the *ruleset configuration*; this section governs *human/agent behavior* on threads.

**Who may resolve a thread.** Prefer the reviewer who opened it. An author (human or agent) may resolve a thread only when the change that addresses it is committed and linked, or when the thread is non-actionable (answered question, acknowledged nit, or out-of-scope item tracked elsewhere).

**Resolve a thread only when one of these is true:**

1. The requested change is implemented and the resolving commit is referenced in a reply, **or**
2. The concern is answered with a substantive reply and the reviewer agrees (or explicitly deferred to author discretion), **or**
3. The item is out of scope and is captured as a `docs/gaps/GAP-*.md` entry or a linked issue, referenced in the reply.

**Do not:**

- Resolve a thread without a reply explaining how it was addressed.
- Bulk-resolve threads to unblock a merge.
- Resolve a thread by deleting or weakening the code, test, or doc it asked about.
- Treat thread resolution as equivalent to closing the work — if a thread maps to deferred work, open or update a gap and link it.

**Stale threads.** If a thread is stale because the surrounding code changed, reply with the superseding commit/PR and resolve. If it is stale because of an unmade decision, leave it open and request maintainer review rather than resolving silently.

**Agent guidance.** Agents must never resolve review threads autonomously to make a PR mergeable. An agent may *reply* to a thread describing the change it made and may resolve only under rule (1) above with the commit linked; otherwise it leaves the thread for maintainer action.

## 10. Known gaps / follow-ups

Detailed status for open and in-progress maintenance traps is tracked in the [gap register](gaps/README.md). Keep this section focused on architecture context; keep item state, checklists, and resolution links in the individual gap files.

| Gap | Status | Architecture note |
| --- | --- | --- |
| [GAP-002](gaps/GAP-002-az-resources-monitoring.md) | resolved | `Az.Resources` is now included in `monitoredModules`; policy tracking scope and dependency docs were updated with structural test coverage. |
| [GAP-003](gaps/GAP-003-exo-teams-probe-commands.md) | in-progress | Deterministic and authenticated read-only EXO/Teams probe commands are implemented and structurally tested; exact-profile CI evidence remains unaccepted. |
| [GAP-004](gaps/GAP-004-vscode-powershelleditorservices-host.md) | open | VS Code / PowerShellEditorServices host behavior is not yet modeled for issue #169. |
| [GAP-005](gaps/GAP-005-odata-conflict-expectation-management.md) | resolved | OData/#174 expectation management is explicit in known-conflict data, docs, and policy tests; changes require runtime re-adjudication. |
| [GAP-006](gaps/GAP-006-release-dispatch-process-trap.md) | resolved | The manual release dispatch runbook (§8.3) documents which changes auto-publish and when `workflow_dispatch` is required; guarded by `tests/Unit/WorkflowGuardrails.Tests.ps1`. |
| [GAP-007](gaps/GAP-007-required-status-check-ruleset-audit.md) | open | Required status-check ruleset configuration lives partly outside the repository and needs an auditable repo-local snapshot or procedure. |
| [GAP-008](gaps/GAP-008-manifest-export-drift.md) | open | Manifest `FunctionsToExport` should be guarded against drift from intended public functions. |
| [GAP-010](gaps/GAP-010-unresolved-review-thread-maintenance.md) | resolved | Review-thread maintenance workflow is documented in §9.1; kept separate from GAP-007 (configuration audit) by design. |
| [GAP-011](gaps/GAP-011-docs-implementation-drift.md) | resolved | Gap register status/index/resolution drift is guarded by `tests/Unit/GapRegister.Tests.ps1`; related-docs updates remain review-only. |

Historical/resolved notes remain below when they explain the current architecture or release contract.

- **Dependency bumps publish on their own — `deps → minor` (decisions 3 & 4).** *Resolved.* `Get-VersionBump.ps1` now recognizes Dependabot's NuGet `deps:` commit prefix (`.github/dependabot.yml`) as a **minor** release prefix (§8.1), so an auto-approved, squash-merged minor/patch dependency bump satisfies both the path gate and the version gate and publishes a **minor** module release. (A maintainer-promoted major dependency PR still carries `breaking:`.) Covered by `tests/Unit/GetVersionBump.Tests.ps1`.
- **Major-dependency draft-PR flow.** *Resolved.* `Dependabot-Auto-Approve.yml` converts a `version-update:semver-major` PR to a **draft** (`gh pr ready --undo`) and posts structured notes (version delta, NuGet package link, TFM-alignment references, Build gate / CI links, conflict-surface / `dependency-policy.json` impact, and a maintainer checklist) instead of the former generic comment. Majors remain excluded from `gh pr merge --auto`. Guarded by `tests/Unit/WorkflowGuardrails.Tests.ps1`.
- **Explicit TFM-alignment inspection (Step 0b).** *Resolved.* `tools/Test-DLLPickleTfmAlignment.ps1` reads NuGet's restored `project.assets.json` and verifies the selected compile/runtime assets for every preload package on `net8.0`, `net9.0`, and `net10.0`, complementing the exact-runtime `Build gate` (Step 0a). Covered by `tests/Unit/TfmAlignment.Tests.ps1`.
- **Platform-support contract vs. manifest edition (decision 2).** The inspection/diagnostic tier is intended to be cross-edition (§1.2), but the manifest declares `CompatiblePSEditions = @('Core')`, so *importing* the module under Windows PowerShell 5.1 surfaces a compatibility warning. The supported manual-remediation path is therefore to run the inspection helpers **from a declared supported PowerShell session** while they scan the Windows PowerShell module roots — not to import DLLPickle under 5.1. Two code paths back this cross-edition intent on purpose: `Set-DPConfig` keeps a `$PSEdition`-aware encoding fallback, and `Find-DLLInPSModulePath` seeds the `WindowsPowerShell\Modules` roots (the all-users WinPS root only when actually running on 5.1). These are intentional, not residual dead code; recorded here so the contract is explicit.
- **Multi-TFM support:** implemented. The build emits physically isolated `net8.0`, `net9.0`, and `net10.0` payloads; the loader selects them fail-closed from the PowerShell/CLR pair; dependency decisions use `targetFrameworks`; NuGet compatibility comes from `project.assets.json`; and the pin updater preserves common versions unless reviewed evidence introduces an existing conditional reference. The exact nine-cell runtime matrix remains the acceptance authority rather than roll-forward behavior.
- **Re-introducing Windows PowerShell 5.1 / net48 (no ALC) — checklist if attempted:** because net48 has no `AssemblyLoadContext`, modules cannot self-isolate and the §3 `block` verdicts for the Azure SDK stack **invert**. Re-support would require: (1) multi-targeting the build to `net48` alongside `net8.0`; (2) **conditionally preloading the Azure SDK stack** (`Azure.Core` + `Azure.Identity`/`Broker` + `System.ClientModel`) for net48 only — pinned to the highest version the WinPS-supported module set agrees on, as #183 did; (3) restoring net48-specific dependency conditions in `DLLPickle.csproj` (e.g. `Condition="'$(TargetFramework)' == 'net48'"`); (4) restoring `CompatiblePSEditions = @('Core','Desktop')` and lowering the manifest `PowerShellVersion`, plus per-edition guards in `Import-DPLibrary`; (5) adding WinPS 5.1 to the CI test matrix and re-validating the #156/#165-class scenarios. The 2.0 refactor's mistake was applying the net48-era Azure.Core preload to net8 unconditionally — any re-introduction must keep it **strictly TFM-conditional**.
- **Planned feature enhancements (backlog).** Forward-looking ideas consolidated from the former root `Roadmap.md`; not yet scheduled, order is not guaranteed, and large dependency/platform shifts may change priority. (Released and in-progress work lives in [CHANGELOG.md](../CHANGELOG.md) — for example the `Microsoft.PowerShell.PlatyPS` help-generation migration is already tracked there, and the broader supported-profile compatibility and supply-chain hardening work is the ongoing subject of §3, §8, and §9.)
  - Import a specific version of MSAL (`Microsoft.Identity.Client`) on demand, rather than only the bundled pin.
  - Verify a package's hash/signature against the original source (e.g. NuGet) metadata before preload — a supply-chain integrity check extending the dependency-update work in §8.
  - Option to preload additional common (non-identity) assemblies beyond the default identity stack.
  - Option to inspect and preload only the newest version of relevant assemblies already present among the modules installed on the current system. The inspection side already exists (`Get-ModuleImportCandidate`, `Get-ModulesWithVersionSortedIdentityClient`, `Find-DLLInPSModulePath`); this would add the preload-from-installed mode.
  - A function to import a specific named set of assemblies — a targeted alternative to the full `Import-DPLibrary` set or `Import-DPBaseProfile`.
  - A function to clean up older installed DLLPickle module versions.
