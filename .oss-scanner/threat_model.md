---
title: DLL Pickle security analysis scope
summary: Trust boundaries, reproduction guidance and severity expectations.
---

## Purpose and security boundary

DLL Pickle is a PowerShell module that preloads compatible identity assemblies
before service modules import their own dependencies. It runs inside the user's
PowerShell process, often a session used to administer Microsoft tenants. It
coordinates library loading; the consuming modules and Microsoft libraries
perform authentication and token handling.

Prioritize defects in DLL Pickle that let less-trusted inputs change which code
executes in that process, disclose sensitive data, or undermine the integrity of
the distributed module. Explain the attacker's initial privileges and the new
capability gained. An attacker who already controls the entire installed module
directory can replace executable code; demonstrate an additional trust-boundary
crossing before treating such control as a vulnerability in the loader.

## Surfaces to examine

- `src/DLLPickle/Public/Import-DPLibrary.ps1` and its private helpers: runtime
  selection, assembly discovery/order, load-context interactions, native runtime
  paths, host-provided assembly exclusions and failure handling.
- Module discovery and import helpers: module roots, filenames, versions and
  assembly metadata. Determine who controls each input and which process trusts it.
- Configuration and runtime-policy parsing: malformed values, unsafe path
  resolution, unintended loading and information exposed through diagnostics.
- Build scripts, NuGet lock enforcement, artifact composition and GitHub release
  workflows: attacker-controlled changes or inputs crossing a build/publish
  permission boundary. Distinguish a vulnerable workflow from authorized
  maintainer changes to trusted source.
- Assembly-resolution callbacks and background execution: process crashes or
  unsafe behavior reachable through DLL Pickle's own implementation.

Dependencies are installed to exercise this project. Attribute bugs in Microsoft
libraries or other service modules to their owning project. Focus reports here
on DLL Pickle's use, selection and packaging of those dependencies.

## Reproduce and validate

The full checkout is `/src`. Run:

```sh
cd /src
pwsh -NoLogo -NoProfile -NonInteractive -File .oss-scanner/test.ps1
```

This rebuilds the module and runs each runtime declared in
`build/powershell-test-matrix.json` in a fresh process. Exact executable paths
are in `/opt/dllpickle/runtimes.json`. The built module is
`/src/module/DLLPickle`; per-runtime results are in
`/src/artifacts/oss-scanner`. Runtime archives, tools and dependency caches remain
available offline. Preserve locked dependency resolution when validating patches.

Use synthetic modules, assemblies and tokens in reproducers. The image contains
no tenant credentials. A mock authentication success is evidence about that mock
only. Linux execution cannot establish Windows broker/WAM, Windows permissions,
macOS behavior or successful real tenant authentication. Label findings requiring
those platforms as unverified on that platform and describe the missing test.

## Severity and report expectations

- Critical: demonstrated broad compromise, such as a viable path to distributing
  attacker-controlled authentication code through the trusted release process.
  State every prerequisite; proximity to authentication alone is insufficient.
- High: demonstrated code execution, credential/token exposure or privilege
  escalation across a real trust boundary under realistic prerequisites.
- Medium: bounded confidentiality/integrity impact or reliably exploitable
  availability loss within the affected user's process.
- Low: limited hardening gaps without a demonstrated stronger impact.

For each report, include the affected source revision, runtime and OS, attacker
control, exact reproduction, expected versus observed behavior, impact and a
focused regression test. Separate verified behavior from inference. Prefer a
small patch that preserves the supported runtime and dependency contracts.
Group findings sharing one root cause; retain distinct exploit prerequisites.

Report vulnerabilities privately through the configured scanner channel or
`SECURITY.md`. Enrollment configuration and workflow logs are public; keep
credentials and sensitive vulnerability details out of them.
