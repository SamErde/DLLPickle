# How to Contribute

Contributions to DLLPickle are welcome. This guide explains the local workflow,
quality checks, and pull request expectations used in this repository.

## Getting Started

1. Create or find an issue describing the bug or enhancement.
1. Fork the repository.
1. Create a feature branch from `main`:

```powershell
git checkout -b feature/my-change main
```

Avoid working directly on `main`.

## Local Development Workflow

### Prerequisites

- PowerShell 7+ recommended for development
- Windows PowerShell 5.1 for compatibility validation
- Required modules/tools installed by build prerequisites

### Common Tasks

Run these via VS Code Tasks or directly with `Invoke-Build`.

- `ValidateRequirements`: verify local environment requirements.
- `TestLocal`: fast validation loop (`Clean`, `ImportModuleManifest`, `Analyze`, `Test`).
- `Test`: run full unit test pass with coverage output.
- `Build`: full validation and packaging workflow.
- `BuildNoIntegration`: full build without integration tests.
- `BuildCrossPlatform`: full build without help generation or integration tests.
- `ValidateBuiltModuleWinPS`: validate built module output in Windows PowerShell 5.1.

Example local loop:

```powershell
Invoke-Build -Task TestLocal
```

### Code Quality Gates

The build enforces:

- PSScriptAnalyzer checks for source and tests.
- OTBS formatting checks.
- Pester tests.
- Coverage threshold (currently 30%).

Before opening a PR, run:

```powershell
Invoke-Build -Task Build
```

If your changes affect compatibility behavior, also run:

```powershell
Invoke-Build -Task ValidateWindowsPowerShellModuleOutput
```

## Documentation Contributions

Documentation updates are encouraged, especially when behavior or command
surfaces change. Keep command reference pages in `docs/DLLPickle` aligned with
the module manifest exports.

## Submitting Changes

1. Push your feature branch to your fork.
1. Open a pull request targeting `main`.
1. Include a concise description, test evidence, and any relevant docs updates.
1. Address review feedback and keep CI green.

## Additional Resources

- [Project README](../README.md)
- [Dependency policy](../DEPENDENCIES.md)
- [Security policy](../SECURITY.md)
