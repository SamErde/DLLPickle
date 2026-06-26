---
id: GAP-002
title: Track Az.Resources as a monitored collision source
status: resolved
severity: high
area: dependency-policy
owner: maintainer
created: 2026-06-23
updated: 2026-06-25
related_issues:
  - "193"
related_prs:
  - https://github.com/SamErde/DLLPickle/pull/264
related_docs:
  - docs/Architecture.md
  - build/dependency-policy.json
  - docs/DEPENDENCIES.md
related_tests:
  - tests/Integration/DLLPickle.IntegrationTest.Tests.ps1
resolution_pr: https://github.com/SamErde/DLLPickle/pull/264
resolved_on: 2026-06-25
---

## GAP-002 — Track Az.Resources as a monitored collision source

## Status

**Current status:** Resolved.

## Problem

`Az.Resources` is the observed source of the #193 `Microsoft.Extensions.*` collision, but it is not currently included in the monitored module set used by the upstream inventory and conflict-surface drift process.

## Why this matters

The existing regression guard keeps the blocked `Microsoft.Extensions.*` transitives out of the DLLPickle bundle, but the upstream drift model does not directly observe future `Az.Resources` changes. A future `Az.Resources` dependency shift could matter without appearing in the current monitored-module inventory.

## Current evidence

- `docs/Architecture.md` records `Az.Resources` as the #193 collision source.
- `docs/Architecture.md` also records that `Az.Resources` is not in `monitoredModules`.
- `dependency-policy.json` currently tracks the blocked transitives with `trackingScope` evidence, but does not inventory `Az.Resources` directly.

## Desired end state

The repository either monitors `Az.Resources` directly or documents a deliberate decision not to do so with a compensating guard.

## Acceptance criteria

- [x] Decide whether `Az.Resources` should be added to `monitoredModules`.
- [x] If added, update `build/dependency-policy.json` and refresh the baseline/fingerprint using the established upstream inventory process.
- [x] If not added, document the rationale and compensating guard in this gap and `docs/Architecture.md`.
- [x] Update or add tests so future workflow/policy changes preserve the decision.
- [x] Update `docs/DEPENDENCIES.md` if the monitored-module lifecycle changes.
- [x] Update `docs/gaps/README.md` and this file when resolved or superseded.

## Implementation notes for Codex

1. Read `docs/Architecture.md` §3, §5, §8, §9, and §10 before changing policy.
2. Read `build/dependency-policy.json` and identify the current `monitoredModules`, blocked entries, and `baseline.conflictSurface` fields.
3. Treat changes to monitoring scope as policy changes that require review.
4. Prefer an automated guard in `tests/Unit/WorkflowGuardrails.Tests.ps1` or an equivalent policy test if the decision can be expressed structurally.
5. Do not mark this gap `resolved` unless the monitoring decision and related documentation are updated.

## Resolution notes

`Az.Resources` was added to `monitoredModules` in `build/dependency-policy.json`, with baseline capture metadata refreshed and #193 tracking-scope notes updated to reflect direct monitoring.

Structural guardrails were added in `tests/Unit/DependencyPolicy.Tests.ps1` to enforce the monitoring decision and preserve `Az.Resources`-linked blocked-transitive expectations.

Documentation was updated in `docs/DEPENDENCIES.md` so monitored-module lifecycle guidance aligns with the policy decision.
