# Quick Reference: Dependency Automation

## Daily Workflow

```
┌─────────────────────┐
│  2:00 AM UTC Daily  │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Check NuGet.org API │
│  for New Versions   │
└──────────┬──────────┘
           │
           ▼
      ┌─────────┐
      │Updates? │
      └────┬────┘
           │
     ┌─────┴─────┐
     │           │
    Yes         No
     │           │
     ▼           ▼
┌─────────┐  ┌──────┐
│Download │  │ Exit │
│Packages │  └──────┘
└────┬────┘
     │
     ▼
┌─────────────┐
│ Update JSON │
│ & Copy DLLs │
└──────┬──────┘
       │
       ▼
┌────────────┐
│ Create PR  │
└──────┬─────┘
       │
       ▼
┌──────────────┐
│Security Scans│
└──────┬───────┘
       │
       ▼
   ┌────────┐
   │Checks? │
   └───┬────┘
       │
  ┌────┴────┐
  │         │
 Pass      Fail
  │         │
  ▼         ▼
┌──────┐ ┌────────┐
│Merge │ │ Manual │
│ PR   │ │ Review │
└──┬───┘ └────────┘
   │
   ▼
┌────────────┐
│   Release  │
│   Publish  │
└────────────┘
```

## Key Files

| File | Purpose |
|------|---------|
| `src/DLLPickle/Lib/Packages.json` | Tracked packages and versions |
| `.github/workflows/1 - Update Dependencies.yml` | Daily automation workflow |
| `.github/scripts/Get-NuGetLatestVersion.ps1` | Check for updates |
| `.github/scripts/Update-NuGetPackages.ps1` | Download and extract |

## Quick Commands

### Check for Updates
```powershell
$JsonPath = "./src/DLLPickle/Lib/Packages.json"
$Packages = (Get-Content $JsonPath | ConvertFrom-Json).packages

foreach ($pkg in $Packages) {
    & .\.github\scripts\Get-NuGetLatestVersion.ps1 `
        -PackageName $pkg.name `
        -CheckVersion $pkg.version
}
```

### Manual Update
```powershell
& .\.github\scripts\Update-NuGetPackages.ps1 `
    -PackageTrackingPath "./src/DLLPickle/Lib/Packages.json" `
    -DestinationPath "./src/DLLPickle/Lib"
```

### Trigger Workflow
```bash
gh workflow run "1 - Update Dependencies.yml"
```

## Package Entry Format

```json
{
  "name": "Package.Name",
  "description": "Brief description",
  "version": "1.0.0",
  "projectUrl": "https://www.nuget.org/packages/Package.Name",
  "autoImport": "true",
  "knownDependents": [
    "Module1",
    "Module2"
  ]
}
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| No PR created | Check workflow logs; verify updates available |
| Download failed | Check framework compatibility; retry |
| Checks failed | Review logs; test locally |
| Auto-merge stuck | Manually enable: `gh pr merge <PR> --auto --squash` |

## Security Features

✅ Harden Runner - Audits network calls  
✅ CodeQL - Security scanning  
✅ Dependency Review - CVE checks  
✅ Minimal Permissions - Principle of least privilege  
✅ Fork Protection - Only runs on main repo  

## More Information

📘 [Full Documentation](./DEPENDENCY_AUTOMATION.md)  
🔧 [Workflow Design](./WorkflowDesign.md)  
📦 [Contributing Guide](../.github/CONTRIBUTING.md)  
