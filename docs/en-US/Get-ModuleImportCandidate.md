---
external help file: DLLPickle-help.xml
Module Name: DLLPickle
online version:
schema: 2.0.0
---

# Get-ModuleImportCandidate

## SYNOPSIS
Returns information about the specific installed version of a module that Import-Module would load.

## SYNTAX

```
Get-ModuleImportCandidate [[-Name] <String[]>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Get-ModuleImportCandidate is a cross-platform function that reliably determines which module version would be
selected by Import-Module when multiple versions of the same module are available in multiple installation scopes.

When importing modules, PSModulePath is the primary factor in determining which module version is loaded,
and the order of the paths in PSModulePath is important.
The CurrentUser paths generally appear first in PSModulePath,
followed by the AllUsers scope paths.
The function takes into account the following rules:

Location takes precedence over version:
- A lower version in a higher-priority location will be loaded before a higher version in a lower-priority location.
- Within a location, higher versions are loaded first.

## EXAMPLES

### EXAMPLE 1
```
Get-ModuleImportCandidate -Name 'Az.Accounts'
```

Returns a PSModuleInfo object for the version of the 'Az.Accounts' module that would be imported by Import-Module.

### EXAMPLE 2
```
'Az.Accounts','Microsoft.Graph.Authentication' | Get-ModuleImportCandidate
```

Returns PSModuleInfo objects for the specified modules that would be imported by Import-Module.

### EXAMPLE 3
```
Get-ModuleImportCandidate -Name @('Az.Accounts','ExchangeOnlineManagement','Microsoft.Graph.Authentication','MicrosoftTeams')
```

Returns PSModuleInfo objects for the versions of the 'Az.Accounts', 'ExchangeOnlineManagement',
'Microsoft.Graph.Authentication', and 'MicrosoftTeams' modules that would be imported by Import-Module.

## PARAMETERS

### -Name
The name of the module\[s\] to check.
This can be a single module name or an array of module names.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: None
Accept pipeline input: True (ByPropertyName, ByValue)
Accept wildcard characters: False
```

### -ProgressAction
{{ Fill ProgressAction Description }}

```yaml
Type: ActionPreference
Parameter Sets: (All)
Aliases: proga

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES

## RELATED LINKS
