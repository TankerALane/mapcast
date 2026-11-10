using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using MapcastCompanion.Interop;
using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DXGI;
using Box = Vortice.Mathematics.Box;
using Size = System.Drawing.Size;
using Windows.Graphics;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.DirectX.Direct3D11;

namespace MapcastCompanion.Capture;

/// <summary>
/// Passive window capture via Windows Graphics Capture.
/// Reads only what Windows composites on screen for the target window. No game memory
/// access, no input, no hooks into the game process.
/// </summary>
public sealed class CaptureEngine : IDisposable
{
    private readonly ID3D11Device _device;
    private readonly ID3D11DeviceContext _context;
    private readonly IDirect3DDevice _winrtDevice;
    private readonly object _bufferLock = new();
    private readonly object _sessionLock = new();

    private GraphicsCaptureItem? _item;
    private Direct3D11CaptureFramePool? _pool;
    private GraphicsCaptureSession? _session;
    private SizeInt32 _poolSize;

    private ID3D11Texture2D? _cropStaging;
    private Size _cropStagingSize;
    private ID3D11Texture2D? _fullStaging;
    private Size _fullStagingSize;

    private byte[] _buffer = Array.Empty<byte>();
    private Size _bufferSize;
    private long _frameNumber;

    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private double _lastProcessed = -1;
    private double _lastDetect = -10;
    private volatile bool _detectRequested;
    private TaskCompletionSource<Bitmap?>? _snapshot;
    private Rectangle? _region;

    /// <summary>Region of the captured window to show, in captured-frame pixels.</summary>
    public Rectangle? Region
    {
        get { lock (_sessionLock) return _region; }
        set { lock (_sessionLock) _region = value; }
    }

    /// <summary>When true, the region follows the magenta marker border automatically.</summary>
    public bool AutoDetect { get; set; } = true;

    public int TargetFps { get; set; } = 30;

    public bool IsCapturing => _session != null;

    public Size FrameSize { get; private set; }

    /// <summary>Raised (on a worker thread) when a new cropped frame is ready.</summary>
    public event Action? FrameReady;

    /// <summary>Raised (on a worker thread) when the marker is found, moves, or is lost (null).</summary>
    public event Action<Rectangle?>? MarkerChanged;

    /// <summary>Raised (on a worker thread) when the captured window closes.</summary>
    public event Action? TargetClosed;

    public static bool IsSupported()
    {
        try { return GraphicsCaptureSession.IsSupported(); }
        catch { return false; }
    }

    public CaptureEngine()
    {
        var levels = new[] { FeatureLevel.Level_11_1, FeatureLevel.Level_11_0, FeatureLevel.Level_10_1, FeatureLevel.Level_10_0 };
        var hr = D3D11.D3D11CreateDevice(null, DriverType.Hardware, DeviceCreationFlags.BgraSupport, levels,
            out ID3D11Device device, out ID3D11DeviceContext context);
        if (hr.Failure)
        {
            // Fall back to the software rasterizer (very old or remote-desktop GPUs).
            D3D11.D3D11CreateDevice(null, DriverType.Warp, DeviceCreationFlags.BgraSupport, levels,
                out device, out context).CheckError();
        }
        _device = device!;
        _context = context!;
        using var dxgiDevice = _device.QueryInterface<IDXGIDevice>();
        _winrtDevice = WgcInterop.CreateWinRTDevice(dxgiDevice.NativePointer);
    }

    public void Start(IntPtr hwnd)
    {
        Stop();
        var item = WgcInterop.CreateItemForWindow(hwnd);
        lock (_sessionLock)
        {
            _item = item;
            _item.Closed += OnItemClosed;
            _poolSize = item.Size;
            FrameSize = new Size(item.Size.Width, item.Size.Height);
            _pool = Direct3D11CaptureFramePool.CreateFreeThreaded(_winrtDevice, DirectXPixelFormat.B8G8R8A8UIntNormalized, 2, item.Size);
            _pool.FrameArrived += OnFrameArrived;
            _session = _pool.CreateCaptureSession(item);
            TryDisableCursorAndBorder(_session);
            _detectRequested = true;
            _session.StartCapture();
        }
    }

    public void Stop()
    {
        lock (_sessionLock)
        {
            if (_pool != null) _pool.FrameArrived -= OnFrameArrived;
            if (_item != null) _item.Closed -= OnItemClosed;
            _session?.Dispose();
            _pool?.Dispose();
            _session = null;
            _pool = null;
            _item = null;
        }
    }

    public void RequestDetect() => _detectRequested = true;

    /// <summary>Grabs one full frame of the target window (for manual region selection).</summary>
    public Task<Bitmap?> SnapshotAsync()
    {
        var tcs = new TaskCompletionSource<Bitmap?>(TaskCreationOptions.RunContinuationsAsynchronously);
        _snapshot = tcs;
        return tcs.Task;
    }

    /// <summary>Copies the latest cropped frame into <paramref name="target"/>, reallocating it if the size changed.</summary>
    public bool CopyLatest(ref Bitmap? target, ref long lastSeenFrame)
    {
        lock (_bufferLock)
        {
            if (_frameNumber == lastSeenFrame || _bufferSize.IsEmpty) return false;
            lastSeenFrame = _frameNumber;
            if (target == null || target.Size != _bufferSize)
            {
                target?.Dispose();
                target = new Bitmap(_bufferSize.Width, _bufferSize.Height, PixelFormat.Format32bppRgb);
            }
            var data = target.LockBits(new Rectangle(Point.Empty, _bufferSize), ImageLockMode.WriteOnly, PixelFormat.Format32bppRgb);
            try
            {
                int rowBytes = _bufferSize.Width * 4;
                for (int y = 0; y < _bufferSize.Height; y++)
                    Marshal.Copy(_buffer, y * rowBytes, data.Scan0 + y * data.Stride, rowBytes);
            }
            finally
            {
                target.UnlockBits(data);
            }
            return true;
        }
    }

    private static void TryDisableCursorAndBorder(GraphicsCaptureSession session)
    {
        try { session.IsCursorCaptureEnabled = false; } catch { /* older Windows 10 */ }
        try
        {
            // Windows 11: hide the yellow "being captured" border. Silently ignored where unsupported.
            if (Windows.Foundation.Metadata.ApiInformation.IsPropertyPresent("Windows.Graphics.Capture.GraphicsCaptureSession", "IsBorderRequired"))
            {
                _ = GraphicsCaptureAccess.RequestAccessAsync(GraphicsCaptureAccessKind.Borderless);
                session.IsBorderRequired = false;
            }
        }
        catch { /* not available */ }
    }

    private void OnItemClosed(GraphicsCaptureItem sender, object args)
    {
        Stop();
        TargetClosed?.Invoke();
    }

    private void OnFrameArrived(Direct3D11CaptureFramePool sender, object args)
    {
        try
        {
            using var frame = sender.TryGetNextFrame();
            if (frame == null) return;

            var size = frame.ContentSize;
            if (size.Width <= 0 || size.Height <= 0) return; // minimised
            if (size.Width != _poolSize.Width || size.Height != _poolSize.Height)
            {
                _poolSize = size;
                FrameSize = new Size(size.Width, size.Height);
                sender.Recreate(_winrtDevice, DirectXPixelFormat.B8G8R8A8UIntNormalized, 2, size);
                _detectRequested = true;
                return; // next frame comes at the new size
            }

            double now = _clock.Elapsed.TotalSeconds;
            var snapshot = Interlocked.Exchange(ref _snapshot, null);
            bool detectDue = AutoDetect && (_detectRequested || now - _lastDetect >= 1.0);
            bool frameDue = now - _lastProcessed >= 1.0 / Math.Max(1, TargetFps);
            if (!detectDue && !frameDue && snapshot == null) return;

            var texPtr = WgcInterop.GetTexturePointer(frame.Surface, typeof(ID3D11Texture2D).GUID);
            using var texture = new ID3D11Texture2D(texPtr);

            if (detectDue || snapshot != null)
            {
                _lastDetect = now;
                _detectRequested = false;
                ProcessFullFrame(texture, size, detectDue, snapshot);
            }

            if (frameDue)
            {
                _lastProcessed = now;
                var region = Region;
                if (region is { } r)
                {
                    r.Intersect(new Rectangle(0, 0, size.Width, size.Height));
                    if (r.Width > 0 && r.Height > 0) CopyCrop(texture, r);
                }
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine("Frame error: " + ex);
        }
    }

    private unsafe void ProcessFullFrame(ID3D11Texture2D texture, SizeInt32 size, bool detect, TaskCompletionSource<Bitmap?>? snapshot)
    {
        var staging = EnsureStaging(ref _fullStaging, ref _fullStagingSize, new Size(size.Width, size.Height));
        _context.CopySubresourceRegion(staging, 0, 0, 0, 0, texture, 0, new Box(0, 0, 0, size.Width, size.Height, 1));
        var mapped = _context.Map(staging, 0, MapMode.Read, Vortice.Direct3D11.MapFlags.None);
        try
        {
            byte* pixels = (byte*)mapped.DataPointer;
            int stride = (int)mapped.RowPitch;

            if (detect)
            {
                var current = Region;
                if (current is not { } cur || !MarkerDetector.StillPresent(pixels, size.Width, size.Height, stride, cur))
                {
                    var found = MarkerDetector.Find(pixels, size.Width, size.Height, stride);
                    if (found != current)
                    {
                        if (found != null) Region = found;
                        MarkerChanged?.Invoke(found);
                    }
                }
            }

            if (snapshot != null)
            {
                var bmp = new Bitmap(size.Width, size.Height, PixelFormat.Format32bppRgb);
                var data = bmp.LockBits(new Rectangle(0, 0, size.Width, size.Height), ImageLockMode.WriteOnly, PixelFormat.Format32bppRgb);
                for (int y = 0; y < size.Height; y++)
                    Buffer.MemoryCopy(pixels + (long)y * stride, (byte*)data.Scan0 + (long)y * data.Stride, data.Stride, size.Width * 4);
                bmp.UnlockBits(data);
                snapshot.TrySetResult(bmp);
            }
        }
        finally
        {
            _context.Unmap(staging, 0);
        }
    }

    private unsafe void CopyCrop(ID3D11Texture2D texture, Rectangle r)
    {
        var staging = EnsureStaging(ref _cropStaging, ref _cropStagingSize, r.Size);
        _context.CopySubresourceRegion(staging, 0, 0, 0, 0, texture, 0, new Box(r.Left, r.Top, 0, r.Right, r.Bottom, 1));
        var mapped = _context.Map(staging, 0, MapMode.Read, Vortice.Direct3D11.MapFlags.None);
        try
        {
            lock (_bufferLock)
            {
                int rowBytes = r.Width * 4;
                if (_buffer.Length != rowBytes * r.Height) _buffer = new byte[rowBytes * r.Height];
                fixed (byte* dst = _buffer)
                {
                    byte* src = (byte*)mapped.DataPointer;
                    for (int y = 0; y < r.Height; y++)
                        Buffer.MemoryCopy(src + (long)y * mapped.RowPitch, dst + (long)y * rowBytes, rowBytes, rowBytes);
                }
                _bufferSize = r.Size;
                _frameNumber++;
            }
        }
        finally
        {
            _context.Unmap(staging, 0);
        }
        FrameReady?.Invoke();
    }

    private ID3D11Texture2D EnsureStaging(ref ID3D11Texture2D? tex, ref Size current, Size wanted)
    {
        if (tex != null && current == wanted) return tex;
        tex?.Dispose();
        var desc = new Texture2DDescription
        {
            Width = (uint)wanted.Width,
            Height = (uint)wanted.Height,
            MipLevels = 1,
            ArraySize = 1,
            Format = Format.B8G8R8A8_UNorm,
            SampleDescription = new SampleDescription(1, 0),
            Usage = ResourceUsage.Staging,
            BindFlags = BindFlags.None,
            CPUAccessFlags = CpuAccessFlags.Read,
            MiscFlags = ResourceOptionFlags.None,
        };
        tex = _device.CreateTexture2D(desc);
        current = wanted;
        return tex;
    }

    public void Dispose()
    {
        Stop();
        _cropStaging?.Dispose();
        _fullStaging?.Dispose();
        _context.Dispose();
        _device.Dispose();
    }
}
