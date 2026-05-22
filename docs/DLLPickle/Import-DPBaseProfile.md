---
external help file: DLLPickle-help.xml
Module Name: DLLPickle
online version:
schema: 2.0.0
title: Import-DPBaseProfile
---

## Synopsis

Imports DLLPickle libraries and the validated base Microsoft service modules.

## Syntax

```powershell
Import-DPBaseProfile [[-ModuleName] <String[]>] [-Force] [-ShowLoaderExceptions] [-SuppressLogo]
```

## Description

`Import-DPBaseProfile` runs `Import-DPLibrary`, then imports the Microsoft
service modules used in the validated base profile:

1. `ExchangeOnlineManagement`
1. `MicrosoftTeams`
1. `Microsoft.Graph.Authentication`
1. `Az.Accounts`

`Az.Accounts` can load older Azure identity assemblies before Microsoft Graph
if imported first, which can reintroduce the
`UserProvidedTokenCredential.GetTokenAsync` type identity failure. The same
order is recommended for consistency.

`Connect-AzAccount` can still fail after Graph or Exchange has loaded its own
Azure.Identity assemblies. Isolate Az authentication in a separate process when
the full base profile must connect to all services.

## Examples

### Example 1

```powershell
Import-Module DLLPickle
Import-DPBaseProfile
```

Imports DLLPickle's dependency libraries and the validated base profile modules.

### Example 2

```powershell
Import-DPBaseProfile -Force -SuppressLogo
```

Re-imports the base profile modules and suppresses the DLLPickle logo.

## Parameters

### -ModuleName

The modules to import after DLLPickle preloads its dependency libraries.

```yaml
Type: String[]
Required: false
Position: 0
Default value: ExchangeOnlineManagement, MicrosoftTeams, Microsoft.Graph.Authentication, Az.Accounts
```

### -Force

Re-imports modules even if they are already loaded.

```yaml
Type: SwitchParameter
Required: false
Position: named
Default value: False
```

### -ShowLoaderExceptions

Displays detailed loader exception information from `Import-DPLibrary`.

```yaml
Type: SwitchParameter
Required: false
Position: named
Default value: False
```

### -SuppressLogo

Suppresses the DLLPickle logo during `Import-DPLibrary`.

```yaml
Type: SwitchParameter
Required: false
Position: named
Default value: False
```

## Outputs

### PSCustomObject

Returns one result for the DLLPickle preload step and one result for each
imported module.

## Related Links

- [Import-DPLibrary](Import-DPLibrary.md)
