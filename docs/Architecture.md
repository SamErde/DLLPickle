<!-- markdownlint-disable MD013 MD024 -->
# DLLPickle Architecture Blueprint

> **Audience:** maintainers and **agentic workstreams**. This is the durable, living source of truth for how DLLPickle is built and why. Read it before changing the preload contract; update it after. For the point-in-time design rationale, see [the needs-analysis design spec](superpowers/specs/2026-05-31-dll-needs-analysis-design.md). For user-facing guidance, see [Deep-Dive.md](Deep-Dive.md) and [DEPENDENCIES.md](../DEPENDENCIES.md).

## 1. What DLLPickle does

A single PowerShell process can load only one assembly of a given identity at a time. When several Microsoft service modules each bundle a different version of the same dependency DLL, the first one loaded "wins" and the others can fail with type-load or missing-method errors. DLLPickle **preloads a curated set of identity-stack assemblies into the default `AssemblyLoadContext` (ALC) before those modules load**, so default-ALC consumers share one coherent version.

**Scope:** PowerShell 7.4+ on the `net8.0` runtime profile. Multi-TFM (net9.0/net10.0) is a deferred goal.

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

> **Windows PowerShell 5.1 caveat — no ALC.** Everything above depends on `AssemblyLoadContext`, which exists only on .NET (Core) 5+. **Windows PowerShell 5.1 runs on .NET Framework 4.8, which has no ALC**, so modules **cannot** self-isolate there — every dependency lands in one shared load context. If net48 / WinPS 5.1 support is ever re-added, the "modules manage the Azure SDK themselves" premise does **not** hold, and the Azure SDK stack (`Azure.Core`, `Azure.Identity`, `Azure.Identity.Broker`, `System.ClientModel`) would need to be **preloaded again — conditionally, per-TFM (net48 only)** — exactly as #183 originally did before the 2.0 refactor over-generalized it. In other words: the `block` verdicts in §3 are correct **because** the runtime is ALC-capable; they are not universal. See §9 for the full re-introduction checklist.

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
| `Azure.Core`, `Azure.Identity`, `Azure.Identity.Broker`, `System.ClientModel` | **block** | Az + Graph self-isolate these privately; preloading splits type identity (the `Connect-AzAccount` break). **ALC-capable runtimes only** — would flip to `preload` on net48 (see §2 caveat / §9). |
| `Microsoft.OData.Core`, `Microsoft.OData.Edm`, `Microsoft.Spatial` | **block** (report-only) | #174 — preloading breaks Az.Storage. |
| `Microsoft.Extensions.DependencyInjection.Abstractions`, `Microsoft.Extensions.Logging.Abstractions` | **block** | #193 — incidental `Microsoft.IdentityModel.Tokens` transitives, not host-provided. Preloading DLLPickle's own copies into the default ALC collided with the copies `Az.Resources` bundles (`assembly with same name is already loaded`). Excluded via `ExcludeAssets="runtime"` (shipped 2.0.2); `Microsoft.IdentityModel.Tokens` still loads without them. |

## 4. Component map (authoritative paths)

| Component | Path | Responsibility |
| --- | --- | --- |
| Module source | `src/DLLPickle/` | The shipped PowerShell module (public/private functions, manifest). |
| Loader | `src/DLLPickle/Public/Import-DPLibrary.ps1` | Loads the bundled `bin/net8.0` DLLs into the default ALC with dependency-ordered, retrying loads. |
| Build project | `src/DLLPickle.Build/DLLPickle.csproj` | **Realizes** the preload set — an assembly is preloaded **iff** it is a direct/transitive package reference here. `packages.lock.json` pins resolved versions. |
| Dependency policy | `build/dependency-policy.json` | **Decision source of truth** — per-assembly classification + evidence, monitored modules, target scenario, drift baseline. |
| Analysis tools | `tools/New-DLLPickleConflictMatrix.ps1`, `Compare-DLLPickleConflictMatrix.ps1`, `Get-DLLPickleRuntimeAssemblySnapshot.ps1`, `Get-DLLPickleUpstreamInventory.ps1`, `Update-DLLPickleDependencyPins.ps1` | Inventory upstream modules, build the conflict matrix, probe runtime ALC ownership, detect drift, and apply policy pins. |
| Build script | `build/DLLPickle.Build.ps1` | Invoke-Build tasks: Analyze, AnalyzeTests, AnalyzeTools, Test, RestoreDependencies, PrepareModuleOutput, IntegrationTest. |
| CI | `.github/workflows/` | Build/test matrix, Upstream-Compatibility (inventory + drift), Dependabot auto-approve, tag-driven Release-and-Publish. |
| Build output | `module/DLLPickle/` | **Generated** (gitignored). Rebuilt by `PrepareModuleOutput`; never hand-edited. |

## 5. Source-of-truth map

| Question | Authoritative source |
| --- | --- |
| Which assemblies are preloaded/blocked, and why? | `build/dependency-policy.json` (classification + evidence) |
| What is actually bundled? | `src/DLLPickle.Build/DLLPickle.csproj` (+ `packages.lock.json`) — must match the policy's `preload` set |
| How does the loader behave? | `src/DLLPickle/Public/Import-DPLibrary.ps1` |
| User guidance | `docs/Deep-Dive.md` |
| Dependency/update policy | `DEPENDENCIES.md`, `.github/dependabot.yml` |
| Design rationale (point-in-time) | `docs/superpowers/specs/2026-05-31-dll-needs-analysis-design.md` |
| Architecture (living) | this file |

## 6. Invariants (and the gate that enforces each)

- **No `block` assembly appears in `module/DLLPickle/bin/net8.0`.** → `tests/Integration/DLLPickle.IntegrationTest.Tests.ps1` (Azure.Core guard + the #193 `Microsoft.Extensions.*` guard; extend per newly-blocked assembly).
- **No preloaded assembly is loaded into two ALCs at once** in the four-module scenario. → integration ALC-split guard (runtime tier; maintainer-run with real modules).
- **The bundled `preload` set equals `dependency-policy.json`'s `preload` entries.** → planned realization guard (Task A6); until then, verified by review.
- **Runtime-provided BCL assemblies (e.g. `System.Text.Json`) are never preloaded.** → conflict-matrix `AlcOwner` = `Default`/runtime + the split guard.
- **Analysis tooling is correct.** → `tests/Unit/ConflictMatrix.Tests.ps1`, `tests/Unit/ConflictMatrixDrift.Tests.ps1`.
- **`tests/` and `tools/` stay analyzer-clean.** → `AnalyzeTests` / `AnalyzeTools` build tasks (throw on any finding; `tests/` excludes only `PSUseDeclaredVarsMoreThanAssignments`).

## 7. Validation gates

- **Unit + analyzer:** `Invoke-Build -Task Analyze,Test` (the PR-smoke gate). Must be green.
- **Issue reproduction + composition:** `Invoke-Build -Task IssueReproTest` (synthetic modules; deterministic).
- **Runtime adjudication — non-auth tier (CI-capable):** per-module ALC snapshots + the four-module import/composition smoke.
- **Runtime adjudication — auth tier (maintainer-run; future Stage 2b automatable via GitHub OIDC + Entra federated credential):** real `Connect-*` to a dev tenant. This is the sign-off for any change to the bundled set.
- **Publish trigger:** `Release-and-Publish` auto-runs **only on bundle-affecting paths** (`src/DLLPickle/**`, `src/DLLPickle.Build/DLLPickle.csproj`, `src/DLLPickle.Build/packages.lock.json`). CI-, policy-, docs-, test-, and tooling-only changes do **not** publish a new gallery version; `workflow_dispatch` is the deliberate-release escape hatch.
- **Dependency PRs (Dependabot):** the bumped *bundle* is validated by **Build Module** (full build under `--locked-mode` + the #193/Azure.Core repro guards), bounded by the csproj floating-with-cap constraints. The Upstream-Compatibility `pr-smoke` adds an **upstream conflict-surface freshness check** — explicitly *not* a bundle validation, since a self-bump does not move the upstream fingerprint. **Enforcement caveat:** these signals only block `gh pr merge --auto` if the build + Dependency Review checks are configured as **required status checks** (see §9).

## 8. Agent workstream conventions

When changing the preload contract, follow this loop:

1. **Inventory** the monitored modules (`Get-DLLPickleUpstreamInventory.ps1`).
2. **Build the conflict matrix** (`New-DLLPickleConflictMatrix.ps1`) to find candidates. It also emits the drift `Fingerprint` — a SHA-256 over each diverging assembly's name, sorted versions, **and** contributing-module set (`ShippedBy`) — which the Upstream-Compatibility gate compares to `baseline.conflictSurfaceFingerprint`. A version move *or* a change in which modules contribute to a conflict trips drift.
3. **Probe runtime ALC ownership** (`Get-DLLPickleRuntimeAssemblySnapshot.ps1`) — private-ALC ownership is a `block` *candidate*, not an automatic verdict.
4. **Adjudicate** with the runtime differential (does preloading help without breaking?). Record the verdict + evidence in `build/dependency-policy.json`.
5. **Realize** in `DLLPickle.csproj` (preload = bundled reference; block = excluded, incl. `ExcludeAssets` for blocked transitives), regenerate `packages.lock.json`.
6. **Validate** (non-auth gates always; auth tier for any bundled-set change).
7. **Update this blueprint** if the contract or invariants changed.

**Hard gates (non-negotiable):**

- A design must be approved before implementation (see the spec/plan workflow under `docs/superpowers/`).
- Changes to the **bundled set** are behavior-changing and require the auth-tier real-environment sign-off before merge (the 2.0.1 precedent). They are **not** auto-merged.
- Commit/push only when the maintainer asks.
- Never hand-edit `module/` (generated). Never weaken analyzer settings to silence a finding — fix the code or scope a justified suppression.

## 9. Known gaps / follow-ups

- **Required status checks.** The "Protect Main" ruleset enforces a PR (with review-thread resolution), Copilot review, and code quality, but historically had **no required *status* checks** — so `gh pr merge --auto` (Dependabot auto-approve) could complete before the build/drift/security checks passed. The gate workflows now **always report**: they trigger on every PR and a `changes`/`pr-changes` job skips the expensive work (skip == passing check) when no relevant paths changed, so they can be required without blocking docs-/CI-only PRs. Required set to configure on the ruleset: **`Build gate`** (the always-present aggregate for the matrix build — *not* the per-OS `Build and test module (…)` legs, which aren't created when the matrix job is skipped), **`Validate upstream compatibility tooling`** (the only PR job running the conflict-surface drift gate; omitting it lets a Dependabot PR auto-merge against a stale upstream fingerprint), and **`dependency-review`**. (The `Dependabot-Auto-Approve.yml` header already notes that `--auto` relies on the Dependency Review and build/test checks being configured as required status checks.)
- **`Az.Resources` is not in `monitoredModules`.** It is the observed #193 collision source, but its copy and future drift are **not** inventoried. Among monitored modules the `Microsoft.Extensions.*` transitives are observed only in `MicrosoftTeams` (a single shipper → not in the conflict surface), recorded as `trackingScope` on the blocked entries. Note #193 was a *bundle-vs-consumer* collision (DLLPickle's preloaded copy vs Az.Resources'), which the cross-module drift gate does not model — the regression guard is the integration test that keeps these transitives out of `bin`, not the matrix. Re-adjudicate manually if an Az.Resources change is suspected, or add it to `monitoredModules` to track it directly.
- **EXO/Teams ALC ownership** is not yet captured — a bare `Import-Module` doesn't eager-load their identity assemblies; the probe needs a representative `-ProbeCommand`.
- **Multi-TFM (net9.0/net10.0):** deferred; the methodology is TFM-parameterizable. net9.0/net10.0 are ALC-capable, so the `block` verdicts in §3 carry over to them. The `net8.0` bundle is confirmed to load on **PS 7.6 / .NET 10 via roll-forward** (Az.Resources import verified, no #193 regression) — a positive signal that multi-TFM is mostly a packaging exercise, not a behavioral one, on ALC-capable runtimes.
- **Re-introducing Windows PowerShell 5.1 / net48 (no ALC) — checklist if attempted:** because net48 has no `AssemblyLoadContext`, modules cannot self-isolate and the §3 `block` verdicts for the Azure SDK stack **invert**. Re-support would require: (1) multi-targeting the build to `net48` alongside `net8.0`; (2) **conditionally preloading the Azure SDK stack** (`Azure.Core` + `Azure.Identity`/`Broker` + `System.ClientModel`) for net48 only — pinned to the highest version the WinPS-supported module set agrees on, as #183 did; (3) restoring net48-specific dependency conditions in `DLLPickle.csproj` (e.g. `Condition="'$(TargetFramework)' == 'net48'"`); (4) restoring `CompatiblePSEditions = @('Core','Desktop')` and lowering the manifest `PowerShellVersion`, plus per-edition guards in `Import-DPLibrary`; (5) adding WinPS 5.1 to the CI test matrix and re-validating the #156/#165-class scenarios. The 2.0 refactor's mistake was applying the net48-era Azure.Core preload to net8 unconditionally — any re-introduction must keep it **strictly TFM-conditional**.
