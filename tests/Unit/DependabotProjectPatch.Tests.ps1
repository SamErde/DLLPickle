BeforeAll {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:ValidatorPath = Join-Path $ProjectRoot 'tools\Test-DLLPicklePackageReferenceUpdate.ps1'
    $script:BaseProject = @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFrameworks>net8.0;net9.0</TargetFrameworks>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Example.One" Version="1.0.0" Condition="'$(TargetFramework)' == 'net8.0'" />
    <PackageReference Include="Example.Two" Version="2.*" />
  </ItemGroup>
</Project>
'@
}

Describe 'Dependabot project patch validation' -Tag 'Unit' {
    BeforeEach {
        $script:BasePath = Join-Path $TestDrive 'base.csproj'
        $script:CandidatePath = Join-Path $TestDrive 'candidate.csproj'
        $script:BaseProject | Set-Content -LiteralPath $script:BasePath -Encoding UTF8
    }

    It 'accepts changes only to existing PackageReference versions' {
        $script:BaseProject.Replace('Version="1.0.0"', 'Version="1.1.0"') |
            Set-Content -LiteralPath $script:CandidatePath -Encoding UTF8

        $Result = & $script:ValidatorPath -BaseProjectPath $script:BasePath -CandidateProjectPath $script:CandidatePath

        $Result.IsVersionOnlyUpdate | Should -BeTrue
        @($Result.ChangedPackages) | Should -Be @('Include:Example.One')
    }

    It 'rejects removal of a PackageReference condition' {
        $Candidate = $script:BaseProject.Replace(
            ' Version="1.0.0" Condition="''$(TargetFramework)'' == ''net8.0''"',
            ' Version="1.1.0"'
        )
        $Candidate | Set-Content -LiteralPath $script:CandidatePath -Encoding UTF8

        { & $script:ValidatorPath -BaseProjectPath $script:BasePath -CandidateProjectPath $script:CandidatePath } |
            Should -Throw '*content other than PackageReference Version*'
    }

    It 'rejects added PackageReference elements' {
        $Candidate = $script:BaseProject.Replace(
            '    <PackageReference Include="Example.Two" Version="2.*" />',
            "    <PackageReference Include=`"Example.Two`" Version=`"2.*`" />`n    <PackageReference Include=`"Example.Three`" Version=`"3.0.0`" />"
        )
        $Candidate | Set-Content -LiteralPath $script:CandidatePath -Encoding UTF8

        { & $script:ValidatorPath -BaseProjectPath $script:BasePath -CandidateProjectPath $script:CandidatePath } |
            Should -Throw '*adds, removes, or renames*'
    }

    It 'rejects removed PackageReference elements' {
        $script:BaseProject.Replace('<PackageReference Include="Example.Two" Version="2.*" />', '') |
            Set-Content -LiteralPath $script:CandidatePath -Encoding UTF8

        { & $script:ValidatorPath -BaseProjectPath $script:BasePath -CandidateProjectPath $script:CandidatePath } |
            Should -Throw '*adds, removes, or renames*'
    }

    It 'rejects renamed PackageReference identities' {
        $script:BaseProject.Replace('Include="Example.One"', 'Include="Example.Renamed"') |
            Set-Content -LiteralPath $script:CandidatePath -Encoding UTF8

        { & $script:ValidatorPath -BaseProjectPath $script:BasePath -CandidateProjectPath $script:CandidatePath } |
            Should -Throw '*adds, removes, or renames*'
    }

    It 'rejects duplicate PackageReference identities' {
        $script:BaseProject.Replace('Include="Example.Two"', 'Include="Example.One"') |
            Set-Content -LiteralPath $script:CandidatePath -Encoding UTF8

        { & $script:ValidatorPath -BaseProjectPath $script:BasePath -CandidateProjectPath $script:CandidatePath } |
            Should -Throw '*duplicate PackageReference identity*'
    }

    It 'rejects PackageReference elements without a Version attribute' {
        $script:BaseProject.Replace(' Version="2.*"', '') |
            Set-Content -LiteralPath $script:CandidatePath -Encoding UTF8

        { & $script:ValidatorPath -BaseProjectPath $script:BasePath -CandidateProjectPath $script:CandidatePath } |
            Should -Throw '*exactly one Include or Update attribute and one Version attribute*'
    }

    It 'rejects unchanged project files' {
        $script:BaseProject | Set-Content -LiteralPath $script:CandidatePath -Encoding UTF8

        { & $script:ValidatorPath -BaseProjectPath $script:BasePath -CandidateProjectPath $script:CandidatePath } |
            Should -Throw '*does not change any PackageReference Version*'
    }

    It 'reports a structural-only change as disallowed project content' {
        $script:BaseProject.Replace('net8.0;net9.0', 'net8.0;net9.0;net10.0') |
            Set-Content -LiteralPath $script:CandidatePath -Encoding UTF8

        { & $script:ValidatorPath -BaseProjectPath $script:BasePath -CandidateProjectPath $script:CandidatePath } |
            Should -Throw '*content other than PackageReference Version*'
    }

    It 'rejects changes to other project properties' {
        $Candidate = $script:BaseProject.Replace('net8.0;net9.0', 'net8.0;net9.0;net10.0').Replace('Version="1.0.0"', 'Version="1.1.0"')
        $Candidate | Set-Content -LiteralPath $script:CandidatePath -Encoding UTF8

        { & $script:ValidatorPath -BaseProjectPath $script:BasePath -CandidateProjectPath $script:CandidatePath } |
            Should -Throw '*content other than PackageReference Version*'
    }

    It 'rejects non-numeric candidate version expressions' {
        $script:BaseProject.Replace('Version="1.0.0"', 'Version="$(InjectedVersion)"') |
            Set-Content -LiteralPath $script:CandidatePath -Encoding UTF8

        { & $script:ValidatorPath -BaseProjectPath $script:BasePath -CandidateProjectPath $script:CandidatePath } |
            Should -Throw '*unsupported candidate version*'
    }

    It 'rejects a wildcard in the middle of a numeric version' {
        $script:BaseProject.Replace('Version="1.0.0"', 'Version="1.*.3"') |
            Set-Content -LiteralPath $script:CandidatePath -Encoding UTF8

        { & $script:ValidatorPath -BaseProjectPath $script:BasePath -CandidateProjectPath $script:CandidatePath } |
            Should -Throw '*unsupported candidate version*'
    }

    It 'accepts documented prerelease floating-version forms' {
        foreach ($CandidateVersion in @('1.1.*-*', '1.2.0-rc.*')) {
            $script:BaseProject.Replace('Version="1.0.0"', "Version=`"$CandidateVersion`"") |
                Set-Content -LiteralPath $script:CandidatePath -Encoding UTF8

            $Result = & $script:ValidatorPath -BaseProjectPath $script:BasePath -CandidateProjectPath $script:CandidatePath
            $Result.IsVersionOnlyUpdate | Should -BeTrue
        }
    }
}
