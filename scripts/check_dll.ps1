$sig = @'
using System;
using System.Runtime.InteropServices;

public class Win32Helper {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr LoadLibrary(string lpFileName);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetProcAddress(IntPtr hModule, string procName);
}
'@

Add-Type -TypeDefinition $sig

$dlls = @("mfvirtualcamera.dll", "mfplat.dll", "mf.dll", "mfcore.dll")
foreach ($d in $dlls) {
    $h = [Win32Helper]::LoadLibrary($d)
    if ($h -ne [IntPtr]::Zero) {
        $p = [Win32Helper]::GetProcAddress($h, "MFCreateVirtualCamera")
        Write-Host "$d -> Handle: $h, Proc: $p"
    } else {
        Write-Host "$d -> Not Found"
    }
}
