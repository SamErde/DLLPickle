# Issue #174 Phase 2 — Conflict Detection & Warning Design

**Goal:** Warn DLLPickle users about the Az.Storage ↔ ExchangeOnlineManagement OData incompatibility (which DLLPickle cannot fix by preloading), driven by a data-defined `knownConflicts` list, plus record the runtime evidence and document the workaround.

**Architecture:** Conflicts are declared as data in `build/dependency-policy.json`; the build ships a small extracted copy into the module; a Private detector compares that data against the session's loaded modules; a public `Test-DPLibraryConflict` and an `Import-DPLibrary`-registered one-shot `AssemblyLoad` handler surface a warning when a conflicting pair becomes co-loaded.

**Tech Stack:** PowerShell 7.4+, `System.AppDomain.AssemblyLoad`, Invoke-Build (`PrepareModuleOutput`), Pester 5.

**Predecessor:** `docs/superpowers/specs/2026-06-01-issue174-odata-alc-probe-design.md` (Phase 1 probe). Phase 1 runtime evidence (2026-06-01): Az.Storage force-loads `Microsoft.OData.Core` 7.6.4 at import; EXO's `Get-EXO*` require 7.22.0; both target the **default ALC** and are strong-named; **both import orders fail** (Az.Storage-first → EXO `REF_DEF_MISMATCH`; EXO-first → Az.Storage "assembly with same name is already loaded"). Verdict: not fixable by preloading — OData stays `block`. This phase records that and warns users.

---

## 1. Scope

In scope: the `knownConflicts` data model, its runtime availability, detection, the public function, the `Import-DPLibrary` warning integration, the OData evidence cross-reference, the known-limitation doc, the extended #174 test, and a findings comment on #174 (kept **open**).

Out of scope: closing #174 (keep open per maintainer); Stage 2b auth automation; any attempt to *fix* the conflict (e.g., private-ALC isolation) — ruled out by Phase 1.

## 2. `knownConflicts` data model (`build/dependency-policy.json`)

New top-level array `knownConflicts`. Each entry:

```json
{
  "id": "174-odata-azstorage-exo",
  "modules": ["Az.Storage", "ExchangeOnlineManagement"],
  "assembly": "Microsoft.OData.Core",
  "issue": "174",
  "reason": "Az.Storage force-loads Microsoft.OData.Core 7.6.4 at import; ExchangeOnlineManagement's Get-EXO* cmdlets require 7.22.0. Both target the default ALC and are strong-named, so the two versions cannot coexist in one process - both import orders fail.",
  "workaround": "Use Az.Storage and ExchangeOnlineManagement (Get-EXO* cmdlets) in separate PowerShell processes - a background job (Start-Job) or a second pwsh. A separate runspace in the same process does NOT help: the conflict is process-wide (one default AssemblyLoadContext per process).",
  "evidence": {
    "versions": { "Az.Storage": "7.6.4", "ExchangeOnlineManagement": "7.22.0" },
    "alc": "Default",
    "runtimeProbe": "2026-06-01 scenarios 1-4: both load OData into the Default ALC; Az.Storage-first -> EXO REF_DEF_MISMATCH (0x80131040); EXO-first -> Az.Storage 'same name already loaded'.",
    "decidedOn": "2026-06-01"
  }
}
```

This is the single source of truth. The matching `blockedPreloadAssemblies` OData entries gain a one-line cross-reference (`see knownConflicts 174-odata-azstorage-exo`) and remain `block`.

## 3. Runtime availability (build ships an extracted subset)

> **Superseded (2026-06-02):** This extraction approach shipped in 2.2.0's PR (#231) but was revised before release in response to Codex review (the policy is a `build/**` file excluded from the release trigger, so a `knownConflicts`-only edit would not have auto-published). The conflict data is now a **committed source file at `src/DLLPickle/KnownConflicts.json`** (the single source of truth), copied into the module verbatim by `CopyModuleFiles` — no extraction step, no sync test, and edits under `src/DLLPickle/` correctly trigger a release. The runtime read path is unchanged (it still reads `KnownConflicts.json` at the module root). The rest of this section describes the original design.

`build/dependency-policy.json` is a build/CI artifact and is **not** shipped in the module. So a build step extracts just `knownConflicts` and writes it to the module output as `module/DLLPickle/KnownConflicts.json` (during `PrepareModuleOutput`, after `CopyModuleFiles`). The runtime reads that shipped file (resolved relative to the module root). A unit test asserts the shipped subset equals the policy's `knownConflicts` (sync guard). Rationale: one source (the policy), small shipped payload (only the conflict list, not the full policy).

## 4. Detection (Private `Test-DPModuleConflict`)

A Private, side-effect-free helper. Input: the `knownConflicts` array (from the shipped file) and the set of currently-imported module names (`Get-Module | Select Name`). Output: the conflict entries whose **every** `modules` member is currently loaded. Pure and unit-testable (caller injects the conflict data + a module-name list).

## 5. Public `Test-DPLibraryConflict`

New exported function (added to the manifest `FunctionsToExport`). Reads the shipped `KnownConflicts.json` (via an optional `-KnownConflictsPath` parameter defaulting to the shipped module location — the parameter exists for testability so a test can point at synthetic data in `TestDrive`), runs `Test-DPModuleConflict` against the current session, and emits one `Write-Warning` per active conflict: the reason, the workaround, and `https://github.com/SamErde/DLLPickle/issues/<issue-number>`. Returns the active conflict objects (so it is also usable programmatically). Comment-based help with examples. Runnable anytime the user suspects a conflict.

## 6. `Import-DPLibrary` integration

After the preload completes, for each known conflict (all wrapped so a detection failure can never throw into the user's load path):

- If **every** module in the pair is already **loaded** → `Write-Warning` immediately (reuse `Test-DPLibraryConflict`'s warning text).
- Else if **every** module is **installed** (`Get-Module -ListAvailable`) but not all loaded → the clash is possible later, so **arm a one-shot handler**: register a single `[System.AppDomain]::CurrentDomain.add_AssemblyLoad(...)` handler. At arm time, capture the `ModuleBase` path(s) of the not-yet-loaded conflict module(s). The handler checks the **loaded assembly's path** (the event arg's `Assembly.Location`) against those base paths (a cheap string check — no cmdlet calls inside the load callback); when an assembly from the watched module loads (meaning the pair is now co-loaded), it emits the warning **once** and **unregisters itself**.
- **Guards:** skip arming under Constrained Language Mode (`$ExecutionContext.SessionState.LanguageMode -eq 'ConstrainedLanguage'` — the AppDomain APIs are blocked there); track handled conflict `id`s in a module-scoped (`$script:`) set so a second `Import-DPLibrary` call does not re-warn or stack handlers; query availability only for the conflict's own module names (not all of PSModulePath); normalize paths before the prefix check; the handler body is wrapped in try/catch and never throws.

**Best-effort limits (acknowledged):** the auto-warn is advisory, not a guarantee. A *rejected* assembly load raises no `AssemblyLoad` event, so if the second module's import fails outright before any of its assemblies load (the EXO-first → Az.Storage-import-failure order), the handler may not fire — the user sees the raw error. Detection keys on imported modules (`Get-Module`), so a module removed with `Remove-Module` while its assemblies remain resident is not re-detected. `Test-DPLibraryConflict` (on demand) and the documented separate-process workaround are the reliable paths; assembly-level detection is a possible future enhancement.

This catches every order automatically while arming only when both modules are installed (no overhead otherwise).

## 7. Supporting items

- **OData `blockedPreloadAssemblies` evidence:** add the cross-reference to the knownConflicts entry; keep `block`.
- **Known-limitation doc:** a short section in `docs/Deep-Dive.md` (and/or `DEPENDENCIES.md`) describing the Az.Storage + EXO OData limitation and the separate-session workaround, linking #174.
- **#174 synthetic test:** extend `tests/Integration/DLLPickle.Issue174.OData.Tests.ps1` to also assert the **EXO-first → Az.Storage import fails** order (the current test only covers Az.Storage-first), so both-orders-fail is the recorded characterization.
- **#174 issue:** post the Phase 1 evidence + this resolution as a comment; **keep the issue open**.

## 8. Error handling

The warning is advisory and must never degrade the session: all detection/handler code is `try/catch`-guarded and emits at most a `Write-Warning` (never throws, never writes errors). A missing or malformed `KnownConflicts.json` → no warning (and a `Write-Verbose` note), not a failure. The armed handler is idempotent and self-unregisters after firing.

## 9. Testing

- **Unit:** `Test-DPModuleConflict` (synthetic knownConflicts + injected loaded-module-name lists → returns the right active conflicts / none — the detector takes both as parameters, so no real modules needed); `Test-DPLibraryConflict` (via `-KnownConflictsPath` pointing at a synthetic file in `TestDrive` with a pair of always-loaded modules like `Microsoft.PowerShell.Management`/`Microsoft.PowerShell.Utility` → asserts a warning is emitted; and a non-loaded pair → asserts silence); the **extractor test** — run `Export-DLLPickleKnownConflicts` to a `TestDrive` path and assert its output equals `dependency-policy.json`'s `knownConflicts` (this validates the extraction against the policy without reading the build-generated `module/KnownConflicts.json`, so it does not depend on build order — the `Clean`/`Test` phases run before `PrepareModuleOutput`). Helpers use approved verbs (`Get-`/`Test-`) to stay `AnalyzeTests`-clean.
- **Integration:** the extended #174 both-orders repro.
- **Import-DPLibrary wiring:** the immediate-warn and armed-handler branches are thin glue over the unit-tested detector; the armed-handler auto-warn path is validated by the maintainer's live probe scenarios rather than a synthetic AssemblyLoad test (to avoid registering real session handlers in CI).

## 10. Success criteria

- A user who has both modules loaded sees a clear, actionable warning (reason + separate-session workaround + #174 link) — via `Test-DPLibraryConflict` on demand, immediately from `Import-DPLibrary` if already co-loaded, or automatically the moment the second module loads after `Import-DPLibrary`.
- The conflict is data-defined (`knownConflicts`); adding a future conflict is a data edit + a sync-test update, no new code.
- OData remains `block` with the runtime evidence recorded; the known limitation is documented; #174 carries the findings and stays open.
- All gates green (`Invoke-Build Analyze,Test`); the warning never throws.
