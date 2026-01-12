---
document type: cmdlet
external help file: DLLPickle-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DLLPickle
ms.date: 01/12/2026
PlatyPS schema version: 2024-05-01
title: Find-DLLInPSModulePath
---

# Find-DLLInPSModulePath

## SYNOPSIS

Show a list of all DLLs in PowerShell module paths that contain the specified product name in their FileInfo property.

## SYNTAX

### __AllParameterSets

```powershell
Find-DLLInPSModulePath [[-ProductName] <string>] [[-FileName] <string>] [[-Path] <string[]>]
 [[-ExcludeDirectories] <string[]>] [[-Scope] <string>] [-NewestVersion] [-ShowDetails]
 [<CommonParameters>]
```

## ALIASES

This cmdlet has the following aliases,
  {{Insert list of aliases}}

## DESCRIPTION

Check all installed PowerShell module locations for DLL files that have the specified product name
(e.g., 'Microsoft Identity') in their file's ProductName attribute.
By default, searches all paths
in the PSModulePath environment variable.
Can optionally check custom locations using the -Path parameter.

## EXAMPLES

### EXAMPLE 1

Find-DLLInPSModulePath -ProductName "Microsoft Identity"

Find all DLLs with 'Microsoft Identity' in their ProductName property within installed PowerShell module locations.

### EXAMPLE 2

Find-DLLInPSModulePath -FileName "Microsoft.IdentityModel*.dll"

Find all DLL files matching the pattern 'Microsoft.IdentityModel*.dll' that also have 'Microsoft Identity' in their ProductName.

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

## PARAMETERS

### -ExcludeDirectories

Directories to exclude from inspection so the process goes faster.

```yaml
Type: System.String[]
DefaultValue: "@('en-US', '.git')"
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

### -FileName

The file name pattern to search for.
Supports wildcards.
Defaults to '*.dll' to search all DLL files.
Use a specific pattern like 'Microsoft.IdentityModel*.dll' to narrow the search.

```yaml
Type: System.String
DefaultValue: '*.dll'
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

### -NewestVersion

If specified, only the newest version of each matching DLL will be returned.

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

### -Path

Locations to search for DLLs.
Defaults to all valid directories in the PSModulePath environment variable.

```yaml
Type: System.String[]
DefaultValue: '@( $env:PSModulePath -split [System.IO.Path]::PathSeparator | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container -ErrorAction SilentlyContinue) } )'
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

### -ProductName

The product name to search for in DLL ProductName properties.
Supports wildcards.
Defaults to 'Microsoft Identity'.

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
  Position: 4
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

### System.Diagnostics.FileVersionInfo

{{ Fill in the Description }}

## NOTES

## RELATED LINKS

{{ Fill in the related links here }}
