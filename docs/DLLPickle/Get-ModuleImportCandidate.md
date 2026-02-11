---
document type: cmdlet
external help file: DLLPickle-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DLLPickle
ms.date: 01/12/2026
PlatyPS schema version: 2024-05-01
title: Get-ModuleImportCandidate
---

# Get-ModuleImportCandidate

## SYNOPSIS

Reports the version, path, and scope that would be imported for a given module name.

## SYNTAX

### __AllParameterSets

```powershell
Get-ModuleImportCandidate [-Name] <string[]> [[-Scope] <string>] [<CommonParameters>]
```

## ALIASES

This cmdlet has the following aliases,
  {{Insert list of aliases}}

## DESCRIPTION

Searches PSModulePath in order to determine which version of a module would be imported
by Import-Module, mimicking PowerShell's module resolution logic.

## EXAMPLES

### EXAMPLE 1

Get-ModuleImportCandidate -Name "Pester"
Gets the effective module information for Pester from any scope.

### EXAMPLE 2

Get-ModuleImportCandidate "PSReadLine" -Scope CurrentUser
Gets the effective module information for PSReadLine only from the CurrentUser scope.

### EXAMPLE 3

"Pester", "PSReadLine" | Get-ModuleImportCandidate
Gets the effective module information for multiple modules from any scope.

## PARAMETERS

### -Name

The name or array of names of the module to check.

```yaml
Type: System.String[]
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

### -Scope

Limits the search to modules installed for the CurrentUser, AllUsers, or Any (default) scope.

```yaml
Type: System.String
DefaultValue: Any
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### System.String[]

{{ Fill in the Description }}

## OUTPUTS

### A full [System.Management.Automation.PSModuleInfo] object with a Scope and custom type name (DLLPickle.ModuleImportCandidate) added.

{{ Fill in the Description }}

### System.Management.Automation.PSObject

{{ Fill in the Description }}

## NOTES

## RELATED LINKS

{{ Fill in the related links here }}
