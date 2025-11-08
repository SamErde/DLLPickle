# 1. Clean start
Remove-Module DLLPickle -ErrorAction SilentlyContinue
[System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers()

# 2. Check assemblies before
$BeforeCount = (Get-LoadedAssembly | Where-Object {$_.Location -match 'DLLPickle'}).Count
Write-Host "Assemblies before import: $BeforeCount" -ForegroundColor Cyan

# 3. Import module
Import-Module .\DLLPickle.psd1 -Verbose

# 4. Check assemblies after import
$AfterImportCount = (Get-LoadedAssembly | Where-Object {$_.Location -match 'DLLPickle'}).Count
Write-Host "Assemblies after import: $AfterImportCount" -ForegroundColor Yellow

# 5. Verify context
Get-Module DLLPickle | ForEach-Object {
    & $_.NewBoundScriptBlock({
        Write-Host "Context: $($script:MsalLoadContext.Name)" -ForegroundColor Green
    })
}

# 6. Remove module
Remove-Module DLLPickle -Verbose

# 7. Force garbage collection (may need to wait a moment)
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
[System.GC]::Collect()
Start-Sleep -Seconds 2  # Give GC time to clean up

# 8. Check assemblies after removal
$AfterRemovalCount = (Get-LoadedAssembly | Where-Object {$_.Location -match 'DLLPickle'}).Count
Write-Host "Assemblies after removal: $AfterRemovalCount" -ForegroundColor Magenta

# 9. Summary
if ($AfterRemovalCount -eq 0) {
    Write-Host "`n✓ SUCCESS: All assemblies were unloaded!" -ForegroundColor Green
} elseif ($AfterRemovalCount -lt $AfterImportCount) {
    Write-Host "`n⚠ PARTIAL: Some assemblies remain (this may be normal if you have active references)" -ForegroundColor Yellow
} else {
    Write-Host "`n✗ FAILED: Assemblies were not unloaded" -ForegroundColor Red
}
