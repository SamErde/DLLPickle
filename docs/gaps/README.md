# DLLPickle Gap Register

This directory tracks open maintenance traps, automation gaps, and unresolved architecture follow-ups that should remain visible to maintainers and agentic workstreams.

Use this register for durable repo-local gap state. Use `docs/superpowers/specs/` and `docs/superpowers/plans/` for larger point-in-time designs and task-by-task implementation plans.

## Rules for maintainers and agents

1. Treat each `GAP-*.md` file as the source of truth for that gap's current status.
2. Do not mark a gap `resolved` unless all acceptance criteria in the gap file are checked or explicitly superseded.
3. When resolving a gap, update:
   - the gap file,
   - this index,
   - related tests,
   - related source, policy, or workflow files,
   - related documentation,
   - `docs/Architecture.md` when architecture, invariants, validation gates, source-of-truth mappings, or known gaps changed.
4. If a gap becomes obsolete because of a different design, mark it `superseded`, explain why, and link the superseding PR, issue, or document.
5. If a gap cannot be completed safely, mark it `blocked`, explain the blocker, and leave the remaining acceptance criteria unchecked.
6. Keep this index synchronized with each gap file's frontmatter.

## Status values

| Status | Meaning |
| --- | --- |
| `open` | Known gap with no active implementation PR. |
| `in-progress` | Implementation is underway in a linked PR or branch. |
| `blocked` | Work cannot proceed without an external decision, credential, environment, or dependency. |
| `resolved` | Acceptance criteria are complete and the resolving PR is linked. |
| `superseded` | A later design or decision made the gap obsolete. |
| `wont-fix` | The gap is accepted intentionally, with rationale documented. |

## Gap index

| ID | Status | Area | Title | File |
| --- | --- | --- | --- | --- |
| GAP-001 | in-progress | dependency-policy | Add dependency policy realization guard | [GAP-001](GAP-001-dependency-policy-realization-guard.md) |
| GAP-002 | open | dependency-policy | Track Az.Resources as a monitored collision source | [GAP-002](GAP-002-az-resources-monitoring.md) |
| GAP-003 | open | runtime-probes | Add representative EXO and Teams probe commands | [GAP-003](GAP-003-exo-teams-probe-commands.md) |
| GAP-004 | open | host-context | Model VS Code and PowerShellEditorServices host behavior | [GAP-004](GAP-004-vscode-powershelleditorservices-host.md) |
| GAP-005 | open | known-conflicts | Strengthen OData conflict expectation management | [GAP-005](GAP-005-odata-conflict-expectation-management.md) |
| GAP-006 | open | release-process | Document manual release dispatch process trap | [GAP-006](GAP-006-release-dispatch-process-trap.md) |
| GAP-007 | open | branch-protection | Audit required status-check ruleset configuration | [GAP-007](GAP-007-required-status-check-ruleset-audit.md) |
| GAP-008 | open | module-manifest | Guard manifest export drift | [GAP-008](GAP-008-manifest-export-drift.md) |
| GAP-009 | open | build-output | Make merged root-module script order deterministic | [GAP-009](GAP-009-merged-root-module-order.md) |
| GAP-010 | open | review-process | Define unresolved review-thread maintenance workflow | [GAP-010](GAP-010-unresolved-review-thread-maintenance.md) |
| GAP-011 | open | documentation | Guard docs and implementation drift for gap closures | [GAP-011](GAP-011-docs-implementation-drift.md) |

## Agent workflow

1. Start with the requested `GAP-*.md` file.
2. Read every file listed in `related_docs`.
3. Search the repository for the gap ID before editing.
4. Make the smallest safe implementation that satisfies the acceptance criteria.
5. Add or update tests before marking a gap resolved when an automated guard is practical.
6. Update related documentation before finalizing the PR.
7. Update this index and the gap file frontmatter in the same PR that resolves, blocks, supersedes, or intentionally accepts the gap.
