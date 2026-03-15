<!-- markdownlint-disable MD024 -->
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.2.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

- Working on updates to replace PlatyPS documentation creation with the new Microsoft.PowerShell.PlatyPS module.

### Added

- Deterministic dependency-aware DLL load ordering and scoped local assembly resolution fallback in `Import-DPLibrary` to reduce transient first-pass assembly load failures.
- Windows PowerShell 5.1 platform caveat guidance in README and cmdlet help.
- Built-module validation in Windows PowerShell 5.1 and integration test coverage for the `module/DLLPickle` output path.
- Focus VS Code tasks for refreshing the local module output and validating the built module in Windows PowerShell 5.1.

### Changed

- Replace manual DLL priority ordering in `Import-DPLibrary` with dependency-graph-based ordering and deterministic alphabetical fallback for unresolved graph nodes.
- Update `Import-DPLibrary` help to document load-order behavior and troubleshooting guidance.
- Expand dependency compatibility notes with .NET Framework 4.8 root-cause details and operational guidance.

### Fixed

- Enable net48 local copy of lock file assemblies in `DLLPickle.csproj` to improve transitive dependency availability during import.
- Harden module output refresh during builds so in-use binaries do not immediately break the prepare-and-validate workflow.

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

[Unreleased]: https://github.com/SamErde/DLLPickle/compare/v0.19.0...HEAD
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
