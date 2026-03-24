<!-- markdownlint-configure-file { "MD012": false } -->
<!--- Provide a general summary of your changes in the Title above -->
# Pull Request

## Description
<!-- Please include a clear description of what your pull request does.
Remember to only include one change (or group of tightly related changes)
per pull request to make review and testing easier. -->



## Type of Change

- [ ] 📖 Documentation
- [ ] 🪲 Fix
- [ ] 🩹 Patch
- [ ] ⚠️ Security Fix
- [ ] 🚀 Feature
- [ ] 💥 Breaking Change

## Issue Resolved
<!-- If this PR resolves an issue, enter the issue number here. -->



## Automated Checks

The following checks run automatically and must pass before this PR can be merged:

- **Build Module** — matrix across Windows, Linux, and macOS; runs PSScriptAnalyzer (default rules + OTBS formatting + PS 5.1 compatibility), Pester unit tests (≥30% coverage), and full module build
- **Dependency Review** — blocks PRs introducing dependencies with known vulnerabilities (moderate severity or higher)
- **Validate .NET Packages** — NuGet lock file is enforced; resolved packages must match `packages.lock.json`

## Checklist

- [ ] I have reviewed my code for errors and tested it.
- [ ] My pull request does not contain multiple types of changes.
- [ ] My code follows the code style of this project.
- [ ] I have updated the documentation as necessary.
- [ ] I have read the **CONTRIBUTING** document.

### Testing

If possible, we kindly ask that Pester tests be added for any new or changed functionality.

- [ ] I have added tests to cover my changes.
- [ ] All new and existing tests passed.
