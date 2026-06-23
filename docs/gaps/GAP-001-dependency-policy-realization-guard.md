---
id: GAP-001
title: Add dependency policy realization guard
status: in-progress
severity: high
area: dependency-policy
owner: maintainer
created: 2026-06-23
updated: 2026-06-23
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
resolved_on:
---

# GAP-001 — Add dependency policy realization guard

## Status

**Current status:** In progress.

Implementation is in draft PR #257. Keep this gap in `in-progress` until the PR merges and the test is confirmed in CI.

## Problem

`build/dependency-policy.json` is the decision source of truth for preload and block classifications, while `src/DLLPickle.Build/DLLPickle.csproj` and the generated `module/DLLPickle/bin/net8.0` output realize the actual bundle. Without an executable realization guard, a future dependency or packaging change can drift away from the policy without failing CI.

## Why this matters

This is a high-risk maintenance trap because the policy can look correct during review while the shipped bundle contains missing preload assemblies, blocked assemblies, or unclassified transitive assemblies.

## Current evidence

- `docs/Architecture.md` identifies `build/dependency-policy.json` as the classification source of truth.
- `docs/Architecture.md` identifies `DLLPickle.csproj` and `packages.lock.json` as the source of what is actually bundled.
- Draft PR #257 adds an integration guard for this gap.

## Desired end state

The repository has an automated integration test that compares the policy, project references, and built output, and fails closed on preload/block/bundle drift.

## Acceptance criteria

- [x] A test exists that asserts every `preload` package is represented in `DLLPickle.csproj`.
- [x] A test exists that asserts preload package references do not exclude runtime assets.
- [x] A test exists that asserts blocked package references exclude runtime assets when they are present in `DLLPickle.csproj`.
- [x] A test exists that asserts every preload assembly appears in the built `bin/net8.0` output.
- [x] A test exists that asserts blocked assemblies do not appear in the built `bin/net8.0` output.
- [x] A test exists that asserts the built `bin/net8.0` output does not contain unclassified managed assemblies.
- [ ] PR #257 has merged.
- [ ] The gap frontmatter is updated to `status: resolved` after merge.
- [ ] `docs/gaps/README.md` is updated after merge.

## Implementation notes for Codex

1. Inspect PR #257 before changing this gap.
2. Do not duplicate the test unless PR #257 is closed without merge.
3. After PR #257 merges, update this file and `docs/gaps/README.md` in the merge-follow-up PR, or in the same PR if the branch is rebased before merge.
4. Do not mark this gap `resolved` until the resolving PR is merged.

## Resolution notes

Pending merge of PR #257.
