# Fresh-Conversation Implementation Prompt

Open a fresh Codex project conversation at the DLLPickle repository root and paste the prompt below. Goal mode is recommended because this is a long-running migration with a concrete validation loop and stopping condition.

```text
/goal Implement docs/plans/2026-08-08-supported-powershell-multitargeting.md completely and safely. Continue through reviewable checkpoints until the implementation and all locally or CI-runnable validation are complete, or until a genuine authority/credential/external-state blocker requires my input.

Repository: DLLPickle
Plan: docs/plans/2026-08-08-supported-powershell-multitargeting.md

Read the complete plan before editing. Then inspect the current repository instructions, worktree status, documentation, workflows, open PRs/issues, and relevant history. Revalidate Microsoft's live PowerShell lifecycle and current servicing patches before relying on the plan's 2026-08-08 snapshot. If the currently supported PowerShell release-line set differs from the plan, stop before changing the settled support set and explain the exact lifecycle delta and implementation impact.

Implement the plan in small, test-first checkpoints. Keep at most one implementation phase in progress at a time, report concise progress, and validate each phase before advancing. Preserve unrelated user changes. Do not commit, push, rebase, open or modify a PR, merge, publish, release, or change external data unless I explicitly authorize it.

Non-negotiable requirements:

1. Within the PowerShell 7 scope, support every and only release lines still supported by Microsoft. The initial expected set is PowerShell 7.4/net8.0, 7.5/net9.0, and 7.6/net10.0.
2. Test the exact current Microsoft-serviced patch for each supported line. Do not infer support for one line from another installed pwsh.
3. Build isolated net8.0, net9.0, and net10.0 dependency bundles while those three PowerShell lines remain supported. Select the bundle using both the running PowerShell minor line and CLR major, and fail closed on mismatches.
4. Keep multi-pwsh strictly optional and CI/test-only. It must not be shipped, added to the module manifest, referenced by production code, added as a runtime/package dependency, or required to build/install/import/use DLLPickle.
5. If multi-pwsh is used to provision tests, pin and checksum it, use a temporary isolated root, and invoke the official installed pwsh/pwsh.exe directly. Do not use multi-pwsh aliases, native host mode, venv startup hooks, or MCP mode as evidence for the stock PowerShell host. Tests must also accept explicit stock PowerShell executable paths so multi-pwsh can be removed or replaced without product changes.
6. Preserve the documented dependency contract: Dependabot patch/minor dependency updates may auto-approve and auto-merge only after every required build, test, compatibility, and dependency-review gate passes. Major dependency updates must become tested draft PRs with per-TFM evidence and must never auto-merge.
7. Make upstream conflict evidence specific to PowerShell line, TFM, OS/platform, module version, selected asset, import order, and AssemblyLoadContext. Cover Microsoft.Graph, Az.Accounts/Az.Resources/Az.Storage, ExchangeOnlineManagement, and MicrosoftTeams. Do not carry net8.0 classifications forward without fresh evidence.
8. Preserve known safety and compatibility lessons from PR #215 and issues #169, #174, #193, #242, and #273. Expected upstream incompatibilities should be documented and tested as limitations, not hidden or falsely reported as fixed.
9. Stabilize Pester/build-tool loading before interpreting dependency failures. Use fresh non-profile child processes and exact tool versions where necessary.
10. Add package inspection proving that multi-pwsh and all CI-only assets are absent from the published artifact.
11. Use natural PowerShell continuation or splatting; do not introduce backtick line continuations.
12. Ordinary unit tests must be deterministic and network-free. Keep live module discovery, external downloads, authentication, and tenant checks in explicit integration/scheduled lanes.
13. Do not use real credentials or perform tenant/external writes without explicit approval. If authenticated read-only validation cannot run, implement and test its harness, then identify the exact missing validation rather than claiming full success.

Required implementation behavior:

- Start by making the existing CI/Pester harness deterministic.
- Add shipped runtime-profile policy separately from non-shipped exact test-patch/tooling metadata.
- Multi-target and locked-restore net8.0, net9.0, and net10.0.
- Parameterize all child-process and scenario tooling with an exact PowerShell executable.
- Generate the PowerShell/OS matrix from canonical data and retain stable aggregate required-check names.
- Derive NuGet asset selection from restored project.assets.json rather than a handwritten TFM approximation.
- Update dependency-policy and upstream evidence per profile.
- Deduplicate unchanged drift reports by fingerprint.
- Add generated compatibility documentation and artifact-size reporting.
- Refresh documentation and changelog claims.

Verification and stopping condition:

- Analyzer, unit, integration, issue-reproduction, restore, build, pack, loader-selection, policy-schema, workflow-guardrail, documentation-drift, and artifact-inspection tests pass.
- Every available supported PowerShell/OS cell runs the expected stock executable and records PowerShell, CLR, TFM, process path, PSHOME, OS, architecture, selected bundle, and ALC evidence.
- The artifact contains exactly the supported TFM bundles and contains no multi-pwsh files or dependency declarations.
- Dependabot patch/minor and major paths retain their distinct automatic-versus-reviewed behavior.
- All deterministic work is complete, the diff is reviewed with git diff --check, and no unrelated files are changed.
- Credential-dependent or externally blocked validation is either completed with authorization or listed precisely as an outstanding release gate.

Do not mark the goal complete merely because implementation is extensive or because an external validation lane is unavailable. If genuinely blocked, exhaust safe local work, preserve a clear validation handoff, and ask for the smallest specific input needed.
```

If `/goal` is unavailable, enable Goal mode in Codex settings or use the same text as a normal implementation prompt. A normal prompt can still implement the plan; Goal mode mainly supplies persistence and progress controls for the long-running execution.
