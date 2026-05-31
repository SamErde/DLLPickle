<!-- markdownlint-disable MD024 -->
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.2.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

- Working on updates to replace PlatyPS documentation creation with the new Microsoft.PowerShell.PlatyPS module. (PRs and other help would be welcomed!)

## [2.0.2] - 2026-05-31

### Fixed

- `Import-Module Az.Resources` (and other Az.* modules) failing with `Could not load file or assembly 'Microsoft.Extensions.DependencyInjection.Abstractions, Version=8.0.0.0 ...'. Assembly with same name is already loaded` after `Import-DPLibrary` (#193). DLLPickle was preloading the `Microsoft.Extensions.DependencyInjection.Abstractions` and `Microsoft.Extensions.Logging.Abstractions` BCL transitives (pulled by `Microsoft.IdentityModel.Tokens`) into the default load context, where they collided with the copies Az modules bundle. `Microsoft.IdentityModel.Tokens` still loads correctly without them preloaded.

### Removed

- `Microsoft.Extensions.DependencyInjection.Abstractions` and `Microsoft.Extensions.Logging.Abstractions` from the bundled preload set (via `ExcludeAssets="runtime"`). They are incidental transitives, not part of DLLPickle's identity-coordination purpose, and PowerShell does not host-provide them — so preloading DLLPickle's own copies only caused conflicts with consuming modules. The service modules that need them supply them at runtime.

## [2.0.1] - 2026-05-31

### Fixed

- `Connect-AzAccount` failing with `Method not found: '...Azure.Identity.InteractiveBrowserCredential.AuthenticateAsync(Azure.Core.TokenRequestContext, ...)'` after `Import-DPLibrary`. Az.Accounts 5.x isolates its Azure SDK stack in a private `AssemblyLoadContext`; preloading `Azure.Core` into the default load context split the identity of `Azure.Core.TokenRequestContext` across load contexts and broke Az's credential method binding. The `Azure.Core` preload was originally scoped to Windows PowerShell (net48) in #183 and was unintentionally promoted to the net8.0 preload during the 2.0.0 net48-removal refactor.

### Removed

- `Azure.Core` (and its `System.ClientModel` / `System.Memory.Data` / `Microsoft.Bcl.AsyncInterfaces` subgraph) from the bundled net8.0 preload set. Microsoft Graph, Exchange Online, and Teams resolve a compatible `Azure.Core` themselves on .NET 8, so the preload is unnecessary for them. Removing the dependency also retires the `Azure.Core` 1.50.0 cap, which existed only to keep that subgraph on the .NET 8 BCL.

### Internal

- Move `Azure.Core` to a report-only entry in `build/dependency-policy.json` and remove the now-moot Dependabot `Azure.Core` ignore.
- Rebase the #156 reproduction tests onto the still-active MSAL broker contract and add a regression guard asserting `Azure.Core` is not preloaded on the net8.0 profile.

## [2.0.0] - 2026-05-30

> **Breaking change:** DLLPickle 2.0 requires **PowerShell 7.4 or later** (running on .NET 8). Windows PowerShell 5.1 and .NET Framework 4.8 are not  supported yet on this major version.

### Added

- Deterministic dependency-aware DLL load ordering and scoped local assembly resolution fallback in `Import-DPLibrary` to reduce transient first-pass assembly load failures.
- PowerShell 7.4+ runtime baseline and net8.0-only dependency pipeline.

### Changed

- Replace manual DLL priority ordering in `Import-DPLibrary` with dependency-graph-based ordering and deterministic alphabetical fallback for unresolved graph nodes.
- Make runtime assembly detection lazy in `Import-DPLibrary` to avoid unnecessary work during import.
- Update `Import-DPLibrary` help to document load-order behavior and troubleshooting guidance for the PowerShell 7.4+ baseline.
- Simplify the build/test/workflow matrix and module metadata to remove Desktop/.NET Framework compatibility paths.

### Fixed

- Cap `Azure.Core` at 1.50.0 to keep the bundled dependency graph on the .NET 8 BCL. Azure.Core 1.51.0+ takes a dependency on the .NET 10 BCL (`System.Text.Json` / `System.Diagnostics.DiagnosticSource` / `Microsoft.Bcl.AsyncInterfaces` 10.x), which fails to load under PowerShell 7.4 (.NET 8).
- Harden module output refresh during builds so in-use binaries do not immediately break the prepare-and-validate workflow.

### Removed

- **Windows PowerShell 5.1 and .NET Framework (net48) support** — including the associated dependencies, conditional branching, validation tasks, and CI workflow paths.

### Dependencies

- Update `Microsoft.Identity.Client`, `Microsoft.Identity.Client.Broker`, and `Microsoft.Identity.Client.Extensions.Msal` to 4.84.1, and `Microsoft.Identity.Client.NativeInterop` to 0.20.6.
- Pin `Azure.Core` to 1.50.0 (capped for the PowerShell 7.4 / .NET 8 baseline — see Fixed).
- Refresh upstream compatibility dependency pins.

### Internal

- Move releases to a tag-driven versioning pipeline: the published version is derived from the Git tag and stamped into the build artifact, nothing is committed to `main`, and a failed release rolls back by deleting only the tag and GitHub release.
- Pin the .NET SDK to 8.0.x via `global.json` and install it explicitly in the build workflow.
- Harden the Dependabot auto-approve workflow (least-privilege GitHub App token, Dependabot-scoped secrets), group and schedule NuGet updates, and ignore `Azure.Core` updates that would cross the .NET 8 baseline.
- Remove the release GitHub App from the branch-protection bypass list.

## [1.3.1] - 2026-05-08

### Added

- Base profile preload helper supporting `Import-DPBaseProfile`.

### Fixed

- Surface base profile preload errors instead of failing silently.

### Dependencies

- Bump `Azure.Core` from 1.51.1 to 1.55.0 (#185).

## [1.3.0] - 2026-05-06

### Fixed

- Resolve a Microsoft Graph / `Azure.Core` assembly preload conflict (#183).

### Internal

- Improve the Dependabot workflow and add supporting documentation (#178); update the GitHub App token action and its identifier (#176).

## [1.2.0] - 2026-04-12

### Added

- Bundle MSAL (`Microsoft.Identity.Client`) packages and update the .NET restore strategy (#170).

### Changed

- Refine project documentation (#167).

### Security

- Workflow hardening: move permissions to the job level and add the `security-events` permission (#171); cross-platform security and validation improvements (#166).

## [1.1.2] - 2026-03-23

### Fixed

- Fix library import on Windows PowerShell 5.1 (#165), reverting the 1.1.1 `Resolve-DPDLLLoadOrder` refactor (#163) that introduced the regression.

## [1.1.1] - 2026-03-15

### Changed

- Streamline conditional logic in `Resolve-DPDLLLoadOrder` (#160). _(Reverted in 1.1.2 — it caused a Windows PowerShell 5.1 import regression.)_

## [1.1.0] - 2026-03-15

### Added

- Windows PowerShell 5.1 compatibility handling for `Import-DPLibrary` (#157).

## [1.0.0] - 2026-03-09

First stable release.

### Changed

- Documentation updates (#155).

## [0.19.0] - 2026-03-09

### Added

- Implement DLL Pickle settings functionality for configuration management
- Enhanced metadata handling in module operations

### Changed

- Removed `SkipProblematicAssemblies` parameter in favor of settings-based configuration
- Workflow hardening improvements including daily Dependabot runs and pinned GitHub app token

## [0.18.0] - 2026-03-03

### Added

- Retry logic for handling module dependencies in `Import-DPLibrary`

### Changed

- Updated `Import-DPLibrary` function with improved dependency handling and resilience

### Fixed

- Pinned checkout action to SHA of v4.2.2 for improved security

## [0.17.0] - 2026-02-23

### Fixed

- Added version sync step to module release workflow to prevent version mismatch issues

## [0.16.0] - 2026-02-22

### Changed

- CI/CD workflow and supply chain improvements for better build reliability

## [0.15.0] - 2026-02-16

### Added

- Binary files now included in module path for improved .NET assembly management

### Changed

- Enhanced Codacy workflow to support multiple analysis tools with unique SARIF outputs
- Updated documentation in README and Roadmap

## [0.10.2] - 2026-02-13

### Fixed

- Fixed module path variable in publish script
- Corrected path to publish script in release workflow

## [0.10.1] - 2026-02-13

### Changed

- Commented out local development imports in PSM1 for cleaner module loading

### Fixed

- Updated workflow permissions to enable GitHub release creation

## [0.10.0] - 2026-02-13

### Changed

- Transitioned to automated release workflow with improved version management

## [0.9.0]

This release contains major refactoring that brings it very close to a true 1.0 release!

### Changed

- Updates to multiple packaged DLLs since the last release.
- Replace `packages.json` with true dependency tracking in `DLLPickle.csproj` and `packages.lock.json`.
- Refactor the structure of the project to separate module source, dependency tracking, build artifacts, and build script.
- Replace manually codified dependency update workflow with Dependabot workflow(s).
- Improve the structural resiliency of the build script and build workflow.
- Improve repository configuration and project metadata file quality.
- Refactor and harden the dev container and docker container.

### Added

- Add proper support for TFM (target framework moniker) handling based on the PowerShell edition being used by the host.
- Add full support for Windows PowerShell 5.1 (.net48) and PowerShell 7.4+ (.net8).
- Add .NET restore, build, and test tasks to the project.

### Security

- Harden workflows with least privilege permissions and token configuration.
- Implement GitHub app for Dependabot updates that require automatic approval and merging.

## [0.2.7]

### Added

Microsoft.IdentityModel.Logging: 0.0.0 → 8.14.0; Microsoft.IdentityModel.Tokens: 0.0.0 → 8.14.0

This release includes new packages related to the Microsoft Identity libraries.

Full Changelog: [v0.2.6...v0.2.7](https://github.com/SamErde/DLLPickle/compare/v0.2.6...v0.2.7)

## [0.2.6]

### Added

Microsoft.Identity.Abstractions: 0.0.0 → 9.5.0
Microsoft.IdentityModel.Abstractions: 0.0.0 → 8.14.0
Microsoft.IdentityModel.JsonWebTokens: 0.0.0 → 8.14.0
System.IdentityModel.Tokens.Jwt: 0.0.0 → 8.14.0

This release includes new packages related to the Microsoft Identity libraries.

Full Changelog: [v0.2.5...v0.2.6](https://github.com/SamErde/DLLPickle/compare/v0.2.1...v0.2.6)

- Initial release.

[Unreleased]: https://github.com/SamErde/DLLPickle/compare/v2.0.2...HEAD
[2.0.2]: https://github.com/SamErde/DLLPickle/tag/v2.0.2
[2.0.1]: https://github.com/SamErde/DLLPickle/tag/v2.0.1
[2.0.0]: https://github.com/SamErde/DLLPickle/tag/v2.0.0
[1.3.1]: https://github.com/SamErde/DLLPickle/tag/v1.3.1
[1.3.0]: https://github.com/SamErde/DLLPickle/tag/v1.3.0
[1.2.0]: https://github.com/SamErde/DLLPickle/tag/v1.2.0
[1.1.2]: https://github.com/SamErde/DLLPickle/tag/v1.1.2
[1.1.1]: https://github.com/SamErde/DLLPickle/tag/v1.1.1
[1.1.0]: https://github.com/SamErde/DLLPickle/tag/v1.1.0
[1.0.0]: https://github.com/SamErde/DLLPickle/tag/v1.0.0
[0.19.0]: https://github.com/SamErde/DLLPickle/tag/v0.19.0
[0.18.0]: https://github.com/SamErde/DLLPickle/tag/v0.18.0
[0.17.0]: https://github.com/SamErde/DLLPickle/tag/v0.17.0
[0.16.0]: https://github.com/SamErde/DLLPickle/tag/v0.16.0
[0.15.0]: https://github.com/SamErde/DLLPickle/tag/v0.15.0
[0.10.2]: https://github.com/SamErde/DLLPickle/tag/v0.10.2
[0.10.1]: https://github.com/SamErde/DLLPickle/tag/v0.10.1
[0.10.0]: https://github.com/SamErde/DLLPickle/tag/v0.10.0
[0.9.0]: https://github.com/SamErde/DLLPickle/tag/v0.9.0
[0.2.7]: https://github.com/SamErde/DLLPickle/tag/v0.2.7
[0.2.6]: https://github.com/SamErde/DLLPickle/tag/v0.2.6
