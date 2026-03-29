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

## 🧑‍💻 Getting Started

### Prerequisites

Any of the following PowerShell editions:

- PowerShell on Linux, macOS, or Windows
- Windows PowerShell 5.1

### Installation

```powershell
Install-Module DLLPickle -Scope CurrentUser
```

Or, if you use **Microsoft.PowerShell.PSResourceGet**, run:

```powershell
Install-PSResource -Name DLLPickle
```

### Using

Import the module, then run `Import-DPLibrary` before connecting to service modules.

```powershell
Import-Module DLLPickle
Import-DPLibrary
```

### Core Commands

DLLPickle currently exports the following commands:

- `Import-DPLibrary`: preload DLLPickle-managed assemblies in dependency-aware order.
- `Get-DPConfig`: view your current DLLPickle configuration.
- `Set-DPConfig`: update DLLPickle configuration (for example, show logo, skip libraries).
- `Find-DLLInPSModulePath`: inspect module paths for matching DLLs.
- `Get-ModuleImportCandidate`: determine which installed module version would import.
- `Get-ModulesWithDependency`: list installed modules that package a target dependency.
- `Get-ModulesWithVersionSortedIdentityClient`: compare modules by packaged `Microsoft.Identity.Client.dll` version.

For complete syntax and examples, see:

- [docs index](docs/index.md)
- [module command reference](docs/DLLPickle.md)

---

## 📝 Description

Let's start with a few FAQs:

- **What does DLL Pickle actually *do*?**

  DLL Pickle pre-loads the newest version of the MSAL DLLs (and some of their transitive dependencies) that may be required by your other installed modules' and scripts' `Connect-*` cmdlets. (See the example below.)

- **Why does it need to do this?**

  It is common for PowerShell modules to ship with DLLs that provide precompiled functionality or dependencies. A PowerShell session cannot import two different versions of the same library (DLL). If a module imports one version of a DLL and then a different module attempts to import a second, newer version of that DLL, they will typically see an error that says, "an assembly with the same name is already loaded" and the second module will not be able to function.

- **Why don't modules use Application Load Context (ALC) to solve this problem?**

  ALC can be very complex to implement *and* is only available in PowerShell 7. For these reasons, it is not commonly used in public modules.

- **Do these issues look familiar?**

### Related GitHub Issues

- [Connect-MgGraph fails after Connect-ExchangeOnline](https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/3394)
- [UUF Customer feedback: Get-EntraExtensionProperty error](https://github.com/microsoftgraph/entra-powershell/issues/1258) (Assembly with same name is already loaded)
- [Assembly with same name is already loaded](https://github.com/microsoftgraph/entra-powershell/issues/1083)
- [Design entra-powershell with ALC bridge pattern for a more robust assembly load handling](https://github.com/microsoftgraph/entra-powershell/issues/1242)
- [Implement proper assembly isolation to play nice with vscode-powershell](https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/2978)
- [Conflict with the .Net dll of the Az module PowerShell/vscode-powershell#3012](https://github.com/PowerShell/vscode-powershell/issues/3012)
- [Unable to load Az modules - Assembly with same name is already loaded PowerShell/vscode-powershell#4727](https://github.com/PowerShell/vscode-powershell/issues/4727)

### 🧑‍💻 An Example Scenario

Numerous PowerShell modules include a dependency on the Microsoft Authentication Library (MSAL) for authenticating to Microsoft's online services. The latest version of the MSAL is actively maintained in **[AzureAD/microsoft-authentication-library-for-dotnet](https://github.com/AzureAD/microsoft-authentication-library-for-dotnet)**. However, modules that depend on the MSAL libraries (such as **Microsoft.Identity.Client.dll**) all update their releases with different versions of MSAL on different schedules. This results in version conflicts that break authentication flows whenever you try to use multiple modules in one session. Examples of modules that can be affected by this include:

- Az.Accounts
- ExchangeOnlineManagement
- Microsoft.Graph.Authentication
- MicrosoftTeams
- ...and many more.

You could *manually* attempt to work around this by checking which version of the conflicting DLLs are used by each of your PowerShell modules and then *connect first* to whichever service module uses the newest version of the DLL. This works because of the "first one wins" rule and because the MSAL is designed to be backwards compatible. DLL Pickle handles this for you by automatically updating and releasing a new version of DLL Pickle whenever a new version of the MSAL is published. As long as you keep the DLL Pickle module up to date and run `Import-DPLibrary` before other modules, you should be able to connect to any Microsoft online service without DLL conflicts.

### 🥒 Using DLL Pickle

The easiest way to benefit from DLL Pickle is to import the module in your PowerShell profile before any other module or assembly is loaded. Just add the line `Import-DPLibrary` to your profile, save it, and start a new instance of PowerShell.

Alternatively, if you are starting work in a new PowerShell session in which you know you will be authenticating to multiple online services, you can run `Import-DPLibrary` at the beginning of your session and then proceed with connecting to Microsoft's online services using their first party modules.

### ⚙️ Platform Caveats

- **PowerShell 7+ (Core, net8.0):** Full support and best overall compatibility.
- **Windows PowerShell 5.1 (Desktop, net48):** Supported with dependency-graph-based loading order, deterministic fallback for unresolved graph nodes, local assembly resolution fallback, and retry behavior for transitive assembly resolution.

If you need diagnostic details in Windows PowerShell 5.1, run:

```powershell
Import-DPLibrary -ShowLoaderExceptions -Verbose
```

For detailed cmdlet guidance, see [docs/DLLPickle/Import-DPLibrary.md](docs/DLLPickle/Import-DPLibrary.md).

For deeper compatibility and dependency details, see [DEPENDENCIES.md](DEPENDENCIES.md).

---

## 📝 Additional Information

### Versioning

This project follows the semantic versioning model. It also packages numerous dependencies that follow their own versioning. To maintain clarity, this project will follow SemVer standards and the following logic for version changes:

#### Major Versions

🏷️ **2.x.x.x** - The major version will only change if there is a breaking change in the DLL Pickle project or if an MSAL dependency is released with a new major version (potentially indicating a breaking change).

#### Minor Versions

🏷️ **X.1.X.X** - The minor version will change if any of the following occur:

- New features are added to the project
- New MSAL library dependencies are added to the project
- A new version of any associated library (DLL) is automatically updated within the project

#### Build Versions

🏷️ **X.X.1.X** - The build version will change if any of the following occur:

- Minor refactoring for performance, error handling, or logging
- Minor fixes for typos or formatting

## External Documentation

All libraries tracked for pre-loading by DLL Pickle are maintained and documented by their own code owners. Please see each project accordingly:

- [Microsoft.Identity.Abstractions](https://www.nuget.org/packages/Microsoft.Identity.Abstractions)
- [Microsoft.Identity.Client](https://www.nuget.org/packages/Microsoft.Identity.Client)
- [Microsoft.IdentityModel.Abstractions](https://www.nuget.org/packages/Microsoft.IdentityModel.Abstractions)
- [Microsoft.IdentityModel.JsonWebTokens](https://www.nuget.org/packages/Microsoft.IdentityModel.JsonWebTokens)
- [Microsoft.IdentityModel.Logging](https://www.nuget.org/packages/Microsoft.IdentityModel.Logging)
- [Microsoft.IdentityModel.Tokens](https://www.nuget.org/packages/Microsoft.IdentityModel.Tokens)
- [System.IdentityModel.Tokens.Jwt](https://www.nuget.org/packages/System.IdentityModel.Tokens.Jwt)

## Project Documentation Map

- User guide and overview: [docs/index.md](docs/index.md)
- Deep technical explanation: [docs/Deep-Dive.md](docs/Deep-Dive.md)
- Full command reference: [docs/DLLPickle.md](docs/DLLPickle.md)
- Changelog and active work: [CHANGELOG.md](CHANGELOG.md)
- Planned work: [Roadmap.md](Roadmap.md)
- Contribution workflow: [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md)
- Dependency and supply chain policy: [DEPENDENCIES.md](DEPENDENCIES.md)
- Security vulnerability reporting: [SECURITY.md](SECURITY.md)
