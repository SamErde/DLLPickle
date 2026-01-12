---
document type: cmdlet
external help file: DLLPickle-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DLLPickle
ms.date: 01/12/2026
PlatyPS schema version: 2024-05-01
title: Import-DPLibrary
---

# Import-DPLibrary

## SYNOPSIS

Import DLLPickle libraries based on Packages.json configuration.

## SYNTAX

### __AllParameterSets

```PowerShell
Import-DPLibrary [-ImportAll] [<CommonParameters>]
```

## ALIASES

This cmdlet has the following aliases,
  {{Insert list of aliases}}

## DESCRIPTION

Import all DLLs (libraries) that are tracked and marked for auto-import in the Packages.json file.

## EXAMPLES

### EXAMPLE 1

Import-DPLibrary
Imports all DLLPickle libraries marked for auto-import.

### EXAMPLE 2

Import-DPLibrary -ImportAll
Imports all DLLPickle libraries, ignoring auto-import settings.

## PARAMETERS

### -ImportAll

Ignore preset 'autoImport' values and attempt to import all packages.

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

Returns information about imported libraries.

{{ Fill in the Description }}

## NOTES

## RELATED LINKS

{{ Fill in the related links here }}
