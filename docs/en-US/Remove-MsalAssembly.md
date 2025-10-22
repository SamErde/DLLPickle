---
external help file: DLLPickle-help.xml
Module Name: DLLPickle
online version:
schema: 2.0.0
---

# Remove-MsalAssembly

## SYNOPSIS
Unloads the MSAL assembly from memory.

## SYNTAX

```
Remove-MsalAssembly [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Unloads the MSAL AssemblyLoadContext and triggers garbage collection
to free memory.
Requires PowerShell 7.0 or higher.

## EXAMPLES

### Example 1
```powershell
PS C:\> {{ Add example code here }}
```

{{ Add example description here }}

## PARAMETERS

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
Unloading may not happen immediately.
The GC will unload when all
references to types from the assembly are released.

## RELATED LINKS
