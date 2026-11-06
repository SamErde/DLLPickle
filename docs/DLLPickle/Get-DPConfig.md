---
document type: cmdlet
external help file: DLLPickle-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DLLPickle
ms.date: 03/29/2026
PlatyPS schema version: 2024-05-01
title: Get-DPConfig
---

## Get-DPConfig

## SYNOPSIS

Gets the current DLLPickle configuration.

## SYNTAX

### __AllParameterSets

```powershell
Get-DPConfig [<CommonParameters>]
```

## DESCRIPTION

Reads DLLPickle configuration from the current user's application data path.
If configuration cannot be read or fails validation, the command reports
`DPConfigReadFailed` and returns all default values. With `-ErrorAction Stop`,
the error terminates the command instead.

The JSON root must be an object. `CheckForUpdates` and `ShowLogo` accept JSON
booleans (`true` or `false`), and `SkipLibraries` accepts an array containing only
strings. Missing or null settings use defaults; unknown settings are ignored.
Setting names are case-insensitive; repeated recognized settings are rejected.
Comments and trailing commas are accepted. JSON nesting is limited to 64 levels.
Strings such as `"false"`, numeric booleans, scalar library names, and non-string
array entries are rejected rather than coerced. Use `Set-DPConfig` to write the
expected types. Library names are literal names, not paths to load or wildcard
patterns. A missing file returns defaults without an error.

## EXAMPLES

### EXAMPLE 1

```powershell
Get-DPConfig
```

Returns the current configuration values.

### EXAMPLE 2

```powershell
Get-DPConfig | Format-List
```

Shows all configuration properties and values in list format.

## PARAMETERS

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

None. You cannot pipe objects to this cmdlet.

## OUTPUTS

### System.Management.Automation.PSCustomObject

Returns a configuration object with the following properties:

- `CheckForUpdates` (`bool`)
- `ShowLogo` (`bool`)
- `SkipLibraries` (`string[]`)

## NOTES

Configuration is stored per user under the application data profile in
`DLLPickle/config.json`.

## RELATED LINKS

[Set-DPConfig](Set-DPConfig.md)

[Import-DPLibrary](Import-DPLibrary.md)
