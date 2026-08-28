Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

[ComImport, Guid("55272A00-42CB-11CE-8135-00AA004BB851"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPropertyBag {
    [PreserveSig]
    int Read([MarshalAs(UnmanagedType.LPWStr)] string pszPropName, ref object pVar, IntPtr pErrorLog);
    [PreserveSig]
    int Write([MarshalAs(UnmanagedType.LPWStr)] string pszPropName, ref object pVar);
}

[ComImport, Guid("29840822-5B84-11D0-BD3B-00A0C911CE86"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ICreateDevEnum {
    [PreserveSig]
    int CreateClassEnumerator([In, MarshalAs(UnmanagedType.LPStruct)] Guid pType, out IEnumMoniker ppEnumMoniker, [In] int dwFlags);
}

public class CameraDetector {
    public static void ListCameras() {
        Guid CLSID_SystemDeviceEnum = new Guid("62BE5D10-60EB-11d0-BD3B-00A0C911CE86");
        Guid CLSID_VideoInputDeviceCategory = new Guid("860BB310-5D01-11d0-BD3B-00A0C911CE86");

        Type type = Type.GetTypeFromCLSID(CLSID_SystemDeviceEnum);
        ICreateDevEnum devEnum = (ICreateDevEnum)Activator.CreateInstance(type);

        IEnumMoniker enumMoniker;
        int hr = devEnum.CreateClassEnumerator(CLSID_VideoInputDeviceCategory, out enumMoniker, 0);

        if (hr != 0 || enumMoniker == null) {
            Console.WriteLine("[DSHOW] No video capture devices found in DirectShow.");
            return;
        }

        IMoniker[] monikers = new IMoniker[1];
        IntPtr fetched = IntPtr.Zero;

        Console.WriteLine("=== DirectShow Detected Video Devices ===");
        while (enumMoniker.Next(1, monikers, fetched) == 0) {
            Guid IID_IPropertyBag = typeof(IPropertyBag).GUID;
            object bagObj;
            monikers[0].BindToStorage(null, null, ref IID_IPropertyBag, out bagObj);
            IPropertyBag bag = (IPropertyBag)bagObj;

            object val = "";
            bag.Read("FriendlyName", ref val, IntPtr.Zero);
            object devPath = "";
            bag.Read("DevicePath", ref devPath, IntPtr.Zero);

            Console.WriteLine(string.Format(" -> Found Camera: {0} (Path: {1})", val, devPath));
            Marshal.ReleaseComObject(bag);
            Marshal.ReleaseComObject(monikers[0]);
        }
    }
}
'@

[CameraDetector]::ListCameras()
