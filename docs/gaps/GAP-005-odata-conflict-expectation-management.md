---
id: GAP-005
title: Strengthen OData conflict expectation management
status: open
severity: medium
area: known-conflicts
owner: maintainer
created: 2026-06-23
updated: 2026-06-23
related_issues:
  - "174"
related_prs: []
related_docs:
  - docs/Architecture.md
  - docs/Deep-Dive.md
  - src/DLLPickle/KnownConflicts.json
  - docs/superpowers/specs/2026-06-01-issue174-conflict-warning-design.md
  - docs/superpowers/plans/2026-06-01-issue174-conflict-warning.md
related_tests:
  - tests/Integration/DLLPickle.Issue174.OData.Tests.ps1
resolution_pr:
resolved_on:
---

# GAP-005 — Strengthen OData conflict expectation management

## Status

**Current status:** Open.

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

- [ ] Confirm `src/DLLPickle/KnownConflicts.json` clearly describes the #174 behavior and workaround.
- [ ] Confirm user-facing docs explain that the workaround is separate PowerShell processes/sessions, not a single-process preload fix.
- [ ] Confirm tests fail if OData assemblies are added back to the preload bundle without a deliberate re-adjudication.
- [ ] Update the issue #174 plan/spec notes if they are stale after the committed-source relocation.
- [ ] Add or update an architecture note that future OData changes require runtime re-adjudication, not static dependency updates alone.
- [ ] Update `docs/gaps/README.md` and this file when resolved or superseded.

## Implementation notes for Codex

1. Treat OData as `block` unless runtime evidence proves both import orders work in one process.
2. Do not remove the separate-session workaround unless tests and runtime evidence prove it is obsolete.
3. Keep known-conflict data, tests, and user docs synchronized.
4. Prefer updating stale plan/spec supersession notes rather than rewriting historical design rationale.
5. Do not mark this gap `resolved` unless user-facing expectation management and regression guards are both current.

## Resolution notes

Pending.
