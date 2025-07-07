Write-Verbose 'Loading the DLLPickle custom format file.' -Verbose
Update-FormatData -PrependPath (Join-Path -Path $PSScriptRoot -ChildPath 'DLLPickle.Format.ps1xml')

foreach ($file in Get-ChildItem -Path $PSScriptRoot -Filter '*.ps1' -Recurse) {
    Write-Verbose "Loading script file: $($file.FullName)" -Verbose
    . $file.FullName
}

$ModuleNames = @(
    'Az.Accounts',
    'ExchangeOnlineManagement',
    'Microsoft.Graph.Authentication',
    'MicrosoftTeams'
)



$ModuleImportCandidate = Get-ModuleImportCandidate -Name $ModuleNames
$ModuleWithDependency = $ModuleImportCandidate | Get-ModulesWithDependency -FileName 'Microsoft.Identity.Client.dll'
$ModuleWithDependency | Format-Table Name, Version, @{N = 'FileName'; E = { ($_.DependencyPath.Split('\'))[-1] } }, DependencyVersion -AutoSize
