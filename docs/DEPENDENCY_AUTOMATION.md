---
title: Automated Dependency Management
description: Documentation for the automated NuGet package update system
---

# 📦 Automated Dependency Management

DLL Pickle uses a fully automated system to keep NuGet packages up to date. This document explains how the automation works and what contributors need to know.

## Overview

The project maintains a curated list of Microsoft Identity and authentication libraries in `src/DLLPickle/Lib/Packages.json`. An automated workflow checks for updates daily, downloads new versions, and creates pull requests with the changes.

## How It Works

### 1. Package Tracking

All tracked packages are defined in **`src/DLLPickle/Lib/Packages.json`**:

```json
{
  "packages": [
    {
      "name": "Microsoft.Identity.Client",
      "description": "Microsoft Authentication Library for .NET (MSAL.NET)",
      "version": "4.82.0",
      "projectUrl": "https://www.nuget.org/packages/Microsoft.Identity.Client",
      "autoImport": "true",
      "knownDependents": [
        "Az.Accounts",
        "ExchangeOnlineManagement",
        "Microsoft.Graph.Authentication"
      ]
    }
  ]
}
```

Each package entry includes:
- **name**: NuGet package identifier
- **description**: Human-readable description
- **version**: Currently packaged version
- **projectUrl**: Link to the NuGet package page
- **autoImport**: Whether to auto-import when module loads
- **knownDependents**: PowerShell modules that depend on this package

### 2. Daily Automated Checks

**Workflow**: `.github/workflows/1 - Update Dependencies.yml`

**Schedule**: Runs daily at 2:00 AM UTC (can also be triggered manually)

**Process**:

1. **Check for Updates**
   - Queries NuGet.org API for each package's latest version
   - Compares current version in `Packages.json` with latest available
   - Tracks which packages have updates available

2. **Download Updated Packages**
   - Downloads `.nupkg` files from NuGet.org
   - Extracts DLLs from appropriate framework directories:
     - `lib/netstandard2.0/` (preferred)
     - `lib/netstandard2.1/`
     - `lib/net6.0/`
     - `lib/net472/`
     - `runtimes/win/lib/netstandard2.0/`

3. **Update Repository**
   - Copies new DLLs to `src/DLLPickle/Lib/`
   - Updates version numbers in `Packages.json`
   - Creates/updates branch `chore/update-packages`

4. **Create Pull Request**
   - Opens a PR with the dependency updates
   - Includes a summary of all version changes
   - Adds labels: `dependencies`, `automated`

5. **Automated Review Process**
   - Security scanning (Harden Runner, CodeQL)
   - PR checks and validations
   - Auto-approval when all checks pass
   - Auto-merge enabled for seamless integration

### 3. Release Process

When the dependency update PR is merged to `main`, the **Release and Publish** workflow automatically:

1. Bumps the module version (patch increment)
2. Updates the module manifest (`DLLPickle.psd1`)
3. Creates a GitHub release with detailed notes
4. Publishes the updated module to PowerShell Gallery

## Scripts

The automation uses these PowerShell scripts located in `.github/scripts/`:

### Get-NuGetLatestVersion.ps1

Queries NuGet.org for the latest version of a package.

**Usage**:
```powershell
$result = & .\.github\scripts\Get-NuGetLatestVersion.ps1 `
    -PackageName "Microsoft.Identity.Client" `
    -CheckVersion "4.82.0"

if ($result.UpdateAvailable) {
    Write-Host "Update available: $($result.CheckVersion) → $($result.LatestVersion)"
}
```

**Returns**: PSCustomObject with properties:
- `PackageName`: Package identifier
- `CheckVersion`: Current version checked
- `LatestVersion`: Latest version on NuGet.org
- `UpdateAvailable`: Boolean indicating if update exists
- `UpdateMessage`: Human-readable summary

### Update-NuGetPackages.ps1

Downloads and extracts packages, updating both DLLs and `Packages.json`.

**Usage**:
```powershell
$result = & .\.github\scripts\Update-NuGetPackages.ps1 `
    -PackageTrackingPath "./src/DLLPickle/Lib/Packages.json" `
    -DestinationPath "./src/DLLPickle/Lib"

Write-Host "Updated: $($result.UpdatedCount), Failed: $($result.FailedCount)"
```

**Returns**: PSCustomObject with properties:
- `Success`: Overall success status
- `UpdatedCount`: Number of packages successfully updated
- `FailedCount`: Number of packages that failed
- `ChangedPackages`: Array of version change summaries
- `UpdateMessage`: Summary message

## For Contributors

### Adding a New Package

To add a new package to the automated tracking system:

1. **Edit `src/DLLPickle/Lib/Packages.json`**:
```json
{
  "name": "Your.Package.Name",
  "description": "Brief description",
  "version": "1.0.0",
  "projectUrl": "https://www.nuget.org/packages/Your.Package.Name",
  "autoImport": "true"
}
```

2. **Manually download the initial version**:
```powershell
# Run the update script to download and extract
& .\.github\scripts\Update-NuGetPackages.ps1 `
    -PackageTrackingPath "./src/DLLPickle/Lib/Packages.json" `
    -DestinationPath "./src/DLLPickle/Lib"
```

3. **Update module manifest** if needed:
   - Add to `RequiredAssemblies` in `src/DLLPickle/DLLPickle.psd1` if auto-loading is desired

4. **Create a PR** with your changes:
   - Include justification for the new package
   - Explain which modules benefit from this addition
   - Note any known compatibility considerations

### Removing a Package

To remove a package from tracking:

1. Remove the package entry from `Packages.json`
2. Delete the corresponding DLL file(s) from `src/DLLPickle/Lib/`
3. Update module manifest if the DLL was in `RequiredAssemblies`
4. Create a PR with clear rationale for removal

### Updating Package Metadata

The `Packages.json` file contains metadata beyond just versions:

- **description**: Keep descriptions clear and concise
- **projectUrl**: Verify links are current
- **autoImport**: Set to "false" if the DLL shouldn't auto-load
- **knownDependents**: Help users understand which modules benefit

Metadata updates don't require version changes but help with documentation.

## Manual Operations

### Manually Trigger Update Check

To manually trigger the dependency check workflow:

```bash
# Using GitHub CLI
gh workflow run "1 - Update Dependencies.yml"

# Or via GitHub UI
# Go to Actions → 📦 Update Dependencies → Run workflow
```

### Test the Update Process Locally

To test the update scripts without committing changes:

```powershell
# Check for available updates
$LibPath = "./src/DLLPickle/Lib"
$JsonPath = "$LibPath/Packages.json"
$PackageTracking = Get-Content $JsonPath | ConvertFrom-Json

foreach ($Package in $PackageTracking.packages) {
    $result = & .\.github\scripts\Get-NuGetLatestVersion.ps1 `
        -PackageName $Package.name `
        -CheckVersion $Package.version
    
    if ($result.UpdateAvailable) {
        Write-Host $result.UpdateMessage -ForegroundColor Yellow
    }
}
```

### Review an Update PR

When a dependency update PR is created:

1. **Review the PR description** - Check which packages are being updated
2. **Check the DLL sizes** - Significant size changes may indicate breaking changes
3. **Review the changelog** - Visit NuGet.org for each updated package
4. **Verify compatibility** - Ensure new versions maintain backward compatibility
5. **Test locally if concerned** - Download the branch and test critical workflows

The automated checks provide baseline validation, but human review is valuable for:
- Major version updates
- New dependencies introduced by packages
- Significant API changes noted in changelogs

## Troubleshooting

### Update PR Fails to Create

**Symptoms**: Workflow runs but no PR appears

**Possible Causes**:
- No updates were available
- All packages are already up to date
- GitHub token lacks permissions

**Resolution**:
1. Check workflow logs for details
2. Verify `PAT_CREATEPR` secret has `repo` and `pull_request` permissions
3. Ensure packages.json is properly formatted

### Download Fails for a Package

**Symptoms**: Some packages update, others show as "Failed"

**Possible Causes**:
- Package not available for target frameworks
- Network connectivity issues
- NuGet.org API rate limiting

**Resolution**:
1. Check workflow logs for specific error messages
2. Verify package exists on NuGet.org
3. Check if package supports required frameworks (netstandard2.0, etc.)
4. Retry the workflow after a short delay

### PR Created but Checks Fail

**Symptoms**: PR is created but CI checks fail

**Possible Causes**:
- Incompatible DLL versions
- Breaking API changes in updated packages
- Test failures due to behavior changes

**Resolution**:
1. Review check logs to identify specific failures
2. Consider pinning to a specific version if latest breaks compatibility
3. Update module code to accommodate breaking changes
4. Document any workarounds needed

### Auto-merge Doesn't Trigger

**Symptoms**: PR approved but doesn't auto-merge

**Possible Causes**:
- Required checks haven't completed
- Branch protection rules not satisfied
- Auto-merge not enabled on the PR

**Resolution**:
1. Wait for all checks to complete
2. Verify branch protection settings
3. Manually enable auto-merge if needed: `gh pr merge <PR> --auto --squash`

## Security Considerations

The automation includes several security measures:

1. **Harden Runner**: Audits all network egress calls
2. **CodeQL Analysis**: Scans for security vulnerabilities
3. **Dependency Review**: Checks for known vulnerabilities in dependencies
4. **Restricted Permissions**: Workflows use minimal required permissions
5. **Fork Safety**: Automation only runs on the main repository, not forks

### Reviewing Security Alerts

If the automated PR includes security fixes:

1. Check the Dependabot alerts or security advisories
2. Review CVE details if applicable
3. Assess impact on DLL Pickle's usage patterns
4. Prioritize merging security updates quickly
5. Consider creating a hotfix release if critical

## Monitoring

### Workflow Status

Check the status of automated workflows:

```bash
# View recent workflow runs
gh run list --workflow="1 - Update Dependencies.yml" --limit 5

# View details of a specific run
gh run view <run-id>
```

### Notification Settings

To receive notifications about workflow status:

1. Go to GitHub Settings → Notifications
2. Enable "Actions" notifications
3. Choose email or web notification preferences

### Package Freshness

To check how current the packages are:

```powershell
# Compare current versions to latest
$JsonPath = "./src/DLLPickle/Lib/Packages.json"
$PackageTracking = Get-Content $JsonPath | ConvertFrom-Json

foreach ($Package in $PackageTracking.packages) {
    $result = & .\.github\scripts\Get-NuGetLatestVersion.ps1 `
        -PackageName $Package.name `
        -CheckVersion $Package.version
    
    $status = if ($result.UpdateAvailable) { "⚠️ Update available" } else { "✓ Current" }
    Write-Host "$($Package.name): $status ($($Package.version))"
}
```

## Best Practices

### For Maintainers

1. **Monitor PRs regularly**: Review automated PRs within 24-48 hours
2. **Test major updates**: For major version bumps, test locally before merging
3. **Keep secrets current**: Rotate `PAT_CREATEPR` and `PSGALLERY_API_KEY` periodically
4. **Review logs**: Periodically check workflow logs for errors or warnings
5. **Update documentation**: Keep this document current as the process evolves

### For Contributors

1. **Don't manually update versions**: Let automation handle version updates
2. **Follow conventional commits**: Use proper commit message format
3. **Test with latest**: Keep your local environment updated to test against current packages
4. **Report issues**: File issues for packages that consistently fail to update
5. **Suggest improvements**: Share ideas for enhancing the automation

## Additional Resources

- [GitHub Actions Workflow File](/.github/workflows/1%20-%20Update%20Dependencies.yml)
- [Update Scripts](/.github/scripts/)
- [Packages.json](../src/DLLPickle/Lib/Packages.json)
- [Workflow Design Documentation](./WorkflowDesign.md)
- [Release Workflow Documentation](./RELEASE_WORKFLOW.md)
- [NuGet API Documentation](https://docs.microsoft.com/en-us/nuget/api/overview)

## Questions or Issues?

If you have questions about the dependency automation:

1. Check this documentation first
2. Review existing [GitHub Issues](https://github.com/SamErde/DLLPickle/issues)
3. Check [workflow run logs](https://github.com/SamErde/DLLPickle/actions/workflows/1%20-%20Update%20Dependencies.yml)
4. Open a new issue with the `question` or `workflow` label

For workflow failures or bugs, include:
- Link to the failed workflow run
- Relevant log excerpts
- Steps to reproduce (if applicable)
- Expected vs actual behavior
