# External Dependencies

This document tracks the external NuGet packages used by DLLPickle and their update policies.

## Purpose

DLLPickle deliberately maintains **current versions** of Microsoft authentication and identity libraries to resolve DLL version conflicts in PowerShell. This is a core feature, not a bug - we want the newest compatible versions loaded first.

For usage and command guidance, see [README.md](README.md) and
[docs/index.md](docs/index.md).

## Dependency Management Strategy

| Update Type | Policy | Automation |
| ------------- | -------- | ------------ |
| **Patch** (x.y.Z) | Auto-merge | ✅ Dependabot + Auto-approve workflow |
| **Minor** (x.Y.z) | Auto-merge | ✅ Dependabot + Auto-approve workflow |
| **Major** (X.y.z) | Manual review | ⚠️ Requires explicit approval |
| **Upstream PowerShell module drift** | Candidate PR or issue | ✅ Upstream Compatibility workflow |

### Upstream Compatibility Automation

Dependabot watches NuGet package releases, but DLLPickle also needs to track the
DLLs bundled by upstream PowerShell modules. The scheduled
**Upstream Compatibility** workflow uses `build/dependency-policy.json` and the
PowerShell tools in `tools/` to monitor the latest PSGallery releases of:

- `Microsoft.Graph.Authentication`
- `ExchangeOnlineManagement`
- `Az.Storage`
- `Az.Accounts`
- `MicrosoftTeams`

The workflow downloads those modules into an artifact cache, inventories their
bundled DLL assembly identities, compares them with DLLPickle's policy, and
generates a candidate dependency-pin update when a safe exact pin can be
derived. Candidate updates must still pass restore, build, and issue
reproduction tests before the workflow opens a PR.

This automation is intentionally fail-closed. It can propose a new net48
`Azure.Core` exact pin when Graph or Teams starts shipping a newer compatible
assembly, but it does not silently publish changed preload behavior. Blocked
families such as OData are reported as compatibility findings instead of being
added to the default preload set.

## NuGet Package Dependencies

### Microsoft Identity & Authentication Stack

| Package | Current Version | Purpose | Owner | Notes |
| --------- | ---------------- | --------- | ------- | ------- |
| **Azure.Core** | 1.55.0 | Azure SDK credential abstractions used by Microsoft.Graph.Authentication | @SamErde | net48 exact pin - tracks the maintained Azure.Core preload line used to avoid Windows PowerShell type identity conflicts |
| **Microsoft.Identity.Client** | 4.83.1 | Microsoft Authentication Library (MSAL) - Core authentication | @SamErde | Exact pin - matches the highest MSAL identity currently shipped by the supported base profile modules|
| **Microsoft.Identity.Client.Broker** | 4.83.1 | Broker support for MSAL authentication flows | @SamErde | Exact pin - kept aligned with MSAL to prevent broker extension missing-method failures|
| **Microsoft.Identity.Client.Extensions.Msal** | 4.83.1 | MSAL token cache helper used by Az and Graph authentication flows | @SamErde | Exact pin - prevents cache helper missing-method failures after mixed module imports |
| **Microsoft.Identity.Client.NativeInterop** | 0.20.4 | Native interop support for broker/native MSAL flows | @SamErde | Exact pin - packaged with native runtime files for broker/WAM scenarios |
| **Microsoft.IdentityModel.Abstractions** | 8.* | Identity model abstractions | @SamErde | Transitive - supports JWT/token handling |
| **Microsoft.IdentityModel.Logging** | 8.* | Identity diagnostics and logging | @SamErde | Transitive - logging infrastructure |
| **Microsoft.IdentityModel.JsonWebTokens** | 8.* | JWT token handling | @SamErde | Transitive - JWT creation/validation |
| **Microsoft.IdentityModel.Tokens** | 8.* | Security token handling | @SamErde | Transitive - token validation/processing |
| **System.IdentityModel.Tokens.Jwt** | 8.* | JWT token handlers | @SamErde | Transitive - JWT implementation |

### Version Strategy Rationale

#### Wildcard Minor Versions (0.*, 4.*, 8.*)

- **Why**: We use wildcard versioning (`0.*`, `4.*`, `8.*`) to automatically pick up the latest minor/patch releases within each major version
- **Benefit**: Ensures we're always loading the newest compatible version, which is the core purpose of DLLPickle
- **Risk Mitigation**:
  - Major version updates require manual review
  - `packages.lock.json` provides reproducible builds
  - Dependency Review workflow scans for vulnerabilities
  - Build validation runs on all updates

#### Exact Compatibility Pins

- **Azure.Core 1.55.0** is pinned for the net48 target with NuGet exact-version
  syntax (`[1.55.0]`) to keep the Windows PowerShell preload line explicit and
  reviewable. Microsoft.Graph.Authentication 2.36.1 ships Azure.Core 1.51.1,
  and Windows PowerShell can load incompatible strong-named Azure.Core copies
  side-by-side, which reintroduces the `UserProvidedTokenCredential.GetTokenAsync`
  type identity failure seen in issue #156.
- Azure.Core is intentionally not packaged for the net8.0 target because the
  current Azure.Core dependency graph includes .NET 10 transitive
  assemblies that are not safe to preload across all supported PowerShell 7
  environments. The #156 import-order failure has only been reproduced in
  Windows PowerShell 5.1.
- Exact pins should be reviewed whenever the affected upstream module updates
  its bundled assembly version. Do not convert an exact pin to a wildcard
  unless the issue repro tests and real-module probes show that both Windows
  PowerShell 5.1 and PowerShell 7+ remain compatible.
- The Upstream Compatibility workflow keeps this review path maintainable by
   detecting Graph and Teams `Azure.Core` drift, generating a candidate exact pin,
   regenerating `packages.lock.json`, and validating the issue repro suite before
   opening a PR.
- **Microsoft.Identity.Client 4.83.1**, **Microsoft.Identity.Client.Broker
  4.83.1**, and **Microsoft.Identity.Client.Extensions.Msal 4.83.1** are exact
  pins because the supported base profile mixes Az.Accounts,
  Microsoft.Graph.Authentication, MicrosoftTeams, and ExchangeOnlineManagement.
  Testing showed that a lower cache-helper or broker assembly can produce
  missing-method failures after those modules are imported in one process.
- **Microsoft.Identity.Client.NativeInterop 0.20.4** is exact-pinned and its
  native runtime files are packaged under `bin/<tfm>/runtimes/<rid>/native`.
  `Import-DPLibrary` adds the current process runtime folder to `PATH` before
  loading managed assemblies and does not call `Add-Type` for native DLLs.
- The Upstream Compatibility workflow can now propose candidate exact-pin
  updates for Azure.Core and the MSAL managed family when monitored PSGallery
  modules start bundling newer compatible assemblies. Native interop updates
  still require manual review because the NuGet package and native runtime file
  versions do not always map directly to the assembly versions bundled by
  upstream modules.

#### Lock File Workflow (Required)

- Build restore runs in `--locked-mode` in both local and CI environments.
- When package references change in `src/DLLPickle.Build/DLLPickle.csproj`, refresh the lock file before committing:

```powershell
dotnet restore src/DLLPickle.Build/DLLPickle.csproj --force-evaluate
```

- Commit the updated `src/DLLPickle.Build/packages.lock.json` in the same change as the package reference update.
- Validate the lock file with:

```powershell
dotnet restore src/DLLPickle.Build/DLLPickle.csproj --locked-mode
```

#### Multi-Targeting (net48 + net8.0)

- **net8.0**: Full compatibility with all modern package features
- **net48**: Windows PowerShell 5.1 support with known limitations (see Known Issues)

## Known Issues & Compatibility

### .NET Framework 4.8 Limitations

Some transitive dependencies contain types that depend on APIs not available in .NET Framework 4.8, causing `ReflectionTypeLoadException` in Windows PowerShell. This affects:

- `System.Diagnostics.DiagnosticSource` 6.x
- Newer versions of `Microsoft.Identity.Client` 4.x

**Root Cause**:

- .NET Framework 4.8 assembly probing can fail on first pass when transitive dependencies are not loaded in the expected order.
- Identity stack assemblies can reference lower-level system assemblies that are not guaranteed to be resolved first in arbitrary file enumeration order.

**Implemented Workaround Strategy**:

- net48 build now copies lock file assemblies locally to improve dependency presence in the module `bin/net48` path.
- `Import-DPLibrary` builds a local assembly dependency graph and applies dependency-first DLL ordering before import attempts.
- If graph nodes are unresolved (for example due to metadata gaps), `Import-DPLibrary` appends the remaining assemblies deterministically in alphabetical order.
- `Import-DPLibrary` registers a scoped assembly resolution fallback so .NET Framework can resolve local same-name dependencies from the module bin folder during import.
- Existing retry logic remains in place as a safety net for unresolved transitive dependencies.

**Operational Guidance**:

- Use `Import-DPLibrary -SuppressLogo -ShowLoaderExceptions -Verbose` for detailed diagnostics.
- Use `Import-DPBaseProfile` for the validated base profile import order:
  ExchangeOnlineManagement, MicrosoftTeams, Microsoft.Graph.Authentication, and
  Az.Accounts.
- For Windows PowerShell 5.1, treat Az.Accounts authentication after Graph or
  Exchange imports as a known upstream loader limitation. Use PowerShell 7+ or
  process isolation when `Connect-AzAccount` must run in the same workflow.
- Use `Set-DPConfig` with `SkipLibraries` only for environment-specific optional assembly incompatibilities.

**Resolution**: All assemblies generally load successfully in PowerShell Core (net8.0), and net48 reliability is improved by packaging and graph-based dependency ordering with deterministic fallback.

### OData assembly conflict in Az.Storage + ExchangeOnlineManagement

Az.Storage 9.6.0 bundles and imports `Microsoft.OData.Core` 7.6.4, while
ExchangeOnlineManagement 3.9.2 can lazily request `Microsoft.OData.Core`
7.22.0 when running `Get-EXO*` cmdlets. Testing showed that preloading OData
7.22.0 from DLLPickle is not a safe default fix: Az.Storage then fails during
module import because its 7.6.4 assembly load collides with the already-loaded
7.22.0 assembly.

DLLPickle therefore does not package the OData family by default. This keeps
Az.Storage import compatibility intact and leaves the #174 scenario covered by
the issue repro tests as a known in-process CLR load-context limitation. Run
ExchangeOnlineManagement and Az.Storage workloads in separate PowerShell
processes when both modules require incompatible OData versions.

## Supply Chain Security

### Protections in Place

1. ✅ **Dependabot** - Monitors for updates and security vulnerabilities
2. ✅ **Dependency Review** - Scans PRs for vulnerable packages (fails on moderate+ severity)
3. ✅ **OSSF Scorecard** - Supply chain security monitoring
4. ✅ **Package Lock** - `packages.lock.json` ensures reproducible builds
5. ✅ **Automated Testing** - All updates validated by build + test workflows
6. ✅ **CODEOWNERS** - Dependency files require explicit review
7. ✅ **Upstream Compatibility** - Scheduled PSGallery module inventory and candidate PR generation for DLL preload policy drift

### Manual Review Required For

- ⚠️ Major version updates (breaking changes possible)
- ⚠️ New package additions
- ⚠️ Changes to version strategies (wildcard patterns)

## Update Process

### Automatic (Patch/Minor)

1. Dependabot creates PR
2. Dependency Review scans for vulnerabilities
3. Build validation runs
4. Auto-approve workflow approves and enables auto-merge
5. PR merges automatically after all checks pass

### Manual (Major Versions)

1. Dependabot creates PR with "major version update" label
2. GitHub comment posted explaining manual review needed
3. Maintainer reviews:
   - Changelog for breaking changes
   - Compatibility with target frameworks (net48, net8.0)
   - Impact on dependent PowerShell modules
4. Local testing
5. Manual approval and merge

## Testing New Dependencies

Before adding or upgrading dependencies:

```powershell
# Build the project
Invoke-Build -Task Build

# Test in both PowerShell editions
pwsh -NoProfile -Command "Import-Module ./module/DLLPickle; Import-DPLibrary; Get-Module"
powershell -NoProfile -Command "Import-Module ./module/DLLPickle; Import-DPLibrary; Get-Module"

# Test with common Microsoft modules
Import-Module Microsoft.Graph
Import-Module ExchangeOnlineManagement
Connect-MgGraph -Scopes "User.Read"
```

## References

- [Dependabot Configuration](/.github/dependabot.yml)
- [Auto-Approve Workflow](/.github/workflows/Dependabot-Auto-Approve.yml)
- [Dependency Review Workflow](/.github/workflows/Dependency-Review.yml)
- [Package Validation Workflow](/.github/workflows/Validate-Packages.yml)
- [CODEOWNERS](/.github/CODEOWNERS)
- [Security Policy](/SECURITY.md)
- [Contributing Guide](/.github/CONTRIBUTING.md)
