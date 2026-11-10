using System.Runtime.InteropServices;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX.Direct3D11;
using WinRT;

namespace MapcastCompanion.Interop;

/// <summary>
/// Minimal bridges between Windows Graphics Capture (WinRT) and Direct3D 11.
/// Uses raw COM vtable calls so it doesn't depend on any particular interop helper.
/// </summary>
internal static unsafe class WgcInterop
{
    private static readonly Guid IID_IGraphicsCaptureItemInterop = new("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356");
    private static readonly Guid IID_IGraphicsCaptureItem = new("79C3F95B-31F7-4EC2-A464-632EF5D30760");
    private static readonly Guid IID_IDirect3DDxgiInterfaceAccess = new("A9B3D012-3DF2-4EE3-B8D1-8695F457D3C1");

    [DllImport("combase.dll", PreserveSig = true)]
    private static extern int WindowsCreateString([MarshalAs(UnmanagedType.LPWStr)] string sourceString, int length, out IntPtr hstring);

    [DllImport("combase.dll", PreserveSig = true)]
    private static extern int WindowsDeleteString(IntPtr hstring);

    [DllImport("combase.dll", PreserveSig = true)]
    private static extern int RoGetActivationFactory(IntPtr activatableClassId, ref Guid iid, out IntPtr factory);

    [DllImport("d3d11.dll", PreserveSig = true)]
    private static extern int CreateDirect3D11DeviceFromDXGIDevice(IntPtr dxgiDevice, out IntPtr graphicsDevice);

    /// <summary>Creates a capture item for a top-level window (IGraphicsCaptureItemInterop::CreateForWindow).</summary>
    public static GraphicsCaptureItem CreateItemForWindow(IntPtr hwnd)
    {
        const string className = "Windows.Graphics.Capture.GraphicsCaptureItem";
        Marshal.ThrowExceptionForHR(WindowsCreateString(className, className.Length, out var hstring));
        IntPtr factory;
        try
        {
            var iid = IID_IGraphicsCaptureItemInterop;
            Marshal.ThrowExceptionForHR(RoGetActivationFactory(hstring, ref iid, out factory));
        }
        finally
        {
            WindowsDeleteString(hstring);
        }

        try
        {
            // vtable: 0-2 IUnknown, 3 CreateForWindow(HWND, REFIID, void**), 4 CreateForMonitor
            var vtbl = *(IntPtr**)factory;
            var createForWindow = (delegate* unmanaged[Stdcall]<IntPtr, IntPtr, Guid*, IntPtr*, int>)vtbl[3];
            var iid = IID_IGraphicsCaptureItem;
            IntPtr itemPtr;
            Marshal.ThrowExceptionForHR(createForWindow(factory, hwnd, &iid, &itemPtr));
            try
            {
                return GraphicsCaptureItem.FromAbi(itemPtr);
            }
            finally
            {
                Marshal.Release(itemPtr);
            }
        }
        finally
        {
            Marshal.Release(factory);
        }
    }

    /// <summary>Wraps a DXGI device as a WinRT IDirect3DDevice for the frame pool.</summary>
    public static IDirect3DDevice CreateWinRTDevice(IntPtr dxgiDevice)
    {
        Marshal.ThrowExceptionForHR(CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice, out var inspectable));
        try
        {
            return MarshalInterface<IDirect3DDevice>.FromAbi(inspectable);
        }
        finally
        {
            Marshal.Release(inspectable);
        }
    }

    /// <summary>Returns an AddRef'd native ID3D11Texture2D* for a captured frame surface.</summary>
    public static IntPtr GetTexturePointer(IDirect3DSurface surface, Guid textureIid)
    {
        var unknown = MarshalInspectable<object>.FromManaged(surface);
        try
        {
            var iid = IID_IDirect3DDxgiInterfaceAccess;
            Marshal.ThrowExceptionForHR(Marshal.QueryInterface(unknown, in iid, out var access));
            try
            {
                // vtable: 0-2 IUnknown, 3 GetInterface(REFIID, void**)
                var vtbl = *(IntPtr**)access;
                var getInterface = (delegate* unmanaged[Stdcall]<IntPtr, Guid*, IntPtr*, int>)vtbl[3];
                IntPtr texture;
                Marshal.ThrowExceptionForHR(getInterface(access, &textureIid, &texture));
                return texture;
            }
            finally
            {
                Marshal.Release(access);
            }
        }
        finally
        {
            Marshal.Release(unknown);
        }
    }
}
