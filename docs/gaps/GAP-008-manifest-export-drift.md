---
id: GAP-008
title: Guard manifest export drift
status: open
severity: low
area: module-manifest
owner: maintainer
created: 2026-06-23
updated: 2026-06-23
related_issues: []
related_prs: []
related_docs:
  - docs/Architecture.md
  - src/DLLPickle/DLLPickle.psd1
  - src/DLLPickle/Public
related_tests: []
resolution_pr:
resolved_on:
---

# GAP-008 — Guard manifest export drift

## Status

**Current status:** Open.

## Problem

The source manifest has an explicit `FunctionsToExport` list, while development/build behavior can also rely on public function discovery and merged module output. Without a guard, the manifest export list can drift from the public functions that should be exported.

## Why this matters

A public function can be added but not exported, or a removed/renamed function can remain in the manifest. Either case causes user-visible behavior to diverge from source layout and documentation.

## Current evidence

- `docs/Architecture.md` identifies `src/DLLPickle/` as the module source and `src/DLLPickle/DLLPickle.psd1` as part of the platform-support contract.
- The source tree uses a `Public` folder convention, while the manifest export list remains an explicit contract.

## Desired end state

The repository has a test that keeps `FunctionsToExport` aligned with the intended public function set, or it documents an intentional exception model.

## Acceptance criteria

- [ ] Decide whether `FunctionsToExport` should exactly match `src/DLLPickle/Public/*.ps1` function names.
- [ ] Add a Pester test that compares the manifest export list to the intended public function list, or document any explicit exceptions.
- [ ] Update docs if public export behavior is part of the supported contract.
- [ ] Ensure the test runs in the regular unit/analyzer path.
- [ ] Update `docs/gaps/README.md` and this file when resolved or superseded.

## Implementation notes for Codex

1. Read the source manifest and public function folder before editing.
2. Preserve intentional export decisions if any function is deliberately private despite location.
3. Prefer a deterministic Pester test over generated manifest mutation.
4. Keep the test compatible with PowerShell 7.4+ repository tooling.
5. Do not mark this gap `resolved` unless export drift is guarded or intentionally documented.

## Resolution notes

Pending.
