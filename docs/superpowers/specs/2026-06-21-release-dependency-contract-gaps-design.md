# Release & Dependency-Update Contract — §10 Gap Closure Design

## Goal

Make the CI/release automation implement the **intended** release & dependency-update
contract that `docs/Architecture.md` §8 documents, closing the three deltas recorded in
§10:

1. **Gap 1** — a merged Dependabot NuGet bump (commit prefix `deps:`) satisfies the publish
   path gate but is not recognized by `Get-VersionBump.ps1`, so `ShouldRelease = $false`
   and no module version is published (decisions 3 & 4).
2. **Gap 2** — major dependency PRs are excluded from auto-merge but only receive a generic
   "requires manual review" comment, not the draft + fully detailed notes decision 4
   requires.
3. **Gap 3** — "TFM alignment" (§8.2 Step 0) is only half-enforced: the Build gate (0a)
   exists, but the explicit `net8.0`/`netstandard2.0` asset inspection (0b) does not.

## Supported Baseline

- PowerShell 7.4+ on the `net8.0` dependency bundle (unchanged).
- This change touches release/CI automation, tooling, tests, and docs only. **No bundle
  path** (`src/DLLPickle/**`, `DLLPickle.csproj`, `packages.lock.json`) is modified, so per
  §8.1 the implementation PR does not itself publish a module version. The first real
  validation of Gap 1 is the next dependency bump merged after this lands.

## Settled Decisions (inputs, not re-litigated)

- A routine tracked-dependency minor/patch bump produces a **minor** module release
  (`deps → minor`).
- TFM alignment = Build gate (0a) **and** explicit TFM inspection (0b) — both halves.
- Major dependency releases land as a **tested draft PR with fully detailed notes**, never
  auto-merged, never auto-published.

## Gap 1 — `deps → minor` in Get-VersionBump.ps1

### Approach

Add `deps` to the existing **minor** prefix alternation in
`.github/ci-scripts/Get-VersionBump.ps1`:

```text
^(feat|minor)(\(.+\))?:   →   ^(feat|minor|deps)(\(.+\))?:
```

`.github/dependabot.yml` is left unchanged.

### Rationale

- Keeps the single "what triggers a release" decision in `Get-VersionBump.ps1`, and leaves
  the Dependabot config conventional.
- **Scoping confirmed against `dependabot.yml`:** only the NuGet ecosystem uses the `deps`
  prefix. github-actions uses `ci`, pip uses `docs`, and docker/devcontainers use the
  Dependabot default (`Bump …`, no colon-prefix). So `deps → minor` affects NuGet bumps
  only.
- NuGet bumps only ever change `DLLPickle.csproj` / `packages.lock.json` (both bundle
  paths), so `deps:` correctly yields path gate ✔ + version gate ✔ = a **minor** publish.
- Major precedence is preserved: the analysis loop still `break`s to `major` when a
  `breaking:` / `BREAKING CHANGE:` / `major-release` commit is present, so a
  maintainer-promoted major dependency PR carried as `breaking:` still resolves to major.

### Verification

New `tests/Unit/GetVersionBump.Tests.ps1` runs the script against an ephemeral `$TestDrive`
git repository with synthetic commits (signing/hooks disabled for hermetic, deterministic
runs — these are throwaway test-repo commits, not repository commits):

- `deps:` (and `deps(scope):`) → `ShouldRelease = $true`, `NewVersionType = 'minor'`.
- `docs:` / `ci:` / `style:` → `NewVersionType = 'none'`, `ShouldRelease = $false`.
- Regression guards: `feat:` → minor, `fix:` → patch, `breaking:` → major still hold,
  and major wins when mixed with `deps:`.

## Gap 3 — Explicit TFM-alignment inspection (Step 0b)

### Approach

Add a read-only tool `tools/Test-DLLPickleTfmAlignment.ps1`:

- A **pure compatibility core** decides whether a single target-framework moniker is
  consumable by `net8.0`:
  - consumable: `.NET 5+` style (`net8.0`, lower `netX.0`), `netcoreapp*`, and
    `.NET Standard` (`netstandard2.1` / `2.0` / `1.x`);
  - not consumable: `.NET Framework` (`net48`, `net472`, `net4xx`, `net2x`/`net3x`) and
    unknown/garbage monikers (fail-closed).
  - Platform suffixes (`net8.0-windows`) are reduced to their base TFM before parsing.
- A **package inspector** enumerates `lib/<tfm>/` folders of a restored NuGet package and
  marks the package **aligned** iff at least one lib asset is net8.0-consumable.
  No `lib/` (or no consumable asset) ⇒ **not aligned**.
- The script resolves the `preload` set from `build/dependency-policy.json`, resolved
  versions from `packages.lock.json`, and package roots from the NuGet global-packages
  folder (`$env:NUGET_PACKAGES` else `~/.nuget/packages`), then emits a structured
  per-package result plus an aggregate, and writes a JSON report.

This is a focused subset of NuGet's compatibility model — sufficient for the in-scope MSAL +
IdentityModel families (all ship `netstandard2.0` and/or `net8.0`) — not a full resolver.
It is documented as such.

### Wiring

A new **fail-closed** step in the **scheduled** job of
`.github/workflows/Upstream-Compatibility.yml`, after the existing
`Generate candidate dependency updates` step (which already runs `-Restore`), runs the tool
against the restored packages, writes a job-summary table, uploads the report as a
candidate artifact, and fails the job if any preload package is not TFM-aligned (consistent
with the existing fail-closed scheduled flow and §8.2: "a release that fails either half …
must not be merged on the automated path").

### Verification

New `tests/Unit/TfmAlignment.Tests.ps1`:

- pure-core decisions: `net8.0` ✓, `netstandard2.0` ✓, `netstandard2.1` ✓, `net6.0` ✓,
  `netcoreapp3.1` ✓, `net48` ✗, `net472` ✗, `garbage` ✗;
- directory inspection with aligned fixtures (`lib/net8.0/`, `lib/netstandard2.0/`) and
  misaligned fixtures (`lib/net48/` only; a package with no `lib/`). Fixtures are empty
  files in directories — no real assemblies required.

## Gap 2 — Major-dependency draft-PR flow

### Approach

In the `version-update:semver-major` branch of
`.github/workflows/Dependabot-Auto-Approve.yml`:

1. Convert the PR to **draft**: `gh pr ready --undo "$PR_URL"`.
2. Replace the generic comment with **structured notes**:
   - version delta (from `dependabot/fetch-metadata` outputs: dependency names, previous /
     new version);
   - a real NuGet package page link (no fabricated changelog URL — brand rule: never
     fabricate specifics);
   - **TFM-alignment** line (see decision below);
   - **Build gate / CI** link (`$PR_URL/checks`) for the Pester/CI outcome;
   - **conflict-surface / `dependency-policy.json`** impact, referencing the
     Upstream-Compatibility drift gate.
3. A **maintainer checklist** to complete before marking the PR ready: re-adjudicate the §3
   preload/block classifications; auth-tier real-environment sign-off per §9; confirm TFM
   alignment (0a + 0b); refresh the `dependency-policy.json` baseline if the conflict surface
   moved; merge carrying a `breaking:` prefix for the intended major release.

Majors remain excluded from `gh pr merge --auto` (unchanged — the approve/auto-merge step
keeps its `update-type != 'version-update:semver-major'` guard, and the major branch never
calls `--auto`).

### TFM-alignment line — decision 2a (approved)

The major-PR comment **references** rather than recomputes the TFM result: it states that
TFM alignment is proven by the `Build gate` required check (0a) and points to
`tools/Test-DLLPickleTfmAlignment.ps1` (0b) as a checklist item. This keeps the
write-scoped comment workflow lightweight; the live 0b gate runs in the candidate flow
(Gap 3), and the major path is never auto-published, so a referenced (not inlined) verdict
is sufficient. (Rejected alternative 2b: checkout + setup-dotnet + restore + inline tool run
in the major branch — materially heavier on a rare, non-auto-merged path.)

### Verification

Extend `tests/Unit/WorkflowGuardrails.Tests.ps1` to assert the workflow contains the draft
conversion (`gh pr ready --undo`), the structured-notes scaffold markers (TFM-alignment /
conflict-surface / maintainer-checklist headings), and that majors remain excluded from
`--auto`. The live draft path cannot be exercised without a real Dependabot PR, so the test
is a structural assertion on the workflow text (validated alongside a careful read).

## Documentation Changes

Because closing these gaps makes the documented contract true, the §10 gap notes and the
§8 caveats are corrected (not new policy):

- `docs/Architecture.md` §8.1 — move `deps:` from the "no publish" list into the **minor**
  prefix row.
- `docs/Architecture.md` §8.2 — drop the "must carry `feat:`" workaround caveat for routine
  bumps; note 0b is now enforced.
- `docs/Architecture.md` §10 — mark the three gaps resolved (what implements each).
- `docs/DEPENDENCIES.md` and `CHANGELOG.md` — reflect `deps → minor`, the major draft-PR notes,
  and the TFM-alignment tool.

In-progress working-tree edits to these docs are diffed first so they are not clobbered.

## Constraints & Gates

- **TDD**: a failing test precedes each gap's implementation.
- `tests/` and `tools/` stay analyzer-clean: test helpers use `Get-*` verbs (the
  `AnalyzeTests` task excludes only `PSUseDeclaredVarsMoreThanAssignments`); the new tool is
  read-only, so it needs no `ShouldProcess`. `PSScriptAnalyzerSettings.psd1` is not weakened.
- **No commits or pushes** until the maintainer asks; branch off `main`.
- Release-automation changes are not auto-merged; they need maintainer review and, for the
  bundled set, the auth-tier sign-off — though this PR touches no bundle path.

## Verification (whole change)

- `Invoke-Build -Task Analyze,Test -File ./build/DLLPickle.Build.ps1` stays green, including
  the new `GetVersionBump`, `TfmAlignment`, and extended `WorkflowGuardrails` tests.
- Dry-run the version-bump logic against synthetic commit messages.
- Careful read / `act`-style validation of the Dependabot workflow YAML (the draft path
  can't be exercised without a real Dependabot PR).
