BeforeAll {
    $RepositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    . (Join-Path $RepositoryRoot 'build/DLLPickle.Tooling.ps1')
}

Describe 'Bounded Gallery retries' -Tag 'Unit' {
    BeforeEach {
        $script:Attempts = 0
        Mock Start-Sleep {}
    }

    It 'returns a successful lookup without retrying' {
        $Actual = @(Invoke-DLLPickleGalleryOperation -Description 'Lookup fixture' -Operation {
                $script:Attempts++
                '1.0.0'
                '2.0.0'
            })

        $Actual | Should -Be @('1.0.0', '2.0.0')
        $script:Attempts | Should -Be 1
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }

    It 'discards partial output and retries the same selected version after transient failure' {
        $SelectedVersion = '5.5.4'
        $Actual = @(Invoke-DLLPickleGalleryOperation -Description 'Save fixture' -Operation {
                $script:Attempts++
                if ($script:Attempts -lt 3) {
                    'incomplete result'
                    throw 'Temporary Gallery failure'
                }
                $SelectedVersion
            })

        $Actual | Should -Be @('5.5.4')
        $script:Attempts | Should -Be 3
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 2 }
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 4 }
        Should -Invoke Start-Sleep -Times 2 -Exactly
    }

    It 'fails closed with the final error after three failed attempts' {
        {
            Invoke-DLLPickleGalleryOperation -Description 'Unavailable fixture' -Operation {
                $script:Attempts++
                throw "Gallery failure $script:Attempts"
            }
        } | Should -Throw '*Gallery failure 3*'

        $script:Attempts | Should -Be 3
        Should -Invoke Start-Sleep -Times 2 -Exactly
    }
}
