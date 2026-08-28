$source = @"
using System;
using System.Runtime.InteropServices;

namespace DShowTest
{
    [ComImport, Guid("56a868a9-0ad4-11ce-b03a-0020af0ba770"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IGraphBuilder
    {
        [PreserveSig] int AddFilter([In] IBaseFilter pFilter, [In, MarshalAs(UnmanagedType.LPWStr)] string pName);
        [PreserveSig] int RemoveFilter([In] IBaseFilter pFilter);
        [PreserveSig] int EnumFilters(out IntPtr ppEnum);
        [PreserveSig] int FindFilterByName([In, MarshalAs(UnmanagedType.LPWStr)] string pName, out IBaseFilter ppFilter);
        [PreserveSig] int ConnectDirect([In] IPin ppinOut, [In] IPin ppinIn, [In] IntPtr pmt);
        [PreserveSig] int Reconnect([In] IPin ppin);
        [PreserveSig] int Disconnect([In] IPin ppin);
        [PreserveSig] int SetDefaultSyncSource();
        [PreserveSig] int Connect([In] IPin ppinOut, [In] IPin ppinIn);
        [PreserveSig] int Render([In] IPin ppinOut);
    }

    [ComImport, Guid("56a868a0-0ad4-11ce-b03a-0020af0ba770"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMediaFilter
    {
        [PreserveSig] int Stop();
        [PreserveSig] int Pause();
        [PreserveSig] int Run(long tStart);
        [PreserveSig] int GetState(int dwMilliSecsTimeout, out int State);
        [PreserveSig] int SetSyncSource([In] IntPtr pClock);
        [PreserveSig] int GetSyncSource(out IntPtr ppClock);
    }

    [ComImport, Guid("56a86895-0ad4-11ce-b03a-0020af0ba770"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IBaseFilter : IMediaFilter
    {
        [PreserveSig] int EnumPins(out IntPtr ppEnum);
        [PreserveSig] int FindPin([In, MarshalAs(UnmanagedType.LPWStr)] string Id, out IPin ppPin);
        [PreserveSig] int QueryFilterInfo(IntPtr pInfo);
        [PreserveSig] int JoinFilterGraph([In] IntPtr pGraph, [In, MarshalAs(UnmanagedType.LPWStr)] string pName);
        [PreserveSig] int QueryVendorInfo(out IntPtr pVendorInfo);
    }

    [ComImport, Guid("56a8689a-0ad4-11ce-b03a-0020af0ba770"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPin
    {
        [PreserveSig] int Connect([In] IPin pReceivePin, [In] IntPtr pmt);
        [PreserveSig] int ReceiveConnection([In] IPin pConnector, [In] IntPtr pmt);
        [PreserveSig] int Disconnect();
        [PreserveSig] int ConnectedTo(out IPin pPin);
        [PreserveSig] int ConnectionMediaType(IntPtr pmt);
        [PreserveSig] int QueryPinInfo(IntPtr pInfo);
        [PreserveSig] int QueryDirection(out int pPinDir);
        [PreserveSig] int QueryId(out IntPtr Id);
        [PreserveSig] int QueryAccept([In] IntPtr pmt);
        [PreserveSig] int EnumMediaTypes(out IntPtr ppEnum);
        [PreserveSig] int QueryInternalConnections(IntPtr apPin, ref int nPin);
        [PreserveSig] int EndOfStream();
        [PreserveSig] int BeginFlush();
        [PreserveSig] int EndFlush();
        [PreserveSig] int NewSegment(long tStart, long tStop, double dRate);
    }

    [ComImport, Guid("e28249a0-3a12-11cf-b1e0-0020afd310b4"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IFilterGraphBuilder
    {
    }

    [ComImport, Guid("e4d8a9f1-3142-4a2d-a483-e18f54687791")]
    public class PhoneCamFilterClass { }

    [ComImport, Guid("e436ebd3-524f-11ce-9f53-0020af0ba770")]
    public class FilterGraph { }

    public class Tester
    {
        public static void Run()
        {
            try
            {
                Console.WriteLine("1. Instantiating PhoneCamFilterClass...");
                var filter = (IBaseFilter)new PhoneCamFilterClass();
                Console.WriteLine("   -> OK! Filter instantiated.");

                Console.WriteLine("2. Creating FilterGraph...");
                var graph = (IGraphBuilder)new FilterGraph();
                int hr = graph.AddFilter(filter, "PhoneCam Source");
                Console.WriteLine("   -> AddFilter hr = 0x{0:X8}", hr);

                Console.WriteLine("3. Finding Output pin...");
                IPin outPin;
                hr = filter.FindPin("Output", out outPin);
                Console.WriteLine("   -> FindPin hr = 0x{0:X8}, outPin is null? {1}", hr, outPin == null);

                Console.WriteLine("4. Testing Graph.Render(outPin)...");
                hr = graph.Render(outPin);
                Console.WriteLine("   -> Graph.Render hr = 0x{0:X8}", hr);

                Console.WriteLine("5. Testing Pause (preroll)...");
                var mediaFilter = (IMediaFilter)graph;
                hr = mediaFilter.Pause();
                Console.WriteLine("   -> Pause hr = 0x{0:X8}", hr);

                System.Threading.Thread.Sleep(1000);

                Console.WriteLine("6. Testing Run...");
                hr = mediaFilter.Run(0);
                Console.WriteLine("   -> Run hr = 0x{0:X8}", hr);

                System.Threading.Thread.Sleep(2000);

                Console.WriteLine("7. Testing Stop...");
                hr = mediaFilter.Stop();
                Console.WriteLine("   -> Stop hr = 0x{0:X8}", hr);

                Console.WriteLine("[SUCCESS] DirectShow graph render test completed!");
            }
            catch (Exception ex)
            {
                Console.WriteLine("[ERROR] " + ex.ToString());
            }
        }
    }
}
"@

Add-Type -TypeDefinition $source -Language CSharp
[DShowTest.Tester]::Run()
