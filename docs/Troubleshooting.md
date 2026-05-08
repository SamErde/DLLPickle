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

DLLPickle packages an exact net48 `Azure.Core` 1.55.0 dependency and exact MSAL
managed-family pins for the supported base profile. Real Windows PowerShell
validation showed that preloading a newer `Azure.Core` can still allow Graph's
1.51.1 copy to load side-by-side, which causes the `GetTokenAsync` type identity
failure. The issue repro tests assert that the protected Windows PowerShell
import path uses the maintained Azure.Core preload line.

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

Windows PowerShell 5.1 can still fail if `Az.Accounts` is imported before
Microsoft Graph because Az.Accounts can load older Azure identity assemblies
first. PowerShell 7+ import-only testing is more flexible, but the same order is
recommended for consistency.

Windows PowerShell 5.1 has a remaining Az authentication limitation even with
the validated import order: `Connect-AzAccount` can fail after Graph or Exchange
loads Azure.Identity because Az.Accounts uses a module-local assembly loader.
Use PowerShell 7+ for the full connected base profile, or run Az authentication
and Az cmdlets in a separate process from Graph/Exchange workloads.

### Issue #174: Az.Storage and ExchangeOnlineManagement OData

Az.Storage 9.6.0 imports `Microsoft.OData.Core` 7.6.4. ExchangeOnlineManagement
3.9.2 can later request `Microsoft.OData.Core` 7.22.0 from `Get-EXO*` cmdlets.
Preloading OData 7.22.0 from DLLPickle was tested and rejected because it
breaks Az.Storage import with an assembly collision against its 7.6.4 copy.

The safe repro tests keep this scenario visible but do not treat OData
preloading as a supported fix. If both modules need incompatible OData versions,
run the Az.Storage and ExchangeOnlineManagement work in separate PowerShell
processes so each process has its own assembly load context.
