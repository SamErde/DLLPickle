---
id: GAP-010
title: Define unresolved review-thread maintenance workflow
status: resolved
severity: low
area: review-process
owner: maintainer
created: 2026-06-23
updated: 2026-06-26
related_issues: []
related_prs: []
related_docs:
  - docs/Architecture.md
  - .github/workflows/Build-Module.yml
related_tests: []
resolution_pr: pending-local-pr
resolved_on: 2026-06-26
---

# GAP-010 — Define unresolved review-thread maintenance workflow

## Status

**Current status:** Resolved.

## Problem

The repository ruleset expects review-thread resolution, but the repo-local process for maintaining, auditing, and resolving stale review threads is not documented in the gap/architecture workflow.

## Why this matters

Unresolved review threads can block merges even after code changes address the underlying concern. Conversely, resolving threads without updating tests or docs can hide incomplete work.

## Current evidence

- The architecture records review-thread resolution as part of the main-protection expectation.
- The external ruleset itself is not fully repo-local, which overlaps with GAP-007.

## Desired end state

The repository documents how maintainers and agents should handle unresolved review threads, including when to update a gap file, when to request maintainer review, and when not to resolve a thread.

## Acceptance criteria

- [x] Decide whether this gap should be folded into GAP-007 or kept separate.
- [x] Document the review-thread maintenance workflow if kept separate.
- [x] Update the relevant PR guidance or architecture note.
- [x] Ensure the workflow does not encourage agents to resolve review threads without addressing the underlying issue.
- [x] Update `docs/gaps/README.md` and this file when resolved, superseded, or folded into GAP-007.

## Implementation notes for Codex

1. Prefer folding this into GAP-007 if the work is only ruleset/process documentation.
2. Do not resolve review threads as a substitute for code, test, or documentation changes.
3. If a review thread corresponds to a gap, link the gap file from the PR discussion or commit message.
4. Do not mark this gap `resolved` unless the review-thread workflow is explicit or intentionally superseded.

## Resolution notes

Decision: **kept separate** from GAP-007. GAP-007 audits the required-status-check *ruleset configuration*; this gap governs *human and agent behavior* on review threads, so folding them would conflate a configuration audit with a process convention.

Documented the workflow in `docs/Architecture.md` §9.1 ("Review-thread maintenance workflow"): who may resolve a thread, the three conditions under which a thread may be resolved, an explicit do-not list, stale-thread handling, and agent-specific guidance. Added a matching hard-gate bullet to §9 stating that resolving a thread is never a substitute for code, test, or documentation changes, and that threads mapping to deferred work must be captured as a `GAP-*` entry or linked issue.
