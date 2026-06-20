BeforeAll {
    $ScriptPath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'tools\Compare-DLLPickleConflictMatrix.ps1'

    function Get-DriftRow {
        param(
            $Name,
            $Diverges,
            $Alc = 'Default',
            $Versions = @(),
            $ShippedBy = @()
        )

        [PSCustomObject]@{
            Name      = $Name
            Diverges  = $Diverges
            AlcOwner  = $Alc
            Versions  = @($Versions)
            ShippedBy = @($ShippedBy)
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
}
