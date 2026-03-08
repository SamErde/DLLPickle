# External Dependencies

This document tracks the external NuGet packages used by DLLPickle and their update policies.

## Purpose

DLLPickle deliberately maintains **current versions** of Microsoft authentication and identity libraries to resolve DLL version conflicts in PowerShell. This is a core feature, not a bug - we want the newest compatible versions loaded first.

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
| **Microsoft.IdentityModel.Abstractions** | 8.* | Identity model abstractions | @SamErde | Transitive - supports JWT/token handling |
| **Microsoft.IdentityModel.Logging** | 8.* | Identity diagnostics and logging | @SamErde | Transitive - logging infrastructure |
| **Microsoft.IdentityModel.JsonWebTokens** | 8.* | JWT token handling | @SamErde | Transitive - JWT creation/validation |
| **Microsoft.IdentityModel.Tokens** | 8.* | Security token handling | @SamErde | Transitive - token validation/processing |
| **System.IdentityModel.Tokens.Jwt** | 8.* | JWT token handlers | @SamErde | Transitive - JWT implementation |

### Version Strategy Rationale

#### Wildcard Minor Versions (4.*, 8.*)

- **Why**: We use wildcard versioning (`4.*`, `8.*`) to automatically pick up the latest minor/patch releases within each major version
- **Benefit**: Ensures we're always loading the newest compatible version, which is the core purpose of DLLPickle
- **Risk Mitigation**:
  - Major version updates require manual review
  - `packages.lock.json` provides reproducible builds
  - Dependency Review workflow scans for vulnerabilities
  - Build validation runs on all updates

#### Multi-Targeting (net48 + net8.0)

- **net8.0**: Full compatibility with all modern package features
- **net48**: Windows PowerShell 5.1 support with known limitations (see Known Issues)

## Known Issues & Compatibility

### .NET Framework 4.8 Limitations

Some transitive dependencies contain types that depend on APIs not available in .NET Framework 4.8, causing `ReflectionTypeLoadException` in Windows PowerShell. This affects:

- `System.Diagnostics.DiagnosticSource` 6.x
- Newer versions of `Microsoft.Identity.Client` 4.x

**Impact**: Assemblies fail to load in Windows PowerShell but don't impact core MSAL functionality.

**Workaround**: Use `Import-DPLibrary -ShowLoaderExceptions` for detailed diagnostics when loader warnings occur.

**Resolution**: All assemblies load successfully in PowerShell Core (net8.0).

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
