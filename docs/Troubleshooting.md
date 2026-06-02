---
post_title: Troubleshooting DLLPickle assembly conflicts
author1: Sam Erde
post_slug: troubleshooting-dllpickle-assembly-conflicts
microsoft_alias: n/a
featured_image: n/a
categories: [documentation]
tags: [powershell, troubleshooting, testing]
ai_note: AI-assisted draft
summary: How to collect DLLPickle issue reproduction diagnostics for assembly conflict reports.
post_date: 2026-05-06
---

## Troubleshooting assembly conflicts

DLLPickle includes an issue reproduction test harness for collecting
repeatable diagnostics when Microsoft service modules load conflicting
assemblies. The default tests use synthetic modules and do not require service
credentials, VS Code, Azure Automation, or PSGallery module installation.

## Run the safe issue repro tests

The safe repro task prepares the built module output and runs integration tests
while excluding tests tagged `LiveRepro`.

```powershell
Invoke-Build -Task IssueReproTest -File .\build\DLLPickle.Build.ps1
```

The tests write Pester output under `artifacts\testOutput`. Individual
scenario tests also return structured JSON in temporary paths while they run.

## Run live repro tests

Live repro tests are skipped unless the `DLLPICKLE_RUN_LIVE_REPRO` environment
variable is set to `1`.

```powershell
$env:DLLPICKLE_RUN_LIVE_REPRO = '1'
Invoke-Build -Task IssueReproTest -File .\build\DLLPickle.Build.ps1
Remove-Item Env:\DLLPICKLE_RUN_LIVE_REPRO -ErrorAction SilentlyContinue
```

Live tests may import installed copies of modules such as
ExchangeOnlineManagement, Microsoft.Graph.Authentication, Az.Storage, and
PowerShellEditorServices.Commands. They are intended for maintainer-controlled
diagnostics because they depend on the local host, installed module versions,
and optional service authentication.

## Run a VS Code host repro

Use the VS Code task named `IssueReproTest-Live` from the integrated PowerShell
terminal to compare VS Code host behavior with a regular terminal session.

## Compare two scenario results

When evaluating a fix, capture a baseline JSON result and a candidate JSON
result, then compare them with:

```powershell
. .\tests\Integration\Compare-DLLPickleScenarioResult.ps1
Compare-DLLPickleScenarioResult -BaselinePath .\before.json -CandidatePath .\after.json
```

The comparison shows changed step outcomes and final loaded assembly
differences by name, version, and location.

## Current issue-specific findings

### Issue #156: Graph Authentication and ExchangeOnlineManagement

DLLPickle packages exact MSAL managed-family pins (`Microsoft.Identity.Client`
and friends) for the supported base profile. The issue repro tests assert that
the protected import path keeps the broker/MSAL line aligned to avoid
`WithBroker` missing-method failures across mixed imports.

`Azure.Core` is intentionally not preloaded on the PowerShell 7.4+ (net8.0)
profile. The original `Azure.Core` preload (#183) was scoped to Windows
PowerShell (net48), which 2.0 no longer supports. On .NET 8, Graph, Exchange,
and Teams resolve a compatible `Azure.Core` themselves, and preloading it breaks
`Connect-AzAccount` (see the Az.Accounts note below).

For sessions that need Exchange Online, Microsoft Teams, Microsoft Graph, and
Az.Accounts imported together, use:

```powershell
Import-Module DLLPickle
Import-DPBaseProfile
```

This imports the validated base profile order:

1. `ExchangeOnlineManagement`
1. `MicrosoftTeams`
1. `Microsoft.Graph.Authentication`
1. `Az.Accounts`

### Connect-AzAccount and the Azure.Core load context

Earlier 2.0 builds preloaded `Azure.Core` into the default load context, which
broke `Connect-AzAccount` with:

```text
Method not found: 'System.Threading.Tasks.Task`1<Azure.Identity.AuthenticationRecord>
Azure.Identity.InteractiveBrowserCredential.AuthenticateAsync(Azure.Core.TokenRequestContext,
System.Threading.CancellationToken)'.
```

Az.Accounts 5.x isolates its Azure SDK stack in a private
`AssemblyLoadContext` (`AzSharedAssemblyLoadContext`). A preloaded `Azure.Core`
in the default context splits the identity of `Azure.Core.TokenRequestContext`
across the two load contexts, so Az's `InteractiveBrowserCredential` method
signature no longer matches its caller.

DLLPickle no longer preloads `Azure.Core` on the net8.0 profile, so Az.Accounts
resolves a single, consistent `Azure.Core` and `Connect-AzAccount` succeeds
alongside the Graph/Exchange/Teams stack. If you still see this error, confirm
no other module or profile script preloaded `Azure.Core` into the session, or
add `Azure.Core.dll` to `Set-DPConfig -SkipLibraries` as a safeguard.

### Issue #174: Az.Storage and ExchangeOnlineManagement OData

Az.Storage (9.6.1) loads `Microsoft.OData.Core` 7.6.4 at import; ExchangeOnlineManagement
(3.9.2) needs 7.22.0 for its `Get-EXO*` cmdlets. Both load into the **default**
`AssemblyLoadContext` and are strong-named, so the two versions cannot coexist in one
process. A 2026-06-01 runtime probe confirmed that **both import orders fail**:

- Az.Storage first, then `Get-EXO*` &rarr; fails (wants 7.22.0, but 7.6.4 is already loaded).
- ExchangeOnlineManagement first, then `Import-Module Az.Storage` &rarr; fails (wants 7.6.4, but 7.22.0 is already loaded).

DLLPickle cannot resolve this by preloading — preloading either version breaks the other
module — so the OData assemblies stay on the block list. As of **2.2.0**, DLLPickle ships
`Test-DPLibraryConflict` (and `Import-DPLibrary` surfaces the same warning automatically) to
flag the conflict when both modules are loaded, with the reason and the workaround below.

**Workaround:** run the Az.Storage and ExchangeOnlineManagement (`Get-EXO*`) work in separate
PowerShell processes so each process has its own assembly load context. A separate runspace in
the *same* process does **not** help (the conflict is process-wide). The safe repro tests keep
this scenario visible but do not treat OData preloading as a supported fix.
