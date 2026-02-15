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

# Import-DPLibrary

## SYNOPSIS

Import DLLPickle dependency libraries.

## SYNTAX

### __AllParameterSets

```PowerShell
Import-DPLibrary [-SkipProblematicAssemblies] [-ShowLoaderExceptions] [<CommonParameters>]
```

## DESCRIPTION

Import all DLL files from the appropriate target framework moniker (TFM) directory.
DLLs are loaded from the TFM folder based on the PowerShell edition:

- PowerShell Desktop Edition: bin/net48/
- PowerShell Core Edition: bin/net8.0/

The latest versions of all dependencies are automatically imported, providing
backwards compatibility and avoiding version conflicts.

Some assemblies may have partial compatibility issues in Windows PowerShell due to
dependencies on types not available in .NET Framework 4.8. The function will continue
loading other assemblies and provide detailed diagnostic information about failures.

## EXAMPLES

### EXAMPLE 1

```powershell
Import-DPLibrary
```

Imports all dependency DLLs from the appropriate TFM directory.

### EXAMPLE 2

```powershell
Import-DPLibrary -SkipProblematicAssemblies
```

Imports compatible DLLs and skips known problematic assemblies in Windows PowerShell.

### EXAMPLE 3

```powershell
Import-DPLibrary -ShowLoaderExceptions
```

Imports DLLs and displays detailed diagnostic information for any failures.

## PARAMETERS

### -SkipProblematicAssemblies

When running in Windows PowerShell, skip assemblies known to have compatibility issues
with .NET Framework 4.8. This prevents warning messages while still loading all
compatible dependencies.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

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

- Microsoft.Identity.Client.dll and System.Diagnostics.DiagnosticSource.dll may fail to load
  in Windows PowerShell due to dependencies on types not available in .NET Framework 4.8.
- Use -SkipProblematicAssemblies to avoid warnings for known incompatibilities.
- Use -ShowLoaderExceptions to get detailed information about why specific types failed to load.

## RELATED LINKS
