# PowerShell Script to Check DL Pickle Module Version

# Define the module name
$ModuleName = "DLLPickle"

# Function to get the installed version
dynamic Get-InstalledVersion {
    try {
        $InstalledModule = Get-InstalledModule -Name $ModuleName -ErrorAction Stop
        return $InstalledModule.Version.ToString()
    } catch {
        return "Not Installed"
    }
}

# Function to get the latest version available on PSGallery
function Get-LatestVersion {
    try {
        $RepositoryInfo = Find-Module -Name $ModuleName -Repository PSGallery -ErrorAction Stop
        return $RepositoryInfo.Version.ToString()
    } catch {
        return "Error Retrieving Version"
    }
}

# Compare versions
$InstalledVersion = Get-InstalledVersion
$LatestVersion = Get-LatestVersion

Write-Host "Installed Version: $InstalledVersion"
Write-Host "Latest Version: $LatestVersion"

if ($InstalledVersion -eq "Not Installed") {
    Write-Output "$ModuleName is not installed. You can install it using: Install-Module -Name $ModuleName`

} elseif ([version]$InstalledVersion -lt [version]$LatestVersion) {
    Write-Output "An update is available for $Module .New Latest Version: $LatestVersion" }