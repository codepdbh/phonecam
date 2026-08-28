$sig = @'
using System;
using System.Runtime.InteropServices;

public class Win32Scanner {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr LoadLibrary(string lpFileName);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetProcAddress(IntPtr hModule, string procName);
}
'@

Add-Type -TypeDefinition $sig

Get-ChildItem -Path "C:\Windows\System32\mf*.dll" | ForEach-Object {
    $h = [Win32Scanner]::LoadLibrary($_.FullName)
    if ($h -ne [IntPtr]::Zero) {
        $p = [Win32Scanner]::GetProcAddress($h, "MFCreateVirtualCamera")
        if ($p -ne [IntPtr]::Zero) {
            Write-Host "FOUND in $($_.Name) -> $p"
        }
    }
}
