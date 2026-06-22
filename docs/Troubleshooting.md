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

## Supported runtime (and Windows PowerShell 5.1)

The automated fix — `Import-DPLibrary` and `Import-DPBaseProfile` — requires
**PowerShell 7.4+ on .NET 8**. It relies on `AssemblyLoadContext`, which does not
exist on .NET Framework 4.8, so it does not run on **Windows PowerShell 5.1**.

If you are on Windows PowerShell 5.1 and hitting the same conflict, you can still
use DLLPickle's **inspection helpers** to solve it manually. Run them from a
PowerShell 7.4+ session — they scan the Windows PowerShell module roots too — to
find which installed module ships the newest identity DLL, then connect to that
service *first* (the "first one wins" workaround). For example:

```powershell
# Compare installed modules by the Microsoft.Identity.Client version they ship,
# and see which copy would load first.
Get-ModulesWithVersionSortedIdentityClient
Get-ModuleImportCandidate
```

See [Architecture.md](Architecture.md) §1.2 for the full platform-support contract.

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

## Common loader errors

### `Binary directory not found for target framework 'net8.0'`

`Import-DPLibrary` loads the bundled assemblies from the module's `bin/net8.0`
folder and throws this error if that folder is missing:

```text
Binary directory not found for target framework 'net8.0' at: <path>\bin\net8.0
```

This usually means the installed module is incomplete, or you are importing from a
source tree that has not been built (the `bin/net8.0` output is generated, not
committed). Re-install the module from the PowerShell Gallery:

```powershell
Install-PSResource -Name DLLPickle   # or: Install-Module DLLPickle -Scope CurrentUser
```

If you are working from a clone, build the module output first and import that:

```powershell
Invoke-Build -Task Build -File .\build\DLLPickle.Build.ps1
Import-Module .\module\DLLPickle\DLLPickle.psd1
```

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
module — so the OData assemblies stay on the block list. As of **2.2.0**, run
`Test-DPLibraryConflict` to reliably check the current session and warn (with the reason and
the workaround below) whenever both modules are loaded. `Import-DPLibrary` warns if the pair is
already loaded when preloading finishes. It does not watch later assembly loads; run
`Test-DPLibraryConflict` after subsequent module imports when you need to recheck the session.

**Workaround:** run the Az.Storage and ExchangeOnlineManagement (`Get-EXO*`) work in separate
PowerShell processes so each process has its own assembly load context. A separate runspace in
the *same* process does **not** help (the conflict is process-wide). The safe repro tests keep
this scenario visible but do not treat OData preloading as a supported fix.
