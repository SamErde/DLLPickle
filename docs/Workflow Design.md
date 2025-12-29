# Workflow Design

## Base Principles

- Require a PR for any changes to files/folders under the source directory (`./src/DLLPickle/*`).
- Follow [Conventional Commits](https://www.conventionalcommits.org/) guidelines for every commit message.
- Do not manually increment versions in the PowerShell module manifest (`./src/DLLPickle/DLLPickle.psd1`).

## Workflow Controls

### Concurrency and race-proofing

- **Concurrency**: Add concurrency keys per workflow (e.g., update-deps, release) to prevent overlapping runs and double-bumps when two PRs merge close together.
- **Single updater PR**: Ensure the daily job reuses a fixed branch (e.g., chore/update-packages) and force-push/rebase it; auto-close older PRs if any exist.

### Avoiding workflow loops

- **Skip tokens**: Use a standard token such as [skip-build] or [no-release] in commit messages and conditional if: guards in jobs to prevent the version-bump commit from re-triggering the release/publish steps.
Path filters: Keep strong paths includes/excludes to avoid artifact/doc-only pushes from triggering build/release.
- **Safer trigger**: Consider moving “version bump + release” to run on workflow_run (after checks) or on tag push instead of on push to main.

### Versioning strategy (pick ONE)

- **Tag-driven**: Create a tag (vX.Y.Z) derived from conventional commits at merge time, then build uses the tag to set the ModuleVersion without committing the .psd1 bump to main. This is clean and avoids a bump commit loop.
- **PR bump**: Have a bot open a short PR with the .psd1 bump before merging to main. This keeps main source-of-truth and avoids post-merge commits to main.

### PR pipeline hygiene

- **Labels by path**: Auto-label PRs based on changed paths (src/docs/workflows) to route checks/review.
- **Draft until ready**: Let the daily updater open PRs as draft until tests pass.
- **Auto-merge rules**: Optionally enable auto-merge for the updater PR when all checks pass.

---

# Steps / Triggers

## 1. Code Contributions

### (a) Scheduled Workflow: Update Monitored Packages

- Check nuget.org for new versions of tracked DLLs in **Packages.json**
- Update DLLs in ./src/DLLPickle/Lib

### (b) Work: Code Contributions

| Contribution Type | Path | Requirements |
| --- | --- | --- |
| Source Code: features, fixes, quality improvements | ./src | Pull Request |
| Documentation: additions, fixes, improvements | ./docs | |
| Repository: workflows, repository settings, metadata | Other | |

&nbsp;
---

### 2. Pull Requests

Actions may be triggered when pull requests are submitted or merged to specific branches (or all branches).

| Trigger | Branch | Details |
| --- | --- | --- |
| PR: On Submit | all | |
| PR: On Merge | main | |

> (placeholder)

&nbsp;
---
### 3. Commits

Actions may be triggered when a commit is pushed to any particular branch or path. (Triggered by merging a PR or by directly commiting to a branch.)

#### On `push` to **main**
| Condition | Action |
| --- | --- |
| all | Run code quality and security checks |
| if `path` in:<br />  ./src/\*\*,<br />  !./src/archive/\*\*,<br />!  ./src/artifacts/\*\*<br /><br />and `flag` not **DoNotReprocessPush** | **Trigger Build, Release, Publish Workflows**<br /><br />Increment version based on conventional commits<br />Update module manifest version with a commit message flag to prevent loop<br />Run `Build Module` workflow |

---

## 4: Workflow: Build, Release, Publish

This workflow (or series of workflows) will be triggered by the previous step that processes commits to the source if/after those commits pass required checks.

If any of these steps fail, the workflow should exit with a warning and detailed summary. (It may be helpful to provide a way to manually trigger any one of these steps during inevitable troubleshooting of this overarching workflow.)

- Build Module
- Check if a GitHub release and PSGallery release already exists with this version
- Update changelog with details from commit messages
- Create GitHub release with details from changelog as notes)
- Publish to PowerShell Gallery
- Provide a summary
