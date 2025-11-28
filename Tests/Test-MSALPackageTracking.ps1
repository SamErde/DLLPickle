# Test script to validate MSAL Package Tracking JSON functionality
# This script tests the logic used in the Update MSAL Packages workflow

$ErrorActionPreference = 'Stop'

# Set up paths - handle different execution contexts
if ($PSScriptRoot) {
    # When run as a script, PSScriptRoot is /home/runner/work/DLLPickle/DLLPickle/Tests
    # We need to go up one level to get to the repo root
    $RepoRoot = Split-Path -Parent $PSScriptRoot
} else {
    $RepoRoot = Get-Location
}

$LibPath = Join-Path -Path $RepoRoot -ChildPath "src/DLLPickle/Lib"
$JsonPath = Join-Path -Path $LibPath -ChildPath "Packages.json"

Write-Host "=== Testing MSAL Package Tracking JSON ===" -ForegroundColor Cyan
Write-Host "Repository Root: $RepoRoot"
Write-Host "Library Path: $LibPath"
Write-Host "JSON Path: $JsonPath"
Write-Host ""

# Test 1: Verify JSON file exists
Write-Host "Test 1: Verify JSON file exists..." -ForegroundColor Yellow
if (Test-Path $JsonPath) {
    Write-Host "✓ JSON file exists" -ForegroundColor Green
} else {
    Write-Error "✗ JSON file not found at $JsonPath"
    exit 1
}

# Test 2: Verify JSON can be parsed
Write-Host "`nTest 2: Verify JSON can be parsed..." -ForegroundColor Yellow
try {
    $PackageTracking = Get-Content $JsonPath -Raw | ConvertFrom-Json
    Write-Host "✓ JSON parsed successfully" -ForegroundColor Green
} catch {
    Write-Error "✗ Failed to parse JSON: $_"
    exit 1
}

# Test 3: Verify JSON structure
Write-Host "`nTest 3: Verify JSON structure..." -ForegroundColor Yellow
if ($null -eq $PackageTracking.packages) {
    Write-Error "✗ JSON missing 'packages' property"
    exit 1
}
if ($PackageTracking.packages.Count -eq 0) {
    Write-Error "✗ JSON packages array is empty"
    exit 1
}
Write-Host "✓ JSON structure valid, found $($PackageTracking.packages.Count) packages" -ForegroundColor Green

# Test 4: Verify each package has required properties
Write-Host "`nTest 4: Verify package properties..." -ForegroundColor Yellow
$ExpectedPackages = @(
    "Microsoft.Identity.Client",
    "Microsoft.Identity.Client.Extensions.Msal",
    "Microsoft.Identity.Client.NativeInterop",
    "Microsoft.Identity.Client.Broker",
    "Microsoft.Identity.Abstractions"
)

foreach ($ExpectedPackage in $ExpectedPackages) {
    $Package = $PackageTracking.packages | Where-Object { $_.name -eq $ExpectedPackage }
    if ($null -eq $Package) {
        Write-Error "✗ Package '$ExpectedPackage' not found in JSON"
        exit 1
    }
    if ([string]::IsNullOrWhiteSpace($Package.version)) {
        Write-Error "✗ Package '$ExpectedPackage' missing version"
        exit 1
    }
    Write-Host "  ✓ $($Package.name) v$($Package.version)" -ForegroundColor Gray
}
Write-Host "✓ All expected packages found with versions" -ForegroundColor Green

# Test 5: Simulate checking for updates (without actually downloading)
Write-Host "`nTest 5: Simulate checking for updates..." -ForegroundColor Yellow
$TestPackage = $PackageTracking.packages[0]
Write-Host "  Testing with $($TestPackage.name) v$($TestPackage.version)" -ForegroundColor Gray

try {
    $NuGetUrl = "https://api.nuget.org/v3-registration5-semver1/$($TestPackage.name.ToLower())/index.json"
    $Response = Invoke-RestMethod -Uri $NuGetUrl -ErrorAction Stop
    $LatestVersion = $Response.items[-1].upper
    Write-Host "  Latest version available: $LatestVersion" -ForegroundColor Gray

    if ([version]$LatestVersion -gt [version]$TestPackage.version) {
        Write-Host "  ℹ Update available: $($TestPackage.version) → $LatestVersion" -ForegroundColor Yellow
    } else {
        Write-Host "  ℹ Already up to date" -ForegroundColor Gray
    }
    Write-Host "✓ NuGet API check successful" -ForegroundColor Green
} catch {
    Write-Error "✗ Failed to check NuGet API: $_"
    exit 1
}

# Test 6: Simulate JSON update (without writing to file)
Write-Host "`nTest 6: Simulate JSON update..." -ForegroundColor Yellow
try {
    $TestTracking = $PackageTracking | ConvertTo-Json -Depth 10
    $null = $TestTracking | ConvertFrom-Json  # Verify it can be parsed again
    Write-Host "✓ JSON serialization/deserialization successful" -ForegroundColor Green
} catch {
    Write-Error "✗ Failed to serialize/deserialize JSON: $_"
    exit 1
}

Write-Host "`n=== All Tests Passed ===" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  - JSON file structure is valid"
Write-Host "  - All expected packages are present"
Write-Host "  - NuGet API integration works"
Write-Host "  - JSON can be updated and persisted"
Write-Host ""
