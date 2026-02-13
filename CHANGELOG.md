<!-- markdownlint-disable MD024 -->
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.2.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

- Working on updates to replace PlatyPS documentation creation with the new Microsoft.PowerShell.PlatyPS module.

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

[Unreleased]: https://github.com/SamErde/DLLPickle/compare/latest...HEAD
[0.2.6]: https://github.com/SamErde/DLLPickle/tag/v0.2.6
[0.2.7]: https://github.com/SamErde/DLLPickle/tag/v0.2.7
[0.9.0]: https://github.com/SamErde/DLLPickle/tag/v0.9.0
