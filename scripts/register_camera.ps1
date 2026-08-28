$dllPath = "c:\Users\Sistemas\Documents\webcam\native\windows\virtual_camera\build\Release\PhoneCamMediaSource.dll"
$clsid = "{E4D8A9F1-3142-4A2D-A483-E18F54687791}"

# 1. Register COM InprocServer32
$keyPath = "HKCU:\Software\Classes\CLSID\$clsid"
if (-not (Test-Path $keyPath)) { New-Item -Path $keyPath -Force | Out-Null }
Set-ItemProperty -Path $keyPath -Name "(Default)" -Value "PhoneCam Virtual Camera Media Source"

$inprocPath = "$keyPath\InprocServer32"
if (-not (Test-Path $inprocPath)) { New-Item -Path $inprocPath -Force | Out-Null }
Set-ItemProperty -Path $inprocPath -Name "(Default)" -Value $dllPath
Set-ItemProperty -Path $inprocPath -Name "ThreadingModel" -Value "Both"

# 2. Register in DirectShow Video Capture Sources Category ({860BB310-5D01-11d0-BD3B-00A0C911CE86})
$dshowCatPath = "HKCU:\Software\Classes\CLSID\{860BB310-5D01-11d0-BD3B-00A0C911CE86}\Instance\$clsid"
if (-not (Test-Path $dshowCatPath)) { New-Item -Path $dshowCatPath -Force | Out-Null }
Set-ItemProperty -Path $dshowCatPath -Name "FriendlyName" -Value "PhoneCam Virtual Camera"
Set-ItemProperty -Path $dshowCatPath -Name "CLSID" -Value $clsid
Set-ItemProperty -Path $dshowCatPath -Name "DevicePath" -Value "\\?\phonecam#virtualcamera#0001"

Write-Host "[OK] Registered PhoneCam Virtual Camera for Windows Media Foundation and DirectShow (Meet, Teams, Zoom, OBS, Camera App)!" -ForegroundColor Green
