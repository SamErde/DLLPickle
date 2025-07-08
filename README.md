# DLL Pickle

A PowerShell module that helps you get un-stuck from dependency version conflicts (aka DLL pickle) that often occur when trying to connect to multiple Microsoft services.

![A stressed pickle trying to explain the problem in their code to a rubber duck.](assets/dllpickle.png)

## Example

Several Microsoft modules include the file **Microsoft.Identity.Client.dll** as a built-in dependency. The latest version of that file (<!--Version-->4.73.1<!--/Version-->) is actively maintained in the **AzureAD/microsoft-authentication-library-for-dotnet** repository. However, the following modules all update this package on different schedules, resulting in version conflicts that break authentication flows whenever you try to use multiple modules in one session:

- Az.Accounts
- ExchangeOnlineManagement
- Microsoft.Graph.Authentication
- MicrosoftTeams

[![NuGet](https://img.shields.io/nuget/v/microsoft.identity.client.svg?style=flat-square&label=nuget&colorB=00b200)](https://www.nuget.org/packages/Microsoft.Identity.Client/)
[![GitHub](https://img.shields.io/github/v/microsoft.identity.client.svg?style=flat-square&label=github&colorB=00b200)](https://github.com/AzureAD/microsoft-authentication-library-for-dotnet)
