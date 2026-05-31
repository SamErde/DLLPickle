BeforeAll {
    $ScriptPath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'tools\New-DLLPickleConflictMatrix.ps1'

    function Get-TestInventory {
        # Two modules; Azure.Core diverges (1.50 vs 1.46), MSAL agrees (4.84.1).
        [PSCustomObject]@{
            Modules = @(
                [PSCustomObject]@{
                    Name              = 'Az.Accounts'
                    TrackedAssemblies = @(
                        [PSCustomObject]@{ Name = 'Azure.Core'; Version = '1.50.0.0' }
                        [PSCustomObject]@{ Name = 'Microsoft.Identity.Client'; Version = '4.84.1.0' }
                    )
                }
                [PSCustomObject]@{
                    Name              = 'Microsoft.Graph.Authentication'
                    TrackedAssemblies = @(
                        [PSCustomObject]@{ Name = 'Azure.Core'; Version = '1.46.0.0' }
                        [PSCustomObject]@{ Name = 'Microsoft.Identity.Client'; Version = '4.84.1.0' }
                    )
                }
            )
        }
    }
}

Describe 'New-DLLPickleConflictMatrix' -Tag 'Unit' {
    It 'flags an assembly shipped by >=2 modules at diverging versions' {
        $Matrix = & $ScriptPath -Inventory (Get-TestInventory)
        $AzureCore = $Matrix.Assemblies | Where-Object Name -EQ 'Azure.Core'
        $AzureCore.Diverges | Should -BeTrue
        @($AzureCore.Versions).Count | Should -Be 2
        @($AzureCore.ShippedBy) | Should -Contain 'Az.Accounts'
    }

    It 'does not flag an assembly all modules ship at the same version' {
        $Matrix = & $ScriptPath -Inventory (Get-TestInventory)
        $Msal = $Matrix.Assemblies | Where-Object Name -EQ 'Microsoft.Identity.Client'
        $Msal.Diverges | Should -BeFalse
    }

    It 'returns a ConflictSurface limited to diverging assemblies' {
        $Matrix = & $ScriptPath -Inventory (Get-TestInventory)
        @($Matrix.ConflictSurface) | Should -Be @('Azure.Core')
    }

    It 'does not flag divergence when a single module ships one assembly at two versions' {
        $Inventory = [PSCustomObject]@{
            Modules = @(
                [PSCustomObject]@{
                    Name              = 'Az.Accounts'
                    TrackedAssemblies = @(
                        [PSCustomObject]@{ Name = 'Azure.Core'; Version = '1.50.0.0' }
                        [PSCustomObject]@{ Name = 'Azure.Core'; Version = '1.46.0.0' }
                    )
                }
            )
        }
        $Matrix = & $ScriptPath -Inventory $Inventory
        $AzureCore = $Matrix.Assemblies | Where-Object Name -EQ 'Azure.Core'
        $AzureCore.Diverges | Should -BeFalse
        @($AzureCore.ShippedBy).Count | Should -Be 1
        @($Matrix.ConflictSurface) | Should -BeNullOrEmpty
    }
}
