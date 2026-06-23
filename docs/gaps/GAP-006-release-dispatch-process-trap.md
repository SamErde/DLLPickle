---
id: GAP-006
title: Document manual release dispatch process trap
status: open
severity: medium
area: release-process
owner: maintainer
created: 2026-06-23
updated: 2026-06-23
related_issues: []
related_prs: []
related_docs:
  - docs/Architecture.md
  - CHANGELOG.md
  - .github/workflows/Release-and-Publish.yml
related_tests:
  - tests/Unit/WorkflowGuardrails.Tests.ps1
resolution_pr:
resolved_on:
---

# GAP-006 — Document manual release dispatch process trap

## Status

**Current status:** Open.

## Problem

The release workflow is intentionally path-gated so docs, policy, test, tooling, and release-logic-only changes do not publish automatically. That protects the gallery, but it creates a process trap: packaging or release-logic changes may require deliberate `workflow_dispatch` to publish even when the code path is correct.

## Why this matters

A maintainer or agent can merge a packaging/release-logic change and assume it has shipped. If the change does not touch bundle-affecting paths and does not pass the publish gates, no PowerShell Gallery release occurs unless the manual release path is used deliberately.

## Current evidence

- `docs/Architecture.md` documents the path gate and version gate.
- `docs/Architecture.md` identifies `workflow_dispatch` as the deliberate-release escape hatch.
- The release workflow is designed to avoid publishing docs/test/tooling-only changes.

## Desired end state

The repository contains clear maintainer-facing instructions for when and how to use manual release dispatch, and tests preserve the intended release-gating behavior.

## Acceptance criteria

- [ ] Add a maintainer-facing release dispatch note to `docs/Architecture.md`, `CHANGELOG.md`, or a dedicated release document.
- [ ] Document examples of changes that do and do not publish automatically.
- [ ] Document when `workflow_dispatch` is appropriate.
- [ ] Confirm workflow guardrail tests cover the path gate and manual-dispatch expectations where practical.
- [ ] Update PR/release guidance so Codex does not claim that non-bundle changes are shipped automatically.
- [ ] Update `docs/gaps/README.md` and this file when resolved or superseded.

## Implementation notes for Codex

1. Preserve the distinction between publishing a module version and merging repository-only changes.
2. Do not weaken the release path gate to close this gap unless the architecture decision changes.
3. Prefer documentation and guardrail tests over broadening release triggers.
4. Update all references that mention the escape hatch if wording changes.
5. Do not mark this gap `resolved` unless the manual release path is documented for maintainers and agents.

## Resolution notes

Pending.
