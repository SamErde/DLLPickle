# PowerShell Script Extraction Summary

## Overview

Successfully extracted inline PowerShell scripts from GitHub Actions workflows into reusable, testable, and maintainable helper scripts located in `.github/scripts/`.

## Scripts Created

### 1. `Get-VersionBump.ps1`

**Purpose:** Analyzes conventional commits since the last tag and determines semantic version bumping.

**Source Code Origin:** `3 - Create Release.yml` (Analyze commits and determine version step)

**Inputs:**

- `CurrentVersion` (optional): Version string to analyze against; defaults to reading from manifest
- `ManifestPath` (optional): Path to module manifest; defaults to `./src/DLLPickle/DLLPickle.psd1`

**Outputs:**

```powershell
PSCustomObject {
  ShouldRelease: Boolean
  VersionBump: String ('major', 'minor', 'patch', 'none')
  NewVersion: Version
  CommitsSinceLastTag: String[]
}
```

**Key Features:**

- Parses conventional commit messages (feat, fix, BREAKING CHANGE, etc.)
- Determines correct semantic version bump
- Returns structured output for workflow integration

---

### 2. `Update-ModuleVersion.ps1`

**Purpose:** Updates the PowerShell module manifest with a new version number and validates the change.

**Source Code Origin:** `3 - Create Release.yml` (Update module manifest step)

**Inputs:**

- `ManifestPath` (required): Path to the .psd1 manifest file
- `NewVersion` (required): New version string to set

**Outputs:**

```powershell
PSCustomObject {
  Success: Boolean
  OldVersion: String
  NewVersion: String
  ManifestPath: String
  ErrorMessage: String (if failed)
}
```

**Key Features:**

- Uses `Update-ModuleManifest` cmdlet for safe updates
- Validates version was actually updated in file
- Returns old and new versions for audit trail

---

### 3. `Publish-ToGallery.ps1`

**Purpose:** Publishes a PowerShell module to PowerShell Gallery with automatic retry logic and verification.

**Source Code Origin:** `3 - Create Release.yml` and `4 - Publish Module.yml` (Publish to PowerShell Gallery steps)

**Inputs:**

- `ModuleDirectory` (required): Path to module directory to publish
- `ApiKey` (required): PowerShell Gallery API key
- `MaxRetries` (optional): Max retry attempts; defaults to 3
- `RepositoryName` (optional): Repository name; defaults to 'PSGallery'

**Outputs:**

```powershell
PSCustomObject {
  Success: Boolean
  ModuleName: String
  Version: String
  GalleryUrl: String
  AttemptCount: Int
  Message: String
  ErrorMessage: String (if failed)
}
```

**Key Features:**

- Automatic retry logic with exponential backoff
- Validates module manifest to extract name/version
- Waits for gallery indexing before verification
- Provides direct link to published module

---

### 4. `Get-NuGetLatestVersion.ps1`

**Purpose:** Queries NuGet.org API for the latest version of a package and determines if update is available.

**Source Code Origin:** `1 - Update Dependencies.yml` (Check for package updates step)

**Inputs:**

- `PackageName` (required): Name of the NuGet package
- `CurrentVersion` (required): Current version for comparison

**Outputs:**

```powershell
PSCustomObject {
  PackageName: String
  CurrentVersion: String
  LatestVersion: String
  UpdateAvailable: Boolean
  UpdateMessage: String
  ErrorMessage: String (if failed)
}
```

**Key Features:**

- Calls official NuGet v3 API
- Performs semantic version comparison
- Provides human-readable update messages
- Graceful error handling for unavailable packages

---

### 5. `Update-NuGetPackages.ps1`

**Purpose:** Downloads, extracts, and installs NuGet packages, updating the package tracking JSON file.

**Source Code Origin:** `1 - Update Dependencies.yml` (Download and extract packages step)

**Inputs:**

- `PackageTrackingPath` (required): Path to Packages.json file
- `DestinationPath` (required): Directory where DLLs should be copied

**Outputs:**

```powershell
PSCustomObject {
  Success: Boolean
  UpdatedCount: Int
  FailedCount: Int
  ChangedPackages: String[]
  UpdateMessage: String
}
```

**Key Features:**

- Downloads packages from NuGet.org
- Extracts from multiple framework targets (.NET Standard, .NET 6, .NET 4.7.2, etc.)
- Updates Packages.json tracking file
- Cleans up temporary files automatically

---

## Workflows Updated

### 1. `3 - Create Release.yml`

**Changes:**

- Replaced 79-line "Analyze commits and determine version" step with 5-line call to `Get-VersionBump.ps1`
- Replaced 11-line "Update module manifest" step with 7-line call to `Update-ModuleVersion.ps1`
- Replaced 45-line "Publish to PowerShell Gallery" step with 11-line call to `Publish-ToGallery.ps1`

**Net Reduction:** ~125 lines of inline PowerShell removed

### 2. `1 - Update Dependencies.yml`

**Changes:**

- Replaced 51-line "Check for package updates" step with 24-line call to `Get-NuGetLatestVersion.ps1`
- Replaced 114-line "Download and extract packages" step with 14-line call to `Update-NuGetPackages.ps1`

**Net Reduction:** ~127 lines of inline PowerShell removed

---

## Benefits

### ✅ Code Reusability

- Scripts can be called from multiple workflows
- Single source of truth for common operations
- Reduces duplication across workflows

### ✅ Testability

- Scripts can be tested independently with Pester
- Easier to validate logic before workflow execution
- Supports unit testing workflow logic

### ✅ Maintainability

- Bug fixes happen in one place
- Easier to understand and modify complex logic
- Clear input/output contracts via parameters and objects

### ✅ Readability

- Workflows are now 60%+ shorter
- Intent is clearer with descriptive script names
- Comments in scripts are more detailed than workflow comments

### ✅ Version Control

- Scripts appear in git history with full context
- Easier to track changes to specific functions
- Better diff visibility for code reviews

---

## Next Steps

1. **Test extracted scripts** with sample inputs
2. **Create Pester tests** for critical scripts
3. **Consolidate release workflows** into single `release.yml`
4. **Add GitHub release helper script** for git tag and release note creation
5. **Implement approval gates** for dependency release pathway

---

## File Structure

```
.github/
├── scripts/
│   ├── Get-VersionBump.ps1              (79 lines)
│   ├── Get-NuGetLatestVersion.ps1       (82 lines)
│   ├── Update-ModuleVersion.ps1         (62 lines)
│   ├── Update-NuGetPackages.ps1        (155 lines)
│   └── Publish-ToGallery.ps1           (138 lines)
└── workflows/
    ├── 1 - Update Dependencies.yml      (REFACTORED)
    ├── 3 - Create Release.yml           (REFACTORED)
    ├── 2 - Build Module - Windows.yml   (unchanged)
    ├── 4 - Publish Module.yml           (unchanged)
    └── ...
```
