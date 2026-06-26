BeforeDiscovery {
    $gapProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $gapDirectory = Join-Path $gapProjectRoot 'docs\gaps'

    function Get-GapFrontmatterField {
        param(
            [string] $Frontmatter,
            [string] $Field
        )

        $fieldMatch = [regex]::Match($Frontmatter, "(?m)^$([regex]::Escape($Field)):\s*(.*)$")
        if (-not $fieldMatch.Success) {
            return $null
        }

        return $fieldMatch.Groups[1].Value.Trim()
    }

    # Parse every gap file's frontmatter once at discovery so -ForEach can fan out per gap.
    $GapFiles = @(
        Get-ChildItem -LiteralPath $gapDirectory -Filter 'GAP-*.md' -File |
            Sort-Object -Property Name |
            ForEach-Object {
                $content = Get-Content -LiteralPath $_.FullName -Raw
                $frontmatterMatch = [regex]::Match($content, '(?s)^---\s*\r?\n(.*?)\r?\n---')
                $frontmatter = if ($frontmatterMatch.Success) { $frontmatterMatch.Groups[1].Value } else { '' }

                # Emit a hashtable so Pester's -ForEach expands keys into per-test variables.
                @{
                    Name         = $_.Name
                    Id           = Get-GapFrontmatterField -Frontmatter $frontmatter -Field 'id'
                    Status       = Get-GapFrontmatterField -Frontmatter $frontmatter -Field 'status'
                    ResolutionPr = Get-GapFrontmatterField -Frontmatter $frontmatter -Field 'resolution_pr'
                    ResolvedOn   = Get-GapFrontmatterField -Frontmatter $frontmatter -Field 'resolved_on'
                }
            }
    )

    $ResolvedGapFiles = @($GapFiles | Where-Object { $_.Status -eq 'resolved' })
}

BeforeAll {
    $projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $indexPath = Join-Path $projectRoot 'docs\gaps\README.md'

    # Status values must stay in sync with the status table in docs/gaps/README.md.
    $script:AllowedGapStatuses = @('open', 'in-progress', 'blocked', 'resolved', 'superseded', 'wont-fix')

    # Parse the index table rows (| GAP-### | status | ... |) into a lookup.
    $indexContent = Get-Content -LiteralPath $indexPath -Raw
    $script:GapIndexRows = @{}
    foreach ($line in ($indexContent -split '\r?\n')) {
        $rowMatch = [regex]::Match($line, '^\|\s*(GAP-\d+)\s*\|\s*([^|]+?)\s*\|')
        if ($rowMatch.Success) {
            $script:GapIndexRows[$rowMatch.Groups[1].Value] = $rowMatch.Groups[2].Value.Trim()
        }
    }
}

Describe 'Gap register consistency' -Tag 'Unit' {
    Context 'Frontmatter for <Name>' -ForEach $GapFiles {
        It 'declares an id that matches its file name' {
            $Id | Should -Not -BeNullOrEmpty
            $Name | Should -BeLike "$Id-*"
        }

        It 'uses an allowed status value' {
            $Status | Should -BeIn $script:AllowedGapStatuses
        }

        It 'appears as a row in the gap index' {
            # Assert the id is present first so a missing-id gap fails with an actionable message
            # instead of ContainsKey($null) throwing an ArgumentNullException.
            $Id | Should -Not -BeNullOrEmpty -Because 'a gap file without an id cannot be matched to an index row'
            $script:GapIndexRows.ContainsKey($Id) | Should -BeTrue
        }

        It 'has an index status matching its frontmatter status' {
            # Guard both lookup inputs so a missing id/status reports the real defect rather than
            # silently comparing $null index values.
            $Id | Should -Not -BeNullOrEmpty -Because 'a gap file without an id cannot be looked up in the index'
            $Status | Should -Not -BeNullOrEmpty -Because 'the index status comparison needs a frontmatter status'
            $script:GapIndexRows[$Id] | Should -Be $Status
        }
    }

    Context 'Resolved gap <Name>' -ForEach $ResolvedGapFiles {
        It 'records a resolution_pr' {
            $ResolutionPr | Should -Not -BeNullOrEmpty
        }

        It 'records a resolved_on date' {
            $ResolvedOn | Should -Not -BeNullOrEmpty
        }
    }
}
