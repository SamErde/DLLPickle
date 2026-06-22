# External Dependencies

This document tracks the external NuGet packages used by DLLPickle and their
update policies.

## Runtime Baseline

DLLPickle now targets **PowerShell 7.4+** with a single **net8.0** runtime
profile. Legacy Windows PowerShell 5.1 and .NET Framework dependency paths are
no longer supported.

The *automated* fix (`Import-DPLibrary` / `Import-DPBaseProfile`) requires
PowerShell 7.4+ / .NET 8 because it depends on `AssemblyLoadContext`. The
*inspection / diagnostic* helpers (`Find-DLLInPSModulePath`,
`Get-ModuleImportCandidate`, `Get-ModulesWithDependency`,
`Get-ModulesWithVersionSortedIdentityClient`, `Test-DPLibraryConflict`) are
intentionally cross-edition — they scan the Windows PowerShell module roots too,
so a Windows PowerShell 5.1 user can still discover which module to load first and
apply the conflict workaround manually. See
[docs/Architecture.md](docs/Architecture.md) §1.2 for the full platform-support
contract.

## Purpose

DLLPickle deliberately maintains current Microsoft authentication and identity
libraries to resolve DLL version conflicts in mixed-module PowerShell sessions.
This is a core feature, not a bug: we want the newest compatible versions
loaded first.

For usage guidance, see [README.md](README.md) and [docs/index.md](docs/index.md).

## Dependency Management Strategy

Every tracked-dependency release is first checked for **target-framework
alignment**: it must restore, build, and pass tests on `net8.0` under
`--locked-mode`, and ship a net8.0/netstandard2.0-compatible assembly (verified
by `tools/Test-DLLPickleTfmAlignment.ps1`). Only then does the severity of the
version jump decide how it ships:

| Update Type | Policy |
| ----------- | ------ |
| **Patch / Minor** (x.Y.Z) | After the TFM-alignment + test gate, approve and merge with a detailed PR comment. Identity-library bumps are the module's core deliverable, so they ship as a **minor** module release — Dependabot's `deps:` commit is a recognized minor release prefix, so an auto-merged bump publishes a minor release on its own. |
| **Major** (X.y.z) | Still fully tested and TFM-verified, with the conflict surface re-adjudicated, but opened as a **draft PR with fully detailed notes** — **not** auto-merged and **not** auto-published. A maintainer promotes and merges it, publishing a **major** release (`breaking:`). |
| **Upstream PowerShell module drift** | Candidate PR or issue after the scheduled inventory + drift check. |

> **Publish note.** A merged dependency PR publishes a new gallery version only
> when its commit also carries a release-worthy Conventional Commit prefix (see
> Versioning, below). Dependabot's NuGet commits use the `deps:` prefix, which
> `Get-VersionBump.ps1` recognizes as a **minor** release prefix, so an
> auto-merged minor/patch bump publishes a **minor** release on its own. Major
> dependency PRs are converted to a reviewed draft with detailed notes (not
> auto-merged or auto-published) and merged carrying a `breaking:` prefix; an
> explicit TFM-alignment check (`tools/Test-DLLPickleTfmAlignment.ps1`) runs
> fail-closed in the candidate flow. See
> [docs/Architecture.md](docs/Architecture.md) §8.2.

The automation that supports this: Dependabot opens NuGet update PRs; the
**Dependabot-Auto-Approve** workflow auto-approves and squash-merges patch/minor
updates (restricted to the exact `DLLPickle.csproj` / `packages.lock.json`
allow-list, and only after the `Build gate`, `Validate upstream compatibility
tooling`, and `dependency-review` required checks pass) and excludes major
updates from auto-merge, converting them to a reviewed **draft PR** with detailed
notes instead.

## Versioning

DLLPickle follows [Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`).
Releases are cut automatically by the **Release-and-Publish** workflow, which
derives the bump **solely from the [Conventional Commit](https://www.conventionalcommits.org/)
prefixes** of the commits since the last tag (see
[`.github/ci-scripts/Get-VersionBump.ps1`](.github/ci-scripts/Get-VersionBump.ps1)):

| Bump | Commit prefix |
| ---- | ------------- |
| **MAJOR** (`X.y.z`) | `BREAKING CHANGE:`, `breaking:`, or `major-release` |
| **MINOR** (`x.Y.z`) | `feat:` (or `minor:`), and `deps:` (Dependabot's NuGet bumps) |
| **PATCH** (`x.y.Z`) | `fix:`, `perf:`, `refactor:`, `security:`, or `chore:` |

The bump is decided by the commit prefix alone — there is **no** separate
detection of dependency or MSAL version changes. The automated MSAL /
identity-library bumps that are the module's core purpose land as `deps:`
(Dependabot's NuGet prefix), which `Get-VersionBump.ps1` maps to a **minor**
release, so an auto-merged minor/patch bump produces a minor release on its own.
A bundled-library **major** jump is reviewed as a draft PR and merged carrying a
`breaking:` prefix. See [docs/Architecture.md](docs/Architecture.md) §8.2 for the
full lifecycle.

A new PowerShell Gallery version is published **only** when a change affects the
published module bundle (`src/DLLPickle/**` or the bundled package set). CI-,
docs-, policy-, and tooling-only changes do not trigger a release. See
[CHANGELOG.md](CHANGELOG.md) for the released history.

## Upstream Compatibility Automation

Dependabot tracks NuGet package releases, but DLLPickle also tracks the DLLs
bundled by upstream PowerShell modules. The scheduled **Upstream Compatibility**
workflow uses `build/dependency-policy.json` and tools under `tools/` to
inventory latest PSGallery releases and propose safe candidate pin updates.

Monitored modules:

- `Microsoft.Graph.Authentication`
- `ExchangeOnlineManagement`
- `Az.Storage`
- `Az.Accounts`
- `MicrosoftTeams`

The workflow is fail-closed: it only opens a candidate PR after inventory,
candidate generation, restore, build, and issue reproduction tests pass.

## NuGet Package Dependencies

Version strategy in `DLLPickle.csproj` is **major-locked floating** (`N.*`); the
lock file pins the concrete resolved version.

| Package | Version Strategy | Notes |
| ------- | ---------------- | ----- |
| `Microsoft.Identity.Client` | `4.*` (major-locked float) | Aligns base profile MSAL line |
| `Microsoft.Identity.Client.Broker` | `4.*` (major-locked float) | Kept aligned with MSAL |
| `Microsoft.Identity.Client.Extensions.Msal` | `4.*` (major-locked float) | Kept aligned with MSAL cache helper line |
| `Microsoft.Identity.Client.NativeInterop` | `0.*` (major-locked float) | Includes native runtime files; tracks the broker requirement |
| `Microsoft.IdentityModel.Abstractions` | `8.*` | Identity model support |
| `Microsoft.IdentityModel.Logging` | `8.*` | Identity diagnostics/logging |
| `Microsoft.IdentityModel.JsonWebTokens` | `8.*` | JWT handling |
| `Microsoft.IdentityModel.Tokens` | `8.*` | Token validation/processing |
| `System.IdentityModel.Tokens.Jwt` | `8.*` | JWT handlers |

### Upstream package documentation

The libraries DLLPickle tracks for preloading are maintained and documented by
their own code owners:

- [Microsoft.Identity.Abstractions](https://www.nuget.org/packages/Microsoft.Identity.Abstractions)
- [Microsoft.Identity.Client](https://www.nuget.org/packages/Microsoft.Identity.Client)
- [Microsoft.IdentityModel.Abstractions](https://www.nuget.org/packages/Microsoft.IdentityModel.Abstractions)
- [Microsoft.IdentityModel.JsonWebTokens](https://www.nuget.org/packages/Microsoft.IdentityModel.JsonWebTokens)
- [Microsoft.IdentityModel.Logging](https://www.nuget.org/packages/Microsoft.IdentityModel.Logging)
- [Microsoft.IdentityModel.Tokens](https://www.nuget.org/packages/Microsoft.IdentityModel.Tokens)
- [System.IdentityModel.Tokens.Jwt](https://www.nuget.org/packages/System.IdentityModel.Tokens.Jwt)

## Version Pinning Rationale

- The MSAL managed family (`Microsoft.Identity.Client` and friends) and the
  IdentityModel family use **major-locked floating** references (`4.*`, `0.*`,
  `8.*`) in `DLLPickle.csproj`: Dependabot can move the minor/patch within the
  major, but a major jump is a deliberate, reviewed change.
  `packages.lock.json` pins the **concrete resolved version**, so every build and
  restore (`--locked-mode`) is reproducible. This matters because mixed-module
  sessions can fail when one module binds to a lower, incompatible assembly.
- Candidate pin updates are generated from upstream module inventories and still
  require full validation before publication.
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
