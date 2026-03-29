---
document type: cmdlet
external help file: DLLPickle-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DLLPickle
ms.date: 01/12/2026
PlatyPS schema version: 2024-05-01
title: Get-ModulesWithVersionSortedIdentityClient
---

## Get-ModulesWithVersionSortedIdentityClient

## SYNOPSIS

Get a list of modules with the MSAL, and which versions each have packaged.

## SYNTAX

### __AllParameterSets

```powershell
Get-ModulesWithVersionSortedIdentityClient [[-Name] <string[]>] [<CommonParameters>]
```

## ALIASES

None.

## DESCRIPTION

Get a list of modules with the MSAL, and which versions each have packaged.

## EXAMPLES

### EXAMPLE 1

Get-ModulesWithVersionSortedIdentityClient -Name 'Az.Accounts','ExchangeOnlineManagement'
This will return a list of modules ordered by the version of 'Microsoft.Identity.Client.dll'.

## PARAMETERS

### -Name

Name of the module.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: true
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

### System.String[]

Optional module names to evaluate. When omitted, supply names explicitly from
the pipeline or parameter input.

## OUTPUTS

### System.Management.Automation.PSCustomObject

Returns objects with `Name`, `ModuleBase`, `ModuleVersion`, and `DLLVersion`,
sorted by `DLLVersion` descending.

## NOTES

## RELATED LINKS

[Get-ModuleImportCandidate](Get-ModuleImportCandidate.md)

[Get-ModulesWithDependency](Get-ModulesWithDependency.md)

[Import-DPLibrary](Import-DPLibrary.md)
