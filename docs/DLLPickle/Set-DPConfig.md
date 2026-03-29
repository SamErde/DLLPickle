---
document type: cmdlet
external help file: DLLPickle-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DLLPickle
ms.date: 03/29/2026
PlatyPS schema version: 2024-05-01
title: Set-DPConfig
---

## Set-DPConfig

## SYNOPSIS

Sets DLLPickle configuration options.

## SYNTAX

### __AllParameterSets

```powershell
Set-DPConfig [[-CheckForUpdates] <bool>] [[-ShowLogo] <bool>] [[-SkipLibraries] <string[]>] [-Reset]
 [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION

Updates configuration values stored for the current user in the DLLPickle
configuration file. If the file does not exist, it is created.

Use `-Reset` to restore default values.

## EXAMPLES

### EXAMPLE 1

```powershell
Set-DPConfig -ShowLogo $false
```

Disables logo output while preserving other settings.

### EXAMPLE 2

```powershell
Set-DPConfig -SkipLibraries @('System.Diagnostics.DiagnosticSource.dll') -PassThru
```

Sets `SkipLibraries` and returns the updated configuration.

### EXAMPLE 3

```powershell
Set-DPConfig -Reset -PassThru
```

Resets all values to defaults and returns the result.

## PARAMETERS

### -CheckForUpdates

Enable or disable automatic update checks.

```yaml
Type: System.Boolean
DefaultValue: Existing value
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

### -ShowLogo

Enable or disable logo output.

```yaml
Type: System.Boolean
DefaultValue: Existing value
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

### -SkipLibraries

One or more DLL file names to skip during `Import-DPLibrary` execution.

```yaml
Type: System.String[]
DefaultValue: Existing value
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

### -Reset

Reset all values to defaults.

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

### -PassThru

Return the updated configuration object.

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
-Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

None. You cannot pipe objects to this cmdlet.

## OUTPUTS

### System.Management.Automation.PSCustomObject

When `-PassThru` is specified, returns configuration with:

- `CheckForUpdates` (`bool`)
- `ShowLogo` (`bool`)
- `SkipLibraries` (`string[]`)

## NOTES

This cmdlet supports `-WhatIf` and `-Confirm` for reset operations.

## RELATED LINKS

[Get-DPConfig](Get-DPConfig.md)

[Import-DPLibrary](Import-DPLibrary.md)
