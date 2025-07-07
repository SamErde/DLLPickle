---
external help file: DLLPickle-help.xml
Module Name: DLLPickle
online version:
schema: 2.0.0
---

# Get-ModulesWithDependency

## SYNOPSIS
Finds installed PowerShell modules that have a common file dependency.

## SYNTAX

```
Get-ModulesWithDependency [-FileName] <String> [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
This function queries installed PowerShell resources to identify all modules that have a common dependency on a
specific file.

## EXAMPLES

### EXAMPLE 1
```
Get-ModulesWithDependency -FileName 'Microsoft.Identity.Client.dll' | Format-Table Name,Version,@{N='FileName';E={($_.DependencyPath.Split('\'))[-1]}},DependencyVersion
This will format the output to show the module name, version, file name, and dependency version in a table.
```

### EXAMPLE 2
```
Get-ModulesWithDependency -FileName 'Microsoft.Identity.Client.dll'
This will return an array of PSResourceInfo objects for modules with the specified dependency.
```

## PARAMETERS

### -FileName
The name of the file dependency to search for in the module's manifest file list.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: True (ByValue)
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

### Microsoft.PowerShell.PSResourceGet.UtilClasses.PSResourceInfo[]
### An array of PSResourceInfo objects, each with an added 'DependencyPath' and 'DependencyVersion' property.
## NOTES

## RELATED LINKS
