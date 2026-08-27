# Cleanly terminate all lingering Godot processes
$processes = Get-Process | Where-Object { $_.ProcessName -like "*Godot*" }
if ($processes) {
    Write-Host "Found $($processes.Count) running Godot process(es):" -ForegroundColor Yellow
    $processes | ForEach-Object {
        Write-Host "  Terminating PID $($_.Id) ($($_.ProcessName)) - Memory: $([math]::Round($_.WorkingSet64 / 1MB, 2)) MB" -ForegroundColor Red
        Stop-Process -Id $_.Id -Force
    }
    Write-Host "All Godot background processes terminated cleanly." -ForegroundColor Green
} else {
    Write-Host "No Godot background processes running." -ForegroundColor Cyan
}
