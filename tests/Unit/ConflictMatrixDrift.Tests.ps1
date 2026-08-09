BeforeAll {
    $ScriptPath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'tools\Compare-DLLPickleConflictMatrix.ps1'

    function Get-DriftRow {
        param(
            $Name,
            $Diverges,
            $Alc = 'Default',
            $Versions = @(),
            $ShippedBy = @(),
            $Hashes = @(),
            $AlcOwners = @($Alc)
        )

        [PSCustomObject]@{
            Name       = $Name
            Diverges   = $Diverges
            AlcOwner   = $Alc
            AlcOwners  = @($AlcOwners)
            Versions   = @($Versions)
            ShippedBy  = @($ShippedBy)
            Hashes     = @($Hashes)
        }
    }
    function Get-DriftMatrix { param($Rows) [PSCustomObject]@{ Assemblies = @($Rows) } }
}

Describe 'Compare-DLLPickleConflictMatrix' -Tag 'Unit' {
    It 'reports no material drift when the conflict surface is unchanged' {
        $b = Get-DriftMatrix @( Get-DriftRow 'Azure.Core' $true )
        $c = Get-DriftMatrix @( Get-DriftRow 'Azure.Core' $true )
        (& $ScriptPath -Baseline $b -Current $c).HasMaterialDrift | Should -BeFalse
    }

    It 'flags a newly diverging assembly' {
        $b = Get-DriftMatrix @( Get-DriftRow 'Azure.Core' $true )
        $c = Get-DriftMatrix @( (Get-DriftRow 'Azure.Core' $true), (Get-DriftRow 'Newtonsoft.Json' $true) )
        $r = & $ScriptPath -Baseline $b -Current $c
        $r.HasMaterialDrift | Should -BeTrue
        $r.Findings.NewConflicts | Should -Contain 'Newtonsoft.Json'
    }

    It 'flags an ALC-ownership change' {
        $b = Get-DriftMatrix @( Get-DriftRow 'Azure.Core' $true 'Default' )
        $c = Get-DriftMatrix @( Get-DriftRow 'Azure.Core' $true 'AzSharedAssemblyLoadContext' )
        $r = & $ScriptPath -Baseline $b -Current $c
        $r.HasMaterialDrift | Should -BeTrue
        $r.Findings.AlcOwnershipChanges | Should -Contain 'Azure.Core'
    }

    It 'flags a selected-hash change even when the assembly is not version-divergent' {
        $b = Get-DriftMatrix @(
            Get-DriftRow 'Microsoft.Identity.Client' $false 'Default' @('4.84.1.0') @('Az.Accounts') @('aaaa')
        )
        $c = Get-DriftMatrix @(
            Get-DriftRow 'Microsoft.Identity.Client' $false 'Default' @('4.84.1.0') @('Az.Accounts') @('bbbb')
        )

        $r = & $ScriptPath -Baseline $b -Current $c

        $r.HasMaterialDrift | Should -BeTrue
        $r.Findings.HashChanges | Should -HaveCount 1
        $r.Findings.HashChanges[0].Name | Should -Be 'Microsoft.Identity.Client'
        @($r.Findings.HashChanges[0].Baseline) | Should -Be @('aaaa')
        @($r.Findings.HashChanges[0].Current) | Should -Be @('bbbb')
    }

    It 'flags added and removed tracked assemblies outside the version-conflict surface' {
        $b = Get-DriftMatrix @(
            Get-DriftRow 'Microsoft.Identity.Client' $false
            Get-DriftRow 'Azure.Core' $false
        )
        $c = Get-DriftMatrix @(
            Get-DriftRow 'Microsoft.Identity.Client' $false
            Get-DriftRow 'System.ClientModel' $false
        )

        $r = & $ScriptPath -Baseline $b -Current $c

        $r.HasMaterialDrift | Should -BeTrue
        $r.Findings.NewTrackedAssemblies | Should -Contain 'System.ClientModel'
        $r.Findings.RemovedTrackedAssemblies | Should -Contain 'Azure.Core'
    }

    It 'flags a version-set change with structured before and after values' {
        $b = Get-DriftMatrix @(Get-DriftRow 'Azure.Core' $true 'Default' @('1.50.0.0', '1.51.1.0') @('Az.Accounts', 'Microsoft.Graph.Authentication'))
        $c = Get-DriftMatrix @(Get-DriftRow 'Azure.Core' $true 'Default' @('1.51.1.0', '1.52.0.0') @('Az.Accounts', 'Microsoft.Graph.Authentication'))

        $r = & $ScriptPath -Baseline $b -Current $c

        $r.HasMaterialDrift | Should -BeTrue
        $r.Findings.VersionChanges | Should -HaveCount 1
        $r.Findings.VersionChanges[0].Name | Should -Be 'Azure.Core'
        @($r.Findings.VersionChanges[0].Baseline) | Should -Be @('1.50.0.0', '1.51.1.0')
        @($r.Findings.VersionChanges[0].Current) | Should -Be @('1.51.1.0', '1.52.0.0')
    }

    It 'flags a contributor-set change with structured before and after values' {
        $b = Get-DriftMatrix @(Get-DriftRow 'Azure.Core' $true 'Default' @('1.50.0.0', '1.51.1.0') @('Az.Accounts', 'Microsoft.Graph.Authentication'))
        $c = Get-DriftMatrix @(Get-DriftRow 'Azure.Core' $true 'Default' @('1.50.0.0', '1.51.1.0') @('Az.Accounts', 'MicrosoftTeams'))

        $r = & $ScriptPath -Baseline $b -Current $c

        $r.HasMaterialDrift | Should -BeTrue
        $r.Findings.ContributorChanges | Should -HaveCount 1
        $r.Findings.ContributorChanges[0].Name | Should -Be 'Azure.Core'
        @($r.Findings.ContributorChanges[0].Baseline) | Should -Be @('Az.Accounts', 'Microsoft.Graph.Authentication')
        @($r.Findings.ContributorChanges[0].Current) | Should -Be @('Az.Accounts', 'MicrosoftTeams')
    }

    It 'treats a removed conflict as material drift' {
        $b = Get-DriftMatrix @((Get-DriftRow 'Azure.Core' $true), (Get-DriftRow 'Microsoft.OData.Core' $true))
        $c = Get-DriftMatrix @(Get-DriftRow 'Azure.Core' $true)

        $r = & $ScriptPath -Baseline $b -Current $c

        $r.HasMaterialDrift | Should -BeTrue
        $r.Findings.RemovedConflicts | Should -Contain 'Microsoft.OData.Core'
    }

    It 'emits a stable finding fingerprint for report deduplication' {
        $b = Get-DriftMatrix @(Get-DriftRow 'Azure.Core' $true 'Default' @('1.50.0.0') @('Az.Accounts'))
        $c = Get-DriftMatrix @(Get-DriftRow 'Azure.Core' $true 'Default' @('1.51.0.0') @('Az.Accounts'))

        $first = & $ScriptPath -Baseline $b -Current $c
        $second = & $ScriptPath -Baseline $b -Current $c

        $first.FindingFingerprint | Should -Match '^[a-f0-9]{64}$'
        $first.FindingFingerprint | Should -BeExactly $second.FindingFingerprint
    }

    It 'rejects comparisons across different runtime profiles' {
        $b = Get-DriftMatrix @(Get-DriftRow 'Azure.Core' $true)
        $b | Add-Member -NotePropertyName ProfileKey -NotePropertyValue 'ps7.4-net8.0-windows-x64'
        $c = Get-DriftMatrix @(Get-DriftRow 'Azure.Core' $true)
        $c | Add-Member -NotePropertyName ProfileKey -NotePropertyValue 'ps7.5-net9.0-windows-x64'

        { & $ScriptPath -Baseline $b -Current $c } | Should -Throw '*different runtime profiles*'
    }
}
