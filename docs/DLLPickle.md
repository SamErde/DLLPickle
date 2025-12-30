---
Module Name: DLLPickle
Module Guid: 4676d9bf-eb37-4a1b-8582-90f7dd9ba726
Download Help Link: NA
Help Version: 0.2.0
Locale: en-US
---

# DLLPickle Module

## Description

A PowerShell module that helps you get un-stuck from version conflicts (aka DLL pickle) that occur when using multiple modules that connect to Microsoft services using different versions of the Microsoft Authentication Library (MSAL).

## DLLPickle Cmdlets

### [Get-ModulesWithDependency](Get-ModulesWithDependency.md)

Finds installed PowerShell modules that have a common file dependency.

### [Get-ModulesWithVersionSortedIdentityClient](Get-ModulesWithVersionSortedIdentityClient.md)

Get a list of modules with the MSAL, and which versions each have packaged.
