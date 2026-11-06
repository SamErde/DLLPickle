# Configuration validation and generated-input pilot

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
| **Validate configuration types plus seeded tests (selected)** | Get-DPConfig catches JSON syntax/read failures, but coerces wrong types and unwraps root arrays. Four existing tests do not exercise real schema failures. | Silver `input_validation` is unanswered; this supplies scoped implementation/evidence, not proof for all inputs. Passing `dynamic_analysis` is already Met. No Scorecard `Fuzzing` credit claimed. | Prevent unintended preference interpretation; small implementation and existing Pester only; maintain a compact contract corpus. |
| Generated dependency-order tests | Existing synthetic transitive-assembly and metadata-only inspection tests exercise real assemblies in child processes. Sparse graph-shape coverage remains (cycles, duplicate names, permutations). | Evidence toward Silver `input_validation` and regression testing; no automatic `Fuzzing` credit. | Useful reliability evidence, but pure graph mocks omit assembly metadata behavior; moderate fixture maintenance. |
| Signed release verification | Immutable release SHA, locked restore and package checks exist; inspected release workflow has no release-signing/attestation step or user verification procedure. | Silver `signed_releases`, `version_tags_signed`; separate Scorecard `Signed-Releases`. | High user-verification value, but needs signing identity/key custody, deliverable scope and verification design; greater ongoing release cost. Checksums alone do not satisfy signing. |
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
In a provisioned offline environment, invoke the existing helper in a fresh process:

```powershell
./build/Invoke-DLLPicklePester.ps1 -TestPath ./tests/Unit/Get-DPConfig.Generated.Tests.ps1 -SummaryPath ./summary.json -TestResultPath ./results.xml -RequiredPesterVersion 5.7.1
```

On Linux prefix the fresh `pwsh -NoProfile -NonInteractive -File ...` process with
`timeout 180`. To replay one seed in a fresh process using Pester 5.7.1:

```powershell
Import-Module Pester -RequiredVersion 5.7.1
$container = New-PesterContainer -Path ./tests/Unit/Get-DPConfig.Generated.Tests.ps1 -Data @{ Seeds = @(322); CasesPerSeed = 32 }
Invoke-Pester -Container $container -Output Detailed
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
  [tests](../../tests/Unit/Get-DPConfig.Generated.Tests.ps1).
- **Already satisfied / unchanged:** Passing `dynamic_analysis` and Silver
  `coding_standards_enforced`, `external_dependencies`, `dependency_monitoring`
  were already Met. This patch does not newly earn them. No change proposed for
  `dynamic_analysis_unsafe`, signing, coverage, governance or training attestations.

No assessment answers were edited. After merge use permanent commit URLs for the
proposed evidence; PR-only code is not an already-deployed control.
