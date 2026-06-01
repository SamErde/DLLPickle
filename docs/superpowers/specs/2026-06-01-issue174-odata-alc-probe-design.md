# Issue #174 OData ALC Probe & Adjudication — Design

**Goal:** Gather runtime AssemblyLoadContext (ALC) evidence for the `Microsoft.OData.*` stack across Az.Storage / ExchangeOnlineManagement (and Teams), then adjudicate issue #174 with a workaround-first, preload-last decision framework.

**Architecture:** Extend the existing runtime-probe tooling to source its assembly filter from `build/dependency-policy.json` (so it captures OData, which is already a tracked assembly), add a small in-session dump helper, provide a self-contained live-probe runbook the maintainer runs against a dev tenant, and define a decision tree that prefers zero-cost workarounds over bundling OData.

**Tech stack:** PowerShell 7.4+, `System.Runtime.Loader.AssemblyLoadContext`, the existing `tools/` probe scripts, Pester for the unit test.

---

## 1. Problem & context

**#174 (OPEN):** With `Az.Storage` imported first, its `Microsoft.OData.Core` (e.g. 7.6.4) loads into the **default ALC**. When `ExchangeOnlineManagement`'s `Get-EXO*` cmdlets then lazily require a **higher** `Microsoft.OData.Core` (e.g. 7.22.0), the load fails: `Could not load file or assembly 'Microsoft.OData.Core, Version=7.22.0.0 ...'`. DLLPickle currently classifies the OData stack as `block` (report-only) and does **not** preload it, because preloading one version breaks the module that needs the other. The repro tests (`tests/Integration/DLLPickle.Issue174.OData.Tests.ps1`) **characterize** this; they do not fix it.

**Probe gap:** `tools/Get-DLLPickleRuntimeAssemblySnapshot.ps1` already spawns a clean child pwsh, imports modules in order, runs an optional `-ProbeCommand`, and reports each loaded identity-stack assembly with its ALC. But its hardcoded assembly-name regex omits `Microsoft.OData.*` / `Microsoft.Spatial`, so it cannot currently show OData ALC ownership.

**Key unknowns the evidence must resolve:**
- Does either module load OData into a **private** ALC (self-isolated → no real default-ALC conflict), or the **default** ALC (shared → genuine conflict)?
- Does **import order** change the outcome (does loading the higher OData version first satisfy both)?
- Does Az.Storage tolerate the **higher** OData version EXO needs?

## 2. Scope

- **Phase 1 (this spec / implementable now):** the probe extension (Components A–B), the live-probe runbook (Component C), and the adjudication framework (Component D) recorded in the repo.
- **Phase 2 (evidence-gated, separate follow-up):** the actual #174 resolution — chosen by applying Component D to the maintainer-provided probe output. The resolution (documented workaround, a built-in assist, or — last resort — an OData preload) is **not** decided in this spec.

**Out of scope:** Stage 2b secretless auth automation (deferred; the live probe stays maintainer-run for now).

> **Placement (A & B):** both live in **`tools/`** as maintainer/analysis scripts — the same family as `New-DLLPickleConflictMatrix`, `Compare-DLLPickleConflictMatrix`, `Get-DLLPickleUpstreamInventory`, and `Update-DLLPickleDependencyPins` (`docs/Architecture.md` §4), kept analyzer-clean by the `AnalyzeTools` build task. They are **not** module code (`src/DLLPickle/`) — they run at adjudication time, not at `Import-DPLibrary` time, so shipping them to the Gallery would bloat the module and turn dev tooling into public API. They are **not** `.github/ci-scripts/` (CI glue: bootstrap, version bump, publish); like the other `tools/` scripts they may be *invoked* by CI but live in `tools/`. (If Phase 2's resolution is a built-in assist, that would be **module** code — a Private function callable from `Import-DPLibrary` — which is a separate decision from these probe tools.)

## 3. Component A — `tools/Get-DLLPickleLoadedTrackedAssembly.ps1` (new, in-session dump)

A small helper that reports, **for the current session**, every loaded assembly whose name is in the policy's `trackedAssemblies`, with version + ALC. This is the shared core used both by the live runbook (interactive, where `Connect-ExchangeOnline` auth cannot run inside a spawned child) and by the snapshot tool's child process.

**Interface:**
```
Get-DLLPickleLoadedTrackedAssembly.ps1
  [-PolicyPath <string>]   # default: <repoRoot>/build/dependency-policy.json
  [-NameLike <string[]>]   # optional post-filter, e.g. 'Microsoft.OData*','Microsoft.Spatial'
  -> PSCustomObject[]: Name, Version, Alc, Path
```

**Behavior:** read `trackedAssemblies` from the policy; enumerate `[AppDomain]::CurrentDomain.GetAssemblies()`; keep those whose `GetName().Name` is in the tracked set (and, if `-NameLike` given, also match one of those wildcards); resolve each assembly's ALC via `AssemblyLoadContext::GetLoadContext` (name, or `Default`). Returns objects (sortable/formattable by the caller).

## 4. Component B — refactor `Get-DLLPickleRuntimeAssemblySnapshot.ps1`

- Add `-PolicyPath` (default `./build/dependency-policy.json`). The parent reads `trackedAssemblies` and passes the names to the child instead of the hardcoded regex.
- The child filters loaded assemblies by membership in that tracked-name set (replacing the `$Pattern` regex). This automatically includes `Microsoft.OData.Core/Edm/Spatial`.
- `-ProbeCommand`, `-PreloadDllPickleManifest`, `-ModuleName`, and the spawn-clean-child design are unchanged.
- Trade-off (accepted): the old regex also captured incidental BCL assemblies (`System.Text.Json`, `System.Memory.Data`, `Microsoft.Bcl.AsyncInterfaces`) that are not in `trackedAssemblies`; those are runtime-provided and not conflict sources, so dropping them is fine. If diagnostic breadth is ever needed, an optional `-AdditionalName <string[]>` can be added later (YAGNI for now).

## 5. Component C — live-probe runbook (maintainer runs, pastes output)

Each scenario runs in a **fresh `pwsh`** to avoid cross-contamination; `Connect-ExchangeOnline` uses the maintainer's dev tenant. The runbook **calls the Component A script** after each step rather than pasting a function — a multi-line function does not paste reliably into an interactive pwsh session (confirmed: the `Show-Loaded` paste produced a `ParserError`), whereas a single-line script call is robust. **Therefore Component A is built first** and the runbook depends on it:

```powershell
$RepoRoot = 'C:/Users/SamErde/Code/Public/DLLPickle'   # local clone
function probe { & "$RepoRoot/tools/Get-DLLPickleLoadedTrackedAssembly.ps1" -NameLike 'Microsoft.OData*','Microsoft.Spatial' | Format-Table -AutoSize }
```

`probe` is a one-line alias the maintainer pastes once (single line = no paste-parse issues); call it after each step. Note: the probe reads `[AppDomain]::CurrentDomain.GetAssemblies()` and `AssemblyLoadContext` — under PowerShell **Constrained Language Mode** these .NET calls are restricted (the maintainer's session showed CLM **audit** mode, which permits them); the runbook assumes a session where these APIs are allowed.

**Scenarios** (each = a fresh session; capture `probe` output after each step):

1. **Az.Storage alone:** `Import-Module Az.Storage`; `probe` (after-import); run a non-network storage cmdlet that touches OData (e.g. `New-AzStorageContext -StorageAccountName x -Anonymous` or `Get-Command -Module Az.Storage | Out-Null`); `probe` (after-cmdlet).
2. **EXO alone:** `Import-Module ExchangeOnlineManagement`; `probe` (after-import); `Connect-ExchangeOnline`; `Get-EXOMailbox -ResultSize 1`; `probe` (after-getexo).
3. **Az.Storage → EXO (failing order):** import Az.Storage, `probe`; import EXO + `Connect-ExchangeOnline` + `Get-EXOMailbox -ResultSize 1` (record success/error); `probe` (after-getexo).
4. **EXO → Az.Storage (candidate workaround order):** import EXO + `Connect-ExchangeOnline` + `Get-EXOMailbox -ResultSize 1`; `probe`; then import Az.Storage + a storage cmdlet (record whether Az.Storage works); `probe` (after-azstorage).
5. **With DLLPickle preloading the candidate OData version** (only if scenarios 1–4 suggest a coherent version exists): `Import-Module $RepoRoot/module/DLLPickle/DLLPickle.psd1`; `Import-DPLibrary`; then repeat scenario 3's imports/cmdlets, capturing `probe` at each step.

**Captured per scenario:** the `OData.*` version(s) loaded, each one's ALC (Default vs a private name), and whether each module's representative cmdlet succeeded.

## 6. Component D — #174 adjudication framework (workaround-first, preload-last)

Apply in order to the probe evidence:

1. **Self-isolation** — if Az.Storage and/or EXO load OData into a **private** ALC and run their own versions side-by-side without conflict, there is no default-ALC clash. → Document #174 as a runtime non-issue (order-independent) and close it; no bundling.
2. **Import-order / no-bundle workaround** — if loading the **higher** OData version first (EXO before Az.Storage) makes both modules work:
   - Ship **documented guidance** (import EXO, or run a `Get-EXO*` command, before importing Az.Storage). Zero module-size cost.
   - Evaluate a lightweight **built-in assist**: `Import-DPLibrary` (or a new helper) force-loads the higher **already-installed** `Microsoft.OData.Core` from the consuming module's own files into the default ALC — **without bundling it in DLLPickle** (still zero bundle-size cost). Feasible only if the higher version is present on the machine and load-order-first resolves the conflict.
3. **Preload fix (last resort)** — only if no workaround is reliable/efficient: bundle a coherent `Microsoft.OData.Core/Edm/Spatial` version in DLLPickle. **Explicitly weigh** the added module size (~1–2 MB for the OData stack) and validate that the bundled version works for **both** Az.Storage and EXO before adopting.

**Decision is recorded** in `build/dependency-policy.json` (classification + evidence) and `docs/Architecture.md` per the standard adjudication loop (§8 of the blueprint). The weighing of option 2 (≈0 cost) vs option 3 (size cost) is documented so the call is evidence-based.

## 7. Testing

- **Component A/B (unit):** a Pester test in `tests/Unit/` that runs `Get-DLLPickleLoadedTrackedAssembly.ps1` against a synthetic policy (a temp `dependency-policy.json` listing a known-loaded assembly such as `System.Management.Automation`) and asserts the helper returns it with a resolved ALC; and that `Get-DLLPickleRuntimeAssemblySnapshot.ps1` includes an OData name in the names it passes to the child (assert via a policy containing `Microsoft.OData.Core`). Analyzer-clean per `AnalyzeTools`.
- **Existing #174 repro tests** remain as characterization and as the regression guard once a resolution lands.
- **Component C** scenarios are manual/maintainer-run (auth tier); not in CI.
- **Component D** produces no code in Phase 1; its output is the recorded decision in Phase 2.

## 8. Follow-ups

- **Phase 2:** apply Component D to the maintainer's probe output and implement the chosen resolution (its own spec/plan if it's a preload or a built-in assist).
- **Stage 2b auth automation** would let scenarios 2–5 run in CI; deferred.

## 9. Success criteria

- The probe captures `Microsoft.OData.*` / `Microsoft.Spatial` ALC ownership + versions, driven by `trackedAssemblies` (stays in sync with policy).
- The maintainer can run the runbook and produce a clear evidence table (version + ALC + cmdlet success) for scenarios 1–5.
- The adjudication framework yields an unambiguous, recorded decision for #174 that favors a reliable zero-bundle workaround and only bundles OData if nothing else works.
