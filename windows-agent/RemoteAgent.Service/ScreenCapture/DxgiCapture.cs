using System.Runtime.InteropServices;
using SharpDX;
using SharpDX.Direct3D11;
using SharpDX.DXGI;
using Device = SharpDX.Direct3D11.Device;
using MapFlags = SharpDX.Direct3D11.MapFlags;

namespace RemoteAgent.Service.ScreenCapture;

/// <summary>
/// Zachytávání obrazovky přes DXGI Desktop Duplication API.
/// Vyžaduje běh pod SYSTEM účtem pro přístup k Secure Desktop.
/// </summary>
public class DxgiCapture : IDisposable
{
    private Device? _device;
    private OutputDuplication? _duplication;
    private Texture2D? _stagingTexture;
    private bool _disposed;
    private byte[]? _pixelBuffer; // Pre-alokovaný buffer – eliminuje 8MB alokaci/frame

    public int ScreenWidth { get; private set; }
    public int ScreenHeight { get; private set; }

    public void Initialize(int monitorIndex = 0)
    {
        // Vytvořit D3D11 device
        _device = new Device(SharpDX.Direct3D.DriverType.Hardware,
            DeviceCreationFlags.BgraSupport);

        // Získat DXGI adapter a output
        using var dxgiDevice = _device.QueryInterface<SharpDX.DXGI.Device>();
        using var adapter = dxgiDevice.Adapter;
        using var output = adapter.GetOutput(monitorIndex);
        using var output1 = output.QueryInterface<Output1>();

        // Rozlišení
        var bounds = output.Description.DesktopBounds;
        ScreenWidth = bounds.Right - bounds.Left;
        ScreenHeight = bounds.Bottom - bounds.Top;

        // Desktop Duplication
        _duplication = output1.DuplicateOutput(_device);

        // Pre-alokovat pixel buffer (reuse across frames)
        _pixelBuffer = new byte[ScreenWidth * ScreenHeight * 4]; // BGRA

        // Staging texture pro čtení z GPU → CPU
        _stagingTexture = new Texture2D(_device, new Texture2DDescription
        {
            Width = ScreenWidth,
            Height = ScreenHeight,
            MipLevels = 1,
            ArraySize = 1,
            Format = Format.B8G8R8A8_UNorm,
            SampleDescription = new SampleDescription(1, 0),
            Usage = ResourceUsage.Staging,
            CpuAccessFlags = CpuAccessFlags.Read,
            BindFlags = BindFlags.None,
            OptionFlags = ResourceOptionFlags.None
        });
    }

    /// <summary>
    /// Reinicializace capture – nutné při přepnutí desktopu (UAC/Secure Desktop).
    /// </summary>
    public void Reinitialize(int monitorIndex = 0)
    {
        Dispose();
        _disposed = false;
        Initialize(monitorIndex);
    }

    public CaptureResult? CaptureFrame(int timeoutMs = 100)
    {
        if (_duplication == null || _device == null || _stagingTexture == null)
            return null;

        SharpDX.DXGI.Resource? desktopResource = null;
        bool frameAcquired = false;

        try
        {
            // TryAcquireNextFrame vrací Result – nepoužívat výjimky pro flow control
            var result = _duplication.TryAcquireNextFrame(timeoutMs, out var frameInfo, out desktopResource);

            // WaitTimeout = žádná změna na obrazovce (normální stav)
            if (result.Code == SharpDX.DXGI.ResultCode.WaitTimeout.Code)
                return null;

            // AccessLost = desktop se změnil (UAC, lock screen)
            if (result.Code == SharpDX.DXGI.ResultCode.AccessLost.Code)
                return null;

            // Jiný error
            if (result.Failure)
            {
                result.CheckError();
                return null;
            }

            frameAcquired = true;

            if (desktopResource == null)
                return null;

            // Extrahovat dirty rects před kopírováním
            List<DirtyRect>? dirtyRegions = null;
            try
            {
                if (frameInfo.TotalMetadataBufferSize > 0)
                {
                    var dirtyRectsSize = frameInfo.TotalMetadataBufferSize;
                    var dirtyRectsBuffer = new SharpDX.Mathematics.Interop.RawRectangle[dirtyRectsSize / Marshal.SizeOf<SharpDX.Mathematics.Interop.RawRectangle>()];
                    if (dirtyRectsBuffer.Length > 0)
                    {
                        _duplication.GetFrameDirtyRects(dirtyRectsSize, dirtyRectsBuffer, out var dirtyRectsActualSize);
                        var dirtyCount = dirtyRectsActualSize / Marshal.SizeOf<SharpDX.Mathematics.Interop.RawRectangle>();
                        dirtyRegions = new List<DirtyRect>(dirtyCount);
                        for (int i = 0; i < dirtyCount; i++)
                        {
                            var r = dirtyRectsBuffer[i];
                            dirtyRegions.Add(new DirtyRect
                            {
                                X = r.Left,
                                Y = r.Top,
                                Width = r.Right - r.Left,
                                Height = r.Bottom - r.Top
                            });
                        }
                    }
                }
            }
            catch
            {
                // Dirty rects nedostupné – fallback na full frame
                dirtyRegions = null;
            }

            using var texture = desktopResource.QueryInterface<Texture2D>();
            _device.ImmediateContext.CopyResource(texture, _stagingTexture);

            var dataBox = _device.ImmediateContext.MapSubresource(
                _stagingTexture, 0, MapMode.Read, MapFlags.None);

            try
            {
                var rowPitch = dataBox.RowPitch;
                var expectedPitch = ScreenWidth * 4; // BGRA = 4 bytes per pixel

                // Reuse pre-alokovaného bufferu místo new byte[] každý frame
                if (rowPitch == expectedPitch)
                {
                    // Bez paddingu – rychlá cesta
                    Marshal.Copy(dataBox.DataPointer, _pixelBuffer!, 0, _pixelBuffer!.Length);
                }
                else
                {
                    // RowPitch má padding – kopírovat řádek po řádku
                    for (int y = 0; y < ScreenHeight; y++)
                    {
                        var srcOffset = dataBox.DataPointer + y * rowPitch;
                        Marshal.Copy(srcOffset, _pixelBuffer!, y * expectedPitch, expectedPitch);
                    }
                }

                return new CaptureResult
                {
                    Width = ScreenWidth,
                    Height = ScreenHeight,
                    RowPitch = expectedPitch,
                    PixelData = _pixelBuffer!,
                    DirtyRegions = dirtyRegions
                };
            }
            finally
            {
                _device.ImmediateContext.UnmapSubresource(_stagingTexture, 0);
            }
        }
        catch (SharpDXException ex)
        {
            Console.WriteLine($"[DxgiCapture] Error: 0x{ex.ResultCode.Code:X8} - {ex.Message}");
            return null;
        }
        finally
        {
            desktopResource?.Dispose();
            // ReleaseFrame POUZE když frame byl skutečně získán
            if (frameAcquired)
            {
                try { _duplication?.ReleaseFrame(); } catch { }
            }
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _stagingTexture?.Dispose();
        _duplication?.Dispose();
        _device?.Dispose();
    }
}

public class CaptureResult
{
    public int Width { get; set; }
    public int Height { get; set; }
    public int RowPitch { get; set; }
    public byte[] PixelData { get; set; } = Array.Empty<byte>(); // BGRA
    public List<DirtyRect>? DirtyRegions { get; set; }
}

public class DirtyRect
{
    public int X { get; set; }
    public int Y { get; set; }
    public int Width { get; set; }
    public int Height { get; set; }
}
