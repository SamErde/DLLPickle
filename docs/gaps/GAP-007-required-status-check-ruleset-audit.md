---
id: GAP-007
title: Audit required status-check ruleset configuration
status: open
severity: medium
area: branch-protection
owner: maintainer
created: 2026-06-23
updated: 2026-06-23
related_issues: []
related_prs: []
related_docs:
  - docs/Architecture.md
  - .github/workflows/Build-Module.yml
  - .github/workflows/Upstream-Compatibility.yml
  - .github/workflows/Dependabot-Auto-Approve.yml
related_tests:
  - tests/Unit/WorkflowGuardrails.Tests.ps1
resolution_pr:
resolved_on:
---

# GAP-007 — Audit required status-check ruleset configuration

## Status

**Current status:** Open.

## Problem

The required status checks and ruleset configuration live partly outside the repository. The workflows and guardrail tests can ensure that expected check names exist, but they cannot prove the GitHub repository ruleset is configured correctly unless the ruleset is exported, documented, or otherwise audited.

## Why this matters

A required-check mismatch can leave PRs blocked forever, or worse, leave intended protection unenforced. Workflow-level path filters can also make required checks stay pending if the repository ruleset requires a check that does not run for a PR.

## Current evidence

- `docs/Architecture.md` documents required checks and warns that workflows should be triggered on every PR while condition jobs internally.
- `WorkflowGuardrails.Tests.ps1` contains structural checks for workflow behavior, but the GitHub-hosted ruleset itself remains an external configuration dependency.

## Desired end state

The repository has a documented, auditable snapshot or procedure for verifying required checks and branch/ruleset settings against workflow behavior.

## Acceptance criteria

- [ ] Export or document the current main-protection ruleset configuration.
- [ ] Record the expected required status-check contexts in a repo-local document or test fixture.
- [ ] Add or update a guardrail test that compares expected check names to workflow aggregate job names when practical.
- [ ] Document a maintainer procedure for auditing the external ruleset after workflow renames.
- [ ] Update `docs/Architecture.md` if required-check names, behavior, or ruleset assumptions change.
- [ ] Update `docs/gaps/README.md` and this file when resolved or superseded.

## Implementation notes for Codex

1. Do not assume repository ruleset state from workflow files alone.
2. If GitHub API access is available, prefer an export or generated snapshot that can be reviewed.
3. If API access is not available, add a manual audit procedure and clearly mark the external dependency.
4. Do not rename aggregate required-check jobs without updating the ruleset documentation and tests.
5. Do not mark this gap `resolved` unless external ruleset verification is documented or captured.

## Resolution notes

Pending.
