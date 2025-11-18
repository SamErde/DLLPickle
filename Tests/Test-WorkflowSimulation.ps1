# Integration test to simulate the Update MSAL Packages workflow
# This script simulates the actual workflow steps without making real changes

$ErrorActionPreference = 'Stop'

# Set up paths
if ($PSScriptRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
} else {
    $RepoRoot = Get-Location
}

$LibPath = Join-Path -Path $RepoRoot -ChildPath "src/DLLPickle/Assembly"
$JsonPath = Join-Path -Path $LibPath -ChildPath "Packages.json"

Write-Host "=== Simulating Update MSAL Packages Workflow ===" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# Step 1: Check for package updates (simulating workflow step)
# ============================================================================
Write-Host "Step 1: Check for package updates" -ForegroundColor Yellow
Write-Host "------------------------------------" -ForegroundColor Gray

# Read package tracking JSON
if (-not (Test-Path $JsonPath)) {
    Write-Error "Package tracking JSON not found at $JsonPath"
    exit 1
}

$PackageTracking = Get-Content $JsonPath -Raw | ConvertFrom-Json
$UpdatesAvailable = $false
$UpdateSummary = @()

# Check each package version for updates
foreach ($Package in $PackageTracking.packages) {
    Write-Host "Checking $($Package.name)..." -NoNewline

    $CurrentVersion = $Package.version

    # Check the latest version from NuGet
    $NuGetUrl = "https://api.nuget.org/v3-registration5-semver1/$($Package.name.ToLower())/index.json"
    try {
        $Response = Invoke-RestMethod -Uri $NuGetUrl -ErrorAction Stop
        $LatestVersion = $Response.items[-1].upper

        if ([version]$LatestVersion -gt [version]$CurrentVersion) {
            Write-Host " ✓ Update available: $CurrentVersion → $LatestVersion" -ForegroundColor Green
            $UpdatesAvailable = $true
            $UpdateSummary += "$($Package.name): $CurrentVersion → $LatestVersion"
        } else {
            Write-Host " Already up to date ($CurrentVersion)" -ForegroundColor Gray
        }
    } catch {
        Write-Host " ✗ Failed to check" -ForegroundColor Red
        Write-Warning "Error: $_"
    }
}

Write-Host ""
if ($UpdatesAvailable) {
    Write-Host "✓ Updates available!" -ForegroundColor Green
    Write-Host "Summary: $($UpdateSummary -join '; ')" -ForegroundColor Cyan
} else {
    Write-Host "ℹ No updates available" -ForegroundColor Blue
}

# ============================================================================
# Step 2: Simulate download and extract (without actually downloading)
# ============================================================================
Write-Host ""
Write-Host "Step 2: Simulate download and extract packages" -ForegroundColor Yellow
Write-Host "------------------------------------------------" -ForegroundColor Gray

if ($UpdatesAvailable) {
    Write-Host "Would download and extract the following packages:" -ForegroundColor Cyan
    foreach ($Summary in $UpdateSummary) {
        Write-Host "  - $Summary" -ForegroundColor Gray
    }

    # Simulate updating the JSON
    Write-Host ""
    Write-Host "Simulating JSON update..." -NoNewline
    $SimulatedTracking = $PackageTracking | ConvertTo-Json -Depth 10
    Write-Host " ✓ Success" -ForegroundColor Green

} else {
    Write-Host "No packages to download (all up to date)" -ForegroundColor Gray
}

# ============================================================================
# Step 3: Verify JSON integrity after hypothetical update
# ============================================================================
Write-Host ""
Write-Host "Step 3: Verify JSON integrity" -ForegroundColor Yellow
Write-Host "------------------------------" -ForegroundColor Gray

try {
    # Re-read and verify JSON
    $VerifyTracking = Get-Content $JsonPath -Raw | ConvertFrom-Json

    if ($null -eq $VerifyTracking.packages) {
        throw "JSON missing 'packages' property"
    }

    if ($VerifyTracking.packages.Count -ne 5) {
        throw "Expected 5 packages, found $($VerifyTracking.packages.Count)"
    }

    # Verify each package has required properties
    foreach ($Package in $VerifyTracking.packages) {
        if ([string]::IsNullOrWhiteSpace($Package.name)) {
            throw "Package missing 'name' property"
        }
        if ([string]::IsNullOrWhiteSpace($Package.version)) {
            throw "Package '$($Package.name)' missing 'version' property"
        }
    }

    Write-Host "✓ JSON structure is valid" -ForegroundColor Green
    Write-Host "  - 5 packages found" -ForegroundColor Gray
    Write-Host "  - All packages have name and version" -ForegroundColor Gray

} catch {
    Write-Error "JSON integrity check failed: $_"
    exit 1
}

# ============================================================================
# Summary
# ============================================================================
Write-Host ""
Write-Host "=== Workflow Simulation Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  - JSON file: $JsonPath"
Write-Host "  - Packages tracked: $($PackageTracking.packages.Count)"
Write-Host "  - Updates available: $UpdatesAvailable"
if ($UpdatesAvailable) {
    Write-Host "  - Update summary: $($UpdateSummary -join '; ')" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "The workflow would:" -ForegroundColor Cyan
if ($UpdatesAvailable) {
    Write-Host "  1. Download and extract updated packages" -ForegroundColor Gray
    Write-Host "  2. Update Packages.json with new versions" -ForegroundColor Gray
    Write-Host "  3. Copy DLL files to Assembly directory" -ForegroundColor Gray
    Write-Host "  4. Increment module version" -ForegroundColor Gray
    Write-Host "  5. Commit and push changes" -ForegroundColor Gray
    Write-Host "  6. Create a GitHub release" -ForegroundColor Gray
} else {
    Write-Host "  - Skip all update steps (no updates available)" -ForegroundColor Gray
}
Write-Host ""
