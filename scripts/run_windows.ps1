# PhoneCam - Run Windows Desktop Application
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "         Launching PhoneCam Windows Desktop Studio     " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

$Root = Split-Path -Parent $PSScriptRoot

# 1. Ensure DLL is compiled and registered
$NativeDll = Join-Path $Root "native\windows\virtual_camera\build\Release\PhoneCamMediaSource_v7.dll"
if (-not (Test-Path $NativeDll)) {
    Write-Host "Native virtual camera DLL not found. Compiling now..." -ForegroundColor Yellow
    $CmakeExe = "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
    if (-not (Test-Path $CmakeExe)) { $CmakeExe = "cmake" }
    $NativeDir = Join-Path $Root "native\windows\virtual_camera"
    Push-Location $NativeDir
    & $CmakeExe -B build -S .
    & $CmakeExe --build build --config Release
    Pop-Location
}

# 2. Ensure the machine-wide Frame Server source matches this build.
$InstalledDll = Join-Path $env:ProgramFiles "PhoneCam\PhoneCamMediaSource_v7.dll"
$NeedsInstall = -not (Test-Path -LiteralPath $InstalledDll)
if (-not $NeedsInstall) {
    $NeedsInstall = (Get-FileHash -LiteralPath $InstalledDll).Hash -ne (Get-FileHash -LiteralPath $NativeDll).Hash
}
if ($NeedsInstall) {
    Write-Host "Installing updated virtual camera (UAC confirmation required)..." -ForegroundColor Yellow
    & (Join-Path $Root "scripts\install_virtual_camera.ps1") -SkipBuild
    if ($LASTEXITCODE -ne 0) { throw "Virtual camera installation was not completed." }
}

# 3. Copy DLL to release and debug folders
$ReleaseDir = Join-Path $Root "apps\windows\build\windows\x64\runner\Release"
if (Test-Path $ReleaseDir) {
    Copy-Item $NativeDll $ReleaseDir -Force
}

$ExePath = Join-Path $ReleaseDir "windows.exe"
if (Test-Path $ExePath) {
    Write-Host "Starting PhoneCam Desktop Studio..." -ForegroundColor Green
    Start-Process $ExePath
    Write-Host "[OK] PhoneCam Desktop Studio is now running on your desktop!" -ForegroundColor Green
} else {
    Push-Location (Join-Path $Root "apps\windows")
    flutter run -d windows
    Pop-Location
}
