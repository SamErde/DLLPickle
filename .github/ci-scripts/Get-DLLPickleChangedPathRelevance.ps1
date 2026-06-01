<#
.SYNOPSIS
    Reports whether a pull request changed any path relevant to a CI gate, writing
    "relevant=true|false" to $env:GITHUB_OUTPUT.
.DESCRIPTION
    Single source of the merge-gate change-detection used by the always-triggered gate workflows
    (Build Module, Upstream-Compatibility) so the required-check skip logic cannot drift between them.

    Enumerates the PR's changed files via the PAGINATED REST endpoint (gh pr view --json files caps at
    100 files) and includes previous_filename so a rename that moves a tracked file OUT of a matched
    tree is still detected. Matching is case-sensitive regex against each path.

    Fail-safe: any error enumerating files - including a native gh non-zero exit, which pwsh does not
    reliably surface as a terminating error - defaults to relevant=true, so a required-check gate runs
    its validation rather than silently skipping on a transient/permission failure.
.PARAMETER Repository
    The owner/repo slug (e.g. SamErde/DLLPickle).
.PARAMETER PullNumber
    The pull request number.
.PARAMETER Pattern
    One or more regex patterns matched against each changed (and previous) file path.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'CI script: emits GitHub Actions log lines and ::warning:: annotations to stdout by design.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Repository,

    [Parameter(Mandatory)]
    [int]$PullNumber,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Pattern
)

$Relevant = $true
try {
    $ErrorActionPreference = 'Stop'
    $Files = gh api "repos/$Repository/pulls/$PullNumber/files" --paginate --jq '.[] | .filename, (.previous_filename // empty)'
    if ($LASTEXITCODE -ne 0) {
        throw "gh api exited $LASTEXITCODE while listing PR files"
    }

    $Relevant = $false
    foreach ($File in $Files) {
        foreach ($Expression in $Pattern) {
            if ($File -match $Expression) {
                $Relevant = $true
                break
            }
        }
        if ($Relevant) {
            break
        }
    }
} catch {
    Write-Host "::warning::Changed-file detection failed; defaulting to relevant=true (fail-safe). $_"
    $Relevant = $true
}

$RelevantValue = $Relevant.ToString().ToLowerInvariant()
if ($env:GITHUB_OUTPUT) {
    "relevant=$RelevantValue" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
}
Write-Host "Change relevance: $RelevantValue"
