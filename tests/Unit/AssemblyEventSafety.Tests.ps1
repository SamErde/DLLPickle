BeforeAll {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:GetUnsafeAssemblyEventRegistrationFiles = {
        param(
            [Parameter(Mandatory)]
            [string]$SearchRoot
        )

        $UnsafePatterns = @(
            '\[System\.(AssemblyLoadEventHandler|ResolveEventHandler)\]\s*\{'
            '\.add_(AssemblyLoad|AssemblyResolve)\s*\(\s*\{'
        )

        @(
            Get-ChildItem -LiteralPath $SearchRoot -File -Recurse |
                Where-Object { $_.Extension -in '.ps1', '.psm1' } |
                Where-Object {
                    $Content = Get-Content -LiteralPath $_.FullName -Raw
                    @($UnsafePatterns | Where-Object { $Content -match $_ }).Count -gt 0
                } |
                Select-Object -ExpandProperty FullName
        )
    }
}

Describe 'Assembly event safety' -Tag 'Unit' {
    It 'flags typed delegate casts and direct script-block subscriptions in PowerShell source files' {
        $TypedDelegateFile = Join-Path $TestDrive 'TypedDelegate.ps1'
        $DirectSubscriptionFile = Join-Path $TestDrive 'DirectSubscription.psm1'
        $SafeFile = Join-Path $TestDrive 'SafeFile.ps1'

        Set-Content -LiteralPath $TypedDelegateFile -Value @'
$Handler = [System.ResolveEventHandler]{
    param($sender, $eventArgs)
    return $null
}
'@ -Encoding utf8
        Set-Content -LiteralPath $DirectSubscriptionFile -Value @'
$Domain = [System.AppDomain]::CurrentDomain
$Domain.add_AssemblyLoad({
    param($sender, $eventArgs)
})
'@ -Encoding utf8
        Set-Content -LiteralPath $SafeFile -Value @'
function Invoke-SafeThing {
    return $true
}
'@ -Encoding utf8

        $UnsafeFiles = @(& $script:GetUnsafeAssemblyEventRegistrationFiles -SearchRoot $TestDrive)

        $UnsafeFiles | Should -Contain $TypedDelegateFile
        $UnsafeFiles | Should -Contain $DirectSubscriptionFile
        $UnsafeFiles | Should -Not -Contain $SafeFile
    }

    It 'does not register PowerShell script blocks as CLR assembly event delegates' {
        $UnsafeSourceFiles = @(& $script:GetUnsafeAssemblyEventRegistrationFiles -SearchRoot (Join-Path $RepoRoot 'src\DLLPickle'))

        $UnsafeSourceFiles | Should -BeNullOrEmpty
    }
}
