# Dot-source public/private functions.
$Public  = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public/*.ps1')  -Recurse -ErrorAction Stop)
$Private = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private/*.ps1') -Recurse -ErrorAction Stop)
foreach ($Import in @($Public + $Private)) {
    try {
        . $Import.FullName
    } catch {
        throw "Unable to dot source [$($Import.FullName)]"
    }
}

Export-ModuleMember -Function $Public.Basename

# Load the assembly on module import. In PowerShell 7+, use Assembly Load Context (ALC) to avoid conflicts.
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Add-MsalAssembly
    } else {
        $MsalDllPath = Join-Path $PSScriptRoot 'lib\Microsoft.Identity.Client.dll'
        Add-Type -Path $MsalDllPath
    }

# Unload the assembly on module removal (ALC requires PS 7 or higher).
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Remove-MsalAssembly
    }
}
