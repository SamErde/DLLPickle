---
document type: cmdlet
external help file: DLLPickle-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DLLPickle
ms.date: 02/13/2026
PlatyPS schema version: 2024-05-01
title: Import-DPLibrary
---

## Import-DPLibrary

## SYNOPSIS

Import DLLPickle dependency libraries.

## SYNTAX

### __AllParameterSets

```PowerShell
Import-DPLibrary [-ShowLoaderExceptions] [-SuppressLogo] [<CommonParameters>]
```

## DESCRIPTION

Import all DLL files from the appropriate target framework moniker (TFM) directory.
DLLs are loaded from the TFM folder based on the PowerShell edition:

- PowerShell Desktop Edition: bin/net48/
- PowerShell Core Edition: bin/net8.0/

The latest versions of all dependencies are automatically imported, providing
backwards compatibility and avoiding version conflicts.

Import-DPLibrary uses dependency-graph-based load ordering, a local assembly
resolution fallback, and retry logic to reduce transient assembly load failures
in Windows PowerShell 5.1 (.NET Framework 4.8).
This approach derives dependency-first ordering from local assembly metadata,
appends unresolved graph nodes deterministically in alphabetical order, and
resolves same-name assemblies from the module's local bin folder when .NET
Framework probing does not resolve them on the first pass.

If an assembly still fails due to unresolved transitive dependencies or platform limitations,
Import-DPLibrary retries the failed assembly set and returns detailed diagnostics for
assemblies that remain unresolved.

## EXAMPLES

### EXAMPLE 1

```powershell
Import-DPLibrary
```

Imports all dependency DLLs from the appropriate TFM directory.

### EXAMPLE 2

```powershell
Import-DPLibrary -ShowLoaderExceptions
```

Imports DLLs and displays detailed diagnostic information for any failures.

## PARAMETERS

### -ShowLoaderExceptions

Display detailed loader exception information when an assembly fails to load.
This is useful for diagnosing why specific types within an assembly cannot be loaded.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SuppressLogo

Suppress the display of the module logo during execution.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

None. You cannot pipe objects to this cmdlet.

## OUTPUTS

### System.Management.Automation.PSCustomObject

Returns information about each imported DLL including:

- DLLName: The name of the DLL file
- AssemblyName: The assembly name
- AssemblyVersion: The version of the assembly
- Status: Import status (Imported, Already Loaded, or Failed)
- Error: Error message if the import failed

## NOTES

Known Issues:

- Windows PowerShell 5.1 uses .NET Framework 4.8 assembly probing behavior. Some transitive
  dependencies can fail on an initial load if prerequisite assemblies are not loaded first.
- Certain identity and diagnostic assemblies may also depend on APIs with limited support in
  .NET Framework 4.8, which can produce ReflectionTypeLoadException details.

Workaround and Reliability Guidance:

- Use `Import-DPLibrary -SuppressLogo -ShowLoaderExceptions -Verbose` to view dependency
  resolution details.
- Keep DLLPickle updated so net48 dependency copies, ordering improvements, and
  local assembly resolution fallback are available.
- If a specific optional assembly is still incompatible in your environment, add it to
  `SkipLibraries` with `Set-DPConfig`.

## RELATED LINKS

[Get-DPConfig](Get-DPConfig.md)

[Set-DPConfig](Set-DPConfig.md)

[Find-DLLInPSModulePath](Find-DLLInPSModulePath.md)

[Get-ModulesWithDependency](Get-ModulesWithDependency.md)
