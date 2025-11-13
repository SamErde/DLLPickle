# DLL Pickle

A PowerShell module that helps you get un-stuck from dependency version conflicts (aka DLL pickle) that often occur when trying to connect to multiple Microsoft services.

<!-- badges-start -->
![GitHub top language](https://img.shields.io/github/languages/top/SamErde/DLLPickle)
[![Codacy Badge](https://app.codacy.com/project/badge/Grade/ae92f0d929de494690e712b68fb3b52c)](https://app.codacy.com/gh/SamErde/DLLPickle/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](http://makeapullrequest.com)
[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/DLLPickle?include_prereleases)](https://powershellgallery.com/packages/DLLPickle)
<!-- badges-end -->

![A stressed pickle trying to explain the problem in their code to a rubber duck.](assets/dllpickle.png)

## Example

Several Microsoft modules include the file **Microsoft.Identity.Client.dll** as a built-in dependency. The latest version of that file (<!--Version-->4.79.0<!--/Version-->) is actively maintained in the **AzureAD/microsoft-authentication-library-for-dotnet** repository. However, the following modules all update this package on different schedules, resulting in version conflicts that break authentication flows whenever you try to use multiple modules in one session:

- Az.Accounts
- ExchangeOnlineManagement
- Microsoft.Graph.Authentication
- MicrosoftTeams

[![NuGet](https://img.shields.io/nuget/v/microsoft.identity.client.svg?style=flat-square&label=nuget&colorB=00b200)](https://www.nuget.org/packages/Microsoft.Identity.Client/)

