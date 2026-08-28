# PhoneCam - Standalone Virtual Camera Test
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "   PhoneCam Virtual Camera - Standalone Test Harness   " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This script boots 'PhoneCam Virtual Camera' with an internal"
Write-Host "1080p30 SMPTE Color Bars test pattern with an animated sync counter."
Write-Host "You can test this camera directly in:"
Write-Host "  - Windows Camera App"
Write-Host "  - Google Meet (meet.google.com)"
Write-Host "  - Zoom / Microsoft Teams"
Write-Host "  - Discord / OBS Studio"
Write-Host ""

$Root = Split-Path -Parent $PSScriptRoot
$RunnerExe = Join-Path $Root "native/windows/virtual_camera/build/Release/PhoneCamTestRunner.exe"

if (-not (Test-Path $RunnerExe)) {
    Write-Host "Test runner binary not found. Compiling now..." -ForegroundColor Yellow
    $CmakeExe = "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
    if (-not (Test-Path $CmakeExe)) { $CmakeExe = "cmake" }
    $NativeDir = Join-Path $Root "native/windows/virtual_camera"
    Push-Location $NativeDir
    & $CmakeExe -B build -S .
    & $CmakeExe --build build --config Release
    Pop-Location
}

if (Test-Path $RunnerExe) {
    Write-Host "Launching PhoneCam Virtual Camera Test Runner..." -ForegroundColor Green
    & $RunnerExe
} else {
    Write-Host "Failed to build or find PhoneCamTestRunner.exe" -ForegroundColor Red
}
