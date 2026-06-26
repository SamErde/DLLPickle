---
id: GAP-005
title: Strengthen OData conflict expectation management
status: resolved
severity: medium
area: known-conflicts
owner: maintainer
created: 2026-06-23
updated: 2026-06-25
related_issues:
  - "174"
related_prs:
  - https://github.com/SamErde/DLLPickle/pull/265
related_docs:
  - docs/Architecture.md
  - docs/Deep-Dive.md
  - src/DLLPickle/KnownConflicts.json
  - docs/superpowers/specs/2026-06-01-issue174-conflict-warning-design.md
  - docs/superpowers/plans/2026-06-01-issue174-conflict-warning.md
related_tests:
  - tests/Integration/DLLPickle.Issue174.OData.Tests.ps1
resolution_pr: https://github.com/SamErde/DLLPickle/pull/265
resolved_on: 2026-06-25
---

## GAP-005 — Strengthen OData conflict expectation management

## Status

**Current status:** Resolved.

## Problem

The Az.Storage and ExchangeOnlineManagement OData conflict is documented and warning-backed, but it remains intentionally unsolved in a single process. That limitation can be mistaken for a fixable preload gap unless the expectation is explicit in user docs, known-conflict data, tests, and architecture notes.

## Why this matters

Trying to make DLLPickle solve #174 by preloading OData can break Az.Storage or ExchangeOnlineManagement depending on import order. The safe workaround is separate PowerShell processes or sessions. Codex and maintainers need to preserve that expectation unless upstream module behavior changes.

## Current evidence

- Issue #174 is represented as a known conflict.
- The architecture records OData assemblies as `block` / report-only.
- The existing plan and design docs describe warning behavior rather than an automatic preload fix.

## Desired end state

The repository makes it unambiguous that #174 is a known unsolved cross-module incompatibility, not a missing preload target, and tests guard against accidentally treating OData as preloadable.

## Acceptance criteria

- [x] Confirm `src/DLLPickle/KnownConflicts.json` clearly describes the #174 behavior and workaround.
- [x] Confirm user-facing docs explain that the workaround is separate PowerShell processes/sessions, not a single-process preload fix.
- [x] Confirm tests fail if OData assemblies are added back to the preload bundle without a deliberate re-adjudication.
- [x] Update the issue #174 plan/spec notes if they are stale after the committed-source relocation.
- [x] Add or update an architecture note that future OData changes require runtime re-adjudication, not static dependency updates alone.
- [x] Update `docs/gaps/README.md` and this file when resolved or superseded.

## Implementation notes for Codex

1. Treat OData as `block` unless runtime evidence proves both import orders work in one process.
2. Do not remove the separate-session workaround unless tests and runtime evidence prove it is obsolete.
3. Keep known-conflict data, tests, and user docs synchronized.
4. Prefer updating stale plan/spec supersession notes rather than rewriting historical design rationale.
5. Do not mark this gap `resolved` unless user-facing expectation management and regression guards are both current.

## Resolution notes

`src/DLLPickle/KnownConflicts.json` now states explicitly that #174 is an upstream incompatibility (not a missing preload target), preserves the separate-process workaround language, and adds a re-adjudication requirement for any future OData classification change.

Expectation-management regression guards were strengthened in `tests/Unit/KnownConflicts.Tests.ps1` and `tests/Unit/DependencyPolicy.Tests.ps1`, while `docs/Deep-Dive.md` and `docs/Architecture.md` now state that OData preload changes require runtime evidence across both import orders.

Historical plan/spec notes were refreshed in `docs/superpowers/plans/2026-06-01-issue174-conflict-warning.md` and `docs/superpowers/specs/2026-06-01-issue174-conflict-warning-design.md` to align with the current committed-source model and ongoing runtime re-adjudication expectation.
