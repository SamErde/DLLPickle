BeforeAll {

    Set-StrictMode -Version Latest

    # Make sure MetaFixers.psm1 is loaded - it contains Get-TextFilesList
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'MetaFixers.psm1') -Verbose:$false -Force

    $ProjectRoot = $ENV:BHProjectPath
    if (-not $ProjectRoot) {
        $ProjectRoot = $PSScriptRoot
    }

    $AllTextFiles      = Get-TextFilesList $ProjectRoot
    $UnicodeFilesCount = 0
    $TotalTabsCount    = 0
    foreach ($TextFile in $AllTextFiles) {
        if (Test-FileUnicode $TextFile) {
            $UnicodeFilesCount++
            Write-Warning (
                "File $($TextFile.FullName) contains 0x00 bytes." +
                " It probably uses Unicode/UTF-16 and needs to be converted to UTF-8." +
                " Use Fixer 'Get-UnicodeFilesList `$pwd | ConvertTo-UTF8'."
            )
        }
        $UnicodeFilesCount | Should -Be 0

        $FileName = $TextFile.FullName
        (Get-Content $FileName -Raw) | Select-String "`t" | ForEach-Object {
            Write-Warning (
                "There are tabs in $FileName." +
                " Use Fixer 'Get-TextFilesList `$pwd | ConvertTo-SpaceIndentation'."
            )
            $TotalTabsCount++
        }
    }
}

Describe 'Text files formatting' {
    Context 'File encoding' {
        It "No text file uses Unicode/UTF-16 encoding" {
            $UnicodeFilesCount | Should -Be 0
        }
    }

    Context 'Indentations' {
        It "No text file use tabs for indentations" {
            $TotalTabsCount | Should -Be 0
        }
    }
}
