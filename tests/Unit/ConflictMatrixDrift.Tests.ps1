BeforeAll {
    $ScriptPath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'tools\Compare-DLLPickleConflictMatrix.ps1'

    function Get-DriftRow { param($Name, $Diverges, $Alc = 'Default')
        [PSCustomObject]@{ Name = $Name; Diverges = $Diverges; AlcOwner = $Alc }
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
}
