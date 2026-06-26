# Issue #174 Phase 2 — Conflict Detection & Warning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Superseded (2026-06-02):** The conflict data was relocated before the 2.2.0 release — it is now a committed source file at `src/DLLPickle/KnownConflicts.json` rather than extracted from `build/dependency-policy.json` at build time. The `Export-DLLPickleKnownConflicts.ps1` extractor, the `ExportKnownConflicts` build task, and the extractor sync test described below no longer exist. See the superseding note in the design doc §3 for the rationale (Codex review of #231).

> **Maintenance note (2026-06-25):** GAP-005 closed by preserving the single-process limitation explicitly in known-conflict data, docs, and policy tests. Any future OData preload change still requires fresh runtime re-adjudication in both import orders.

**Goal:** Warn DLLPickle users about the Az.Storage ↔ ExchangeOnlineManagement OData incompatibility, driven by a data-defined `knownConflicts` list, and record the runtime evidence + workaround.

**Architecture:** Conflicts are data in `build/dependency-policy.json`; the build extracts them into a shipped `module/DLLPickle/KnownConflicts.json`; a pure Private detector compares them against the session's loaded modules; a public `Test-DPLibraryConflict` and an `Import-DPLibrary`-armed one-shot `AssemblyLoad` handler surface a `Write-Warning`. The warning never throws.

**Tech Stack:** PowerShell 7.4+, `System.AppDomain.AssemblyLoad`, Invoke-Build, Pester 5.

**Spec:** `docs/superpowers/specs/2026-06-01-issue174-conflict-warning-design.md`. Branch: `feat/issue174-conflict-warning`.

**Release note:** this changes `src/DLLPickle/**` (a real module change) → merging triggers a PSGallery release. Use `feat:` commits so the bump is a minor.

---

## File Structure

- **Modify** `build/dependency-policy.json` — add top-level `knownConflicts` (+ #174 entry); cross-reference it from the OData `blockedPreloadAssemblies` evidence.
- **Create** `build/Export-DLLPickleKnownConflicts.ps1` — reusable extraction: policy → `KnownConflicts.json`. One responsibility, so the build and the test share it.
- **Modify** `build/DLLPickle.Build.ps1` — call the extractor after `CopyModuleFiles`.
- **Create** `src/DLLPickle/Private/Get-DPKnownConflict.ps1` — read the shipped `KnownConflicts.json` (or `-Path`), return the array; `@()` on missing/malformed.
- **Create** `src/DLLPickle/Private/Test-DPModuleConflict.ps1` — pure detector: `(-Conflict, -LoadedModule)` → active conflicts.
- **Create** `src/DLLPickle/Private/Format-DPConflictWarning.ps1` — `(-Conflict)` → warning message string.
- **Create** `src/DLLPickle/Private/Invoke-DPConflictCheck.ps1` — `Import-DPLibrary` glue: immediate-warn loaded pairs, arm one-shot handlers for installed pairs; CLM-guarded; never throws.
- **Create** `src/DLLPickle/Public/Test-DPLibraryConflict.ps1` — public entry: read + detect + warn; returns active conflicts.
- **Modify** `src/DLLPickle/DLLPickle.psd1` — add `Test-DPLibraryConflict` to `FunctionsToExport`.
- **Modify** `src/DLLPickle/Public/Import-DPLibrary.ps1` — call `Invoke-DPConflictCheck` near the end (try/catch).
- **Modify** `docs/Deep-Dive.md` — known-limitation section.
- **Create** `tests/Unit/KnownConflicts.Tests.ps1` — extractor + reader + detector + formatter + public-function tests.
- **Modify** `tests/Integration/DLLPickle.Issue174.OData.Tests.ps1` — assert both import orders fail.

All function names use approved, non-state-changing verbs (`Get`/`Test`/`Format`/`Invoke`) to stay `Analyze`/`AnalyzeTests`/`AnalyzeTools`-clean.

---

## Task 1: Add `knownConflicts` to the policy

**Files:**
- Modify: `build/dependency-policy.json`

- [ ] **Step 1: Add the `knownConflicts` array**

Add a top-level `"knownConflicts"` member to `build/dependency-policy.json` (e.g., immediately after the `"baseline"` object — valid anywhere at top level):

```json
  "knownConflicts": [
    {
      "id": "174-odata-azstorage-exo",
      "modules": [ "Az.Storage", "ExchangeOnlineManagement" ],
      "assembly": "Microsoft.OData.Core",
      "issue": "174",
      "reason": "Az.Storage force-loads Microsoft.OData.Core 7.6.4 at import; ExchangeOnlineManagement's Get-EXO* cmdlets require 7.22.0. Both target the default ALC and are strong-named, so the two versions cannot coexist in one process - both import orders fail.",
      "workaround": "Use Az.Storage and ExchangeOnlineManagement (Get-EXO* cmdlets) in separate PowerShell sessions or processes (for example, run one in a background job or a separate runspace/pwsh).",
      "evidence": {
        "versions": { "Az.Storage": "7.6.4", "ExchangeOnlineManagement": "7.22.0" },
        "alc": "Default",
        "runtimeProbe": "2026-06-01 scenarios 1-4: both load OData into the Default ALC; Az.Storage-first -> EXO REF_DEF_MISMATCH (0x80131040); EXO-first -> Az.Storage 'same name already loaded'.",
        "decidedOn": "2026-06-01"
      }
    }
  ]
```

- [ ] **Step 2: Cross-reference from the OData block evidence**

In the three `Microsoft.OData.*`/`Microsoft.Spatial` entries under `blockedPreloadAssemblies`, append to each `evidence.basis` string: ` See knownConflicts 174-odata-azstorage-exo for the runtime adjudication.` (Keep `classification`/`updateMode` as `block`/`reportOnly`.)

- [ ] **Step 3: Verify the JSON parses and the entry is well-formed**

Run:
```bash
pwsh -NoProfile -Command "$p = Get-Content ./build/dependency-policy.json -Raw | ConvertFrom-Json; $k = $p.knownConflicts | Where-Object id -eq '174-odata-azstorage-exo'; if (-not $k) { throw 'missing' }; @($k.modules) -join ',' "
```
Expected: `Az.Storage,ExchangeOnlineManagement` (and no parse error).

- [ ] **Step 4: Commit**

```bash
git add build/dependency-policy.json
git commit -m "feat(policy): add knownConflicts (#174 Az.Storage+EXO OData) + OData evidence cross-ref"
```

---

## Task 2: Ship `knownConflicts` to the module at build time

**Files:**
- Create: `build/Export-DLLPickleKnownConflicts.ps1`
- Modify: `build/DLLPickle.Build.ps1`
- Test: `tests/Unit/KnownConflicts.Tests.ps1`

- [ ] **Step 1: Write the failing extractor test**

Create `tests/Unit/KnownConflicts.Tests.ps1`:

```powershell
BeforeAll {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $ExportScript = Join-Path $RepoRoot 'build\Export-DLLPickleKnownConflicts.ps1'
    $PolicyPath = Join-Path $RepoRoot 'build\dependency-policy.json'
}

Describe 'Export-DLLPickleKnownConflicts' -Tag 'Unit' {
    It 'writes the policy knownConflicts array to the output file verbatim' {
        $Out = Join-Path $TestDrive 'KnownConflicts.json'
        & $ExportScript -PolicyPath $PolicyPath -OutputPath $Out
        Test-Path -LiteralPath $Out | Should -BeTrue
        $Written = Get-Content -LiteralPath $Out -Raw | ConvertFrom-Json
        $Policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
        @($Written).Count | Should -Be @($Policy.knownConflicts).Count
        ($Written | Where-Object id -EQ '174-odata-azstorage-exo') | Should -Not -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/Unit/KnownConflicts.Tests.ps1 -Output Detailed"`
Expected: FAIL — `Export-DLLPickleKnownConflicts.ps1` not found.

- [ ] **Step 3: Create the extractor**

Create `build/Export-DLLPickleKnownConflicts.ps1`:

```powershell
<#
.SYNOPSIS
    Extracts the knownConflicts array from the dependency policy into a standalone JSON file shipped
    with the module, so the runtime conflict-warning can read it (the full policy is not shipped).
.PARAMETER PolicyPath
    Path to dependency-policy.json.
.PARAMETER OutputPath
    Path to write the extracted knownConflicts JSON (an array).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$Policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
$Conflicts = @($Policy.knownConflicts)

$OutputDirectory = Split-Path -Path $OutputPath -Parent
if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
}

ConvertTo-Json -InputObject $Conflicts -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/Unit/KnownConflicts.Tests.ps1 -Output Detailed"`
Expected: PASS.

- [ ] **Step 5: Wire the extractor into the build**

In `build/DLLPickle.Build.ps1`, add this task after the `CopyModuleFiles` task definition (it runs as part of `PrepareModuleOutput`):

```powershell
# Synopsis: Ship the policy's knownConflicts list into the module for the runtime conflict warning
Add-BuildTask ExportKnownConflicts -After CopyModuleFiles {
    Write-Build Gray '        Exporting knownConflicts to the module output...'
    $PolicyPath = Join-Path -Path $script:ProjectRoot -ChildPath 'build/dependency-policy.json'
    $OutputPath = Join-Path -Path $script:ModuleOutputPath -ChildPath 'KnownConflicts.json'
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Export-DLLPickleKnownConflicts.ps1') -PolicyPath $PolicyPath -OutputPath $OutputPath
    Write-Build Gray '        ...knownConflicts exported.'
}
```

- [ ] **Step 6: Verify the build ships the file**

Run: `pwsh -NoProfile -Command "Invoke-Build -File ./build/DLLPickle.Build.ps1 -Task PrepareModuleOutput; Test-Path ./module/DLLPickle/KnownConflicts.json"`
Expected: ends with `True`, and the file contains the #174 conflict.

- [ ] **Step 7: Commit**

```bash
git add build/Export-DLLPickleKnownConflicts.ps1 build/DLLPickle.Build.ps1 tests/Unit/KnownConflicts.Tests.ps1
git commit -m "feat(build): ship knownConflicts.json into the module output"
```

---

## Task 3: Detector, reader, and formatter (Private)

**Files:**
- Create: `src/DLLPickle/Private/Test-DPModuleConflict.ps1`
- Create: `src/DLLPickle/Private/Get-DPKnownConflict.ps1`
- Create: `src/DLLPickle/Private/Format-DPConflictWarning.ps1`
- Test: `tests/Unit/KnownConflicts.Tests.ps1`

- [ ] **Step 1: Write the failing detector + formatter tests**

Append to `tests/Unit/KnownConflicts.Tests.ps1` (inside `BeforeAll`, add the dot-sources; then add the Describe blocks):

In `BeforeAll`, after the existing lines, add:

```powershell
    . (Join-Path $RepoRoot 'src\DLLPickle\Private\Test-DPModuleConflict.ps1')
    . (Join-Path $RepoRoot 'src\DLLPickle\Private\Get-DPKnownConflict.ps1')
    . (Join-Path $RepoRoot 'src\DLLPickle\Private\Format-DPConflictWarning.ps1')

    $SampleConflict = [PSCustomObject]@{
        id = 'sample'; modules = @('Alpha', 'Beta'); assembly = 'Some.Assembly'; issue = '999'
        reason = 'Alpha and Beta clash.'; workaround = 'Use separate sessions.'
    }
```

Append these Describe blocks:

```powershell
Describe 'Test-DPModuleConflict' -Tag 'Unit' {
    It 'returns a conflict when every module in the pair is loaded' {
        $Active = Test-DPModuleConflict -Conflict @($SampleConflict) -LoadedModule @('Alpha', 'Beta', 'Gamma')
        @($Active).Count | Should -Be 1
        $Active[0].id | Should -Be 'sample'
    }

    It 'returns nothing when only one module in the pair is loaded' {
        $Active = Test-DPModuleConflict -Conflict @($SampleConflict) -LoadedModule @('Alpha', 'Gamma')
        @($Active) | Should -BeNullOrEmpty
    }

    It 'returns nothing for an empty conflict list' {
        $Active = Test-DPModuleConflict -Conflict @() -LoadedModule @('Alpha', 'Beta')
        @($Active) | Should -BeNullOrEmpty
    }
}

Describe 'Format-DPConflictWarning' -Tag 'Unit' {
    It 'includes the modules, workaround, and issue link' {
        $Message = Format-DPConflictWarning -Conflict $SampleConflict
        $Message | Should -Match 'Alpha'
        $Message | Should -Match 'Beta'
        $Message | Should -Match 'separate sessions'
        $Message | Should -Match 'issues/999'
    }
}

Describe 'Get-DPKnownConflict' -Tag 'Unit' {
    It 'reads conflicts from an explicit path' {
        $Path = Join-Path $TestDrive 'kc.json'
        ConvertTo-Json -InputObject @($SampleConflict) -Depth 20 | Set-Content -LiteralPath $Path -Encoding utf8
        $Conflicts = Get-DPKnownConflict -Path $Path
        @($Conflicts).Count | Should -Be 1
        $Conflicts[0].id | Should -Be 'sample'
    }

    It 'returns an empty array when the file is missing' {
        $Conflicts = Get-DPKnownConflict -Path (Join-Path $TestDrive 'nope.json')
        @($Conflicts) | Should -BeNullOrEmpty
    }

    It 'returns an empty array (no throw) when the file is malformed' {
        $Path = Join-Path $TestDrive 'bad.json'
        Set-Content -LiteralPath $Path -Value '{ not json' -Encoding utf8
        { Get-DPKnownConflict -Path $Path } | Should -Not -Throw
        @(Get-DPKnownConflict -Path $Path) | Should -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/Unit/KnownConflicts.Tests.ps1 -Output Detailed"`
Expected: FAIL — the three Private scripts don't exist (dot-source errors).

- [ ] **Step 3: Create `Test-DPModuleConflict.ps1`**

```powershell
function Test-DPModuleConflict {
    <#
    .SYNOPSIS
        Returns the known conflicts whose every module is currently loaded.
    .DESCRIPTION
        Pure comparison: given the knownConflicts data and the set of loaded module names, returns the
        conflict entries where every module in the pair appears in the loaded set. No side effects.
    .PARAMETER Conflict
        The knownConflicts entries (each with a .modules string array).
    .PARAMETER LoadedModule
        The names of modules currently imported in the session.
    .OUTPUTS
        The subset of Conflict whose modules are all loaded.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$Conflict,

        [Parameter()]
        [string[]]$LoadedModule
    )

    process {
        foreach ($Entry in @($Conflict)) {
            $Modules = @($Entry.modules)
            if ($Modules.Count -eq 0) { continue }
            $AllLoaded = $true
            foreach ($Name in $Modules) {
                if ($LoadedModule -notcontains $Name) { $AllLoaded = $false; break }
            }
            if ($AllLoaded) { $Entry }
        }
    }
}
```

- [ ] **Step 4: Create `Format-DPConflictWarning.ps1`**

```powershell
function Format-DPConflictWarning {
    <#
    .SYNOPSIS
        Builds the user-facing warning message for a known module conflict.
    .PARAMETER Conflict
        A knownConflicts entry (modules, reason, workaround, issue).
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object]$Conflict
    )

    process {
        $Modules = @($Conflict.modules) -join ' + '
        $Lines = @(
            "DLLPickle: '$Modules' cannot be used together in one PowerShell session. $($Conflict.reason)"
            "Workaround: $($Conflict.workaround)"
            "Details: https://github.com/SamErde/DLLPickle/issues/$($Conflict.issue)"
        )
        $Lines -join [System.Environment]::NewLine
    }
}
```

- [ ] **Step 5: Create `Get-DPKnownConflict.ps1`**

```powershell
function Get-DPKnownConflict {
    <#
    .SYNOPSIS
        Reads the module's shipped knownConflicts data.
    .DESCRIPTION
        Loads KnownConflicts.json (shipped at the module root by the build) and returns the conflict
        array. Returns an empty array - never throws - if the file is missing or malformed, so the
        advisory warning can never break a session.
    .PARAMETER Path
        Optional path to a knownConflicts JSON file. Defaults to KnownConflicts.json at the module root
        (this script lives in <module>/Private, so the module root is its parent directory).
    .OUTPUTS
        The knownConflicts entries, or an empty array.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path
    )

    process {
        if (-not $Path) {
            $Path = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'KnownConflicts.json'
        }
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            Write-Verbose "No knownConflicts file at '$Path'."
            return @()
        }
        try {
            return @((Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json))
        } catch {
            Write-Verbose "Could not parse knownConflicts at '$Path': $_"
            return @()
        }
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/Unit/KnownConflicts.Tests.ps1 -Output Detailed"`
Expected: PASS — all detector/formatter/reader tests green.

- [ ] **Step 7: Run the analyzer**

Run: `pwsh -NoProfile -Command "Invoke-Build -File ./build/DLLPickle.Build.ps1 -Task Analyze"`
Expected: PASS — no findings (approved verbs `Test`/`Format`/`Get`; no `Write-Host`).

- [ ] **Step 8: Commit**

```bash
git add src/DLLPickle/Private/Test-DPModuleConflict.ps1 src/DLLPickle/Private/Format-DPConflictWarning.ps1 src/DLLPickle/Private/Get-DPKnownConflict.ps1 tests/Unit/KnownConflicts.Tests.ps1
git commit -m "feat(module): add knownConflicts reader, detector, and warning formatter (private)"
```

---

## Task 4: Public `Test-DPLibraryConflict`

**Files:**
- Create: `src/DLLPickle/Public/Test-DPLibraryConflict.ps1`
- Modify: `src/DLLPickle/DLLPickle.psd1`
- Test: `tests/Unit/KnownConflicts.Tests.ps1`

- [ ] **Step 1: Write the failing public-function tests**

In `BeforeAll`, add the dot-source:

```powershell
    . (Join-Path $RepoRoot 'src\DLLPickle\Public\Test-DPLibraryConflict.ps1')
```

Append this Describe block (it uses two real, always-loaded modules so the loaded-check is true):

```powershell
Describe 'Test-DPLibraryConflict' -Tag 'Unit' {
    BeforeAll {
        Import-Module Microsoft.PowerShell.Management -ErrorAction SilentlyContinue
        Import-Module Microsoft.PowerShell.Utility -ErrorAction SilentlyContinue
        $LoadedPairPath = Join-Path $TestDrive 'loaded-pair.json'
        ConvertTo-Json -Depth 20 -InputObject @(
            [PSCustomObject]@{ id = 'loaded'; modules = @('Microsoft.PowerShell.Management', 'Microsoft.PowerShell.Utility'); assembly = 'x'; issue = '174'; reason = 'r'; workaround = 'w' }
        ) | Set-Content -LiteralPath $LoadedPairPath -Encoding utf8
        $UnloadedPairPath = Join-Path $TestDrive 'unloaded-pair.json'
        ConvertTo-Json -Depth 20 -InputObject @(
            [PSCustomObject]@{ id = 'unloaded'; modules = @('No.Such.ModuleA', 'No.Such.ModuleB'); assembly = 'x'; issue = '174'; reason = 'r'; workaround = 'w' }
        ) | Set-Content -LiteralPath $UnloadedPairPath -Encoding utf8
    }

    It 'warns and returns the conflict when both modules are loaded' {
        $Active = Test-DPLibraryConflict -KnownConflictsPath $LoadedPairPath -WarningAction SilentlyContinue
        @($Active).Count | Should -Be 1
        $Active[0].id | Should -Be 'loaded'
    }

    It 'emits a Write-Warning when a conflict is active' {
        $Warnings = $null
        Test-DPLibraryConflict -KnownConflictsPath $LoadedPairPath -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null
        @($Warnings).Count | Should -BeGreaterThan 0
    }

    It 'is silent and returns nothing when no conflict pair is fully loaded' {
        $Warnings = $null
        $Active = Test-DPLibraryConflict -KnownConflictsPath $UnloadedPairPath -WarningVariable Warnings -WarningAction SilentlyContinue
        @($Active) | Should -BeNullOrEmpty
        @($Warnings) | Should -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/Unit/KnownConflicts.Tests.ps1 -Output Detailed"`
Expected: FAIL — `Test-DPLibraryConflict` not defined.

- [ ] **Step 3: Create `Test-DPLibraryConflict.ps1`**

```powershell
function Test-DPLibraryConflict {
    <#
    .SYNOPSIS
        Reports known module conflicts that are active in the current PowerShell session.
    .DESCRIPTION
        Compares DLLPickle's shipped knownConflicts list against the modules currently imported and
        writes a warning for each conflict whose modules are all loaded together (a combination known
        to fail, such as Az.Storage + ExchangeOnlineManagement sharing an incompatible Microsoft.OData
        version). Returns the active conflict objects. Advisory only - never throws.
    .PARAMETER KnownConflictsPath
        Optional path to a knownConflicts JSON file. Defaults to the file shipped with the module.
    .OUTPUTS
        The active conflict entries (or nothing if none are active).
    .EXAMPLE
        Test-DPLibraryConflict

        Warns if any known-incompatible module combination is currently loaded.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$KnownConflictsPath
    )

    process {
        $Conflicts = Get-DPKnownConflict -Path $KnownConflictsPath
        $LoadedModule = @(Get-Module | Select-Object -ExpandProperty Name)
        $Active = @(Test-DPModuleConflict -Conflict $Conflicts -LoadedModule $LoadedModule)
        foreach ($Entry in $Active) {
            Write-Warning -Message (Format-DPConflictWarning -Conflict $Entry)
        }
        $Active
    }
}
```

- [ ] **Step 4: Export the function in the manifest**

In `src/DLLPickle/DLLPickle.psd1`, add `'Test-DPLibraryConflict'` to the `FunctionsToExport` array (alongside the existing entries).

- [ ] **Step 5: Run the tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/Unit/KnownConflicts.Tests.ps1 -Output Detailed"`
Expected: PASS.

- [ ] **Step 6: Run the analyzer**

Run: `pwsh -NoProfile -Command "Invoke-Build -File ./build/DLLPickle.Build.ps1 -Task Analyze"`
Expected: PASS — no findings.

- [ ] **Step 7: Commit**

```bash
git add src/DLLPickle/Public/Test-DPLibraryConflict.ps1 src/DLLPickle/DLLPickle.psd1 tests/Unit/KnownConflicts.Tests.ps1
git commit -m "feat(module): add public Test-DPLibraryConflict"
```

---

## Task 5: `Invoke-DPConflictCheck` + `Import-DPLibrary` integration

**Files:**
- Create: `src/DLLPickle/Private/Invoke-DPConflictCheck.ps1`
- Modify: `src/DLLPickle/Public/Import-DPLibrary.ps1`

- [ ] **Step 1: Create `Invoke-DPConflictCheck.ps1`**

```powershell
function Invoke-DPConflictCheck {
    <#
    .SYNOPSIS
        After preload, warns about (or arms a one-shot warning for) known incompatible module pairs.
    .DESCRIPTION
        For each known conflict: if every module is already loaded, warn immediately. Otherwise, if
        every module is installed (so the clash can still happen later), register a single
        AssemblyLoad handler that warns the first time the remaining module's assemblies load, then
        unregisters itself. Advisory only: fully guarded, never throws, and skipped under Constrained
        Language Mode (where the AppDomain APIs are unavailable).
    .PARAMETER KnownConflictsPath
        Optional override for the knownConflicts file (testing). Defaults to the shipped file.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$KnownConflictsPath
    )

    process {
        try {
            if ($ExecutionContext.SessionState.LanguageMode -eq [System.Management.Automation.PSLanguageMode]::ConstrainedLanguage) {
                Write-Verbose 'Constrained Language Mode: skipping conflict-watch arming.'
                return
            }

            $Conflicts = Get-DPKnownConflict -Path $KnownConflictsPath
            if (@($Conflicts).Count -eq 0) { return }

            $LoadedNames = @(Get-Module | Select-Object -ExpandProperty Name)
            $AvailableNames = @(Get-Module -ListAvailable | Select-Object -ExpandProperty Name -Unique)

            foreach ($Conflict in $Conflicts) {
                $Modules = @($Conflict.modules)
                if ($Modules.Count -eq 0) { continue }

                $LoadedCount = @($Modules | Where-Object { $LoadedNames -contains $_ }).Count
                if ($LoadedCount -eq $Modules.Count) {
                    Write-Warning -Message (Format-DPConflictWarning -Conflict $Conflict)
                    continue
                }

                $AllInstalled = $true
                foreach ($Name in $Modules) {
                    if ($AvailableNames -notcontains $Name) { $AllInstalled = $false; break }
                }
                if (-not $AllInstalled) { continue }

                # Watch the not-yet-loaded module(s): capture their installed base path(s) now, and warn
                # the first time an assembly loads from one of them (meaning the pair is now co-loaded).
                $WatchedBase = @(
                    $Modules |
                        Where-Object { $LoadedNames -notcontains $_ } |
                        ForEach-Object { Get-Module -ListAvailable -Name $_ | Sort-Object Version -Descending | Select-Object -First 1 -ExpandProperty ModuleBase } |
                        Where-Object { $_ }
                )
                if ($WatchedBase.Count -eq 0) { continue }

                $State = [PSCustomObject]@{ Conflict = $Conflict; Bases = $WatchedBase; Handler = $null }
                $State.Handler = [System.AssemblyLoadEventHandler]{
                    param($EventSender, $LoadArgs)
                    try {
                        $Location = $LoadArgs.LoadedAssembly.Location
                        if ($Location) {
                            foreach ($Base in $State.Bases) {
                                if ($Location.StartsWith($Base, [System.StringComparison]::OrdinalIgnoreCase)) {
                                    Write-Warning -Message (Format-DPConflictWarning -Conflict $State.Conflict)
                                    [System.AppDomain]::CurrentDomain.remove_AssemblyLoad($State.Handler)
                                    break
                                }
                            }
                        }
                    } catch {
                        # Advisory only: never let the warning path disrupt assembly loading.
                    }
                }.GetNewClosure()
                [System.AppDomain]::CurrentDomain.add_AssemblyLoad($State.Handler)
            }
        } catch {
            Write-Verbose "Conflict check skipped due to error: $_"
        }
    }
}
```

- [ ] **Step 2: Call it from `Import-DPLibrary`**

In `src/DLLPickle/Public/Import-DPLibrary.ps1`, near the end of the function (after the preload work completes, before the function returns its results), add:

```powershell
        # Advisory: warn about known-incompatible module combinations (e.g. #174 Az.Storage + EXO).
        try {
            Invoke-DPConflictCheck
        } catch {
            Write-Verbose "Invoke-DPConflictCheck failed: $_"
        }
```

(Place it inside the same scope where the rest of the import logic runs, guarded so it can never affect the import result.)

- [ ] **Step 3: Verify the module imports and the function is callable**

Run:
```bash
pwsh -NoProfile -Command "Invoke-Build -File ./build/DLLPickle.Build.ps1 -Task PrepareModuleOutput; Import-Module ./module/DLLPickle/DLLPickle.psd1 -Force; Import-DPLibrary -SuppressLogo | Out-Null; 'ok'"
```
Expected: ends with `ok` (no errors; the conflict check is a no-op unless both conflicting modules are present).

- [ ] **Step 4: Run the analyzer**

Run: `pwsh -NoProfile -Command "Invoke-Build -File ./build/DLLPickle.Build.ps1 -Task Analyze"`
Expected: PASS — no findings (`Invoke` is approved and not state-changing-flagged).

- [ ] **Step 5: Commit**

```bash
git add src/DLLPickle/Private/Invoke-DPConflictCheck.ps1 src/DLLPickle/Public/Import-DPLibrary.ps1
git commit -m "feat(module): warn on known module conflicts from Import-DPLibrary (immediate + armed handler)"
```

---

## Task 6: Known-limitation documentation

**Files:**
- Modify: `docs/Deep-Dive.md`

- [ ] **Step 1: Add a known-limitation section**

Append a section to `docs/Deep-Dive.md`:

```markdown
## Known limitation: Az.Storage + ExchangeOnlineManagement (issue #174)

`Az.Storage` and `ExchangeOnlineManagement` bundle **incompatible, strong-named versions of
`Microsoft.OData.Core`** (7.6.4 and 7.22.0 respectively) and both load it into the default
`AssemblyLoadContext`. Only one version can exist per process, and **neither import order works**:

- Import `Az.Storage` first, then run `Get-EXO*` → fails (`Could not load … Microsoft.OData.Core,
  Version=7.22.0.0 … manifest definition does not match`).
- Import `ExchangeOnlineManagement`/`Connect-ExchangeOnline` first, then import `Az.Storage` → fails
  (`Microsoft.OData.Core, Version=7.6.4.0 … assembly with same name is already loaded`).

This is an upstream incompatibility between the two modules; **DLLPickle cannot fix it by preloading**
(preloading either version breaks the other module), which is why the OData assemblies are
classified `block`. DLLPickle warns when it detects both modules loaded (see `Test-DPLibraryConflict`).

**Workaround:** use the two modules in **separate PowerShell sessions or processes** — for example,
run `Get-EXO*` work in one `pwsh`/runspace/background job and `Az.Storage` work in another.
```

- [ ] **Step 2: Commit**

```bash
git add docs/Deep-Dive.md
git commit -m "docs: document the Az.Storage + EXO OData known limitation (#174)"
```

---

## Task 7: Extend the #174 repro test to both orders

**Files:**
- Modify: `tests/Integration/DLLPickle.Issue174.OData.Tests.ps1`

**Why a rework:** the current `Initialize-Issue174SyntheticModule` makes `Get-EXOMailbox` throw unless a real `Microsoft.OData.Core` 7.22 assembly is loaded (which never happens synthetically), so it can only model the Az.Storage-first failure. To model **both** orders, replace the helper with a single shared "OData slot" global (`$global:DPSyntheticODataVersion`) that simulates the one default-ALC OData identity: Az.Storage force-loads 7.6.4 **at import** (throws if a higher version already occupies the slot); EXO's `Get-EXOMailbox` lazily needs 7.22.0 (throws if the lower version is already in the slot, else takes the slot and succeeds). Each scenario runs in a fresh child `pwsh`, so the slot is naturally per-scenario.

- [ ] **Step 1: Replace `Initialize-Issue174SyntheticModule`**

Replace the entire `Initialize-Issue174SyntheticModule` function (in the file's `BeforeAll`) with:

```powershell
    function Initialize-Issue174SyntheticModule {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$RootPath,

            [Parameter(Mandatory)]
            [ValidateSet('Az.Storage', 'ExchangeOnlineManagement')]
            [string]$Name,

            [Parameter(Mandatory)]
            [string]$Version
        )

        $ModuleDirectory = Join-Path -Path $RootPath -ChildPath ([System.IO.Path]::Combine($Name, $Version))
        $null = New-Item -Path $ModuleDirectory -ItemType Directory -Force
        $ModuleFile = Join-Path -Path $ModuleDirectory -ChildPath "$Name.psm1"
        $ManifestFile = Join-Path -Path $ModuleDirectory -ChildPath "$Name.psd1"

        if ($Name -eq 'Az.Storage') {
            @'
# Synthetic Az.Storage: at import it force-loads Microsoft.OData.Core 7.6.4 into the single shared
# OData slot. If a higher version (EXO 7.22.0) already holds the slot, the load collides.
if ($global:DPSyntheticODataVersion -and [version]$global:DPSyntheticODataVersion -gt [version]'7.6.4.0') {
    throw [System.IO.FileNotFoundException]::new("Could not load file or assembly 'Microsoft.OData.Core, Version=7.6.4.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35'. Assembly with same name is already loaded")
}
$global:DPSyntheticODataVersion = '7.6.4.0'

function New-AzStorageContext {
    [CmdletBinding()]
    param(
        [Parameter()] [string]$StorageAccountName,
        [Parameter()] [switch]$Anonymous
    )
    [PSCustomObject]@{ StorageAccountName = $StorageAccountName }
}
Export-ModuleMember -Function New-AzStorageContext
'@ | Set-Content -LiteralPath $ModuleFile -Encoding UTF8
        } else {
            @'
function Connect-ExchangeOnline {
    [CmdletBinding()]
    param(
        [Parameter()] [switch]$ManagedIdentity,
        [Parameter()] [string]$Organization
    )
    [PSCustomObject]@{ Connected = $true; Organization = $Organization }
}

# Synthetic EXO: Get-EXO* lazily needs Microsoft.OData.Core 7.22.0. If the lower 7.6.4 already holds
# the slot (Az.Storage imported first), the higher reference cannot bind; otherwise it takes the slot.
function Get-EXOMailbox {
    [CmdletBinding()]
    param(
        [Parameter()] [int]$ResultSize
    )
    if ($global:DPSyntheticODataVersion -and [version]$global:DPSyntheticODataVersion -lt [version]'7.22.0.0') {
        throw [System.IO.FileNotFoundException]::new("Could not load file or assembly 'Microsoft.OData.Core, Version=7.22.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35'. The located assembly's manifest definition does not match the assembly reference. (0x80131040)")
    }
    $global:DPSyntheticODataVersion = '7.22.0.0'
    [PSCustomObject]@{ DisplayName = 'Synthetic mailbox' }
}
Export-ModuleMember -Function Connect-ExchangeOnline, Get-EXOMailbox
'@ | Set-Content -LiteralPath $ModuleFile -Encoding UTF8
        }

        New-ModuleManifest -Path $ManifestFile -RootModule "$Name.psm1" -ModuleVersion $Version -FunctionsToExport '*' -ErrorAction Stop
    }
```

The two existing tests keep their assertions and still pass with this model: in the Az.Storage→EXO order, Az.Storage takes the slot at 7.6.4, then `Get-EXOMailbox` sees 7.6.4 < 7.22 and throws a `Microsoft.OData.Core` error (their `Should -Match 'Microsoft.OData.Core'` still holds; the DLLPickle-preload test's `AssembliesAfter` check is about the real built module and is unaffected).

- [ ] **Step 2: Add the EXO-first It block**

Add to the `Describe 'Issue 174 …'` block:

```powershell
    It 'fails the EXO-first order too: importing Az.Storage after EXO is loaded throws' {
        $Result = Invoke-DLLPickleScenario -Name 'Issue174-EXOThenAzStorage-Synthetic' `
            -ModuleManifestPath $BuiltModuleManifestPath `
            -AdditionalModulePath $SyntheticModuleRoot `
            -OutputPath (Join-Path $ScenarioOutputRoot 'Issue174-EXOThenAzStorage-Synthetic.json') `
            -Step @(
                @{ Name = 'Import ExchangeOnlineManagement'; Script = 'Import-Module ExchangeOnlineManagement -Force' }
                @{ Name = 'Connect ExchangeOnlineManagement'; Script = 'Connect-ExchangeOnline -ManagedIdentity -Organization synthetic.example' }
                @{ Name = 'Get EXO Mailbox'; Script = 'Get-EXOMailbox' }
                @{ Name = 'Import Az.Storage'; Script = 'Import-Module Az.Storage -Force' }
            )

        $Result.Success | Should -BeFalse
        $MailboxStep = $Result.Steps | Where-Object Name -EQ 'Get EXO Mailbox'
        $MailboxStep.Success | Should -BeTrue
        $AzStorageStep = $Result.Steps | Where-Object Name -EQ 'Import Az.Storage'
        $AzStorageStep.Success | Should -BeFalse
        $AzStorageStep.Error.Message | Should -Match 'Microsoft.OData.Core'
    }
```

(Note the EXO-first assertions: `Get-EXOMailbox` now **succeeds** — taking the slot at 7.22.0 — and the subsequent **Az.Storage import** fails. This is the inverse of the Az.Storage-first test.)

- [ ] **Step 3: Run the issue-repro suite to verify both orders fail**

Run: `pwsh -NoProfile -Command "Invoke-Build -File ./build/DLLPickle.Build.ps1 -Task IssueReproTest"`
Expected: PASS — the Az.Storage-first tests (Get-EXOMailbox fails) and the new EXO-first test (Az.Storage import fails) all assert the expected failures.

- [ ] **Step 4: Commit**

```bash
git add tests/Integration/DLLPickle.Issue174.OData.Tests.ps1
git commit -m "test(#174): model both import orders with a shared OData slot (EXO-first fails on Az.Storage import)"
```

---

## Task 8: Validate the full gate and post the #174 findings

**Files:** none (verification + coordination)

- [ ] **Step 1: Run the full gate**

Run: `pwsh -NoProfile -Command "Invoke-Build -File ./build/DLLPickle.Build.ps1 -Task Analyze,Test"`
Expected: PASS — analyzer clean on src/tests/tools; all unit tests pass (existing + the new `KnownConflicts.Tests.ps1`).

- [ ] **Step 2: Smoke the public function against the shipped data**

Run:
```bash
pwsh -NoProfile -Command "Invoke-Build -File ./build/DLLPickle.Build.ps1 -Task PrepareModuleOutput; Import-Module ./module/DLLPickle/DLLPickle.psd1 -Force; Test-DPLibraryConflict -WarningAction SilentlyContinue | Format-Table id,modules"
```
Expected: no error; returns nothing (unless both Az.Storage + EXO happen to be loaded). Confirms the shipped `KnownConflicts.json` is readable.

- [ ] **Step 3: Post the findings comment on #174 (keep it open)**

The controller posts a comment on issue #174 summarizing the Phase 1 runtime evidence (both orders fail; OData stays `block`), the workaround (separate sessions), and the new `Test-DPLibraryConflict` warning. Do **not** close the issue. This is a coordination step, not a code change.

---

## Notes for the implementer

- **Pester:** `Invoke-Pester -Path <file>` (Pester 5; the bootstrap installs it). The full suite runs via `Invoke-Build -Task Test`.
- **Analyzer:** `AnalyzeTests` excludes only `PSUseDeclaredVarsMoreThanAssignments`; `AnalyzeTools` excludes nothing. Every function here uses an approved, non-state-changing verb (`Get`/`Test`/`Format`/`Invoke`). No `Write-Host`.
- **Never throw:** the warning path is advisory. `Get-DPKnownConflict`, `Invoke-DPConflictCheck`, and the AssemblyLoad handler are all try/catch-guarded and degrade to silence.
- **CLM:** the armed handler uses `[AppDomain]`/`AssemblyLoadContext`; it is skipped under Constrained Language Mode. CI and normal `pwsh` run Full Language Mode.
- **Release:** `src/DLLPickle/**` changes here are a real module feature → merging triggers a PSGallery release (minor, from `feat:` commits). The runbook/probe tooling from Phase 1 is unaffected.
