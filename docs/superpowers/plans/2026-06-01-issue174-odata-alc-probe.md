# Issue #174 OData ALC Probe — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the runtime ALC-ownership probe tooling that captures `Microsoft.OData.*`/`Microsoft.Spatial` (and the rest of the tracked stack) so the maintainer can gather the evidence needed to adjudicate issue #174.

**Architecture:** A new in-session dump script (`tools/Get-DLLPickleLoadedTrackedAssembly.ps1`) sources its assembly filter from `build/dependency-policy.json` → `trackedAssemblies` and resolves each loaded assembly's ALC. The existing spawn-a-clean-child probe (`tools/Get-DLLPickleRuntimeAssemblySnapshot.ps1`) is refactored to reuse that helper inside its child process (DRY) via a new `-PolicyPath` parameter, replacing its hardcoded regex. A unit test file covers both. The live-probe runbook (in the design spec) then calls the helper.

**Tech Stack:** PowerShell 7.4+, `System.Runtime.Loader.AssemblyLoadContext`, Pester 5, Invoke-Build (`Analyze`, `Test`, `AnalyzeTools`).

**Spec:** `docs/superpowers/specs/2026-06-01-issue174-odata-alc-probe-design.md` (Phase 1 = Components A, B, the runbook, tests; Phase 2 = the #174 resolution, evidence-gated, OUT OF SCOPE here).

---

## File Structure

- **Create** `tools/Get-DLLPickleLoadedTrackedAssembly.ps1` — Component A: in-session dump of loaded tracked assemblies + ALC. One responsibility: "given the policy, what tracked assemblies are loaded right now and in which ALC."
- **Modify** `tools/Get-DLLPickleRuntimeAssemblySnapshot.ps1` — Component B: spawn a clean child, import modules, run the probe command, then call Component A in the child to produce the snapshot. Adds `-PolicyPath`; removes the hardcoded regex.
- **Create** `tests/Unit/RuntimeAssemblyProbe.Tests.ps1` — unit tests for A (in-process) and B (end-to-end via a spawned child against an always-loaded assembly).
- **Modify** `docs/Architecture.md` — §4 component map: add Component A and note the snapshot tool now sources its filter from `trackedAssemblies`.

Each task ends green (analyzer + tests) and is committed independently.

---

## Task 1: Component A — `tools/Get-DLLPickleLoadedTrackedAssembly.ps1`

**Files:**
- Create: `tools/Get-DLLPickleLoadedTrackedAssembly.ps1`
- Test: `tests/Unit/RuntimeAssemblyProbe.Tests.ps1`

- [ ] **Step 1: Write the failing tests**

Create `tests/Unit/RuntimeAssemblyProbe.Tests.ps1`:

```powershell
BeforeAll {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $LoadedScript = Join-Path $RepoRoot 'tools\Get-DLLPickleLoadedTrackedAssembly.ps1'

    # Named Get-* (not New-*): the AnalyzeTests task only excludes PSUseDeclaredVarsMoreThanAssignments,
    # so a New-*/Set-* helper would trip PSUseShouldProcessForStateChangingFunctions and fail the gate.
    function Get-TempPolicyPath {
        param([string[]]$TrackedAssemblies)
        $Path = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('n') + '.json')
        [PSCustomObject]@{ trackedAssemblies = $TrackedAssemblies } |
            ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding utf8
        $Path
    }
}

Describe 'Get-DLLPickleLoadedTrackedAssembly' -Tag 'Unit' {
    It 'returns a loaded assembly that is in trackedAssemblies, with version + ALC' {
        $Policy = Get-TempPolicyPath -TrackedAssemblies @('System.Management.Automation')
        $Result = & $LoadedScript -PolicyPath $Policy
        $Row = $Result | Where-Object Name -EQ 'System.Management.Automation'
        $Row | Should -Not -BeNullOrEmpty
        $Row.Alc | Should -Not -BeNullOrEmpty
        $Row.Version | Should -Not -BeNullOrEmpty
    }

    It 'excludes loaded assemblies that are not in trackedAssemblies' {
        $Policy = Get-TempPolicyPath -TrackedAssemblies @('System.Management.Automation')
        $Result = & $LoadedScript -PolicyPath $Policy
        ($Result | Where-Object Name -EQ 'System.Private.CoreLib') | Should -BeNullOrEmpty
    }

    It 'returns nothing when -NameLike matches no tracked+loaded assembly' {
        $Policy = Get-TempPolicyPath -TrackedAssemblies @('System.Management.Automation')
        $Result = & $LoadedScript -PolicyPath $Policy -NameLike 'Microsoft.OData*'
        @($Result) | Should -BeNullOrEmpty
    }

    It 'returns the row when -NameLike matches a tracked+loaded assembly' {
        $Policy = Get-TempPolicyPath -TrackedAssemblies @('System.Management.Automation')
        $Result = & $LoadedScript -PolicyPath $Policy -NameLike 'System.Management.*'
        ($Result | Where-Object Name -EQ 'System.Management.Automation') | Should -Not -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/Unit/RuntimeAssemblyProbe.Tests.ps1 -Output Detailed"`
Expected: FAIL — the script does not exist yet (`& $LoadedScript` errors with "The term '...Get-DLLPickleLoadedTrackedAssembly.ps1' is not recognized" / path not found).

- [ ] **Step 3: Create the script**

Create `tools/Get-DLLPickleLoadedTrackedAssembly.ps1`:

```powershell
<#
.SYNOPSIS
    Reports the assemblies loaded in the CURRENT session whose simple name is tracked by the
    dependency policy, with version and AssemblyLoadContext (ALC).
.DESCRIPTION
    Enumerates [System.AppDomain]::CurrentDomain.GetAssemblies(), keeps those whose GetName().Name is
    in the policy's trackedAssemblies (optionally further filtered by -NameLike wildcards), and
    resolves each one's ALC name (or 'Default'). A private ALC name signals the owning module
    self-manages that assembly. Shared by the #174 live-probe runbook and by the child process of
    Get-DLLPickleRuntimeAssemblySnapshot.ps1, so the merge-gate filter logic lives in one place.

    Requires a session where direct .NET API access is permitted (Full Language Mode, or Constrained
    Language AUDIT mode); these reflection calls are blocked under enforced Constrained Language Mode.
.PARAMETER PolicyPath
    Path to dependency-policy.json. Defaults to build/dependency-policy.json relative to the repo root
    (the parent of this script's tools/ folder).
.PARAMETER NameLike
    Optional wildcard patterns; when supplied, an assembly must ALSO match one of them to be returned.
.OUTPUTS
    PSCustomObject[] with Name, Version, Alc, Path. Sorted by Name.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$PolicyPath,

    [Parameter()]
    [string[]]$NameLike
)

$ErrorActionPreference = 'Stop'

if (-not $PolicyPath) {
    $PolicyPath = Join-Path -Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path -ChildPath 'build/dependency-policy.json'
}

$TrackedNames = @((Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json).trackedAssemblies)

[System.AppDomain]::CurrentDomain.GetAssemblies() |
    Where-Object { $TrackedNames -contains $_.GetName().Name } |
    Where-Object {
        if (-not $NameLike) { return $true }
        $AssemblyName = $_.GetName().Name
        foreach ($Pattern in $NameLike) {
            if ($AssemblyName -like $Pattern) { return $true }
        }
        return $false
    } |
    ForEach-Object {
        $Alc = [System.Runtime.Loader.AssemblyLoadContext]::GetLoadContext($_)
        [PSCustomObject]@{
            Name    = $_.GetName().Name
            Version = $_.GetName().Version.ToString()
            Alc     = if ($Alc -and $Alc.Name) { $Alc.Name } else { 'Default' }
            Path    = $_.Location
        }
    } |
    Sort-Object Name
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/Unit/RuntimeAssemblyProbe.Tests.ps1 -Output Detailed"`
Expected: PASS — 4/4.

- [ ] **Step 5: Run the analyzer on tools/ + tests/ to verify clean**

Run: `pwsh -NoProfile -Command "Invoke-Build -File ./build/DLLPickle.Build.ps1 -Task Analyze"`
Expected: PASS — `Analyze`, `AnalyzeTests`, `AnalyzeTools` all complete with no findings (the build fails on any finding). The script uses the approved `Get-` verb and no `Write-Host`, so no `PSUseShouldProcessForStateChangingFunctions`/`PSAvoidUsingWriteHost` findings.

- [ ] **Step 6: Commit**

```bash
git add tools/Get-DLLPickleLoadedTrackedAssembly.ps1 tests/Unit/RuntimeAssemblyProbe.Tests.ps1
git commit -m "feat(tools): add Get-DLLPickleLoadedTrackedAssembly (policy-driven in-session ALC dump)"
```

---

## Task 2: Component B — refactor `tools/Get-DLLPickleRuntimeAssemblySnapshot.ps1`

**Files:**
- Modify: `tools/Get-DLLPickleRuntimeAssemblySnapshot.ps1`
- Test: `tests/Unit/RuntimeAssemblyProbe.Tests.ps1` (add a Describe block)

- [ ] **Step 1: Write the failing test**

Append this `Describe` block to `tests/Unit/RuntimeAssemblyProbe.Tests.ps1` (the `BeforeAll` from Task 1 already defines `$RepoRoot` and `Get-TempPolicyPath`; add `$SnapshotScript` there too — see Step 1a):

Step 1a — extend the existing `BeforeAll` (after the `$LoadedScript = ...` line) with:

```powershell
    $SnapshotScript = Join-Path $RepoRoot 'tools\Get-DLLPickleRuntimeAssemblySnapshot.ps1'
```

Step 1b — append this block at the end of the file:

```powershell
Describe 'Get-DLLPickleRuntimeAssemblySnapshot' -Tag 'Unit' {
    It 'sources its filter from -PolicyPath and returns tracked assemblies loaded in the child session' {
        $Policy = Get-TempPolicyPath -TrackedAssemblies @('System.Management.Automation')
        # Microsoft.PowerShell.Management is always importable; the child always has SMA loaded.
        $Result = & $SnapshotScript -ModuleName 'Microsoft.PowerShell.Management' -PolicyPath $Policy
        ($Result | Where-Object Name -EQ 'System.Management.Automation') | Should -Not -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/Unit/RuntimeAssemblyProbe.Tests.ps1 -Output Detailed"`
Expected: FAIL — the current script has no `-PolicyPath` parameter, so binding errors ("A parameter cannot be found that matches parameter name 'PolicyPath'").

- [ ] **Step 3: Refactor the snapshot script**

Replace the entire contents of `tools/Get-DLLPickleRuntimeAssemblySnapshot.ps1` with:

```powershell
<#
.SYNOPSIS
    Snapshots which tracked assemblies a module loads, and into which AssemblyLoadContext.
.DESCRIPTION
    Spawns a fresh pwsh process, optionally preloads DLLPickle, imports the named module(s) in order,
    optionally runs a probe command, then reports each loaded assembly whose name is in the dependency
    policy's trackedAssemblies, with its version, path, and ALC name. The set of tracked names (and the
    ALC capture) is sourced from build/dependency-policy.json via Get-DLLPickleLoadedTrackedAssembly.ps1,
    so this tool and the live-probe runbook share one filter. A private ALC (name other than 'Default')
    indicates the module self-manages that assembly — a strong signal that DLLPickle must NOT preload it.
.PARAMETER ModuleName
    One or more modules to import, in order.
.PARAMETER PreloadDllPickleManifest
    Optional path to a DLLPickle manifest; when supplied, Import-DPLibrary runs before the imports.
.PARAMETER ProbeCommand
    Optional command string run after imports (e.g. 'Get-AzContext') to force lazy ALC init.
.PARAMETER PolicyPath
    Path to dependency-policy.json. Defaults to build/dependency-policy.json relative to the repo root.
.OUTPUTS
    PSCustomObject[] one row per loaded tracked assembly: Name, Version, Alc, Path.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$ModuleName,

    [Parameter()]
    [string]$PreloadDllPickleManifest,

    [Parameter()]
    [string]$ProbeCommand,

    [Parameter()]
    [string]$PolicyPath
)

$ErrorActionPreference = 'Stop'

$HelperScript = Join-Path -Path $PSScriptRoot -ChildPath 'Get-DLLPickleLoadedTrackedAssembly.ps1'
if (-not $PolicyPath) {
    $PolicyPath = Join-Path -Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path -ChildPath 'build/dependency-policy.json'
}

$ChildScript = @'
param($ModuleNames, $PreloadManifest, $ProbeCommand, $HelperScript, $PolicyPath)
$ModuleNames = $ModuleNames -split ','
$ErrorActionPreference = 'Continue'
if ($PreloadManifest) {
    Import-Module $PreloadManifest -Force
    Import-DPLibrary -SuppressLogo | Out-Null
}
foreach ($Name in $ModuleNames) { Import-Module $Name -Force -ErrorAction Continue }
if ($ProbeCommand) { try { Invoke-Expression $ProbeCommand | Out-Null } catch { } }
& $HelperScript -PolicyPath $PolicyPath | ConvertTo-Json -Depth 5
'@

$TempScript = Join-Path ([System.IO.Path]::GetTempPath()) ("dpp-snap-{0}.ps1" -f ([System.Guid]::NewGuid().ToString('n')))
Set-Content -LiteralPath $TempScript -Value $ChildScript -Encoding utf8NoBOM
try {
    $ChildArguments = @(
        '-NoProfile', '-NonInteractive', '-File', $TempScript,
        '-ModuleNames', ($ModuleName -join ','),
        '-HelperScript', $HelperScript,
        '-PolicyPath', $PolicyPath
    )
    if ($PreloadDllPickleManifest) { $ChildArguments += @('-PreloadManifest', $PreloadDllPickleManifest) }
    if ($ProbeCommand) { $ChildArguments += @('-ProbeCommand', $ProbeCommand) }
    $Raw = & pwsh @ChildArguments
    $Json = ($Raw | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($Json)) { return @() }
    @($Json | ConvertFrom-Json)
} finally {
    Remove-Item -LiteralPath $TempScript -Force -ErrorAction SilentlyContinue
}
```

Key changes from the previous version: added the `-PolicyPath` parameter; the child now calls `Get-DLLPickleLoadedTrackedAssembly.ps1` (passed as `-HelperScript`) instead of the inline `$Pattern` regex + AppDomain enumeration, so the filter is the policy's `trackedAssemblies` (now including OData/Spatial). Behavior trade-off (per spec): the old regex also captured incidental BCL assemblies (`System.Text.Json`, `System.Memory.Data`, `Microsoft.Bcl.AsyncInterfaces`) that are not tracked; those are dropped (runtime-provided, not conflict sources).

- [ ] **Step 4: Run the test to verify it passes**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/Unit/RuntimeAssemblyProbe.Tests.ps1 -Output Detailed"`
Expected: PASS — 5/5 (the 4 from Task 1 + the new snapshot test). Note: the snapshot test spawns a child `pwsh` (~1-3s).

- [ ] **Step 5: Run the analyzer to verify clean**

Run: `pwsh -NoProfile -Command "Invoke-Build -File ./build/DLLPickle.Build.ps1 -Task Analyze"`
Expected: PASS — no findings.

- [ ] **Step 6: Commit**

```bash
git add tools/Get-DLLPickleRuntimeAssemblySnapshot.ps1 tests/Unit/RuntimeAssemblyProbe.Tests.ps1
git commit -m "refactor(tools): source runtime-snapshot filter from trackedAssemblies (captures OData)"
```

---

## Task 3: Update the architecture component map

**Files:**
- Modify: `docs/Architecture.md` (§4 component map row for analysis tools)

- [ ] **Step 1: Update the §4 "Analysis tools" row**

In `docs/Architecture.md`, find the §4 table row that begins with `| Analysis tools |` and listing the `tools/` scripts. Add `Get-DLLPickleLoadedTrackedAssembly.ps1` to that list and note the policy-sourced filter. Replace the row's path cell so it reads (keep the table formatting):

```markdown
| Analysis tools | `tools/Get-DLLPickleLoadedTrackedAssembly.ps1`, `New-DLLPickleConflictMatrix.ps1`, `Compare-DLLPickleConflictMatrix.ps1`, `Get-DLLPickleRuntimeAssemblySnapshot.ps1`, `Get-DLLPickleUpstreamInventory.ps1`, `Update-DLLPickleDependencyPins.ps1` | Inventory upstream modules, build the conflict matrix, probe runtime ALC ownership (filter sourced from `trackedAssemblies`), detect drift, and apply policy pins. |
```

- [ ] **Step 2: Verify the table still renders (no broken pipes)**

Run: `pwsh -NoProfile -Command "Get-Content ./docs/Architecture.md | Select-String 'Get-DLLPickleLoadedTrackedAssembly'"`
Expected: one line — the §4 row containing the new script.

- [ ] **Step 3: Commit**

```bash
git add docs/Architecture.md
git commit -m "docs: list Get-DLLPickleLoadedTrackedAssembly in the architecture component map"
```

---

## Task 4: Validate the full gate and hand off the live-probe runbook

**Files:** none (verification + handoff)

- [ ] **Step 1: Run the full PR-smoke gate**

Run: `pwsh -NoProfile -Command "Invoke-Build -File ./build/DLLPickle.Build.ps1 -Task Analyze,Test"`
Expected: PASS — analyzer clean on `src/`, `tests/`, `tools/`; all unit tests pass (the existing suite + the 5 new probe tests). "Build succeeded".

- [ ] **Step 2: Smoke-test the helper locally (no auth, no spawn)**

Run: `pwsh -NoProfile -Command "Import-Module ./module/DLLPickle/DLLPickle.psd1 -Force; & ./tools/Get-DLLPickleLoadedTrackedAssembly.ps1 | Format-Table -AutoSize"`
Expected: a table of tracked assemblies loaded by importing the DLLPickle module (e.g. the MSAL / IdentityModel preload set), each with an `Alc` (likely `Default`). Confirms the policy-driven filter + ALC resolution work end-to-end.

- [ ] **Step 3: Hand off the live-probe runbook to the maintainer**

The probe is now usable. Surface the §5 runbook from the spec to the maintainer, with the `probe` helper bound to the built script. The maintainer runs each scenario in a fresh `pwsh` (Full Language Mode or CLM audit), against their dev tenant, and pastes back the per-step `probe` output (OData version(s) + ALC + cmdlet success/error). That evidence feeds the Phase 2 (#174) adjudication — OUT OF SCOPE for this plan.

One-line `probe` binding to paste once per session:

```powershell
$RepoRoot = (git rev-parse --show-toplevel)   # run from inside your DLLPickle clone
function probe { & "$RepoRoot/tools/Get-DLLPickleLoadedTrackedAssembly.ps1" -NameLike 'Microsoft.OData*','Microsoft.Spatial' | Format-Table -AutoSize }
```

- [ ] **Step 4: Final commit (if any doc/runbook tweaks were made); otherwise none**

No code change in this task. If the runbook handoff prompted a spec tweak, commit it; otherwise nothing to commit.

---

## Notes for the implementer

- **Pester version:** the repo pins Pester 5.2.2–5.99.99. `Invoke-Pester -Path <file>` works with Pester 5; if `Invoke-Pester` is missing, run `Import-Module Pester -MinimumVersion 5.2.2` first (the build bootstrap installs it).
- **Analyzer gate:** `AnalyzeTests` excludes only `PSUseDeclaredVarsMoreThanAssignments`; `AnalyzeTools` excludes nothing. Do **not** name test-helper *functions* with state-changing verbs (`New-*`, `Set-*`, `Remove-*`): they trip `PSUseShouldProcessForStateChangingFunctions` and fail the gate. That is why the temp-policy helper is `Get-TempPolicyPath` (returns a path; file creation is incidental), matching the existing `Get-TestInventory`/`Get-DriftRow` test helpers in this repo.
- **CLM:** the probe uses `[AppDomain]`/`[AssemblyLoadContext]` reflection, blocked under enforced Constrained Language Mode. The maintainer's session was CLM **audit** (allowed). CI runs Full Language Mode.
- **No release impact:** `tools/`, `tests/`, and `docs/` are outside the Release-and-Publish bundle paths, so merging this triggers no PSGallery publish.
