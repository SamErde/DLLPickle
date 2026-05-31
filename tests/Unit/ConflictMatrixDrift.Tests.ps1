BeforeAll {
    $ScriptPath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'tools\Compare-DLLPickleConflictMatrix.ps1'

    function New-Row { param($Name, $Diverges, $Alc = 'Default')
        [PSCustomObject]@{ Name = $Name; Diverges = $Diverges; AlcOwner = $Alc }
    }
    function New-Mtx { param($Rows) [PSCustomObject]@{ Assemblies = @($Rows) } }
}

Describe 'Compare-DLLPickleConflictMatrix' -Tag 'Unit' {
    It 'reports no material drift when the conflict surface is unchanged' {
        $b = New-Mtx @( New-Row 'Azure.Core' $true )
        $c = New-Mtx @( New-Row 'Azure.Core' $true )
        (& $ScriptPath -Baseline $b -Current $c).HasMaterialDrift | Should -BeFalse
    }

    It 'flags a newly diverging assembly' {
        $b = New-Mtx @( New-Row 'Azure.Core' $true )
        $c = New-Mtx @( (New-Row 'Azure.Core' $true), (New-Row 'Newtonsoft.Json' $true) )
        $r = & $ScriptPath -Baseline $b -Current $c
        $r.HasMaterialDrift | Should -BeTrue
        $r.Findings.NewConflicts | Should -Contain 'Newtonsoft.Json'
    }

    It 'flags an ALC-ownership change' {
        $b = New-Mtx @( New-Row 'Azure.Core' $true 'Default' )
        $c = New-Mtx @( New-Row 'Azure.Core' $true 'AzSharedAssemblyLoadContext' )
        $r = & $ScriptPath -Baseline $b -Current $c
        $r.HasMaterialDrift | Should -BeTrue
        $r.Findings.AlcOwnershipChanges | Should -Contain 'Azure.Core'
    }
}
