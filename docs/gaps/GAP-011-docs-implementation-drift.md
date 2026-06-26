---
id: GAP-011
title: Guard docs and implementation drift for gap closures
status: resolved
severity: medium
area: documentation
owner: maintainer
created: 2026-06-23
updated: 2026-06-26
related_issues: []
related_prs: []
related_docs:
  - docs/Architecture.md
  - docs/gaps/README.md
  - docs/superpowers/plans
  - docs/superpowers/specs
related_tests:
  - tests/Unit/GapRegister.Tests.ps1
resolution_pr: https://github.com/SamErde/DLLPickle/pull/266
resolved_on: 2026-06-26
---

# GAP-011 — Guard docs and implementation drift for gap closures

## Status

**Current status:** Resolved.

## Problem

Gap closure depends on agents updating implementation, tests, and related documentation together. The gap register and prompt define the convention, but there is not yet an automated guard that detects when a PR resolves a gap without updating the required related docs or index.

## Why this matters

Without a guard, Codex or a maintainer can fix code and mark a gap resolved while leaving `docs/Architecture.md`, `docs/gaps/README.md`, or older `docs/superpowers` plans/specs stale.

## Current evidence

- The gap register is a documentation/process system in this PR.
- The repository already relies on architecture and superpowers docs as durable agent context.

## Desired end state

The repository has either a lightweight automated consistency check for gap files and the index, or a documented review checklist that is enforced by maintainers.

## Acceptance criteria

- [x] Add a structural test or script that validates gap frontmatter status values.
- [x] Add a structural test or script that checks every `docs/gaps/GAP-*.md` file appears in `docs/gaps/README.md`.
- [x] Add a structural test or script that checks resolved gaps include `resolution_pr` and `resolved_on`.
- [x] Decide whether related docs updates can be tested structurally or must remain review-only.
- [x] Update `.github/prompts/maintain-gap.prompt.md` if the workflow changes.
- [x] Update `docs/gaps/README.md` and this file when resolved or superseded.

## Implementation notes for Codex

1. Prefer a small Pester test under `tests/Unit/` if the repository wants automated enforcement.
2. Keep validation structural and deterministic; do not require GitHub API access for unit tests.
3. Do not block normal documentation edits on overly complex parsing.
4. Do not mark this gap `resolved` unless the register/index consistency rule is automated or explicitly accepted as review-only.

## Resolution notes

Added `tests/Unit/GapRegister.Tests.ps1`, a deterministic, local-only Pester guard that validates: allowed `status` values, gap-file-to-index membership, index/frontmatter status agreement, and `resolution_pr`/`resolved_on` presence on resolved gaps. Implementing the guard surfaced existing drift: GAP-001 (resolved) was missing from the index and is now listed.

Decision on related-docs updates: kept **review-only**. Verifying that a resolved gap's `related_docs` were meaningfully updated cannot be done structurally without false positives, so it remains a maintainer/agent review responsibility documented in `docs/gaps/README.md` and `.github/prompts/maintain-gap.prompt.md`.
