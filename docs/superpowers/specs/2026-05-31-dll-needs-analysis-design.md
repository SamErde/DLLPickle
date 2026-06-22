<!-- markdownlint-disable MD024 -->
# Design: Dependency / Preload-Set Needs Analysis (net8.0)

- **Status:** Draft (design approved in brainstorming; pending written-spec review)
- **Date:** 2026-05-31
- **Author:** Sam Erde (with AI assistance)
- **Scope:** PowerShell 7.4+ / `net8.0` profile only. Multi-TFM (net9.0/net10.0) is explicitly deferred.
- **Related:** Resolves the *class* of bug behind the Azure.Core/`Connect-AzAccount` fix (2.0.1) and targets issue #193. Issue #174 (OData) is out of scope (see "Deferred / out of scope").

## 1. Problem

DLLPickle resolves assembly-version conflicts that occur when multiple Microsoft service modules are used in one PowerShell session, by **preloading a curated set of assemblies into the default `AssemblyLoadContext` (ALC) before those modules load**. The preload set has historically been assembled by intuition and reactive fixes, which caused two failure modes:

1. **Over-preloading.** Bundling an assembly that a self-isolating module (e.g., Az.Accounts 5.x, which loads its Azure SDK stack into a private `AzSharedAssemblyLoadContext`) manages itself **splits that assembly's type identity across ALCs**. This is exactly what broke `Connect-AzAccount` (Azure.Core `TokenRequestContext` split → `MissingMethodException`), fixed in 2.0.1, and is the same mechanism behind #193 (`Microsoft.Extensions.DependencyInjection.Abstractions` vs Az.Resources).
2. **No principled basis.** Static version-matching is demonstrably insufficient — the ALC split is only observable at runtime — so decisions need runtime evidence, and there is no repeatable way to keep the set correct as upstream modules evolve.

This design establishes a **repeatable methodology + decision artifact** that determines which assemblies are *truly needed* in the preload set, grounded in real load behavior, and a **drift-detection gate** that keeps the decision valid as monitored modules (and our own Dependabot bumps) change over time.

## 2. Primary objective and key decisions

**Primary objective:** the four-module *simultaneous* scenario — `Az.Accounts` + `Microsoft.Graph.Authentication` + `ExchangeOnlineManagement` + `MicrosoftTeams` imported and connected in one session, in varying orders. The unit of analysis is each module's **transitive dependency closure**.

Decisions made during brainstorming (decision log):

| # | Decision | Rationale |
| --- | --- | --- |
| D1 | Deliverable = a **methodology + decision artifact** (not a full standalone tooling subsystem). | Highest-value, lowest-risk: get the decision logic right; prove it by hand once. |
| D2 | Evidence basis = **hybrid** — static narrows candidates, **runtime adjudicates**. | Static alone produced the Azure.Core mistake; pure-runtime over everything is expensive. |
| D3 | Phasing = **Stage 1 (baseline + decision) and Stage 2 (drift detection) now**; Stage 2b (auth automation) optional; Stage 3 (auto-derive set) deferred. | Stage 2 makes floating versions safe; Stage 3 needs the methodology proven first. |
| D4 | **No exact pins.** `preload` is realized as major-locked floating refs (`N.*`); **Dependabot** owns minor/patch (auto-merge gated by the upstream-compatibility checks); major bumps are manual. | Removes pin-maintenance burden; the Stage 2 gate is the safety net. |
| D5 | Build on the **existing** pipeline (`Get-DLLPickleUpstreamInventory.ps1`, `dependency-policy.json`, Upstream-Compatibility workflow) rather than a parallel subsystem. | Reuses maintained surfaces; one source of truth. |
| D6 | Produce a durable, **in-repo architectural blueprint** structured for agentic workstreams (separate from this dated design spec). | Tracking, validation, and future agent-driven maintenance. |
| D7 | **net8.0 only**; multi-TFM deferred. | #193/#174 do not require multi-TFM; keep scope focused. |

## 3. Architecture and data flow

Five single-purpose components; the first extends an existing tool, the rest are new and small.

```text
PSGallery (4 core modules)
        │
        ▼
[1] Inventory  ──────────────►  inventory.json
   (extend Get-DLLPickleUpstreamInventory.ps1)
   per-module transitive DLL closure + bundled-ALC hints
        │
        ▼
[2] Conflict-matrix builder  ─►  conflict-matrix.json
   assembly → { which modules ship it, versions, diverge?, ALC owner }
        │
        ▼
[3] Runtime probe  ───────────►  runtime-evidence.json
   (a) per-module isolation snapshot: loaded assemblies + their ALC
   (b) combined 4-module scenario (Invoke-DLLPickleScenario),
       with/without candidate preload set, multiple import orders
        │
        ▼
[4] Classification (human-adjudicated, recorded)
   each assembly → preload | block | ignore  + evidence
        │
        ├──►  dependency-policy.json   (decision + rationale: source of truth)
        └──►  DLLPickle.csproj          (realizes it: preload = bundled ref;
                                          block/ignore = not bundled)
        ▼
[5] Stage-2 drift gate  (in Upstream-Compatibility workflow)
   on monitored-module release OR Dependabot bump: re-run [1]+[2],
   diff vs recorded baseline, flag material change → fail check / open issue
```

**Principles:** static narrows, runtime decides (D2). The decision lives in two linked places — `dependency-policy.json` holds *what + why*; `DLLPickle.csproj` *realizes* it (an assembly is preloaded **iff** it is a direct/transitive package reference). The methodology can both **trim** the set (Azure.Core, #193's `M.E.DI.Abstractions`) and **add** to it. **ALC ownership is a first-class signal** throughout.

## 4. Classification taxonomy and decision artifact

| Class | Meaning | Decision rule (testable) |
| --- | --- | --- |
| **preload** | Bundle it; load it early | Loaded into the **default ALC** by ≥2 target modules at **diverging versions**, *and* the runtime probe shows preloading one coherent version **fixes/prevents** a failure in the 4-module scenario **without** breaking a self-isolating module. |
| **block** | Never bundle | Owned by a module's **private ALC** (e.g., `AzSharedAssemblyLoadContext`), *or* preloading it is observed to **break** a scenario. |
| **ignore** | No action | No cross-module version divergence (single consumer or all agree) and not harmful. |

**Operational definition of "needed":** an assembly is `preload` **iff** excluding it breaks a target scenario that including it fixes, *and* including it harms nothing. This is the with/without differential from the runtime probe — the test static data could never satisfy.

**Mapping onto the existing `dependency-policy.json`:**

- `preload` → `preload` entry with a **`versionPolicy`** (default: *minor/patch float, major-locked*; realized as `N.*` in the csproj). Replaces the retired `exactPins` + `maximumPackageVersion` shape (`maximumPackageVersion` survives only as a rare escape hatch for a known-bad-minor).
- `block` → `blockedPreloadAssemblies` (report-only; not bundled).
- `ignore` → tracked-but-unclassified, or simply untracked.

Array membership is the canonical denotation of class; each entry additionally records an explicit `classification` and an **`evidence`** object so the rationale travels with the decision:

```jsonc
{ "assemblyName": "Azure.Core", "classification": "block",
  "evidence": {
    "alcOwner": "AzSharedAssemblyLoadContext",
    "shippedBy": { "Az.Accounts": "1.50.0.0", "Microsoft.Graph.Authentication": "1.46.x" },
    "runtime": "preloading splits TokenRequestContext across ALCs; Connect-AzAccount MissingMethodException",
    "decidedOn": "2026-05-31" } }
```

Two new top-level keys: **`targetScenario`** (the 4 modules + the import/connect orders validated against) and **`baseline`** (recorded module versions + a conflict-matrix fingerprint that Stage 2 diffs against).

## 5. Runtime adjudication (component [3])

Two depths:

1. **Non-auth tier — CI-automatable.** Fresh process per case. (a) *Isolation snapshot:* import one target module alone; record every loaded assembly and its ALC → the ground-truth ALC-ownership map. (b) *Combined smoke:* import all four modules in several orders, with and without the candidate preload set; assert no load failures and **no preloaded assembly appears in two ALCs at once** (the structural signature of the Azure.Core break).
2. **Auth tier — maintainer-run (or automated via Stage 2b).** `Connect-*` to a tenant in the orders that matter; the only tier that catches auth-time-only failures. Until Stage 2b is set up, this is on the **pre-release checklist**.

## 6. Stage 2 — drift detection

The gate recomputes the conflict matrix and diffs it against the recorded `baseline`. It **flags (fails the check + opens an issue)** only on *material* drift:

- a **new** assembly enters the conflict surface (now shipped by ≥2 target modules at diverging versions) and is **unclassified**;
- a preloaded assembly's required version crosses its **major lock** (a target module now needs `N+1`);
- an **ALC-ownership change** (an assembly moves between default and a private ALC) — the Azure.Core-class signal.

> **Superseded by the version-aware drift gate (2026-06-01):** patch/minor moves no longer pass silently. The accepted fingerprint includes versions and contributing modules, so either kind of change fails closed for re-adjudication. `Compare-DLLPickleConflictMatrix.ps1` reports the same structured reasons.

**Two contexts:** scheduled (monitored-module releases) and **Dependabot bump PRs** (re-evaluate the bumped library against the 4 modules). The drift comparison is **bundled-version vs the 4 modules' expected versions**, not merely module-vs-module, so a bump that drifts from what the modules expect is caught.

**Residual risk (explicit):** the auth tier cannot run in CI without tenant credentials, so a minor bump could pass CI yet break a `Connect-*`. Bounded because: the worst class (Az private-ALC assemblies) is `block` and never bundled, so Dependabot never bumps it in our set; preloaded assemblies are default-ALC/shared, where bad minors tend to surface at import/non-auth time. The maintainer auth tier (or Stage 2b) is the backstop.

## 7. Stage 2b (optional) — secretless auth automation

Promotes the auth tier from maintainer-run to an environment-gated automated job using **GitHub OIDC + Microsoft Entra Workload Identity Federation (a federated credential)** — no stored secret/cert in GitHub, consistent with the org "no secrets in CI" rule. **Setup is a follow-up task owned by the maintainer** (Entra app, federated credential, role assignments, Key Vault); this spec does not implement it, and the methodology works without it.

Per-service feasibility (verified against Microsoft Learn, 2026-05-31):

- **Az.Accounts** — `azure/login` OIDC → fully secretless. Highest value (the original bug).
- **Microsoft.Graph** — `Connect-MgGraph -AccessToken` (or `-Identity`); exchange the federated token → secretless.
- **MicrosoftTeams** — app-only via certificate or access token; access-token path is secretless.
- **Exchange Online** — app-only is **certificate-based** (no OIDC/access-token path; `-ManagedIdentity` only on Azure-hosted compute). Mitigation: store the cert in **Azure Key Vault**, fetch at runtime via the federated SP. The one non-secretless wrinkle.

Abuse-prevention controls: dedicated dev-tenant app; federated credential scoped to `repo:SamErde/DLLPickle:environment:<env>` (Environment entity type; exact subject match, no pattern matching); a GitHub Environment with required reviewers + protected-branch restriction; auth job runs only on trusted triggers (post-merge / scheduled / `workflow_dispatch`), never fork PRs; **least-privilege read-only roles** (Az Reader on one empty RG; minimal Graph read scope; EXO View-Only; Teams minimal read); short-lived tokens; Conditional Access on workload identities if licensed.

## 8. Stage 1 deliverables (the first run produces)

1. **Baseline** — transitive-closure inventory of the 4 modules at current versions (net8/PS 7.4+), plus the conflict matrix and ALC-ownership map.
2. **Classified, evidence-backed decision** in `dependency-policy.json` (every tracked assembly → `preload | block | ignore` + evidence). Formalizes the Azure.Core `block`; produces the verdict on `Microsoft.Extensions.DependencyInjection.Abstractions` that **closes #193**.
3. **csproj realized to match** — surviving MSAL exact pins converted to floating `N.*`; anything newly `block` excluded from the bundle.
4. **In-repo architectural blueprint** (see §9).

## 9. In-repo architectural blueprint (agent-oriented)

A durable, living document — **`docs/Architecture.md`** — distinct from this dated design spec. The design spec is a point-in-time decision record; the blueprint is the **maintained source of truth** that agentic workstreams read before changing the project and validate against after.

Required structure:

- **Component map:** module source (`src/DLLPickle`), build project (`src/DLLPickle.Build`), the `Import-DPLibrary` loader, `dependency-policy.json`, the `tools/` inventory/analysis scripts, CI workflows, and the tag-driven release pipeline — each with its responsibility and authoritative file path.
- **Source-of-truth map:** which file is authoritative for what (e.g., preload decision = `dependency-policy.json`; realization = `DLLPickle.csproj`; user guidance = `docs/Deep-Dive.md`; dependency policy/automation = `docs/DEPENDENCIES.md`).
- **Invariants (machine-checkable where possible):** e.g., *no assembly classified `block` may appear in `module/DLLPickle/bin`*; *the preloaded set ⟺ `dependency-policy.json` `preload` entries*; *Az private-ALC-owned assemblies are never preloaded*; *runtime-provided BCL assemblies are never preloaded*. Each invariant links to the test/CI gate that enforces it.
- **Validation gates:** map each invariant to the test (`tests/`) or workflow check that verifies it, so an agent knows how to prove a change is safe.
- **Workstream conventions for agents:** the standard change loop (update policy → regenerate inventory/matrix → run runtime probe → realize in csproj → validate → update blueprint), the hard gates (design approval before implementation; commit/push only when asked), and where new decisions get recorded.

The blueprint is produced as part of Stage 1 implementation and updated by every subsequent workstream that changes the preload contract.

## 10. Testing

- **Unit** (mirrors `tests/Unit/DependencyAutomation.Tests.ps1`): conflict-matrix builder + classifier fed synthetic inventories → asserted matrix/classification; drift gate fed synthetic before/after inventories → asserted flag/no-flag.
- **Integration:** the non-auth runtime probe via `Invoke-DLLPickleScenario` (synthetic modules for deterministic CI; real modules for maintainer runs).
- **Regression guards:** keep the 2.0.1 "Azure.Core not preloaded" guard; add an equivalent guard per newly-blocked assembly.

## 11. Edge cases

- **Runtime-provided assemblies** (e.g., `System.Text.Json`, `System.Security.Cryptography.ProtectedData` — the "Already Loaded" entries): the .NET runtime owns them; detect the shared-framework load path in the ALC snapshot → never classify `preload`.
- **Blocking a *transitive*** (e.g., `M.E.DI.Abstractions`, pulled by `Microsoft.IdentityModel.Tokens`) is harder than a direct ref — requires `ExcludeAssets`/asset filtering in the csproj so the transitive DLL is not copied to `bin`.
- **Modules not installed** for the runtime tier → probe marks "not validated" rather than failing; CI leans on download-inventory + synthetic scenarios.
- **"Diverging versions" defined:** same assembly name, differing assembly `Version` among **default-ALC** consumers triggers a conflict *candidate*; runtime adjudicates whether preloading helps.
- **Floating + drift interaction:** the drift gate compares the bundled version against the 4 modules' expected versions (not only module-vs-module).

## 12. Deferred / out of scope

- **Multi-TFM (net9.0/net10.0).** The methodology is TFM-parameterizable; only net8.0 is executed now.
- **Stage 3 — auto-deriving the preload set** from inventory. Revisit after the methodology is proven by hand.
- **Issue #174 (OData).** Not a preload problem and not TFM-related: Az.Storage and ExchangeOnlineManagement need *major-incompatible* `Microsoft.OData.Core` in the same runtime. Resolution would require ALC-isolation or process isolation — a separate, harder effort. Documented workaround (process isolation) stands.

## 13. Open questions / assumptions

- **A1:** Live validation depends on the real modules being installed locally; the auth tier needs a tenant. Accepted (two-tier validation; Stage 2b optional).
- **A2:** The verdict on `M.E.DI.Abstractions` (block vs coherent-version preload) is determined by the first runtime adjudication, not pre-judged here; either way it must close #193.
- **A3:** `docs/Architecture.md` is the chosen blueprint location; adjust if a different path is preferred.

## 14. Session findings (runtime evidence — 2026-05-31)

Adjudication evidence gathered by running the new tooling against the real four modules. These update the design's assumptions:

- **Both Az and Graph now self-isolate.** `Az.Accounts` loads its Azure SDK stack into `AzSharedAssemblyLoadContext`; `Microsoft.Graph.Authentication` loads its into `msgraph-load-context`. They run **different `Azure.Core` versions side-by-side** (Az `1.50`, Graph `1.51.1`) without conflict. Graph self-isolating is new since #183.
- **Adjudicated verdicts (net8.0):** `block` the Azure SDK stack (`Azure.Core`, `Azure.Identity`, `Azure.Identity.Broker`, `System.ClientModel`); `preload` the MSAL + IdentityModel stack; `block` (report-only) the OData family (#174). The current 2.0.1 bundle already matches this, so recording it is not a behavior change.
- **Static narrows, runtime decides — confirmed.** `Microsoft.Identity.Client.Extensions.Msal` is owned by Az's private ALC (a `block` *candidate*) yet preloading the MSAL/IdentityModel stack is proven safe (2.0.1). Only the Azure SDK stack breaks when preloaded.
- **DLLPickle's scope shrinks on PS 7.4+.** As modules self-isolate, the only assemblies that still need a shared preload are MSAL/IdentityModel (for default-ALC consumers EXO/Teams + the #156 broker fix).
- **The `block` verdicts are ALC-conditional, not universal.** Windows PowerShell 5.1 / .NET Framework 4.8 has **no `AssemblyLoadContext`**, so modules cannot self-isolate there. If net48 / WinPS 5.1 support is re-added, the Azure SDK stack must be **preloaded again, conditionally per-TFM (net48 only)** — the inverse of the net8 verdict. See the re-introduction checklist in `docs/Architecture.md` §9. (The 2.0 regression was exactly an unconditional application of the net48-era preload to net8.)
- **#193 methodology gap:** `Microsoft.Extensions.DependencyInjection.Abstractions` is a DLLPickle *transitive* not in `trackedAssemblies`, so the conflict matrix can't see it. Fix: track DLLPickle's full bundled set, re-run inventory, confirm the Az.Resources repro on current `main`, then decide/validate exclusion.
- **EXO/Teams ALC ownership not yet captured** — bare `Import-Module` doesn't eager-load their identity assemblies; the probe needs a representative `-ProbeCommand`.
