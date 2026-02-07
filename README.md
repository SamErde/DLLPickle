<!-- markdownlint-configure-file { "MD033": false } -->
# 🥒 DLL Pickle

A PowerShell module that helps you get un-stuck from dependency version conflicts that can occur when connecting to multiple Microsoft online services.

<!-- badges-start -->
![GitHub top language](https://img.shields.io/github/languages/top/SamErde/DLLPickle)
[![Codacy Badge](https://app.codacy.com/project/badge/Grade/ae92f0d929de494690e712b68fb3b52c)](https://app.codacy.com/gh/SamErde/DLLPickle/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](http://makeapullrequest.com)
[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/DLLPickle?include_prereleases)](https://powershellgallery.com/packages/DLLPickle)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/11450/badge)](https://www.bestpractices.dev/projects/11450)
<!-- badges-end -->

<img src="https://raw.githubusercontent.com/SamErde/DLLPickle/main/assets/dllpickle.png" alt="A stressed pickle trying to explain the problem in their code to a rubber duck." width="400" />

## 📝 Description

Let's start with a few FAQs:

- **What does DLL Pickle actually *do*?**

  DLL Pickle pre-loads the newest version of DLLs that may be required by your other installed modules and scripts. (See the example below.)

- **Why does it need to do this?**

  It is common for PowerShell modules to ship with DLLs that provide precompiled functionality or dependencies. A PowerShell session cannot import two different versions of the same library (DLL). If a module imports one version of a DLL and then a different module attempts to import a second, newer version of that DLL, they will typically see an error that says, "an assembly with the same name is already loaded."

- **Why don't modules use Application Load Context (ALC) to solve this problem?**

  ALC can be complex to implement and is only available in PowerShell 7, so it is not commonly used in public modules.

- **Do these issues look familiar?**

  <details>
  <summary>Related GitHub Issues</summary>

  - [Connect-MgGraph fails after Connect-ExchangeOnline](https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/3394)
  - [UUF Customer feedback: Get-EntraExtensionProperty error](https://github.com/microsoftgraph/entra-powershell/issues/1258) (Assembly with same name is already loaded)
  - [Assembly with same name is already loaded](https://github.com/microsoftgraph/entra-powershell/issues/1083)
  - [Design entra-powershell with ALC bridge pattern for a more robust assembly load handling](https://github.com/microsoftgraph/entra-powershell/issues/1242)
  - [Implement proper assembly isolation to play nice with vscode-powershell](https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/2978)
  - [Conflict with the .Net dll of the Az module PowerShell/vscode-powershell#3012](https://github.com/PowerShell/vscode-powershell/issues/3012)
  - [Unable to load Az modules - Assembly with same name is already loaded PowerShell/vscode-powershell#4727](https://github.com/PowerShell/vscode-powershell/issues/4727)
  </details>

### 🧑‍💻 An Example Scenario

Numerous PowerShell modules include a dependency on the Microsoft Authentication Library (MSAL) for authenticating to Microsoft's online services. The latest version of the MSAL is actively maintained in **[AzureAD/microsoft-authentication-library-for-dotnet](https://github.com/AzureAD/microsoft-authentication-library-for-dotnet)**. However, modules that depend on the MSAL libraries (such as **Microsoft.Identity.Client.dll**) all update their releases with different versions of MSAL on different schedules. This results in version conflicts that break authentication flows whenever you try to use multiple modules in one session. Examples of modules that can be affected by this include:

- Az.Accounts
- ExchangeOnlineManagement
- Microsoft.Graph.Authentication
- MicrosoftTeams

...and many more.

You can manually attempt to work around this by checking which version of the conflicting DLLs are used by each of your PowerShell modules and then *connect first* to whichever service module uses the newest version of the DLL.

This works because of the "first one wins" rule and because the MSAL is designed to be backwards compatible.

DLL Pickle handles this for you by automatically releasing a new version of DLL Pickle whenever a new release of the MSAL is found. As long as you keep the DLL Pickle module up to date and load it first in your PowerShell profile (or manually load it first in your session), then all other PowerShell modules should be able to use this new MSAL that is loaded by DLL Pickle.

## 🧑‍💻 Getting Started

### Prerequisites

Any of the following PowerShell editions:

- PowerShell on Linux, macOS, or Windows
- Windows PowerShell 5.1

### Installation

```powershell
Install-PSResource -Name DLLPickle -Prerelease
```

### 🥒 Using DLL Pickle

The easiest way to benefit from DLL Pickle is to import the module in your PowerShell profile before any other module or assembly is loaded. Just add the line `Import-Module DLLPickle` to your profile, save it, and start a new instance of PowerShell.

Alternatively, if you are starting work in a new PowerShell session in which you know you will be authenticating to multiple online services, you can run `Import-Module DLLPickle` at the beginning of your session and then proceed with the rest of your modules.

## 📝 Additional Information

### Versioning

This project follows the semantic versioning model. It also packages numerous dependencies that follow their own versioning. To maintain clarity, this project will follow SemVer standards and the following logic for version changes:

#### Major Versions

🏷️ **2.x.x.x** - The major version will only change if there is a breaking change in the DLL Pickle project.

#### Minor Versions

🏷️ **X.1.X.X** - The minor version will change if any of the following occur:

- New features are added to the project
- New tracked assemblies are added to the project

#### Build Versions

🏷️ **X.X.1.X** - The build version will change if any of the following occur:

- Minor refactoring for performance, error handling, or logging
- A new version of any packaged assembly is automatically updated within the project

#### Revisions

🏷️ **X.X.X.1234** - The revision segment of the version may change if any of the following occur:

- Minor fixes for typos or formatting
- Changes to documentation

## External Documentation

All libraries tracked for pre-loading by DLL Pickle are maintained and documented by their own code owners. Please see each project accordingly:

- [Microsoft.Identity.Abstractions](https://www.nuget.org/packages/Microsoft.Identity.Abstractions)
- [Microsoft.Identity.Client](https://www.nuget.org/packages/Microsoft.Identity.Client)
- [Microsoft.Identity.Client.Broker](https://www.nuget.org/packages/Microsoft.Identity.Client.Broker)
- [Microsoft.Identity.Client.Extensions.Msal](https://www.nuget.org/packages/Microsoft.Identity.Client.Extensions.Msal)
- [Microsoft.Identity.Client.NativeInterop](https://www.nuget.org/packages/Microsoft.Identity.Client.NativeInterop)
- [Microsoft.IdentityModel.Abstractions](https://www.nuget.org/packages/Microsoft.IdentityModel.Abstractions)
- [Microsoft.IdentityModel.JsonWebTokens](https://www.nuget.org/packages/Microsoft.IdentityModel.JsonWebTokens)
- [Microsoft.IdentityModel.Logging](https://www.nuget.org/packages/Microsoft.IdentityModel.Logging)
- [Microsoft.IdentityModel.Tokens](https://www.nuget.org/packages/Microsoft.IdentityModel.Tokens)
- [System.IdentityModel.Tokens.Jwt](https://www.nuget.org/packages/System.IdentityModel.Tokens.Jwt)
