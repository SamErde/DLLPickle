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

# DLLPickle Module

## Description

A PowerShell module that helps you get un-stuck from version conflicts that occur when using modules that depend on different versions of the same dependency (such as the Microsoft Authentication Library (MSAL)).

## DLLPickle

### [Get-DLLsInModulePath](Get-DLLsInModulePath.md)

Show a list of all DLLs in PowerShell module paths that contain the specified product name in their FileInfo property.

### [Get-ModulesWithDependency](Get-ModulesWithDependency.md)

Finds installed PowerShell modules that have a common file dependency.

### [Get-ModulesWithVersionSortedIdentityClient](Get-ModulesWithVersionSortedIdentityClient.md)

Get a list of modules with the MSAL, and which versions each have packaged.

### [Import-DPLibrary](Import-DPLibrary.md)

Import DLLPickle libraries based on Packages.json configuration.

