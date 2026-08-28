Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | ? { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]

function Await($WinRtTask, $ResultType) {
    $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    $netTask.Wait(-1) | Out-Null
    $netTask.Result
}

[Windows.Devices.Enumeration.DeviceInformation, Windows.Devices.Enumeration, ContentType = WindowsRuntime] | Out-Null
$devices = Await ([Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync([Windows.Devices.Enumeration.DeviceClass]::VideoCapture)) ([Windows.Devices.Enumeration.DeviceInformationCollection])

Write-Host "Detected Cameras in Windows:" -ForegroundColor Cyan
foreach ($d in $devices) {
    Write-Host " - $($d.Name) ($($d.Id))"
}
