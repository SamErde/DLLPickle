# External Dependencies

This document tracks the external NuGet packages used by DLLPickle and their
update policies.

## Runtime Baseline

DLLPickle now targets **PowerShell 7.4+** with a single **net8.0** runtime
profile. Legacy Windows PowerShell 5.1 and .NET Framework dependency paths are
no longer supported.

## Purpose

DLLPickle deliberately maintains current Microsoft authentication and identity
libraries to resolve DLL version conflicts in mixed-module PowerShell sessions.
This is a core feature, not a bug: we want the newest compatible versions
loaded first.

For usage guidance, see [README.md](README.md) and [docs/index.md](docs/index.md).

## Dependency Management Strategy

| Update Type | Policy | Automation |
| ----------- | ------ | ---------- |
| **Patch** (x.y.Z) | Auto-merge | Dependabot + auto-approve workflow |
| **Minor** (x.Y.z) | Auto-merge | Dependabot + auto-approve workflow |
| **Major** (X.y.z) | Manual review | Explicit maintainer approval |
| **Upstream PowerShell module drift** | Candidate PR or issue | Upstream Compatibility workflow |

## Upstream Compatibility Automation

Dependabot tracks NuGet package releases, but DLLPickle also tracks the DLLs
bundled by upstream PowerShell modules. The scheduled **Upstream Compatibility**
workflow uses `build/dependency-policy.json` and tools under `tools/` to
inventory latest PSGallery releases and propose safe exact-pin updates.

Monitored modules:

- `Microsoft.Graph.Authentication`
- `ExchangeOnlineManagement`
- `Az.Storage`
- `Az.Accounts`
- `MicrosoftTeams`

The workflow is fail-closed: it only opens a candidate PR after inventory,
candidate generation, restore, build, and issue reproduction tests pass.

## NuGet Package Dependencies

| Package | Version Strategy | Notes |
| ------- | ---------------- | ----- |
| `Microsoft.Identity.Client` | Exact pin | Aligns base profile MSAL line |
| `Microsoft.Identity.Client.Broker` | Exact pin | Kept aligned with MSAL |
| `Microsoft.Identity.Client.Extensions.Msal` | Exact pin | Kept aligned with MSAL cache helper line |
| `Microsoft.Identity.Client.NativeInterop` | Exact pin | Includes native runtime files |
| `Microsoft.IdentityModel.Abstractions` | `8.*` | Identity model support |
| `Microsoft.IdentityModel.Logging` | `8.*` | Identity diagnostics/logging |
| `Microsoft.IdentityModel.JsonWebTokens` | `8.*` | JWT handling |
| `Microsoft.IdentityModel.Tokens` | `8.*` | Token validation/processing |
| `System.IdentityModel.Tokens.Jwt` | `8.*` | JWT handlers |

## Exact Pin Rationale

- Exact pins are used for the MSAL managed family (`Microsoft.Identity.Client`
  and friends) because mixed-module sessions can fail when one module binds to a
  lower, incompatible assembly.
- Candidate exact-pin updates are generated from upstream module inventories and
  still require full validation before publication.
- `Azure.Core` is intentionally **not** preloaded on the PowerShell 7.4+
  (net8.0) profile. Az.Accounts 5.x isolates its Azure SDK stack in a private
  `AssemblyLoadContext`; preloading `Azure.Core` into the default load context
  splits the identity of `Azure.Core.TokenRequestContext` across load contexts
  and breaks `Connect-AzAccount` with a `MissingMethodException` on
  `InteractiveBrowserCredential.AuthenticateAsync`. Graph, Exchange, and Teams
  resolve a compatible `Azure.Core` themselves on .NET 8, so the preload is
  unnecessary. `Azure.Core` remains report-only in policy for monitoring. The
  original net48-only `Azure.Core` preload (#183) does not apply to the net8.0
  baseline.
- OData families remain report-only in policy because preloading them by
  default can break compatibility when upstream modules require different OData
  identities.

## Lock File Workflow

- Restore in CI and local build runs in `--locked-mode`.
- When package references change in `src/DLLPickle.Build/DLLPickle.csproj`,
  refresh the lock file:

```powershell
dotnet restore src/DLLPickle.Build/DLLPickle.csproj --force-evaluate
```

- Commit the updated `src/DLLPickle.Build/packages.lock.json` in the same
  change.
- Validate lock consistency:

```powershell
dotnet restore src/DLLPickle.Build/DLLPickle.csproj --locked-mode
```

## Supply Chain Security

Protections in place:

1. Dependabot monitoring and update PRs
1. Dependency Review checks
1. OSSF Scorecard monitoring
1. Package lock file for reproducible restore
1. Automated build and test validation
1. CODEOWNERS review gates
1. Upstream compatibility inventory + candidate PR workflow

Manual review required for:

- Major version upgrades
- New package additions
- Changes to version strategy

## References

- [Dependabot Configuration](/.github/dependabot.yml)
- [Auto-Approve Workflow](/.github/workflows/Dependabot-Auto-Approve.yml)
- [Dependency Review Workflow](/.github/workflows/Dependency-Review.yml)
- [Package Validation Workflow](/.github/workflows/Validate-Packages.yml)
- [CODEOWNERS](/.github/CODEOWNERS)
- [Security Policy](/SECURITY.md)
- [Contributing Guide](/.github/CONTRIBUTING.md)
