# DirectShow Video Capture Source FilterData binary signature
# Version 2, Merit MERIT_DO_NOT_USE (0x00200000), 1 output pin, MEDIATYPE_Video (73646976-0000-0010-8000-00AA00389B71)
$filterData = [byte[]]@(
    0x02, 0x00, 0x00, 0x00, # Version 2
    0x00, 0x00, 0x20, 0x00, # Merit MERIT_DO_NOT_USE (0x00200000)
    0x01, 0x00, 0x00, 0x00, # 1 Pin
    0x00, 0x00, 0x00, 0x00, # Pin 0 flags (rendered = 0, output = 1, zero = 0, many = 0)
    0x30, 0x70, 0x69, 0x6e, # '0pin' Signature
    0x00, 0x00, 0x00, 0x00, 
    0x01, 0x00, 0x00, 0x00, # 1 Media Type
    0x00, 0x00, 0x00, 0x00, # 0 Mediums
    0x00, 0x00, 0x00, 0x00, # Category (none)
    0x30, 0x74, 0x79, 0x70, # '0typ' Signature
    0x00, 0x00, 0x00, 0x00,
    # MEDIATYPE_Video: {73646976-0000-0010-8000-00AA00389B71}
    0x76, 0x69, 0x64, 0x73, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71,
    # MEDIASUBTYPE_NULL: {00000000-0000-0000-0000-000000000000}
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
)

$dllPath = "c:\Users\Sistemas\Documents\webcam\native\windows\virtual_camera\build\Release\PhoneCamMediaSource.dll"
$clsid = "{E4D8A9F1-3142-4A2D-A483-E18F54687791}"
$dshowCategory = "{860BB310-5D01-11d0-BD3B-00A0C911CE86}"

Write-Host "Registering PhoneCam Virtual Camera in Windows Registry..." -ForegroundColor Cyan

# 1. Register CLSID in HKCU:\Software\Classes\CLSID
$clsidKey = "HKCU:\Software\Classes\CLSID\$clsid"
if (-not (Test-Path $clsidKey)) { New-Item -Path $clsidKey -Force | Out-Null }
Set-ItemProperty -Path $clsidKey -Name "(Default)" -Value "PhoneCam Virtual Camera"

$inprocKey = "$clsidKey\InprocServer32"
if (-not (Test-Path $inprocKey)) { New-Item -Path $inprocKey -Force | Out-Null }
Set-ItemProperty -Path $inprocKey -Name "(Default)" -Value $dllPath
Set-ItemProperty -Path $inprocKey -Name "ThreadingModel" -Value "Both"

# 2. Register DirectShow Video Input Device Category in HKCU
$instanceKey = "HKCU:\Software\Classes\CLSID\$dshowCategory\Instance\$clsid"
if (-not (Test-Path $instanceKey)) { New-Item -Path $instanceKey -Force | Out-Null }
Set-ItemProperty -Path $instanceKey -Name "FriendlyName" -Value "PhoneCam Virtual Camera"
Set-ItemProperty -Path $instanceKey -Name "CLSID" -Value $clsid
Set-ItemProperty -Path $instanceKey -Name "DevicePath" -Value "\\?\phonecam#virtualcamera#0001"
Set-ItemProperty -Path $instanceKey -Name "FilterData" -Value $filterData -Type Binary

# 3. Also register 32-bit WoW6432Node for 32-bit apps
$wowClsidKey = "HKCU:\Software\Classes\WOW6432Node\CLSID\$clsid"
if (-not (Test-Path $wowClsidKey)) { New-Item -Path $wowClsidKey -Force | Out-Null }
Set-ItemProperty -Path $wowClsidKey -Name "(Default)" -Value "PhoneCam Virtual Camera"
$wowInprocKey = "$wowClsidKey\InprocServer32"
if (-not (Test-Path $wowInprocKey)) { New-Item -Path $wowInprocKey -Force | Out-Null }
Set-ItemProperty -Path $wowInprocKey -Name "(Default)" -Value $dllPath
Set-ItemProperty -Path $wowInprocKey -Name "ThreadingModel" -Value "Both"

$wowInstanceKey = "HKCU:\Software\Classes\WOW6432Node\CLSID\$dshowCategory\Instance\$clsid"
if (-not (Test-Path $wowInstanceKey)) { New-Item -Path $wowInstanceKey -Force | Out-Null }
Set-ItemProperty -Path $wowInstanceKey -Name "FriendlyName" -Value "PhoneCam Virtual Camera"
Set-ItemProperty -Path $wowInstanceKey -Name "CLSID" -Value $clsid
Set-ItemProperty -Path $wowInstanceKey -Name "DevicePath" -Value "\\?\phonecam#virtualcamera#0001"
Set-ItemProperty -Path $wowInstanceKey -Name "FilterData" -Value $filterData -Type Binary

Write-Host "[OK] DirectShow Video Capture Source and FilterData successfully registered!" -ForegroundColor Green
