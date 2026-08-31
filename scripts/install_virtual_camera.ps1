param(
    [switch]$SkipBuild,
    [string]$SourceDll
)

$ErrorActionPreference = 'Stop'
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($SkipBuild) { $arguments += ' -SkipBuild' }
    if ($SourceDll) { $arguments += " -SourceDll `"$SourceDll`"" }
    $process = Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        # Some regsvr32/FilterMapper combinations report a non-zero status
        # after updating the registrations. Verify the actual durable state so
        # the desktop UI does not display a false installation failure.
        $candidateSource = if ($SourceDll) {
            [IO.Path]::GetFullPath($SourceDll)
        } else {
            Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path `
                'native\windows\virtual_camera\build\Release\PhoneCamMediaSource_v7.dll'
        }
        $candidateInstalled = Join-Path $env:ProgramFiles 'PhoneCam\PhoneCamMediaSource_v7.dll'
        $candidateKey = 'Registry::HKEY_LOCAL_MACHINE\Software\Classes\CLSID\{E4D8A9F1-3142-4A2D-A483-E18F54687791}\InprocServer32'
        if ((Test-Path -LiteralPath $candidateSource) -and
            (Test-Path -LiteralPath $candidateInstalled) -and
            (Test-Path -LiteralPath $candidateKey) -and
            ((Get-FileHash -LiteralPath $candidateSource).Hash -eq
             (Get-FileHash -LiteralPath $candidateInstalled).Hash) -and
            ((Get-ItemPropertyValue -LiteralPath $candidateKey -Name '(default)') -eq
             $candidateInstalled)) {
            exit 0
        }
    }
    exit $process.ExitCode
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$nativeDir = Join-Path $projectRoot 'native\windows\virtual_camera'
$sourceDll = if ($SourceDll) { [IO.Path]::GetFullPath($SourceDll) } else { Join-Path $nativeDir 'build\Release\PhoneCamMediaSource_v7.dll' }
if (-not $SkipBuild) {
    $cmake = 'C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    if (-not (Test-Path -LiteralPath $cmake)) { $cmake = 'cmake.exe' }
    & $cmake -B (Join-Path $nativeDir 'build') -S $nativeDir
    if ($LASTEXITCODE -ne 0) { throw 'CMake configuration failed.' }
    & $cmake --build (Join-Path $nativeDir 'build') --config Release
    if ($LASTEXITCODE -ne 0) { throw 'Native camera build failed.' }
}
if (-not (Test-Path -LiteralPath $sourceDll)) { throw "Missing camera DLL: $sourceDll" }

$installDir = Join-Path $env:ProgramFiles 'PhoneCam'
if (-not [IO.Path]::GetFullPath($installDir).StartsWith([IO.Path]::GetFullPath($env:ProgramFiles), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Resolved install directory is outside Program Files.'
}
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
$brokerDir = Join-Path $env:ProgramData 'PhoneCam'
New-Item -ItemType Directory -Path $brokerDir -Force | Out-Null
# Builtin Users covers the desktop producer; LOCAL SERVICE is used by the
# Windows Camera Frame Server on current Windows 11 builds.
& "$env:SystemRoot\System32\icacls.exe" $brokerDir /inheritance:e `
    /grant '*S-1-5-32-545:(OI)(CI)M' '*S-1-5-19:(OI)(CI)M' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not configure the frame broker permissions.' }
$installedDll = Join-Path $installDir 'PhoneCamMediaSource_v7.dll'

# Both services cache in-proc sources. Stopping only the monitor can leave the
# capture service executing an older image after the DLL on disk is replaced.
foreach ($serviceName in @('FrameServerMonitor', 'FrameServer')) {
    $cameraService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($cameraService -and $cameraService.Status -eq 'Running') {
        Stop-Service -Name $serviceName -Force
        $cameraService.WaitForStatus(
            [System.ServiceProcess.ServiceControllerStatus]::Stopped,
            [TimeSpan]::FromSeconds(15))
    }
}
Copy-Item -LiteralPath $sourceDll -Destination $installedDll -Force
& "$env:SystemRoot\System32\regsvr32.exe" /s $installedDll
if ($LASTEXITCODE -ne 0) { throw "COM registration failed with exit code $LASTEXITCODE." }
foreach ($legacyName in @('PhoneCamMediaSource_v3.dll', 'PhoneCamMediaSource_v4.dll', 'PhoneCamMediaSource_v5.dll', 'PhoneCamMediaSource_v6.dll')) {
    $legacyDll = Join-Path $installDir $legacyName
    if (Test-Path -LiteralPath $legacyDll) {
        try { Remove-Item -LiteralPath $legacyDll -Force -ErrorAction Stop }
        catch { Write-Warning "$legacyName remains loaded; it can be removed after its client exits." }
    }
}

$clsid = '{E4D8A9F1-3142-4A2D-A483-E18F54687791}'
$key = "Registry::HKEY_LOCAL_MACHINE\Software\Classes\CLSID\$clsid\InprocServer32"
if (-not (Test-Path -LiteralPath $key)) { throw 'Machine-wide Media Foundation registration was not created.' }

# The service is demand-started by MFCreateVirtualCamera. Leaving it stopped
# here avoids racing the service control manager during upgrades.
Write-Host "PhoneCam virtual camera installed: $installedDll" -ForegroundColor Green
Write-Host 'Restart camera/browser applications that still have an older camera DLL loaded.' -ForegroundColor Yellow
exit 0
