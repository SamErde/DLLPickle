---
document type: module
Help Version: 0.6.2
HelpInfoUri: https://day3bits.com/DLLPickle
Locale: en-US
Module Guid: 4676d9bf-eb37-4a1b-8582-90f7dd9ba726
Module Name: DLLPickle
ms.date: 01/11/2026
PlatyPS schema version: 2024-05-01
title: DLLPickle Module
---

## DLLPickle Module

## Description

A PowerShell module that helps you get un-stuck from version conflicts that occur when using modules that depend on different versions of the same dependency (such as the Microsoft Authentication Library (MSAL)).

## DLLPickle

### [Get-DPConfig](DLLPickle/Get-DPConfig.md)

Gets the current DLLPickle configuration.

### [Set-DPConfig](DLLPickle/Set-DPConfig.md)

Sets DLLPickle configuration options.

### [Find-DLLInPSModulePath](DLLPickle/Find-DLLInPSModulePath.md)

Find DLL files in module paths, filtered by product metadata.

### [Get-ModuleImportCandidate](DLLPickle/Get-ModuleImportCandidate.md)

Reports the version, path, and scope that would be imported for a given module name.

### [Get-ModulesWithDependency](DLLPickle/Get-ModulesWithDependency.md)

Finds installed PowerShell modules that have a common file dependency.

### [Get-ModulesWithVersionSortedIdentityClient](DLLPickle/Get-ModulesWithVersionSortedIdentityClient.md)

Gets modules and sorts them by packaged `Microsoft.Identity.Client.dll` version.

### [Import-DPLibrary](DLLPickle/Import-DPLibrary.md)

Imports DLLPickle dependency libraries.

## Archived Commands

The following pages are retained for historical reference and migration guidance.

### [Get-DLLsInModulePath (Archived)](DLLPickle/Get-DLLsInModulePath.md)

Replaced by `Find-DLLInPSModulePath`.

### [Get-ModuleImportOrder (Archived)](DLLPickle/Get-ModuleImportOrder.md)

Replaced by `Get-ModulesWithVersionSortedIdentityClient`.
