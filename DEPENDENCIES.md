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

## NuGet Package Dependencies

### Microsoft Identity & Authentication Stack

| Package | Current Version | Purpose | Owner | Notes |
| --------- | ---------------- | --------- | ------- | ------- |
| **Microsoft.Identity.Client** | 4.* | Microsoft Authentication Library (MSAL) - Core authentication | @SamErde | Primary dependency - enables auth for MS services |
| **Microsoft.Identity.Client.NativeInterop** | 0.* | Native interop support used by MSAL broker flows | @SamErde | Package major version is currently 0.x |
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
- Use `Set-DPConfig` with `SkipLibraries` only for environment-specific optional assembly incompatibilities.

**Resolution**: All assemblies generally load successfully in PowerShell Core (net8.0), and net48 reliability is improved by packaging and graph-based dependency ordering with deterministic fallback.

## Supply Chain Security

### Protections in Place

1. ✅ **Dependabot** - Monitors for updates and security vulnerabilities
2. ✅ **Dependency Review** - Scans PRs for vulnerable packages (fails on moderate+ severity)
3. ✅ **OSSF Scorecard** - Supply chain security monitoring
4. ✅ **Package Lock** - `packages.lock.json` ensures reproducible builds
5. ✅ **Automated Testing** - All updates validated by build + test workflows
6. ✅ **CODEOWNERS** - Dependency files require explicit review

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
