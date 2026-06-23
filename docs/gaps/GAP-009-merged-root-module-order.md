---
id: GAP-009
title: Make merged root-module script order deterministic
status: open
severity: low
area: build-output
owner: maintainer
created: 2026-06-23
updated: 2026-06-23
related_issues: []
related_prs: []
related_docs:
  - docs/Architecture.md
  - build/DLLPickle.Build.ps1
related_tests: []
resolution_pr:
resolved_on:
---

# GAP-009 — Make merged root-module script order deterministic

## Status

**Current status:** Open.

## Problem

The merged root module output depends on recursive source-file discovery. If discovery order is not explicitly sorted and tested, the generated module can change across filesystems, platforms, or future refactors.

## Why this matters

A nondeterministic merge order can create hard-to-debug import behavior when private/public function files gain ordering assumptions, and it can add noise to generated output or release artifacts.

## Current evidence

- The architecture identifies `module/DLLPickle/` as generated output rebuilt by `PrepareModuleOutput`.
- The build process merges source files into the module output.

## Desired end state

The build has an explicit deterministic ordering rule for merged source files, and a test or documented guard preserves it.

## Acceptance criteria

- [ ] Inspect the build merge logic and identify the current ordering rule.
- [ ] If ordering is implicit, make it explicit with a stable sort.
- [ ] Add or update a test that detects nondeterministic merge ordering when practical.
- [ ] Document any required ordering convention for public/private scripts.
- [ ] Update `docs/gaps/README.md` and this file when resolved or superseded.

## Implementation notes for Codex

1. Do not hand-edit generated `module/` output.
2. Prefer a build-script fix plus a structural test over relying on platform-specific `Get-ChildItem` behavior.
3. Avoid introducing source-file ordering dependencies unless they are documented and tested.
4. Do not mark this gap `resolved` unless deterministic ordering is verified or intentionally accepted.

## Resolution notes

Pending.
