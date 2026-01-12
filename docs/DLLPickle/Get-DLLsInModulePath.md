---
document type: cmdlet
external help file: DLLPickle-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DLLPickle
ms.date: 01/11/2026
PlatyPS schema version: 2024-05-01
title: Get-DLLsInModulePath
---

# Get-DLLsInModulePath

## SYNOPSIS

Show a list of all DLLs in PowerShell module paths that contain the specified product name in their FileInfo property.

## SYNTAX

### __AllParameterSets

```
Get-DLLsInModulePath [[-ProductName] <string>] [[-Path] <string[]>]
 [[-ExcludeDirectories] <string[]>] [[-Scope] <string>] [-ShowDetails] [<CommonParameters>]
```

## ALIASES

This cmdlet has the following aliases,
  {{Insert list of aliases}}

## DESCRIPTION

Check all installed PowerShell module locations for DLL files that have the specified product name (e.g., 'Microsoft Identity') in their file's ProductName attribute.
By default, searches all paths in the PSModulePath environment variable.
Can optionally check custom locations using the -Path parameter.

## EXAMPLES

### EXAMPLE 1

Get-DLLsInModulePath -ProductName "Microsoft Identity"

Find all Microsoft Identity-related DLLs within installed PowerShell module locations.

### EXAMPLE 2

Get-DLLsInModulePath -ProductName "Microsoft Identity" | Sort-Object -Property InternalName | Format-Table InternalName, @{Label = 'ProductVersion'; Expression = { $_.ProductVersionRaw } }, @{Label = 'Module'; Expression = { $($_.FileName -replace '^.*Modules[\\/]([^\\/]+)([\\/].*)?', '$1') }}

Find all Microsoft Identity-related DLLs within installed PowerShell module locations.
Shows the name of the module that the DLL is included in.

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

## OUTPUTS

### System.Object

{{ Fill in the Description }}

### System.Diagnostics.FileVersionInfo

{{ Fill in the Description }}

## NOTES

To Do:

- Further reduce the number of paths inspected by (optionally) only scanning the newest version of each module in each scope's paths.
- Fix ShowDetails logic.
- Apply custom formatting type for output.

Example Output:

InternalName                                        ProductVersion Module
------------                                        -------------- ------
Microsoft.Identity.Abstractions.dll                 9.5.0.0        DLLPickle
Microsoft.IdentityModel.Abstractions.dll            0.0.0.0        Az.Accounts
Microsoft.IdentityModel.JsonWebTokens.dll           8.6.0.0        ExchangeOnlineManagement
Microsoft.IdentityModel.Logging.dll                 8.6.0.0        ExchangeOnlineManagement
Microsoft.IdentityModel.Protocols.dll               8.6.1.0        WinTuner
Microsoft.IdentityModel.Protocols.OpenIdConnect.dll 8.6.1.0        WinTuner
Microsoft.IdentityModel.Tokens.dll                  8.6.0.0        ExchangeOnlineManagement
Microsoft.IdentityModel.Validators.dll              8.6.1.0        WinTuner
System.IdentityModel.Tokens.Jwt.dll                 8.6.0.0        ExchangeOnlineManagement


## RELATED LINKS

{{ Fill in the related links here }}

