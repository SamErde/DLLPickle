---
title: Configuration validation and generated-input pilot
post_title: Configuration validation and generated-input pilot
author1: OpenAI Codex
post_slug: configuration-validation-generated-input-pilot
microsoft_alias: null
featured_image: null
categories: []
tags: [PowerShell, testing, security]
ai_note: Prepared with OpenAI Codex for maintainer review.
summary: Bounded configuration validation, reproducible tests, and badge evidence.
post_date: 2026-11-06
---

Issue: [#322](https://github.com/SamErde/DLLPickle/issues/322).
Baseline: `9e79bac6371e1fa498dd4fb23715863026c3d091` (current main at investigation).

## Baseline and decision

On 2026-11-06 the [public assessment JSON](https://www.bestpractices.dev/en/projects/11450.json)
reported Passing **100%**, Silver **45%**, Gold **13%**. An unanswered criterion
does not demonstrate an absent control. Existing architecture documentation,
Pester CI and the scanner threat model already supply evidence not reflected in
some answers. This investigation does not attest to maintainer training, governance,
access continuity, review percentages, or repository-wide coverage.

Current source and policy, rather than historical implementation tasks in the
[multi-targeting plan](2026-08-08-supported-powershell-multitargeting.md), establish
three runtime bundles: PowerShell 7.4.21/.NET 8.0.32/net8.0,
7.5.12/9.0.21/net9.0 and 7.6.7/10.0.13/net10.0. The shipped profile policy checks
PowerShell and CLR identity; the CI matrix covers Windows, Linux and macOS x64.
The SDK is pinned to 10.0.302; Pester to 5.7.1. Existing locked dependencies,
profile-aware dependency policy, package-composition checks, lifecycle checks and
authenticated release-evidence gates remain unchanged. Release jobs bind tagging,
build and publishing to an immutable source revision. No release was performed.

| Candidate | Risk/gap and existing controls | Exact assessment relationship | Benefit, effort, maintenance |
| --- | --- | --- | --- |
| **Configuration validation (selected)** | Syntax/read checks exist; wrong types and root arrays are coerced. Four tests omit schema failures. | Silver `input_validation`: scoped evidence only. Passing `dynamic_analysis` already Met; no Scorecard `Fuzzing` credit. | Prevent unintended preferences; small implementation using existing Pester; maintain a compact corpus. |
| Dependency-order tests | Real-assembly and metadata-only tests exist; cycles, duplicate names and permutations lack coverage. | Silver `input_validation` and regression evidence; no automatic `Fuzzing` credit. | Useful reliability evidence; moderate fixture cost because graph mocks omit metadata behavior. |
| Release verification | Immutable SHA, locked restore and package checks exist; no signing step or user verification procedure found. | Silver `signed_releases`, `version_tags_signed`; Scorecard `Signed-Releases`. | High value, but needs signing identity, key custody and deliverable scope decisions; greater release maintenance. Checksums alone are insufficient. |
| Security expectations documentation | SECURITY.md documents reporting; the existing threat model already describes ownership and trust boundaries. User-facing expectations are less direct. | Silver `documentation_security` unanswered: primarily documentation/evidence gap. | Low maintenance; included only to explain the selected validation guarantee and limits. No new threat model. |
| Measured coverage improvement | Pester coverage and CI exist, with a 30% build threshold; no verified 80% statement-coverage evidence. | Silver `test_statement_coverage80`; Gold `test_statement_coverage90` / `test_branch_coverage80` require separate measurements. | Broader evidence work; raising a threshold without measurements is not protection. Deferred beyond this bounded change. |

Configuration validation wins because there is a directly reproducible behavior
gap in project-owned code and inexpensive, independent contract assertions.
`{"ShowLogo":"false"}` previously becomes true; `[{"ShowLogo":false}]` is
accepted as an object. These are minimized regressions from contract inspection,
not vulnerabilities discovered by coverage-guided fuzzing. No privilege escalation
is claimed: the configuration is controlled by the user running the module.
Review also identified automatic date-string conversion in PowerShell's JSON
parser. The implementation uses the supported runtimes' built-in System.Text.Json
document API to validate JSON kinds and retain exact strings without adding a
dependency. The document is disposed even when validation fails.

## Contract and testing strategy

Only an object root is accepted. Non-null booleans must be JSON booleans; a
non-null skip list must be an array of strings. Missing/null settings retain
defaults and unknown keys remain ignored for compatibility. String contents are
literal filename comparisons in Import-DPLibrary, not executable code, wildcard
patterns or paths to load. The entire invalid configuration is discarded through
the existing DPConfigReadFailed/defaults behavior; ErrorAction Stop terminates.
Set-DPConfig's existing write behavior is outside this change; hand-edited invalid
values must not be relied upon to survive its existing normalization either.
Recognized setting names remain case-insensitive; duplicates are now rejected
instead of allowing ambiguous preferences. Comments and trailing commas remain
accepted. The document parser limits nesting to 64 levels, including unknown
settings; there is no new file-size bound.

The pilot uses Pester's TestDrive and redirects file reads to one fixture. It
never reads or writes the real configuration, imports installed service modules,
loads generated assemblies, or uses credentials/tenants. Production JSON parsing
and validation are not mocked. The existing missing-file and read-error tests
remain. Independent properties are preservation of known typed values (including
order, case and duplicates), complete default fallback and one stable error on
a deliberately invalid type, and terminating-error semantics. The oracle does
not reimplement normalization.

Default seeds: **11450, 322, 20261106**, **32 cases per seed**, each testing a valid
object and one wrong-type mutation (192 generated inputs). Inputs contain at most
eight short names and bounded nesting. Explicit fixtures cover roots, scalar
lists, nested/mixed lists, null members, syntax errors and missing/null fields.
Each seed has a 60-second elapsed-budget assertion; run the process with an outer
180-second timeout to interrupt a stuck call. Diagnostics include seed, case and
complete synthetic JSON. Keep any newly discovered defect as a small explicit
fixture before changing the generator. Fixed seeds are a reproducible pilot,
not exhaustive exploration; .NET Random streams may differ across runtimes, so
record the runtime and emitted failing JSON as well as the seed.

### Replay

Use the exact executable provisioned by `tools/Install-DLLPickleTestPowerShell.ps1`
from `build/powershell-test-matrix.json`, and Pester from `build/build-tool-versions.json`.
First provision the selected runtime and pinned tools while networking is allowed.
For example, save the provisioner's returned executable path:

```powershell
$Matrix = Get-Content ./build/powershell-test-matrix.json -Raw | ConvertFrom-Json
$Provision = @{
    Provider = 'DirectArchive'
    PowerShellVersion = $Matrix.profiles[0].powerShellVersion
}
$Executable = ./tools/Install-DLLPickleTestPowerShell.ps1 @Provision
```

After disabling networking, invoke the helper in a fresh process (from the
repository root). The argument array also makes the process timeout explicit:

```powershell
$ReplayArguments = @(
    '-NoProfile', '-NonInteractive', '-File'
    './build/Invoke-DLLPicklePester.ps1'
    '-TestPath', './tests/Unit/Get-DPConfig.Property.Tests.ps1'
    '-SummaryPath', './summary.json'
    '-TestResultPath', './results.xml'
    '-RequiredPesterVersion', '5.7.1'
)
# Linux: external timeout interrupts a stuck call.
timeout 180 $Executable @ReplayArguments
if ($LASTEXITCODE -ne 0 -or
    (Get-Content ./summary.json -Raw | ConvertFrom-Json).FailedCount -ne 0) {
    throw 'Configuration pilot failed; inspect results.xml.'
}
# Other hosts: launch with & $Executable @ReplayArguments and enforce
# a 180-second timeout in the parent process supervisor.
```

To replay one seed, run this in a fresh process using the same executable (and
the same external process timeout):

```powershell
& $Executable -NoProfile -NonInteractive -Command {
    Import-Module Pester -RequiredVersion 5.7.1
    $Container = New-PesterContainer -Path (
        './tests/Unit/Get-DPConfig.Property.Tests.ps1'
    ) -Data @{ Seeds = @(322); CasesPerSeed = 32 }
    $Result = Invoke-Pester -Container $Container -Output Detailed -PassThru
    if ($Result.FailedCount -gt 0) { exit 1 }
}
```

Do not use execution timeouts as an assertion that large arbitrary configuration
files are resource-bounded: this patch sets no production file-size limit.

## Fuzzing and assessment boundaries

These are **seeded generated-input/property tests**, not coverage-guided fuzzing.
[SharpFuzz](https://github.com/Metalnem/sharpfuzz) instruments .NET assemblies and
supports AFL/libFuzzer; the selected behavior is PowerShell script, while JSON
parsing is provided by PowerShell. Instrumenting the engine would primarily test
dependencies and require a substantially different harness. The dependency bundle
project is not a project-owned parser target. No concrete supported target here
justifies OSS-Fuzz enrollment or an architectural rewrite. The
[OSS-Fuzz guide](https://google.github.io/oss-fuzz/getting-started/new-project-guide/)
requires integrated fuzz targets and a build/runner environment.

[Scorecard Fuzzing](https://github.com/ossf/scorecard/blob/main/docs/checks.md#fuzzing)
detects OSS-Fuzz, ClusterFuzzLite and specified language/library integrations;
Pester is not among them. Best Practices has different criteria: its
[Silver criteria](https://www.bestpractices.dev/en/criteria/1?details=true)
require all relevant untrusted inputs to be validated, and its
`dynamic_analysis_unsafe` concerns memory-unsafe project code with memory-safety
detection. This pilot provides neither whole-project validation nor memory-safety
instrumentation. No Gold criterion becomes satisfied from this patch.

[Scanner environment PR #319](https://github.com/SamErde/DLLPickle/pull/319) is
separate from [enrollment PR #1417](https://github.com/anthropics/oss-scanner/pull/1417),
which was still open/unmerged when rechecked on 2026-11-06. Local offline tests
are not evidence of active Anthropic scanning.

## Validation record

Implementation revision: `410d7267b594e97f091cbcfe953fb1b6058d77b8`.
The later review follow-up changes documentation and renames the hand-written
test to `.Property.Tests.ps1` so automated reviewers do not exclude it as
generated source; its test logic and the product source are unchanged.

The final 29-test corpus against baseline `9e79bac` passed 5 and failed 24.
Against the patch it passed all 29 in 9.55 seconds on Linux PowerShell 7.6.7.
The complete offline acceptance command was:

```sh
docker exec dllpickle-config-322 timeout 1200 pwsh -NoProfile \
  -NonInteractive -File /src/.oss-scanner/test.ps1
```

The container used the existing provisioned scanner image
`sha256:cf150f6118d12598e24e6902b1b770815204556d821f709b3d26757a96f8056b`,
with current-main source overlaid from `git archive` and the changed files copied
in before testing. Inspection confirmed network mode `none`, zero host mounts,
2 CPUs and 8 GiB RAM. Tests ran as the unprivileged `scanner` user on Ubuntu 24.04
under WSL2 x64. An empty container-only Application Data directory was created
before execution. No user configuration or host credentials were mounted.

| PowerShell | .NET | Unit passed | Synthetic integration passed | Failed/skipped |
| --- | --- | --- | --- | --- |
| 7.4.21 | 8.0.32 | 489 | 22 | 0 / 0 |
| 7.5.12 | 9.0.21 | 489 | 22 | 0 / 0 |
| 7.6.7 | 10.0.13 | 489 | 22 | 0 / 0 |

BuildCrossPlatform (17 tasks), pinned analyzer/formatting checks, cached locked
restore, package composition and framework alignment passed. The acceptance
summary reports `passed` for all three profiles. Per-profile XML/JSON reports,
runtime identities, container inspection and focused/baseline logs were retained
locally under `artifacts/config-validation`. The host-side full-build console log
was lost when WSL shut down; per-profile result files were recovered from the
container. The [hosted build run](https://github.com/SamErde/DLLPickle/actions/runs/42187368716)
also passed its offline scanner job and retains independent logs/artifacts.

At this revision, hosted standard Windows/Linux/macOS builds and eight of nine
exact-runtime cells passed. macOS 7.6 failed while downloading Pester, before
tests; it requires a successful new-head run. Hosted jobs are not claimed to be
network-disabled except for the explicit offline scanner job. No Windows broker,
tenant authentication or live-credential claims follow from these results.

The [upstream-evidence run](https://github.com/SamErde/DLLPickle/actions/runs/42187368633)
is a separate merge limitation: the inspected Linux 7.6 conflict and scenario
fingerprints are unchanged, but normalized evidence changed with Az.Accounts
5.5.3 → 5.5.4 and Az.Resources 10.2.1 → 10.2.2. Linux 7.4 also encountered a
damaged Az.Storage package download. The existing
[drift issue #273](https://github.com/SamErde/DLLPickle/issues/273) remains open.
This change does not accept refreshed dependency baselines or weaken their gate.
Use the PR's latest checks for final-head status, not this earlier-run snapshot.

Engineering review checked correctness, test isolation and maintenance cost.
A bounded security-diff review reused the existing threat model and found no
reportable vulnerability in `9e79bac..58f0bb8`; the subsequent singleton-array
correction in `410d726` received a separate engineering review. This is not a
repository-wide security attestation. Hosted Codex and automatically triggered
Copilot reviews found no code issues. Copilot review was not requested by this
task. CodeRabbit's replay and document-metadata findings were addressed in one
follow-up; unavailable author alias/image/category metadata remains empty.

## Proposed assessment answers (maintainer review only)

- **Silver `documentation_security`: `?` → `Met` after merge.** Proposed
  justification: "SECURITY.md documents DLL Pickle's assembly-selection,
  configuration and distribution responsibilities, dependency-owned authentication
  and token handling, and limits on isolation and configuration trust. The linked
  existing threat model identifies trust boundaries and attacker prerequisites."
  Evidence: [SECURITY.md](../../SECURITY.md), [threat model](../../.oss-scanner/threat_model.md).
- **Silver `input_validation`: retain `?`.** Add scoped evidence, not a Met answer:
  "Get-DPConfig validates object roots and recognized JSON field types before
  applying preferences; seeded and fixed Pester tests exercise rejection and
  normalization. Other input surfaces require separate assessment."
  Evidence: [implementation](../../src/DLLPickle/Public/Get-DPConfig.ps1),
  [tests](../../tests/Unit/Get-DPConfig.Property.Tests.ps1).
- **Already satisfied / unchanged:** Passing `dynamic_analysis` and Silver
  `coding_standards_enforced`, `external_dependencies`, `dependency_monitoring`
  were already Met. This patch does not newly earn them. No change proposed for
  `dynamic_analysis_unsafe`, signing, coverage, governance or training attestations.

No assessment answers were edited. After merge use permanent commit URLs for the
proposed evidence; PR-only code is not an already-deployed control.
