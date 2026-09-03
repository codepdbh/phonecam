# PhoneCam - Release Packaging Script
#
# Builds everything a fresh recipient needs and assembles it into dist/:
#   dist/PhoneCam-Windows/   -> windows.exe + PhoneCamMediaSource_v7.dll +
#                                install/uninstall scripts + a short guide
#   dist/PhoneCam-Android.apk
#
# Order matters: the native virtual-camera DLL must exist BEFORE the Windows
# app's CMake project is first configured, or its `install()` step (see
# apps/windows/windows/CMakeLists.txt) has nothing to copy next to the exe —
# that check runs once at CMake configure time, not on every build. This
# script always reconfigures from a clean apps/windows/build to guarantee it
# picks the DLL up regardless of what was built before.
param(
    [switch]$SkipApk,
    [switch]$Zip
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$DistDir = Join-Path $Root 'dist'
$WinDistDir = Join-Path $DistDir 'PhoneCam-Windows'

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "             PhoneCam - Release Packaging              " -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan

# 1. Native virtual camera DLL (must come first, see note above).
Write-Host "`n[1/4] Building native virtual camera (C++)..." -ForegroundColor Yellow
$CmakeExe = "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
if (-not (Test-Path $CmakeExe)) { $CmakeExe = "cmake" }
$NativeDir = Join-Path $Root "native/windows/virtual_camera"
& $CmakeExe -B (Join-Path $NativeDir 'build') -S $NativeDir
if ($LASTEXITCODE -ne 0) { throw 'Native camera CMake configuration failed.' }
& $CmakeExe --build (Join-Path $NativeDir 'build') --config Release
if ($LASTEXITCODE -ne 0) { throw 'Native camera build failed.' }
$NativeDll = Join-Path $NativeDir 'build\Release\PhoneCamMediaSource_v7.dll'
if (-not (Test-Path -LiteralPath $NativeDll)) { throw "Native DLL missing after build: $NativeDll" }
Write-Host "      [OK] $NativeDll" -ForegroundColor Green

# 2. Windows Flutter app — force a clean CMake configure so its install()
#    step picks up the DLL built above.
Write-Host "`n[2/4] Building Windows app (Release)..." -ForegroundColor Yellow
$WinAppDir = Join-Path $Root 'apps/windows'
$WinCmakeCache = Join-Path $WinAppDir 'build/windows'
if (Test-Path -LiteralPath $WinCmakeCache) {
    Remove-Item -LiteralPath $WinCmakeCache -Recurse -Force
}
Push-Location $WinAppDir
flutter build windows --release
if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'Windows app build failed.' }
Pop-Location
$WinReleaseDir = Join-Path $WinAppDir 'build/windows/x64/runner/Release'
if (-not (Test-Path -LiteralPath (Join-Path $WinReleaseDir 'PhoneCamMediaSource_v7.dll'))) {
    throw 'PhoneCamMediaSource_v7.dll was not bundled next to windows.exe — the CMake install() step did not pick it up. Delete apps\windows\build and retry.'
}
Write-Host "      [OK] $WinReleaseDir" -ForegroundColor Green

# 3. Android APK.
if (-not $SkipApk) {
    Write-Host "`n[3/4] Building Android APK (Release)..." -ForegroundColor Yellow
    $MobileDir = Join-Path $Root 'apps/mobile'
    Push-Location $MobileDir
    flutter build apk --release
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'Android APK build failed.' }
    Pop-Location
    $ApkPath = Join-Path $MobileDir 'build/app/outputs/flutter-apk/app-release.apk'
    if (-not (Test-Path -LiteralPath $ApkPath)) { throw "APK missing after build: $ApkPath" }
    Write-Host "      [OK] $ApkPath" -ForegroundColor Green
} else {
    Write-Host "`n[3/4] Skipping Android APK build (-SkipApk)." -ForegroundColor Yellow
}

# 4. Assemble dist/.
Write-Host "`n[4/4] Assembling dist/..." -ForegroundColor Yellow
if (Test-Path -LiteralPath $DistDir) { Remove-Item -LiteralPath $DistDir -Recurse -Force }
New-Item -ItemType Directory -Path $WinDistDir -Force | Out-Null

Copy-Item -Path (Join-Path $WinReleaseDir '*') -Destination $WinDistDir -Recurse -Force
# Stale versioned DLLs from older builds aren't cleaned by the CMake install
# step (it only ever adds files); the app only ever loads _v7, drop the rest
# so nobody double-clicks the wrong one by mistake.
Get-ChildItem -Path $WinDistDir -Filter 'PhoneCamMediaSource*.dll' |
    Where-Object { $_.Name -ne 'PhoneCamMediaSource_v7.dll' } |
    Remove-Item -Force
Copy-Item -Path (Join-Path $Root 'scripts\uninstall_virtual_camera.ps1') -Destination $WinDistDir -Force

$readme = @'
PhoneCam Virtual Camera Studio
===============================

1. En el celular: instala PhoneCam-Android.apk (activa "orígenes desconocidos"
   si Android lo pide) y abre la app. Concede el permiso de cámara.

2. En la PC: entra a la carpeta PhoneCam-Windows y ejecuta windows.exe.
   - La primera vez que actives la "Cámara Virtual" en la app, te va a pedir
     instalar un componente de Windows (driver). Acepta el aviso de permisos
     de administrador — es de una sola vez.
   - Windows 10 / Windows 11 sin la última actualización: la cámara funciona
     igual en Zoom, OBS, navegadores y Python/OpenCV, pero no aparece en apps
     que solo usan la cámara "moderna" de Windows 11 (22H2 o más nuevo).

3. Conecta el celular y la PC a la misma red WiFi (o USB con depuración),
   selecciona el dispositivo en la app de Windows y activa la cámara virtual.

Para desinstalar el driver de la PC: ejecuta uninstall_virtual_camera.ps1
dentro de la carpeta PhoneCam-Windows.
'@
Set-Content -Path (Join-Path $DistDir 'LEEME.txt') -Value $readme -Encoding UTF8

if (-not $SkipApk) {
    Copy-Item -Path (Join-Path $Root 'apps/mobile/build/app/outputs/flutter-apk/app-release.apk') `
        -Destination (Join-Path $DistDir 'PhoneCam-Android.apk') -Force
}

if ($Zip) {
    $zipPath = Join-Path $Root 'dist\PhoneCam-Release.zip'
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -Path (Join-Path $DistDir '*') -DestinationPath $zipPath
    Write-Host "      [OK] $zipPath" -ForegroundColor Green
}

Write-Host "`n======================================================" -ForegroundColor Green
Write-Host "   Ready to hand out: $DistDir" -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
