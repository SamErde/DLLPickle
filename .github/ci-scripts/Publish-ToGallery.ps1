<#
.SYNOPSIS
    Publishes a PowerShell module to the PowerShell Gallery with automatic retry logic.

.DESCRIPTION
    Publishes a PowerShell module to the PowerShell Gallery, verifies publication,
    and provides detailed status information. Includes automatic retry logic for
    transient failures.

.PARAMETER ModuleDirectory
    Path to the module directory to publish.

.PARAMETER ApiKey
    The PowerShell Gallery API key for authentication.

.PARAMETER MaxRetries
    Maximum number of retry attempts. Default is 3.

.PARAMETER RepositoryName
    Name of the PowerShell repository to publish to. Default is 'PSGallery'.

.OUTPUTS
    PSCustomObject with properties:
    - Success: Boolean indicating if publish succeeded
    - ModuleName: Name of the published module
    - Version: Version that was published
    - GalleryUrl: Direct link to the module in the gallery
    - AttemptCount: Number of publish attempts made
    - Message: Status message

.EXAMPLE
    $Result = & .\.github\scripts\Publish-ToGallery.ps1 `
        -ModuleDirectory "./src/DLLPickle" `
        -ApiKey $env:PSGALLERY_API_KEY
    if ($Result.Success) {
        Write-Host "Published: $($Result.GalleryUrl)"
    }

.NOTES
    The script will wait 30 seconds after publishing to allow the gallery to index.
    Transient failures trigger automatic retries with exponential backoff.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$ModuleDirectory,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ApiKey,

    [Parameter(Mandatory = $false)]
    [int]$MaxRetries = 3,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$RepositoryName = 'PSGallery'
)

$ErrorActionPreference = 'Stop'

# Read module manifest to get name and version
$ManifestFile = Get-ChildItem -Path $ModuleDirectory -Filter '*.psd1' | Select-Object -First 1
if (-not $ManifestFile) {
    throw "No .psd1 manifest file found in $ModuleDirectory"
}

$Manifest = Import-PowerShellDataFile -Path $ManifestFile.FullName
$ModuleName = $Manifest.RootModule -replace '\.psm1$'
if ([string]::IsNullOrEmpty($ModuleName)) {
    $ModuleName = (Split-Path -Leaf $ModuleDirectory)
}
$ModuleVersion = $Manifest.ModuleVersion

Write-Host "Preparing to publish module: $ModuleName"
Write-Host "Version: $ModuleVersion"

# Configure PowerShell Gallery
Set-PSRepository -Name $RepositoryName -InstallationPolicy Trusted -ErrorAction SilentlyContinue | Out-Null

$PublishParams = @{
    Path        = $ModuleDirectory
    NuGetApiKey = $ApiKey
    Repository  = $RepositoryName
    Verbose     = $true
    Force       = $true
}

Write-Host 'Publishing module to PowerShell Gallery...' -ForegroundColor Green

# Publish with retry logic
$PublishSuccess = $false
$AttemptCount = 0
$LastError = $null

while (-not $PublishSuccess -and $AttemptCount -lt $MaxRetries) {
    $AttemptCount++

    if ($AttemptCount -gt 1) {
        $WaitSeconds = 5 * ($AttemptCount - 1)
        Write-Host "Retry attempt $AttemptCount of $MaxRetries. Waiting ${WaitSeconds}s..." -ForegroundColor Yellow
        Start-Sleep -Seconds $WaitSeconds
    }

    try {
        Publish-Module @PublishParams -ErrorAction Stop
        $PublishSuccess = $true
        Write-Host "`n✓ Module published successfully!" -ForegroundColor Green
    } catch {
        $LastError = $_
        Write-Warning "Publish attempt $AttemptCount failed: $($_.Exception.Message)"

        if ($AttemptCount -ge $MaxRetries) {
            Write-Error "Failed to publish module after $MaxRetries attempts: $($_.Exception.Message)"
        }
    }
}

$GalleryUrl = "https://www.powershellgallery.com/packages/$ModuleName/$ModuleVersion"

if (-not $PublishSuccess) {
    $Result = @{
        Success      = $false
        ModuleName   = $ModuleName
        Version      = $ModuleVersion
        GalleryUrl   = $GalleryUrl
        AttemptCount = $AttemptCount
        Message      = "Failed to publish after $MaxRetries attempts"
        ErrorMessage = $LastError.Exception.Message
    }
    $Result
    exit 1
}

# Wait for gallery indexing
Write-Host 'Waiting for PowerShell Gallery indexing...' -ForegroundColor Gray
Start-Sleep -Seconds 30

# Verify publication
try {
    $Published = Find-Module -Name $ModuleName -RequiredVersion $ModuleVersion `
        -AllowPrerelease -ErrorAction SilentlyContinue

    if ($Published) {
        Write-Host '✓ Module verified in PowerShell Gallery' -ForegroundColor Green
    } else {
        Write-Warning 'Module published but not yet visible in gallery search (may take additional time)'
    }
} catch {
    Write-Warning "Could not verify publication: $_"
}

Write-Host "View at: $GalleryUrl" -ForegroundColor Cyan

$Result = @{
    Success      = $true
    ModuleName   = $ModuleName
    Version      = $ModuleVersion
    GalleryUrl   = $GalleryUrl
    AttemptCount = $AttemptCount
    Message      = 'Published successfully'
}

$Result
