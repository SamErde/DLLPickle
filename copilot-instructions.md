# Repository-Specific Copilot Additions

Use the custom instruction files under `.github/instructions/` for PowerShell,
Markdown, testing, and other general guidance. This file only keeps repo-level
instructions that are not already covered there or implicit in the agent
runtime.

## Additional Project Expectations

- Include unit tests for all new functions.

## PowerShell Commit Message Template

Generate commit messages for PowerShell projects using this format:

`<type>[optional scope]: <description>`

Tailor commit messages for PowerShell development, using the provided types and
scopes.

### PowerShell-Specific Commit Types

- `feat`: New cmdlet, function, or module feature
- `fix`: Bug fix in PowerShell code
- `docs`: Help documentation, comment-based help
- `style`: Code formatting, OTBS compliance, Pascal case fixes
- `refactor`: Code restructuring, approved verb compliance
- `test`: Pester tests, unit tests
- `build`: Module manifest, build scripts
- `ci`: Azure DevOps, GitHub Actions for PowerShell
- `chore`: Module organization, file cleanup
- `perf`: Performance improvements in cmdlets or functions
- `revert`: Reverting changes in PowerShell scripts or modules
- `packaging`: Packaging and module manifest metadata changes (ModuleVersion is
  stamped from the Git tag at release time, not committed)
- `security`: Security-related changes, input validation, authentication

### PowerShell Commit Scopes

- `module`: Module-level changes
- `cmdlet`: Specific cmdlet modifications
- `function`: Function updates
- `help`: Documentation changes
- `manifest`: Module manifest updates
- `tests`: Test-related changes

### Example Commit Messages

- `feat(cmdlet): add Get-UserProfile with parameter validation`
- `fix(function): resolve Invoke-ApiCall error handling`
- `docs(help): update comment-based help for Set-Configuration`
- `style(module): apply OTBS formatting and Pascal case`
- `test(cmdlet): add Pester tests for Get-SystemInfo`
