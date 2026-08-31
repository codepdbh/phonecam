$ErrorActionPreference = 'Stop'
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $process = Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Wait -PassThru
    exit $process.ExitCode
}

$installDir = Join-Path $env:ProgramFiles 'PhoneCam'
$installedDll = Join-Path $installDir 'PhoneCamMediaSource_v7.dll'
if (Test-Path -LiteralPath $installedDll) {
    & "$env:SystemRoot\System32\regsvr32.exe" /s /u $installedDll
    if ($LASTEXITCODE -ne 0) { throw "COM unregistration failed with exit code $LASTEXITCODE." }
    Remove-Item -LiteralPath $installedDll -Force
}
foreach ($legacyName in @('PhoneCamMediaSource_v3.dll', 'PhoneCamMediaSource_v4.dll', 'PhoneCamMediaSource_v5.dll', 'PhoneCamMediaSource_v6.dll')) {
    $legacyDll = Join-Path $installDir $legacyName
    if (Test-Path -LiteralPath $legacyDll) {
        try { Remove-Item -LiteralPath $legacyDll -Force -ErrorAction Stop }
        catch { Write-Warning "$legacyName is still loaded and will need removal after its client exits." }
    }
}
if ((Test-Path -LiteralPath $installDir) -and -not (Get-ChildItem -LiteralPath $installDir -Force)) {
    Remove-Item -LiteralPath $installDir
}
$brokerDir = Join-Path $env:ProgramData 'PhoneCam'
$brokerFile = Join-Path $brokerDir 'frame-broker-v4.bin'
if (Test-Path -LiteralPath $brokerFile) {
    try { Remove-Item -LiteralPath $brokerFile -Force -ErrorAction Stop }
    catch { Write-Warning 'The frame broker is still in use and will remain until clients exit.' }
}
if ((Test-Path -LiteralPath $brokerDir) -and -not (Get-ChildItem -LiteralPath $brokerDir -Force)) {
    Remove-Item -LiteralPath $brokerDir
}
Write-Host 'PhoneCam virtual camera uninstalled.' -ForegroundColor Green
exit 0
