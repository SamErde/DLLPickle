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

PowerShell 7.4 or later on Linux, macOS, or Windows.

### Installation

```powershell
Install-Module DLLPickle -Scope CurrentUser
```

Or, with **Microsoft.PowerShell.PSResourceGet**:

```powershell
Install-PSResource -Name DLLPickle
```

### Using

Import DLL Pickle and run `Import-DPLibrary` **before** connecting to other service modules — ideally as the first thing in your PowerShell profile, so it loads first in every session.

```powershell
Import-Module DLLPickle
Import-DPLibrary
```

For diagnostic detail, add `-ShowLoaderExceptions -Verbose`.

### Commands

**Primary:**

- `Import-DPLibrary` — preload DLLPickle-managed assemblies in dependency-aware order.
- `Import-DPBaseProfile` — preload, then import the validated base-profile modules (Exchange Online, Teams, Graph, Az.Accounts) in a known-good order.
- `Test-DPLibraryConflict` — report known-incompatible module pairs loaded in the current session, with the workaround.
- `Get-DPConfig` / `Set-DPConfig` — view or change configuration (for example, show logo, skip libraries).

**Inspection helpers:**

- `Find-DLLInPSModulePath` — find DLLs across module paths, filtered by product metadata.
- `Get-ModuleImportCandidate` — show which installed module version would import.
- `Get-ModulesWithDependency` — list installed modules that package a given dependency.
- `Get-ModulesWithVersionSortedIdentityClient` — compare modules by packaged `Microsoft.Identity.Client.dll` version.

Full syntax and examples: [docs index](docs/index.md) · [command reference](docs/DLLPickle.md).

## 🥒 How It Works

Many PowerShell modules — Az, Exchange Online, Microsoft Graph, Teams, and more — bundle their own copy of the Microsoft Authentication Library (MSAL) and related DLLs. A single PowerShell session can only load **one** version of a given DLL, so when two modules ship different versions you hit *"an assembly with the same name is already loaded"* and authentication breaks.

DLL Pickle preloads a current, compatible set of these assemblies **first**, so the "first one wins" rule works in your favor and the modules you load afterward reuse what's already there. A new DLL Pickle release is published automatically whenever a new MSAL version ships — so keep it updated and load it first.

For the full explanation (and the real-world issues that motivated it), read the [Deep Dive](docs/Deep-Dive.md). The supported platform is **PowerShell 7.4+ (Core, net8.0)**; compatibility, versioning, and dependency details live in [DEPENDENCIES.md](DEPENDENCIES.md).

## 📚 Documentation Map

- User guide and overview: [docs/index.md](docs/index.md)
- Deep technical explanation: [docs/Deep-Dive.md](docs/Deep-Dive.md)
- Troubleshooting and issue reproduction: [docs/Troubleshooting.md](docs/Troubleshooting.md)
- Full command reference: [docs/DLLPickle.md](docs/DLLPickle.md)
- Changelog and active work: [CHANGELOG.md](CHANGELOG.md)
- Architecture blueprint and planned enhancements: [docs/Architecture.md](docs/Architecture.md)
- Dependency, versioning, and supply-chain policy: [DEPENDENCIES.md](DEPENDENCIES.md)
- Contribution workflow: [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md)
- Security vulnerability reporting: [SECURITY.md](SECURITY.md)
