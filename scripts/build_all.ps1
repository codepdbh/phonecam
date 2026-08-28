# PhoneCam - Build All Script
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "             PhoneCam - Full Build Pipeline           " -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

$Root = Split-Path -Parent $PSScriptRoot

# 1. Build Shared Packages
Write-Host "[1/4] Testing shared Dart packages..." -ForegroundColor Yellow
$Packages = @("packages/shared_models", "packages/protocol", "packages/discovery")
foreach ($pkg in $Packages) {
    Write-Host "      -> Testing $pkg..."
    Push-Location (Join-Path $Root $pkg)
    flutter test
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error in $pkg tests!" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Pop-Location
}
Write-Host "      [OK] All shared packages passed tests!" -ForegroundColor Green

# 2. Build Native Windows Media Foundation Virtual Camera DLL
Write-Host "`n[2/4] Building Windows Media Foundation Virtual Camera (C++)..." -ForegroundColor Yellow
$CmakeExe = "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
if (-not (Test-Path $CmakeExe)) {
    $CmakeExe = "cmake"
}
$NativeDir = Join-Path $Root "native/windows/virtual_camera"
Push-Location $NativeDir
& $CmakeExe -B build -S .
& $CmakeExe --build build --config Release
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error building native virtual camera DLL!" -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location
Write-Host "      [OK] PhoneCamMediaSource.dll built successfully!" -ForegroundColor Green

# 3. Test Windows Flutter Desktop App
Write-Host "`n[3/4] Testing Flutter Windows App..." -ForegroundColor Yellow
Push-Location (Join-Path $Root "apps/windows")
flutter test
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error in Windows app tests!" -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location
Write-Host "      [OK] Flutter Windows App passed tests!" -ForegroundColor Green

# 4. Test Mobile Flutter App
Write-Host "`n[4/4] Testing Flutter Mobile App..." -ForegroundColor Yellow
Push-Location (Join-Path $Root "apps/mobile")
flutter test
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error in Mobile app tests!" -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location
Write-Host "      [OK] Flutter Mobile App passed tests!" -ForegroundColor Green

Write-Host "`n======================================================" -ForegroundColor Green
Write-Host "   BUILD SUCCESSFUL: All components verified & ready!  " -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
