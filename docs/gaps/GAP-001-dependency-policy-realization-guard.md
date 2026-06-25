---
id: GAP-001
title: Add dependency policy realization guard
status: resolved
severity: high
area: dependency-policy
owner: maintainer
created: 2026-06-23
updated: 2026-06-25
related_issues: []
related_prs:
  - https://github.com/SamErde/DLLPickle/pull/257
related_docs:
  - docs/Architecture.md
  - build/dependency-policy.json
  - src/DLLPickle.Build/DLLPickle.csproj
related_tests:
  - tests/Integration/DependencyPolicyRealization.Tests.ps1
resolution_pr: https://github.com/SamErde/DLLPickle/pull/257
resolved_on: 2026-06-23
---

# GAP-001 — Add dependency policy realization guard

## Status

**Current status:** Resolved.

PR #257 merged into `main` on 2026-06-23 as commit `56f41a2` (`[codex] Add dependency policy realization guard (#257)`).

## Problem

`build/dependency-policy.json` is the decision source of truth for preload and block classifications, while `src/DLLPickle.Build/DLLPickle.csproj` and the generated `module/DLLPickle/bin/net8.0` output realize the actual bundle. Without an executable realization guard, a future dependency or packaging change can drift away from the policy without failing CI.

## Why this matters

This is a high-risk maintenance trap because the policy can look correct during review while the shipped bundle contains missing preload assemblies, blocked assemblies, or unclassified transitive assemblies.

## Current evidence

- `docs/Architecture.md` identifies `build/dependency-policy.json` as the classification source of truth.
- `docs/Architecture.md` identifies `DLLPickle.csproj` and `packages.lock.json` as the source of what is actually bundled.
- PR #257 added `tests/Integration/DependencyPolicyRealization.Tests.ps1` and the corresponding `DLLPickle.csproj` / `dependency-policy.json` updates on `main`.

## Desired end state

The repository has an automated integration test that compares the policy, project references, and built output, and fails closed on preload/block/bundle drift.

## Acceptance criteria

- [x] A test exists that asserts every `preload` package is represented in `DLLPickle.csproj`.
- [x] A test exists that asserts preload package references do not exclude runtime assets.
- [x] A test exists that asserts blocked package references exclude runtime assets when they are present in `DLLPickle.csproj`.
- [x] A test exists that asserts every preload assembly appears in the built `bin/net8.0` output.
- [x] A test exists that asserts blocked assemblies do not appear in the built `bin/net8.0` output.
- [x] A test exists that asserts the built `bin/net8.0` output does not contain unclassified managed assemblies.
- [x] PR #257 has merged.
- [x] The gap frontmatter is updated to `status: resolved` after merge.
- [x] `docs/gaps/README.md` is updated after merge.

## Implementation notes for Codex

1. Use this file as the historical closure record for the realization guard added by PR #257.
2. If the policy/csproj/built-output contract changes, update the integration guard instead of reopening this exact gap by default.
3. Open a new gap only if future drift requires materially new guard behavior beyond the current realization test.

## Resolution notes

Resolved by PR #257 on 2026-06-23. The merged change added `tests/Integration/DependencyPolicyRealization.Tests.ps1`, updated `src/DLLPickle.Build/DLLPickle.csproj` to realize platform-scoped policy decisions correctly, and aligned `build/dependency-policy.json` with the enforced runtime/bundle contract.
