---
document type: cmdlet
external help file: DLLPickle-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DLLPickle
ms.date: 01/11/2026
PlatyPS schema version: 2024-05-01
title: Get-ModulesWithDependency
---

# Get-ModulesWithDependency

## SYNOPSIS

Finds installed PowerShell modules that have a common file dependency.

## SYNTAX

### __AllParameterSets

```
Get-ModulesWithDependency [-FileName] <string> [<CommonParameters>]
```

## ALIASES

This cmdlet has the following aliases,
  {{Insert list of aliases}}

## DESCRIPTION

This function queries installed PowerShell resources to identify all modules that have a common dependency on a specific file.

## EXAMPLES

### EXAMPLE 1

Get-ModulesWithDependency -FileName 'Microsoft.Identity.Client.dll' | Format-Table Name,Version,@{N='FileName';E={($_.DependencyPath.Split('\'))[-1]}},DependencyVersion

This will format the output to show the module name, version, file name, and dependency version in a table.

### EXAMPLE 2

Get-ModulesWithDependency -FileName 'Microsoft.Identity.Client.dll'

This will return an array of PSResourceInfo objects for modules with the specified dependency.

## PARAMETERS

### -FileName

The name of the file dependency to search for in the module's manifest file list.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
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

### System.String

{{ Fill in the Description }}

## OUTPUTS

### Microsoft.PowerShell.PSResourceGet.UtilClasses.PSResourceInfo[]
An array of PSResourceInfo objects

{{ Fill in the Description }}

## NOTES

## RELATED LINKS

{{ Fill in the related links here }}

