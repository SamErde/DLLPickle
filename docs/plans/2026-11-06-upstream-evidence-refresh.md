---
title: Upstream evidence refresh and bounded Gallery retries
post_title: Upstream evidence refresh and bounded Gallery retries
author1: OpenAI Codex
post_slug: upstream-evidence-refresh-gallery-retries
microsoft_alias: null
featured_image: null
categories: []
tags: [PowerShell, testing]
ai_note: Prepared with OpenAI Codex for maintainer review.
summary: Adjudication of nine upstream snapshots and preservation of compatibility gates.
post_date: 2026-11-06
---

## Decision and evidence

Refresh the nine accepted deterministic profile snapshots under
[#273](https://github.com/SamErde/DLLPickle/issues/273) to unblock
[#323](https://github.com/SamErde/DLLPickle/pull/323), following the update
procedure in [Architecture](../Architecture.md). Comparison is against main
`9e79bac6371e1fa498dd4fb23715863026c3d091`.

Eight snapshots come from [run 42188864218](https://github.com/SamErde/DLLPickle/actions/runs/42188864218)
at `8bff5d6105f32b0217ab87aac97241d8628e3e17`, including the macOS 7.6 retry.
Windows 7.4 comes from [run 42187368633](https://github.com/SamErde/DLLPickle/actions/runs/42187368633)
at the preceding implementation revision; its later capture failed during a Gallery download.
Each committed snapshot retains its observed provenance. The final PR checks
must recapture all nine profiles against these baselines before merge.

All nine content comparisons have exactly 33 changed values:

- Az.Accounts: version and latest-compatible version, 5.5.3 to 5.5.4.
- Az.Resources: version and latest-compatible version, 10.2.1 to 10.2.2.
- 25 selected-asset paths and four imported manifest paths change only these version segments.

No other content changes: assembly versions and hashes, load-context ownership,
runtime identity, conflict and scenario fingerprints, scenario outcomes, and
validation tier remain identical. These are material version/path changes that
require review even though the conflict fingerprint alone is unchanged. The
existing runtime differential therefore supports retaining the classifications
and selected DLL set. Only the nine normalized snapshots and their policy
evidence fingerprints are refreshed. No dependency classification, bundled DLL,
acceptance status, scenario requirement, or authenticated evidence is changed.
Authenticated validation remains a separate required tier where policy requires it;
these deterministic import results do not establish tenant or broker correctness.

## Gallery failures

The failing captures include Az.Storage and ExchangeOnlineManagement dependency
downloads; earlier build bootstrap also failed downloading Pester. Retry only
Gallery discovery and module save/install operations, at most three attempts,
with two- and four-second delays. Existing workflow timeouts bound the job;
the retry helper does not impose a per-download timeout. Persistent failures
still throw the final error. Failed attempts cannot leak partial lookup results.
Downloads retain the already selected exact version, repository, publisher-check
policy and command options. No alternate feed, version fallback or gate bypass
is introduced. Retries reduce transient failures; they cannot guarantee Gallery availability.

## Validation and replay

The unchanged `Test-DLLPickleProfileConflictBaseline.ps1` accepts all nine
downloaded candidate artifacts with the refreshed policy (`AcceptedUnchanged`).
To reproduce, download the run artifacts and execute for each profile directory:

```powershell
$Parameters = @{
    PolicyPath = 'build/dependency-policy.json'
    ConflictMatrixPath = "$ProfileDirectory/conflict-matrix.json"
    ScenarioEvidencePath = "$ProfileDirectory/scenario-evidence.json"
    NormalizedEvidencePath = "$ProfileDirectory/normalized-profile-evidence.json"
    PassThru = $true
}
./tools/Test-DLLPickleProfileConflictBaseline.ps1 @Parameters
```

`tests/Unit/GalleryRetry.Tests.ps1` uses controlled callbacks and mocked delays:
immediate success, recovery without partial output or version change, and final
failure after three attempts. Run through the existing pinned Pester helper;
no Gallery, credentials, tenant or installed-module mutations are involved in
these tests. The complete offline scanner acceptance command is
`pwsh -NoProfile -NonInteractive -File .oss-scanner/test.ps1` in the provisioned
scanner container with `--network none`. Hosted PR checks provide the separate
Windows and macOS validation.

No new Best Practices or Scorecard answer is proposed by this follow-up.
