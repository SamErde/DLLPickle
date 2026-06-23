---
description: 'Resolve or update a DLLPickle gap register item.'
mode: 'agent'
tools: ['codebase', 'editFiles', 'terminal']
---

# Maintain DLLPickle Gap

## Mission

Resolve, update, block, supersede, or intentionally accept one gap from `docs/gaps/`.

## Required input

Gap file path: `${input:gapFile:docs/gaps/GAP-001-dependency-policy-realization-guard.md}`

## Scope and preconditions

- Work only on the requested gap unless another gap must be updated because of the same change.
- Do not mark a gap `resolved` unless every acceptance criterion in the gap file is complete or explicitly superseded.
- Do not hide unresolved work by deleting acceptance criteria.
- If the implementation changes architecture, invariants, validation gates, source-of-truth mappings, release behavior, or user-facing behavior, update the related documentation in the same PR.

## Workflow

1. Read the requested gap file.
2. Read `docs/gaps/README.md`.
3. Read every file listed in the gap file's `related_docs` frontmatter.
4. Search the repository for the gap ID.
5. Determine whether the gap is still `open`, `in-progress`, `blocked`, `resolved`, `superseded`, or `wont-fix`.
6. If implementing a fix:
   - make the smallest safe source, workflow, policy, test, or documentation change;
   - add or update automated guards when practical;
   - run the relevant validation commands;
   - capture any validation that cannot be run and why.
7. Before finishing, update:
   - the gap file frontmatter,
   - the gap file checklist,
   - `docs/gaps/README.md`,
   - `docs/Architecture.md` if architecture, invariants, validation gates, source-of-truth mappings, or known gaps changed,
   - any related `docs/superpowers/plans/*` or `docs/superpowers/specs/*` file when the plan/spec is stale, superseded, or completed.

## Resolution rules

- Use `status: resolved` only when the implementation, tests, and documentation updates are complete and the resolving PR is linked.
- Use `status: in-progress` when an implementation PR exists but has not merged.
- Use `status: blocked` when a decision, credential, tenant, environment, external ruleset, or upstream dependency prevents safe completion.
- Use `status: superseded` when a newer design or decision makes the gap obsolete. Explain the superseding reference in `Resolution notes`.
- Use `status: wont-fix` only when the maintainer intentionally accepts the gap and the rationale is documented.

## Output expectations

Summarize:

- status before and after,
- files changed,
- tests or checks run,
- documentation updated,
- remaining caveats.

## Quality checks

- [ ] The gap file status and checklist match the actual changes.
- [ ] `docs/gaps/README.md` matches the gap file frontmatter.
- [ ] Related docs are updated or explicitly left unchanged with rationale.
- [ ] Relevant tests were added or updated when practical.
- [ ] Validation commands were run or a clear blocker is documented.
