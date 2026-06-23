---
id: GAP-004
title: Model VS Code and PowerShellEditorServices host behavior
status: open
severity: medium
area: host-context
owner: maintainer
created: 2026-06-23
updated: 2026-06-23
related_issues:
  - "169"
related_prs: []
related_docs:
  - docs/Architecture.md
  - docs/Deep-Dive.md
related_tests: []
resolution_pr:
resolved_on:
---

# GAP-004 — Model VS Code and PowerShellEditorServices host behavior

## Status

**Current status:** Open.

## Problem

Issue #169 reports different behavior between Windows Terminal and the VS Code integrated terminal / PowerShellEditorServices host context. DLLPickle's current validation model is mostly normal `pwsh` process behavior and may not model assemblies preloaded by the editor host.

## Why this matters

Many users run Microsoft Graph, Azure, and Exchange commands inside VS Code. If PowerShellEditorServices or the integrated terminal preloads conflicting assemblies before DLLPickle can act, DLLPickle may appear unreliable in one of the most common development hosts.

## Current evidence

- Issue #169 reports Graph authentication behavior that differs between Windows Terminal and VS Code.
- Existing runtime validation focuses on normal PowerShell sessions, not editor-host bootstrap behavior.

## Desired end state

The repository documents the VS Code / PowerShellEditorServices host scenario and either adds a reproducible validation path or records a clear limitation with user guidance.

## Acceptance criteria

- [ ] Reproduce or characterize the VS Code / PowerShellEditorServices host behavior in issue #169.
- [ ] Identify whether the issue is caused by the integrated terminal, PowerShell extension host, PowerShellEditorServices, profile scripts, or another preload source.
- [ ] Add a maintainer-run repro script or documented diagnostic procedure.
- [ ] Add an automated structural test when practical, or document why a live/editor-host test is not CI-suitable.
- [ ] Update `docs/Deep-Dive.md` with user-facing guidance if the limitation remains.
- [ ] Update `docs/Architecture.md` if host-context assumptions affect the preload model.
- [ ] Update `docs/gaps/README.md` and this file when resolved, blocked, or superseded.

## Implementation notes for Codex

1. Search for issue #169 references before editing.
2. Do not assume VS Code integrated terminal and PowerShellEditorServices are the same host path.
3. Preserve the distinction between normal `pwsh` sessions and editor-integrated host behavior.
4. Prefer user-safe diagnostics over hidden environment assumptions.
5. Do not mark this gap `resolved` unless the repo contains either a validation path or explicit documented limitation.

## Resolution notes

Pending.
