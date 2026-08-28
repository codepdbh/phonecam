# PhoneCam - Run Android Application
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "         Launching PhoneCam Mobile (Android)           " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

$Root = Split-Path -Parent $PSScriptRoot

Push-Location (Join-Path $Root "apps/mobile")
flutter run -d android
Pop-Location
