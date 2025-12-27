# PowerShell Helper Scripts - Quick Reference

This directory contains reusable PowerShell scripts extracted from GitHub Actions workflows.

## Testing Scripts Locally

Each script returns a `PSCustomObject` with structured output, making them easy to test and debug locally.

### Example: Test Get-VersionBump

```powershell
# Navigate to your workspace root
cd C:\Users\SamErde\Code\Personal\DLLPickle

# Run the script and capture output
$result = & .\.github\scripts\Get-VersionBump.ps1

# Check if release is needed
if ($result.ShouldRelease) {
    Write-Host "New version: $($result.NewVersion)"
    Write-Host "Bump type: $($result.VersionBump)"
} else {
    Write-Host "No release needed"
}
```

### Example: Test Update-ModuleVersion

```powershell
$result = & .\.github\scripts\Update-ModuleVersion.ps1 `
  -ManifestPath "./src/DLLPickle/DLLPickle.psd1" `
  -NewVersion "1.5.0"

if ($result.Success) {
    Write-Host "Updated from $($result.OldVersion) to $($result.NewVersion)"
} else {
    Write-Error $result.ErrorMessage
}
```

### Example: Test Publish-ToGallery

```powershell
$result = & .\.github\scripts\Publish-ToGallery.ps1 `
  -ModuleDirectory "./src/DLLPickle" `
  -ApiKey $env:PSGALLERY_API_KEY

if ($result.Success) {
    Write-Host "Published to: $($result.GalleryUrl)"
}
```

### Example: Test Get-NuGetLatestVersion

```powershell
$result = & .\.github\scripts\Get-NuGetLatestVersion.ps1 `
  -PackageName "Microsoft.Identity.Client" `
  -CurrentVersion "4.48.0"

if ($result.UpdateAvailable) {
    Write-Host "Update available: $($result.UpdateMessage)"
}
```

### Example: Test Update-NuGetPackages

```powershell
$result = & .\.github\scripts\Update-NuGetPackages.ps1 `
  -PackageTrackingPath "./src/DLLPickle/Lib/Packages.json" `
  -DestinationPath "./src/DLLPickle/Lib"

Write-Host "Updated $($result.UpdatedCount) package(s)"
```

## Calling from Workflows

In GitHub Actions workflows, call scripts from the workflow directory context:

```yaml
- name: Determine version bump
  shell: pwsh
  run: |
    $result = & .\.github\scripts\Get-VersionBump.ps1
    "should_release=$($result.ShouldRelease)" >> $env:GITHUB_OUTPUT
    "new_version=$($result.NewVersion)" >> $env:GITHUB_OUTPUT
```

## Integration with CI/CD

These scripts are designed to be called in sequence:

```powershell
Get-VersionBump
    ↓ (if should_release)
Update-ModuleVersion
    ↓
Build & Test
    ↓
Create GitHub Release
    ↓
Publish-ToGallery
```

For dependencies:

```powershell
Get-NuGetLatestVersion (for each package)
    ↓ (if updates available)
Update-NuGetPackages
    ↓
Commit & Create PR
```

## Creating Tests with Pester

Example test structure for `Get-VersionBump.ps1`:

```powershell
# .github\scripts\Tests\Get-VersionBump.Tests.ps1

Describe "Get-VersionBump" {
    Context "No commits since last tag" {
        It "returns ShouldRelease = false" {
            # Mock git describe to return a tag
            # Mock git log to return empty
            
            $result = & .\.github\scripts\Get-VersionBump.ps1
            $result.ShouldRelease | Should -Be $false
        }
    }
    
    Context "Contains fix commits" {
        It "returns patch version bump" {
            # Setup test scenario
            # Run script
            # Assert $result.VersionBump -eq 'patch'
        }
    }
}
```

## Error Handling

All scripts include error handling and return a `Success` property. Always check this before using other properties:

```powershell
$result = & .\.github\scripts\Update-ModuleVersion.ps1 -ManifestPath $path -NewVersion $version

if (-not $result.Success) {
    Write-Error "Update failed: $($result.ErrorMessage)"
    exit 1
}

# Safe to use other properties
Write-Host "Updated to $($result.NewVersion)"
```

## Contributing

When adding new helper scripts:

1. **Follow naming convention:** `Verb-Noun.ps1` (e.g., `Get-Version.ps1`, `Update-Config.ps1`)
2. **Add full comment-based help** with `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.OUTPUTS`, `.EXAMPLE`
3. **Return PSCustomObject** with structured output, not Write-Host
4. **Handle errors gracefully** - catch exceptions and return error in result object
5. **Document integration points** - show how this script is called from workflows
6. **Add Pester tests** in `Tests/` subdirectory

## Troubleshooting

### Script not found error

- Ensure working directory is the repository root
- Use relative paths: `.\.github\scripts\Script.ps1`
- In workflows, paths are relative to repository root

### Output not being captured

- Scripts must return object or output to `$env:GITHUB_OUTPUT`
- Use `Write-Output` for the final result object
- Use `Write-Host` for logging only

### Git commands failing

- Ensure you're in the correct working directory
- Ensure git repository is initialized
- Some operations need `fetch-depth: 0` in checkout step

---

For detailed documentation, see `REFACTORING_SUMMARY.md`
