---
external help file: DLLPickle-help.xml
Module Name: DLLPickle
online version:
schema: 2.0.0
---

# Get-ModulesWithVersionSortedIdentityClient

## SYNOPSIS

Get a list of modules with the MSAL, and which versions each have packaged.

## SYNTAX

```powershell
Get-ModulesWithVersionSortedIdentityClient [[-Name] <String[]>]
 [<CommonParameters>]
```

## DESCRIPTION

Get a list of modules with the MSAL, and which versions each have packaged.

## EXAMPLES

### EXAMPLE 1

```powershell
Get-ModulesWithVersionSortedIdentityClient -Name 'Az.Accounts','ExchangeOnlineManagement'
This will return a list of modules ordered by the version of 'Microsoft.Identity.Client.dll'
```

## PARAMETERS

### -Name

Parameter description

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable, -Verbose, -WarningAction, -WarningVariable, and -ProgressAction.
For more information, see about_CommonParameters <http://go.microsoft.com/fwlink/?LinkID=113216>.

## INPUTS

## OUTPUTS

## NOTES

General notes

## RELATED LINKS
