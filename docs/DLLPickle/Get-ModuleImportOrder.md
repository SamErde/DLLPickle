---
external help file: DLLPickle-help.xml
Module Name: DLLPickle
online version:
schema: 2.0.0
---

# Get-ModuleImportOrder

## SYNOPSIS
Evaluates the import order of specified modules based on their versions and the location in PSModulePath.

## SYNTAX

```powershell
Get-ModuleImportOrder [[-Name] <String[]>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
This function evaluates the import order of specified modules based on their versions and the location in PSModulePath.
It uses Get-ModuleImportCandidate to determine which version of each module would be imported by Import-Module,
and then sorts them by the version of 'Microsoft.Identity.Client.dll' that is packaged with each module.

## EXAMPLES

### EXAMPLE 1

```powershell
Get-ModuleImportOrder -Name 'Az.Accounts','ExchangeOnlineManagement'
```

Returns a list of modules ordered by the version of 'Microsoft.Identity.Client.dll' they contain.

## PARAMETERS

### -Name
A list of module names to evaluate for proper import order.
Wildcards are allowed.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: None
Accept pipeline input: True (ByPropertyName)
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
