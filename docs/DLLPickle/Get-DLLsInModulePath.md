---
document type: cmdlet
external help file: DLLPickle-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DLLPickle
ms.date: 01/12/2026
PlatyPS schema version: 2024-05-01
title: Get-DLLsInModulePath
---

## Get-DLLsInModulePath

> [!WARNING]
> This page is archived. `Get-DLLsInModulePath` is no longer exported by
> DLLPickle.

## SYNOPSIS

Archived command reference retained for migration guidance.

## SYNTAX

### __AllParameterSets

```PowerShell
Get-DLLsInModulePath [[-ProductName] <string>] [[-Path] <string[]>]
 [[-ExcludeDirectories] <string[]>] [[-Scope] <string>] [-ShowDetails]
 [<CommonParameters>]
```

## ALIASES

None.

## DESCRIPTION

This command is no longer part of the exported DLLPickle command set.

Use `Find-DLLInPSModulePath` instead. It supersedes this command and provides
improved path scoping, metadata-rich output, and optional newest-version
filtering.

## EXAMPLES

### EXAMPLE 1

```powershell
Find-DLLInPSModulePath -ProductName "Microsoft Identity"
```

Replacement for the archived command.

### EXAMPLE 2

```powershell
Find-DLLInPSModulePath -FileName "Microsoft.IdentityModel*.dll" -NewestVersion
```

Modern equivalent that narrows results and returns newest matching versions.

## PARAMETERS

### -ExcludeDirectories

Directories to exclude from inspection so the process goes faster.

```yaml
Type: System.String[]
DefaultValue: "@('en-US', 'help', 'Tests', '.git')"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 2
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Path

Locations to search for Microsoft Identity-related DLLs.

```yaml
Type: System.String[]
DefaultValue: '@( $env:PSModulePath -split [System.IO.Path]::PathSeparator | Where-Object { Test-Path $_ -PathType Container } )'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ProductName

The product name to search for in DLL file info properties.

```yaml
Type: System.String
DefaultValue: Microsoft Identity
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Scope

The module installation scope to search.
Valid options are AllUsers, CurrentUser, or Both (default).

```yaml
Type: System.String
DefaultValue: Both
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 3
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ShowDetails

Display formatted output to host in addition to returning objects to the pipeline.

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

None.

## OUTPUTS

### System.Object

Not applicable for current module versions.

### System.Diagnostics.FileVersionInfo

Historical output details are preserved for reference only.

## NOTES

This page is intentionally retained to avoid breaking older external links.

## RELATED LINKS

[Find-DLLInPSModulePath](Find-DLLInPSModulePath.md)

[Get-ModulesWithDependency](Get-ModulesWithDependency.md)
