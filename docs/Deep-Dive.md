# Deep Dive

DLLPickle exists to solve a specific PowerShell assembly-loading problem:
different modules can ship different versions of the same dependency DLL, but a
single PowerShell process can only load one assembly identity at a time. In
practice, this often shows up as authentication failures when connecting to
multiple Microsoft services in one session.

## Problem Model

Multiple service modules (for example, Graph, Exchange, Teams, Az) commonly
package identity-related assemblies such as `Microsoft.Identity.Client.dll`.
When one module loads an older copy first, another module that expects a newer
copy can fail with "an assembly with the same name is already loaded" or type
load errors.

DLLPickle addresses this by loading a compatible set of identity-related
assemblies before other modules attempt their own assembly loads.

## Related Issues

This class of conflict is widely reported across Microsoft's first-party
PowerShell modules:

- [Connect-MgGraph fails after Connect-ExchangeOnline](https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/3394)
- [UUF Customer feedback: Get-EntraExtensionProperty error](https://github.com/microsoftgraph/entra-powershell/issues/1258) (Assembly with same name is already loaded)
- [Assembly with same name is already loaded](https://github.com/microsoftgraph/entra-powershell/issues/1083)
- [Design entra-powershell with ALC bridge pattern for more robust assembly load handling](https://github.com/microsoftgraph/entra-powershell/issues/1242)
- [Implement proper assembly isolation to play nice with vscode-powershell](https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/2978)
- [Conflict with the .NET DLL of the Az module (vscode-powershell#3012)](https://github.com/PowerShell/vscode-powershell/issues/3012)
- [Unable to load Az modules — Assembly with same name is already loaded (vscode-powershell#4727)](https://github.com/PowerShell/vscode-powershell/issues/4727)

## How DLLPickle Works

`Import-DPLibrary` loads DLLs from the module's packaged `bin` folder that
matches the supported runtime target:

- `bin/net8.0` for PowerShell 7.4+

To improve reliability, the loader:

1. Builds a dependency graph from local assembly metadata.
1. Applies dependency-first ordering where possible.
1. Appends unresolved nodes in deterministic alphabetical order.
1. Adds packaged native runtime directories for the current process RID to
   `PATH` so broker/MSAL native dependencies can be found without loading native
   DLLs as managed assemblies.
1. Retries failed loads and reports unresolved failures.

This approach reduces transient first-pass load failures while keeping behavior
predictable and diagnosable.

## The inspection helpers (and Windows PowerShell 5.1)

`Import-DPLibrary` is the *automated* fix, and it needs PowerShell 7.4+ / .NET 8
because it depends on `AssemblyLoadContext`. But DLLPickle also ships a set of
**inspection helpers** that are deliberately cross-edition:

- `Find-DLLInPSModulePath` — find DLLs across the installed module paths
  (including the Windows PowerShell roots), filtered by product metadata.
- `Get-ModulesWithDependency` — list installed modules that package a given
  dependency DLL.
- `Get-ModulesWithVersionSortedIdentityClient` — compare modules by the
  `Microsoft.Identity.Client.dll` version they ship.
- `Get-ModuleImportCandidate` — show which installed module version would import.
- `Test-DPLibraryConflict` — report known-incompatible module pairs already loaded
  in the current session.

These exist so the project charter still helps environments the preloader cannot
reach. A **Windows PowerShell 5.1** user who hits the same DLL conflict can run
these helpers from a PowerShell 7.4+ session, see which installed module ships the
newest identity DLL, and connect to that service *first* — the same "first one
wins" idea, applied by hand. The automated preload is the convenience; the manual
workaround is always available.

## Dependency Maintenance Automation

DLLPickle's preload set must track both NuGet package releases and the DLLs that
upstream Microsoft PowerShell modules bundle in PSGallery releases. A package
can be current on NuGet and still be the wrong preload candidate if Graph,
Teams, Exchange, or Az modules reference a different strong-named assembly in
their module folders.

The repository therefore includes an upstream compatibility policy and scheduled
workflow:

- `build/dependency-policy.json` declares monitored PSGallery modules, tracked
  assembly families, per-assembly version policies, and blocked preload families.
- `tools/Get-DLLPickleUpstreamInventory.ps1` downloads and inventories the
  latest monitored modules.
- `tools/Update-DLLPickleDependencyPins.ps1` compares the inventory with the
  policy and applies safe candidate pin updates (major-locked floating `N.*`, or an exact pin when a `maximumPackageVersion` cap applies).
- `.github/workflows/Upstream-Compatibility.yml` runs the inventory and
  candidate update flow on a schedule or on demand.

The monitored module set currently includes:

- `Microsoft.Graph.Authentication`
- `ExchangeOnlineManagement`
- `Az.Storage`
- `Az.Accounts`
- `MicrosoftTeams`

The workflow is fail-closed. It may open a candidate PR when a policy-supported
pin changes, such as a Graph or Teams `Azure.Core` update. It does not merge or
publish changed preload behavior unless the
candidate passes restore, build, and issue reproduction validation.

Some dependency families are deliberately report-only. For example, OData
assemblies are tracked because ExchangeOnlineManagement and Az.Storage can
require incompatible versions in one process, but OData is not added to the
default preload set unless a future isolation strategy makes that safe.

`Azure.Core` is also report-only. It is intentionally not preloaded on the
PowerShell 7.4+ profile: both `Az.Accounts` (`AzSharedAssemblyLoadContext`) and
`Microsoft.Graph.Authentication` (`msgraph-load-context`) isolate their Azure SDK
stack in private `AssemblyLoadContext`s — they even run different `Azure.Core`
versions side-by-side without conflict. Preloading `Azure.Core` into the default
load context splits the identity of `Azure.Core.TokenRequestContext` across that
boundary and breaks `Connect-AzAccount`. Because the modules self-manage it, the
preload is unnecessary on .NET 8.

> **Windows PowerShell 5.1 caveat:** this module self-isolation relies on
> `AssemblyLoadContext`, which only exists on .NET (Core) 5+. Windows PowerShell
> 5.1 (.NET Framework 4.8) has no ALC, so modules cannot self-isolate there —
> which is exactly why DLLPickle's automated preloader does not support 5.1 (use
> the inspection helpers above for the manual path). Re-adding net48 is **out of
> scope for the current major version**; if it were ever revisited, the Azure SDK
> stack would have to be preloaded again, net48-only. The maintainer-facing
> re-introduction checklist lives in [Architecture.md](Architecture.md) §10.

## Validated Base Profile

The validated base profile for a single interactive session is:

1. `ExchangeOnlineManagement`
1. `MicrosoftTeams`
1. `Microsoft.Graph.Authentication`
1. `Az.Accounts`

Use `Import-DPBaseProfile` to run `Import-DPLibrary` and import those modules in
that order. If `Az.Accounts` is imported first, it can load an older Azure
identity stack before Microsoft Graph and recreate
the `UserProvidedTokenCredential.GetTokenAsync` type identity failure.

`Import-DPBaseProfile` intentionally does not authenticate to any service. It
only prepares the process and imports modules so connection commands such as
`Connect-ExchangeOnline`, `Connect-MicrosoftTeams`, `Connect-MgGraph`, and
`Connect-AzAccount` can run afterward using credentials and tenant choices from
the caller's environment.

Live testing confirms the full base profile can connect to Exchange Online,
Microsoft Teams, Microsoft Graph, and Az.Accounts in one session. Because
DLLPickle no longer preloads `Azure.Core` on the net8.0 profile, Az.Accounts'
private `AssemblyLoadContext` resolves a single, consistent `Azure.Core`, and
`Connect-AzAccount` succeeds alongside the Graph/Exchange/Teams identity stack.

## Why This Helps

- Preloads a coherent identity stack early in the session.
- Reduces module-to-module assembly contention.
- Preserves normal module workflows after one initial preloading step.

## Recommended Usage Pattern

Run DLLPickle early in the session, before connecting to service modules:

```powershell
Import-Module DLLPickle
Import-DPLibrary
```

For the supported base profile, prefer:

```powershell
Import-Module DLLPickle
Import-DPBaseProfile
```

For diagnostics:

```powershell
Import-DPLibrary -SuppressLogo -ShowLoaderExceptions -Verbose
```

## Configuration

DLLPickle supports user-level configuration through:

- `Get-DPConfig`
- `Set-DPConfig`

You can use these commands to manage behaviors such as logo display and library
exclusion for environment-specific troubleshooting.

## More Reference Material

- [Import-DPLibrary command help](DLLPickle/Import-DPLibrary.md)
- [Module reference](DLLPickle.md)
- [Dependency policy and compatibility notes](DEPENDENCIES.md)

## Known limitation: Az.Storage + ExchangeOnlineManagement (issue #174)

`Az.Storage` and `ExchangeOnlineManagement` bundle **incompatible, strong-named versions of
`Microsoft.OData.Core`** (7.6.4 and 7.22.0 respectively) and both load it into the default
`AssemblyLoadContext`. Only one version can exist per process, and **neither import order works**:

- Import `Az.Storage` first, then run `Get-EXO*` → fails (`Could not load … Microsoft.OData.Core,
  Version=7.22.0.0 … manifest definition does not match`).
- Import `ExchangeOnlineManagement`/`Connect-ExchangeOnline` first, then import `Az.Storage` → fails
  (`Microsoft.OData.Core, Version=7.6.4.0 … assembly with same name is already loaded`).

This is an upstream incompatibility between the two modules; **DLLPickle cannot fix it by preloading**
(preloading either version breaks the other module), which is why the OData assemblies are
classified `block`. `Import-DPLibrary` warns if it finds both modules already loaded; run
`Test-DPLibraryConflict` after later imports to check the session again.

**Workaround:** use the two modules in **separate PowerShell processes** — for example, run `Get-EXO*`
work in one `pwsh` (or a `Start-Job` background job) and `Az.Storage` work in another. A separate
**runspace** in the *same* process does **not** help: the conflict is process-wide (one default
`AssemblyLoadContext` per process).

## Audio Discussion

[![Listen](https://raw.githubusercontent.com/SamErde/DLLPickle/main/assets/DLL_Pickle__A_Clever_Fix.png)](https://raw.githubusercontent.com/SamErde/DLLPickle/main/assets/DLL_Pickle__Interactive_Deep_Dive_audio.mp4)

> Ending PowerShell DLL Hell: How a Community Fix Uses "First-One-Wins" to Master Azure, Exchange, and Teams Connection Conflicts. An interactive audio deep-dive generated by NotebookLM.

## Video Explanation

[![Watch](https://raw.githubusercontent.com/SamErde/DLLPickle/main/assets/DLL_Pickle__A_Clever_Fix.png)](https://raw.githubusercontent.com/SamErde/DLLPickle/main/assets/DLL_Pickle__A_Clever_Fix.mp4)

> A high-level walkthrough of the dependency conflict model and how preloading
> reduces assembly contention in mixed-module sessions.
