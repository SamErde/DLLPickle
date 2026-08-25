# External Dependencies

This document tracks the external NuGet packages used by DLLPickle and their
update policies.

## Runtime Baseline

DLLPickle ships three physically isolated bundles for the exact profiles in the
[generated support matrix](generated/Support-Matrix.md): PowerShell 7.4 / .NET 8
(`net8.0`), PowerShell 7.5 / .NET 9 (`net9.0`), and PowerShell 7.6 / .NET 10
(`net10.0`). The loader checks both the PowerShell minor and CLR major and fails
closed on an undeclared or mismatched profile. Legacy Windows PowerShell 5.1 and
.NET Framework dependency paths are not supported by the automated preloader.

The *automated* fix (`Import-DPLibrary` / `Import-DPBaseProfile`) requires
one of those supported .NET profiles because it depends on `AssemblyLoadContext`. The
*inspection / diagnostic* helpers (`Find-DLLInPSModulePath`,
`Get-ModuleImportCandidate`, `Get-ModulesWithDependency`,
`Get-ModulesWithVersionSortedIdentityClient`, `Test-DPLibraryConflict`) are
intentionally cross-edition — from a supported PowerShell session they still inspect
the current-user Windows PowerShell roots (for example
`Documents\WindowsPowerShell\Modules`), and when actually running on 5.1 they
also auto-seed the all-users WinPS root. That lets a Windows PowerShell 5.1
user still discover which module to load first and apply the conflict
workaround manually. See
[Architecture.md](Architecture.md) §1.2 for the full platform-support
contract.

## Purpose

DLLPickle deliberately maintains current Microsoft authentication and identity
libraries to resolve DLL version conflicts in mixed-module PowerShell sessions.
This is a core feature, not a bug: we want the newest compatible versions
loaded first.

For usage guidance, see [README.md](../README.md) and [docs/index.md](index.md).

## Dependency Management Strategy

Every tracked-dependency release is first checked for **target-framework
alignment**: it must restore under `--locked-mode`, build and pass tests for all
three TFMs, and have NuGet select a managed asset for every preload package in
each restored `project.assets.json` target graph. `tools/Test-DLLPickleTfmAlignment.ps1`
records those selected assets rather than approximating compatibility from folder
names. Only then does the severity of the version jump decide how it ships:

| Update Type | Policy |
| ----------- | ------ |
| **Patch / Minor** (x.Y.Z) | May auto-approve and register auto-merge only when the exact actor/author, file-set, complete TFM/runtime matrix, upstream-policy, build, artifact-size, and dependency-review gates pass. A conditional TFM pin, classification edit, or material size growth routes to review. Identity-library bumps ship as a **minor** module release through the `deps:` prefix. |
| **Major** (X.y.z) | Fully tested and TFM-verified, with per-TFM graph/asset/assembly/size evidence and the conflict surface re-adjudicated, but converted to a **draft PR** — **not** auto-merged and **not** auto-published. A maintainer promotes and merges it as a **major** release (`breaking:`). |
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
> [Architecture.md](Architecture.md) §8.2.

The automation that supports this: Dependabot opens NuGet update PRs; the
**Dependabot-Auto-Approve** workflow auto-approves and squash-merges patch/minor
updates (restricted to the exact `DLLPickle.csproj` / `packages.lock.json`
  allow-list, and only after the `Build gate`, `Validate upstream compatibility
  tooling`, complete exact-runtime matrix, artifact-size policy, and
  `dependency-review` required checks pass) and excludes major
updates from auto-merge, converting them to a reviewed **draft PR** with detailed
notes instead.

## Versioning

DLLPickle follows [Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`).
Releases are cut automatically by the **Release-and-Publish** workflow, which
derives the bump **solely from the [Conventional Commit](https://www.conventionalcommits.org/)
prefixes** of the commits since the last tag (see
[`../.github/ci-scripts/Get-VersionBump.ps1`](../.github/ci-scripts/Get-VersionBump.ps1)):

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
`breaking:` prefix. See [Architecture.md](Architecture.md) §8.2 for the
full lifecycle.

A new PowerShell Gallery version is published **only** when a change affects the
published module bundle (`src/DLLPickle/**` or the bundled package set). CI-,
docs-, policy-, and tooling-only changes do not trigger a release. See
[CHANGELOG.md](../CHANGELOG.md) for the released history.

## Upstream Compatibility Automation

Dependabot tracks NuGet package releases, but DLLPickle also tracks the DLLs
bundled by upstream PowerShell modules. The scheduled **Upstream Compatibility**
workflow uses `build/dependency-policy.json` and tools under `tools/` to
inventory the newest compatible PSGallery release independently in each exact
PowerShell profile. It records the umbrella and constituent module, selected
asset path, hash, ALC, OS, architecture, import order, and deterministic probe.
The generated status is [Compatibility Evidence](generated/Compatibility-Evidence.md).

Monitored modules:

- `Microsoft.Graph.Authentication`
- `ExchangeOnlineManagement`
- `Az.Storage`
- `Az.Accounts`
- `MicrosoftTeams`
- `Az.Resources`

`Az.Resources` is monitored explicitly because it is the observed collision
source for the #193 `Microsoft.Extensions.*` transitive-assembly conflict.

The workflow is fail-closed: it only opens a candidate PR after inventory,
candidate generation, restore, build, and issue reproduction tests pass.

## NuGet Package Dependencies

Version strategy in `DLLPickle.csproj` is **major-locked floating** (`N.*`); the
lock file pins the concrete resolved version for all three TFMs. Common versions
are preserved across TFMs unless profile evidence requires a reviewed conditional
pin.

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
- `Azure.Core` is intentionally **not** preloaded on any supported ALC-capable
  profile. Az.Accounts 5.x isolates its Azure SDK stack in a private
  `AssemblyLoadContext`; preloading `Azure.Core` into the default load context
  splits the identity of `Azure.Core.TokenRequestContext` across load contexts
  and breaks `Connect-AzAccount` with a `MissingMethodException` on
  `InteractiveBrowserCredential.AuthenticateAsync`. Graph, Exchange, and Teams
  resolve a compatible `Azure.Core` themselves, so the preload is
  unnecessary. `Azure.Core` remains report-only in policy for monitoring. The
  original net48-only `Azure.Core` preload (#183) does not apply to these profiles.
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
- A new conditional per-TFM package pin or preload/block classification change
- A material breach of `build/artifact-size-baseline.json`

## References

- [Dependabot Configuration](/.github/dependabot.yml)
- [Auto-Approve Workflow](/.github/workflows/Dependabot-Auto-Approve.yml)
- [Dependency Review Workflow](/.github/workflows/Dependency-Review.yml)
- [Package Validation Workflow](/.github/workflows/Validate-Packages.yml)
- [CODEOWNERS](/.github/CODEOWNERS)
- [Security Policy](/SECURITY.md)
- [Contributing Guide](/.github/CONTRIBUTING.md)
