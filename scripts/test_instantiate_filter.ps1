Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[ComImport, Guid("56a86895-0ad4-11ce-b03a-0020af0ba770"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IBaseFilter {
    [PreserveSig] int GetClassID(out Guid pClassID);
    [PreserveSig] int Stop();
    [PreserveSig] int Pause();
    [PreserveSig] int Run(long tStart);
    [PreserveSig] int GetState(int dwMilliSecsTimeout, out int State);
}

public class FilterTester {
    public static void TestInstantiate() {
        Guid clsid = new Guid("E4D8A9F3-3142-4A2D-A483-E18F54687791");
        Type type = Type.GetTypeFromCLSID(clsid);
        if (type == null) {
            Console.WriteLine("[ERROR] Could not get Type for CLSID");
            return;
        }

        object instance = Activator.CreateInstance(type);
        if (instance == null) {
            Console.WriteLine("[ERROR] CoCreateInstance failed!");
            return;
        }

        IBaseFilter filter = instance as IBaseFilter;
        if (filter != null) {
            Guid outClsid;
            filter.GetClassID(out outClsid);
            Console.WriteLine(string.Format("[SUCCESS] Successfully instantiated PhoneCam DirectShow Filter! CLSID: {0}", outClsid));
            Marshal.ReleaseComObject(filter);
        } else {
            Console.WriteLine("[ERROR] Instance does not implement IBaseFilter");
        }
    }
}
'@

[FilterTester]::TestInstantiate()
