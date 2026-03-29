<!-- markdownlint-disable MD022 -->
<!-- markdownlint-disable MD025 -->

# DLLPickle

## about_DLLPickle

```text
ABOUT TOPIC NOTE:
The first header of the about topic should be the topic name.
The second header contains the lookup name used by the help system.

IE:
# Some Help Topic Name

## SomeHelpTopicFileName

This will be transformed into the text file
as `about_SomeHelpTopicFileName`.
Do not include file extensions.
The second header should have no spaces.
```

# SHORT DESCRIPTION

DLLPickle helps prevent assembly version conflicts in mixed-module PowerShell
sessions by preloading compatible identity-related dependencies.

```powershell
ABOUT TOPIC NOTE:
About topics can be no longer than 80 characters wide when rendered to text.
Any topics greater than 80 characters will be automatically wrapped.
The generated about topic will be encoded UTF-8.
```

# LONG DESCRIPTION

When multiple Microsoft service modules are used in the same PowerShell
session, they can package different versions of shared identity assemblies.
Because only one assembly identity can be loaded into the process, module
loading order can cause authentication failures.

DLLPickle addresses this with `Import-DPLibrary`, which preloads a known,
compatible dependency set from the module's `bin` folder:

- `bin/net8.0` on PowerShell 7+
- `bin/net48` on Windows PowerShell 5.1

The loader applies dependency-aware ordering, deterministic fallback ordering,
and scoped local resolution fallback to improve reliability on .NET Framework
assembly probing behaviors.

## Optional Subtopics

### Recommended startup sequence

```powershell
Import-Module DLLPickle
Import-DPLibrary
```

Run this before importing and connecting with Microsoft service modules.

### Configuration

Use the following commands to manage local DLLPickle behavior:

- `Get-DPConfig`
- `Set-DPConfig`

### Diagnostics

For verbose diagnostics, especially on Windows PowerShell 5.1:

```powershell
Import-DPLibrary -SuppressLogo -ShowLoaderExceptions -Verbose
```

# EXAMPLES

```powershell
# Load DLLPickle dependencies first
Import-Module DLLPickle
Import-DPLibrary

# Inspect current configuration
Get-DPConfig

# Skip an environment-specific optional DLL if needed
Set-DPConfig -SkipLibraries @('System.Diagnostics.DiagnosticSource.dll')
```

# NOTE

DLLPickle focuses on assembly-preloading behavior for compatibility. It does not
replace module-specific authentication guidance from each service module owner.

# TROUBLESHOOTING NOTE

If you still encounter load issues:

1. Confirm DLLPickle is loaded before service modules.
1. Run `Import-DPLibrary -ShowLoaderExceptions -Verbose`.
1. Update DLLPickle to the latest release.
1. Use `Set-DPConfig -SkipLibraries` only for environment-specific exceptions.

# SEE ALSO

- [Import-DPLibrary](Import-DPLibrary.md)
- [Get-DPConfig](Get-DPConfig.md)
- [Set-DPConfig](Set-DPConfig.md)
- [Find-DLLInPSModulePath](Find-DLLInPSModulePath.md)
- [Project README](../../../README.md)
- [Deep Dive](../../Deep-Dive.md)

# KEYWORDS

about_DLLPickle

- MSAL
- Assembly Load Order
- PowerShell Module Compatibility
- Import-DPLibrary
