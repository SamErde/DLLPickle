---
id: GAP-003
title: Add representative EXO and Teams probe commands
status: open
severity: high
area: runtime-probes
owner: maintainer
created: 2026-06-23
updated: 2026-06-23
related_issues: []
related_prs: []
related_docs:
  - docs/Architecture.md
  - build/dependency-policy.json
  - docs/DEPENDENCIES.md
related_tests: []
resolution_pr:
resolved_on:
---

# GAP-003 — Add representative EXO and Teams probe commands

## Status

**Current status:** Open.

## Problem

The runtime ALC ownership probe can capture module behavior after bare `Import-Module`, but ExchangeOnlineManagement and MicrosoftTeams may not eagerly load the identity assemblies that matter until representative commands run.

## Why this matters

DLLPickle's preload/block classification depends on observed runtime ownership, not static package inventory alone. If EXO or Teams loads identity assemblies only after command execution, bare import probes can under-model default-ALC consumers and create false confidence.

## Current evidence

- `docs/Architecture.md` says static narrows but runtime decides.
- `docs/Architecture.md` records that EXO/Teams ALC ownership is not yet captured because bare `Import-Module` does not eagerly load their identity assemblies.

## Desired end state

The runtime probe system supports representative `-ProbeCommand` execution for EXO and Teams, and the policy or tooling documents which probe commands establish ALC ownership for those modules.

## Acceptance criteria

- [ ] Define safe, representative probe commands for ExchangeOnlineManagement and MicrosoftTeams.
- [ ] Update the relevant runtime probe tooling to support module-specific probe commands if it does not already.
- [ ] Record the selected probe commands in `build/dependency-policy.json` or another authoritative policy/configuration file.
- [ ] Add tests for probe-command configuration parsing and invocation behavior without requiring live authentication.
- [ ] Document which probes are CI-capable and which require maintainer-run/auth-tier validation.
- [ ] Update `docs/Architecture.md` §7, §9, or §10 as needed.
- [ ] Update `docs/gaps/README.md` and this file when resolved or superseded.

## Implementation notes for Codex

1. Do not invent authenticated commands that require production tenant access.
2. Prefer no-op or discovery commands that are safe, read-only, and can be skipped or documented when authentication is unavailable.
3. Keep CI-capable probes separate from maintainer-run auth-tier probes.
4. Add structural tests for the tooling even if live EXO/Teams execution remains maintainer-run only.
5. Do not mark this gap `resolved` unless the probe-command contract is documented and tested.

## Resolution notes

Pending.
