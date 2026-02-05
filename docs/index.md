# DLL Pickle

A PowerShell module that helps you get un-stuck from dependency version conflicts (aka DLL pickle) that often occur when trying to connect to multiple Microsoft services.

<!-- badges-start -->
![GitHub top language](https://img.shields.io/github/languages/top/SamErde/DLLPickle)
[![Codacy Badge](https://app.codacy.com/project/badge/Grade/ae92f0d929de494690e712b68fb3b52c)](https://app.codacy.com/gh/SamErde/DLLPickle/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](http://makeapullrequest.com)
[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/DLLPickle?include_prereleases)](https://powershellgallery.com/packages/DLLPickle)
<!-- badges-end -->

<!-- markdownlint-disable MD033 -->
<img src="https://raw.githubusercontent.com/SamErde/DLLPickle/main/assets/dllpickle.png" alt="A stressed pickle trying to explain the problem in their code to a rubber duck." width="400" />

## Description

Numerous PowerShell modules include a dependency on the Microsoft Authentication Library (MSAL) for authenticating to Microsoft's online services. The latest version of the MSAL (<!--Version-->4.79.1<!--/Version-->) is actively maintained in **[AzureAD/microsoft-authentication-library-for-dotnet](https://github.com/AzureAD/microsoft-authentication-library-for-dotnet)**. However, modules that depend on the MSAL libraries (such as **Microsoft.Identity.Client.dll**) all update their releases with different versions of MSAL on different schedules. This results in version conflicts that break authentication flows whenever you try to use multiple modules in one session. Examples of modules that can be affected by this include:

- Az.Accounts
- ExchangeOnlineManagement
- Microsoft.Graph.Authentication
- MicrosoftTeams
- MSAL.PS
- Maester

...and many more.

You can manually attempt to work around this by checking which version of the conflicting DLLs are used by each of your PowerShell modules and then _connect first_ to whichever service module uses the newest version of the DLL.

This works because of the "first one wins" rule and because the MSAL is designed to be backwards compatible.

DLL Pickle handles this for you by automatically releasing a new version of DLL Pickle whenever a new release of the MSAL is found. As long as you keep the DLL Pickle module up to date and load it first in your PowerShell profile (or manually load it first in your session), then all other PowerShell modules should be able to use this new MSAL that is loaded by DLL Pickle.

For more information about how this works, [read here](https://raw.githubusercontent.com/SamErde/DLLPickle/main/docs/deepdive.md).

## Getting Started

### Prerequisites

Any of the following PowerShell editions:

- PowerShell on Linux, macOS, or Windows
- Windows PowerShell 5.1

### Installation

```powershell
Install-PSResource -Name DLLPickle
```

### Using DLL Pickle

The easiest way to benefit from DLL Pickle is to import the module in your PowerShell profile before any other module or assembly is loaded. Just add the line `Import-Module DLLPickle` to your profile, save it, and start a new instance of PowerShell.

Alternatively, if you are starting work in a new PowerShell session in which you know you will be authenticating to multiple online services, you can run `Import-Module DLLPickle` at the beginning of your session and then proceed with the rest of your modules.

## Tracked Libraries

MSAL Latest Version: [![NuGet](https://img.shields.io/nuget/v/microsoft.identity.client.svg?style=flat-square&label=nuget&colorB=00b200)](https://www.nuget.org/packages/Microsoft.Identity.Client/)
