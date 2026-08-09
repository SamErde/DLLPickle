---
id: GAP-003
title: Add representative EXO and Teams probe commands
status: in-progress
severity: high
area: runtime-probes
owner: maintainer
created: 2026-06-23
updated: 2026-08-08
related_issues: []
related_prs: []
related_docs:
  - docs/Architecture.md
  - build/dependency-policy.json
  - docs/DEPENDENCIES.md
related_tests:
  - tests/Unit/DependencyPolicy.Tests.ps1
  - tests/Unit/UpstreamInventoryProfile.Tests.ps1
resolution_pr:
resolved_on:
---

# GAP-003 — Add representative EXO and Teams probe commands

## Status

**Current status:** In progress. The probe-command contract and tooling are implemented; exact profile/platform evidence has not yet been accepted.

## Problem

The runtime ALC ownership probe can capture module behavior after bare `Import-Module`, but ExchangeOnlineManagement and MicrosoftTeams may not eagerly load the identity assemblies that matter until representative commands run.

## Why this matters

DLLPickle's preload/block classification depends on observed runtime ownership, not static package inventory alone. If EXO or Teams loads identity assemblies only after command execution, bare import probes can under-model default-ALC consumers and create false confidence.

## Current evidence

- `build/dependency-policy.json` assigns `Get-ConnectionInformation -ErrorAction SilentlyContinue | Out-Null` and a read-only `Get-Team` execution with errors suppressed to the deterministic no-auth tier. The Teams command executes the cmdlet surface without claiming an authenticated tenant read.
- It separately records `Get-EXOMailbox -ResultSize 1 | Out-Null` and an access-token-based `Connect-MicrosoftTeams` / `Get-CsTenant` / `Disconnect-MicrosoftTeams` sequence as authenticated read-only release gates.
- `Get-DLLPickleUpstreamInventory.ps1` passes the profile-specific deterministic command into the exact stock-host snapshot process.
- Unit tests validate policy parsing, probe separation, exact-host inventory, and selected-asset evidence without service authentication.

## Desired end state

The runtime probe system supports representative `-ProbeCommand` execution for EXO and Teams, and the policy or tooling documents which probe commands establish ALC ownership for those modules.

## Acceptance criteria

- [x] Define safe, representative probe commands for ExchangeOnlineManagement and MicrosoftTeams.
- [x] Update the relevant runtime probe tooling to support module-specific probe commands if it does not already.
- [x] Record the selected probe commands in `build/dependency-policy.json` or another authoritative policy/configuration file.
- [x] Add tests for probe-command configuration parsing and invocation behavior without requiring live authentication.
- [x] Document which probes are CI-capable and which require maintainer-run/auth-tier validation.
- [x] Update `docs/Architecture.md` §7, §9, or §10 as needed.
- [ ] Accept fresh exact-profile evidence for all required platforms and then update `docs/gaps/README.md` and this file as resolved.

## Implementation notes for Codex

1. Do not invent authenticated commands that require production tenant access.
2. Prefer no-op or discovery commands that are safe, read-only, and can be skipped or documented when authentication is unavailable.
3. Keep CI-capable probes separate from maintainer-run auth-tier probes.
4. Add structural tests for the tooling even if live EXO/Teams execution remains maintainer-run only.
5. Do not mark this gap `resolved` unless the probe-command contract is documented and tested.

## Resolution notes

Implementation is present in the current change. Resolution remains pending until the nine profile/platform baselines contain reviewed fingerprints rather than `requires-profile-refresh` placeholders.
