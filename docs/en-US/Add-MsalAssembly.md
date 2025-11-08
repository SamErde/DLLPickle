---
external help file: DLLPickle-help.xml
Module Name: DLLPickle
online version:
schema: 2.0.0
---

# Add-MsalAssembly

## SYNOPSIS
Loads the MSAL assembly into a custom AssemblyLoadContext.

## SYNTAX

```
Add-MsalAssembly [[-ModuleRoot] <String>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Loads Microsoft.Identity.Client.dll into an isolated load context
that can be unloaded later.
Requires PowerShell 7.0 or higher.

## EXAMPLES

### Example 1
```powershell
PS C:\> {{ Add example code here }}
```

{{ Add example description here }}

## PARAMETERS

### -ModuleRoot
The root path of the module containing the 'lib' folder with the MSAL DLLs.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: None
Accept pipeline input: False
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
