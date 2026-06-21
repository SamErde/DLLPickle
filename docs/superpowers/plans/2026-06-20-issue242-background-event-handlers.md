# Issue 242 Background Event Handlers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate process-terminating PowerShell CLR event delegates while preserving supported-runtime DLL loading, adding a compiled resolver only if deletion evidence requires it.

**Architecture:** Delete the advisory `AssemblyLoad` watcher and experimentally remove the legacy `AssemblyResolve` fallback. Deterministic Pester tests verify source safety, child-process survival, and synthetic transitive dependency loading; a narrowly scoped precompiled resolver is conditional on an observed loading failure.

**Tech Stack:** PowerShell 7.4+, .NET 8, Pester 5.7, Invoke-Build.

## Global Constraints

- Support PowerShell 7.4+ and `net8.0` only.
- Do not execute PowerShell script blocks from CLR assembly-event publisher threads.
- Do not use runtime `Add-Type` as the production fix.
- Do not add network-dependent tests.
- Run fatal-crash regressions only in child processes with bounded timeouts.
- Preserve `Import-DPLibrary` result objects and the public `Test-DPLibraryConflict` command.

---

### Task 1: Add deletion-experiment regression tests

**Files:**
- Create: `tests/Unit/AssemblyEventSafety.Tests.ps1`
- Modify: `tests/Unit/Import-DPLibrary.Tests.ps1`

**Interfaces:**
- Consumes: source files under `src/DLLPickle` and the existing `Import-DPLibrary` function.
- Produces: source guardrails and supported-runtime dependency-loading evidence.

- [ ] **Step 1: Add a source guard that rejects direct assembly-event script-block delegates**

```powershell
Describe 'Assembly event safety' -Tag 'Unit' {
    It 'does not register PowerShell script blocks as CLR assembly event delegates' {
        $Source = Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'src\DLLPickle') -Filter '*.ps1' -Recurse |
            Get-Content -Raw

        ($Source -join [Environment]::NewLine) | Should -Not -Match '\[System\.(AssemblyLoadEventHandler|ResolveEventHandler)\]\s*\{'
    }
}
```

- [ ] **Step 2: Run the source guard and verify RED**

Run: `Invoke-Pester -Path ./tests/Unit/AssemblyEventSafety.Tests.ps1 -Output Detailed`

Expected: FAIL because both direct script-block delegate casts still exist.

- [ ] **Step 3: Add a deterministic synthetic dependency test to `Import-DPLibrary.Tests.ps1`**

Compile `Synthetic.Dependency.dll` and `Synthetic.Consumer.dll` into the test TFM directory. The consumer exposes a method returning a value from the dependency. Mock configuration and file discovery, invoke `Import-DPLibrary`, invoke the consumer method, and assert both assemblies report `Imported` or `Already Loaded` without relying on an `AssemblyResolve` callback.

- [ ] **Step 4: Run the synthetic dependency test before deletion**

Run: `Invoke-Pester -Path ./tests/Unit/Import-DPLibrary.Tests.ps1 -Output Detailed`

Expected: PASS, establishing the test fixture and current loading baseline.

- [ ] **Step 5: Commit the test-first state**

```powershell
git add tests/Unit/AssemblyEventSafety.Tests.ps1 tests/Unit/Import-DPLibrary.Tests.ps1
git commit -m "test(module): reproduce unsafe assembly event delegates"
```

### Task 2: Delete unsafe callbacks and preserve immediate conflict checks

**Files:**
- Modify: `src/DLLPickle/Public/Import-DPLibrary.ps1`
- Modify: `src/DLLPickle/Private/Invoke-DPConflictCheck.ps1`
- Modify: `tests/Unit/KnownConflicts.Tests.ps1`

**Interfaces:**
- Consumes: `Get-DPKnownConflict`, `Format-DPConflictWarning`, dependency ordering, and retry loading.
- Produces: `Invoke-DPConflictCheck` that warns once only for conflicts already loaded; `Import-DPLibrary` with no assembly-event delegate.

- [ ] **Step 1: Remove the resolver map, `ResolveEventHandler`, subscription, and unsubscription**

Retain `ConvertTo-DPPublicKeyTokenText` and `Test-DPAssemblyIdentityCompatible` because the main load loop uses them to classify already-loaded compatible assemblies.

- [ ] **Step 2: Reduce `Invoke-DPConflictCheck` to immediate detection**

For each known conflict, compare its module names with `Get-Module`; warn and add the conflict ID to `$script:DPConflictHandled` only when every module is currently loaded. Do not query installed modules or register future callbacks.

- [ ] **Step 3: Add focused immediate-check tests**

Add tests that dot-source `Invoke-DPConflictCheck.ps1`, use synthetic known-conflict JSON with always-loaded PowerShell modules, and assert one warning across two invocations plus no event subscriber growth.

- [ ] **Step 4: Verify GREEN and apply the resolver decision gate**

Run:

```powershell
Invoke-Pester -Path ./tests/Unit/AssemblyEventSafety.Tests.ps1,./tests/Unit/Import-DPLibrary.Tests.ps1,./tests/Unit/KnownConflicts.Tests.ps1 -Output Detailed
```

Decision:

- If the synthetic consumer executes and all focused tests pass, do not add C#.
- If the consumer fails specifically because `Synthetic.Dependency` cannot resolve despite dependency ordering and retries, execute Task 3.
- For any unrelated failure, diagnose it rather than adding the resolver.

- [ ] **Step 5: Commit the deletion implementation**

```powershell
git add src/DLLPickle/Public/Import-DPLibrary.ps1 src/DLLPickle/Private/Invoke-DPConflictCheck.ps1 tests/Unit/KnownConflicts.Tests.ps1
git commit -m "fix(module): remove unsafe assembly event callbacks"
```

### Task 3: Conditional compiled resolver fallback

**Condition:** Execute only if Task 2's synthetic dependency test proves that the supported runtime requires explicit resolution.

**Files:**
- Create: `src/DLLPickle.Build/AssemblyResolverScope.cs`
- Modify: `src/DLLPickle.Build/DLLPickle.csproj`
- Modify: `build/DLLPickle.Build.ps1`
- Modify: `src/DLLPickle/Public/Import-DPLibrary.ps1`
- Create: `tests/Unit/AssemblyResolverScope.Tests.ps1`

**Interfaces:**
- Produces: `DLLPickle.Runtime.AssemblyResolverScope : IDisposable`, constructed with `IReadOnlyDictionary<string,string>` and a canonical allowed root.
- Behavior: subscribes to `AppDomain.AssemblyResolve`; returns only exact-identity assemblies under the allowed root; returns `null` otherwise; idempotently unsubscribes from `Dispose()`.

- [ ] **Step 1: Add failing resolver contract tests**

Cover exact identity, unknown name, incompatible version, out-of-root path, background-thread invocation, and double disposal.

- [ ] **Step 2: Verify RED because the runtime helper does not exist**

Run: `Invoke-Pester -Path ./tests/Unit/AssemblyResolverScope.Tests.ps1 -Output Detailed`

- [ ] **Step 3: Implement the minimal resolver and package it as `DLLPickle.Runtime.dll`**

Use immutable constructor state, `Path.GetFullPath`, directory-boundary validation, exact identity comparison, and a `try/catch` returning `null`. Never hold a lock while calling `Assembly.LoadFrom`.

- [ ] **Step 4: Scope the resolver with PowerShell `try/finally`**

Create it immediately before the load loop and call `Dispose()` in `finally`. Build its map only from DLLs already enumerated under the TFM directory.

- [ ] **Step 5: Verify the resolver tests and deletion guard**

Run: `Invoke-Pester -Path ./tests/Unit/AssemblyResolverScope.Tests.ps1,./tests/Unit/AssemblyEventSafety.Tests.ps1,./tests/Unit/Import-DPLibrary.Tests.ps1 -Output Detailed`

- [ ] **Step 6: Commit the evidence-required fallback**

```powershell
git add src/DLLPickle.Build/AssemblyResolverScope.cs src/DLLPickle.Build/DLLPickle.csproj build/DLLPickle.Build.ps1 src/DLLPickle/Public/Import-DPLibrary.ps1 tests/Unit/AssemblyResolverScope.Tests.ps1
git commit -m "fix(module): add thread-safe assembly resolver scope"
```

### Task 4: Add child-process regression and update documentation

**Files:**
- Create: `tests/Integration/DLLPickle.Issue242.BackgroundEvents.Tests.ps1`
- Modify: `docs/Troubleshooting.md`
- Modify: `docs/Deep-Dive.md`
- Modify: `docs/DLLPickle/Import-DPLibrary.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: built module at `module/DLLPickle/DLLPickle.psd1` and `Invoke-DLLPickleScenario`.
- Produces: isolated process regression evidence and accurate user-facing behavior.

- [ ] **Step 1: Add the child-process regression**

Import the built module, call `Import-DPLibrary -SuppressLogo`, cause a background-thread dynamic assembly load, and assert process exit code zero with no `PSInvalidOperationException`. Use a 30-second timeout.

- [ ] **Step 2: Run the regression against the fixed source**

Run: `Invoke-Build -File ./build/DLLPickle.Build.ps1 -Task IssueReproTest`

Expected: PASS.

- [ ] **Step 3: Update documentation**

Remove claims that DLLPickle automatically warns when future module loads complete a conflict. State that `Import-DPLibrary` warns for conflicts already loaded and `Test-DPLibraryConflict` is the reliable on-demand check. Record issue #242 under the unreleased changelog.

- [ ] **Step 4: Commit regression and documentation**

```powershell
git add tests/Integration/DLLPickle.Issue242.BackgroundEvents.Tests.ps1 docs/Troubleshooting.md docs/Deep-Dive.md docs/DLLPickle/Import-DPLibrary.md CHANGELOG.md
git commit -m "test(module): cover issue 242 background assembly events"
```

### Task 5: Full verification and review

**Files:**
- Verify all changed files.

**Interfaces:**
- Produces: evidence that issue #242 is resolved without a maintenance-heavy bridge.

- [ ] **Step 1: Run analyzer and unit tests**

Run: `Invoke-Build -File ./build/DLLPickle.Build.ps1 -Task Analyze,Test`

Expected: zero errors and zero failed tests.

- [ ] **Step 2: Run issue reproductions**

Run: `Invoke-Build -File ./build/DLLPickle.Build.ps1 -Task IssueReproTest`

Expected: zero failed integration tests.

- [ ] **Step 3: Run the complete build**

Run: `Invoke-Build -File ./build/DLLPickle.Build.ps1`

Expected: build exit code zero.

- [ ] **Step 4: Review repository state**

```powershell
git status --short
git diff origin/main...HEAD --check
git diff origin/main...HEAD --stat
```

Expected: only issue-242 files changed, no whitespace errors, and no uncommitted generated artifacts.

