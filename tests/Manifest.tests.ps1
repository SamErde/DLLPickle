BeforeAll {

    # NEW: Pre-Specify RegEx Matching Patterns
    $GitTagMatchRegex        = 'tag:\s?.(\d+(\.\d+)*)' # NOTE - was 'tag:\s*(\d+(?:\.\d+)*)' previously
    $ChangelogTagMatchRegex  = "^##\s\[(?<Version>(\d+\.){1,3}\d+)\]"

    $ModuleName         = $env:BHProjectName
    $Manifest           = Import-PowerShellDataFile -Path $env:BHPSModuleManifest
    $OutputDir          = Join-Path -Path $ENV:BHProjectPath -ChildPath 'Output'
    $OutputModDir       = Join-Path -Path $OutputDir -ChildPath $env:BHProjectName
    $OutputModVerDir    = Join-Path -Path $OutputModDir -ChildPath $Manifest.ModuleVersion
    $OutputManifestPath = Join-Path -Path $OutputModVerDir -Child "$($ModuleName).psd1"
    $ManifestData       = Test-ModuleManifest -Path $OutputManifestPath -Verbose:$false -ErrorAction Stop -WarningAction SilentlyContinue

    $ChangelogPath    = Join-Path -Path $env:BHProjectPath -Child 'CHANGELOG.md'
    $ChangelogVersion = Get-Content $ChangelogPath | ForEach-Object {
        if ($_ -match $ChangelogTagMatchRegex) {
            $ChangelogVersion = $matches.Version
            break
        }
    }

    $script:Manifest    = $null
}
Describe 'Module manifest' {

    Context 'Validation' {

        It 'Has a valid manifest' {
            $ManifestData | Should -Not -BeNullOrEmpty
        }

        It 'Has a valid name in the manifest' {
            $ManifestData.Name | Should -Be $ModuleName
        }

        It 'Has a valid root module' {
            $ManifestData.RootModule | Should -Be "$($ModuleName).psm1"
        }

        It 'Has a valid version in the manifest' {
            $ManifestData.Version -as [Version] | Should -Not -BeNullOrEmpty
        }

        It 'Has a valid description' {
            $ManifestData.Description | Should -Not -BeNullOrEmpty
        }

        It 'Has a valid author' {
            $ManifestData.Author | Should -Not -BeNullOrEmpty
        }

        It 'Has a valid guid' {
            {[guid]::Parse($ManifestData.Guid)} | Should -Not -Throw
        }

        It 'Has a valid copyright' {
            $ManifestData.CopyRight | Should -Not -BeNullOrEmpty
        }

        It 'Has a valid version in the changelog' {
            $ChangelogVersion               | Should -Not -BeNullOrEmpty
            $ChangelogVersion -as [Version] | Should -Not -BeNullOrEmpty
        }

        It 'Changelog and manifest versions are the same' {
            $ChangelogVersion -as [Version] | Should -Be ( $ManifestData.Version -as [Version] )
        }
    }
}

Describe 'Git tagging' -Skip {
    BeforeAll {
        $gitTagVersion = $null

        # Ensure to only pull in a single git executable (in case multiple git's are found on path).
        if ($git = (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)[0]) {
            $thisCommit = & $git log --decorate --oneline HEAD~1..HEAD
            if ($thisCommit -match $gitTagMatchRegEx) { $gitTagVersion = $matches[1] }
        }
    }

    It 'Is tagged with a valid version' {
        $gitTagVersion               | Should -Not -BeNullOrEmpty
        $gitTagVersion -as [Version] | Should -Not -BeNullOrEmpty
    }

    It 'Matches manifest version' {
        $manifestData.Version -as [Version] | Should -Be ( $gitTagVersion -as [Version])
    }
}
