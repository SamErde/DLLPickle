# MSAL Package Tracking Migration

## Overview
The MSAL package tracking system has been migrated from individual text files to a single JSON file for better maintainability and easier version management.

## Changes Made

### Before (Old System)
- 5 separate version files:
  - `MSAL_VERSION.txt`
  - `MSAL_Extensions_VERSION.txt`
  - `MSAL_NativeInterop_VERSION.txt`
  - `MSAL_Broker_VERSION.txt`
  - `MSAL_Abstractions_VERSION.txt`
- Package list duplicated in workflow file
- Manual mapping of package names to version files

### After (New System)
- Single JSON file: `Packages.json`
- Centralized package configuration
- No code duplication
- Easy to add new packages

## JSON File Structure

```json
{
  "packages": [
    {
      "name": "Microsoft.Identity.Client",
      "version": "4.77.1"
    },
    {
      "name": "Microsoft.Identity.Client.Extensions.Msal",
      "version": "4.78.0"
    },
    ...
  ]
}
```

## Location
`src/DLLPickle/Assembly/Packages.json`

## Workflow Changes
The `.github/workflows/Update MSAL Packages.yml` workflow now:
1. Reads package list from JSON file
2. Checks NuGet for updates
3. Downloads and extracts packages if updates are available
4. Updates the JSON file with new versions
5. Commits both the DLLs and the updated JSON file

## Adding New Packages
To add a new MSAL package to track:
1. Add a new entry to the `packages` array in `Packages.json`:
   ```json
   {
     "name": "New.Package.Name",
     "version": "1.0.0"
   }
   ```
2. The workflow will automatically detect and process it on the next run

## Testing
Two test scripts are provided:
- `Tests/Test-MSALPackageTracking.ps1` - Validates JSON structure and NuGet API
- `Tests/Test-WorkflowSimulation.ps1` - Simulates the complete workflow

Run tests with:
```powershell
pwsh -File Tests/Test-MSALPackageTracking.ps1
pwsh -File Tests/Test-WorkflowSimulation.ps1
```

## Migration Notes
- Old `.txt` files have been removed
- Versions from old files were migrated to JSON
- No other code referenced the old files
- Workflow now uses JSON exclusively
