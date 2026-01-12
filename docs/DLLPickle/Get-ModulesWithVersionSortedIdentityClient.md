---
document type: cmdlet
external help file: DLLPickle-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DLLPickle
ms.date: 01/11/2026
PlatyPS schema version: 2024-05-01
title: Get-ModulesWithVersionSortedIdentityClient
---

# Get-ModulesWithVersionSortedIdentityClient

## SYNOPSIS

Get a list of modules with the MSAL, and which versions each have packaged.

## SYNTAX

### __AllParameterSets

```powershell
Get-ModulesWithVersionSortedIdentityClient [[-Name] <string[]>] [<CommonParameters>]
```

## ALIASES

This cmdlet has the following aliases,
  {{Insert list of aliases}}

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

{{ Fill in the Description }}

## OUTPUTS

## NOTES

## RELATED LINKS

{{ Fill in the related links here }}

