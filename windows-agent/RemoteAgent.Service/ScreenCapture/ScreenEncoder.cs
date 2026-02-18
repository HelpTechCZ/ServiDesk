using System.Runtime.InteropServices;
using SkiaSharp;

namespace RemoteAgent.Service.ScreenCapture;

/// <summary>
/// Enkódování raw framů (BGRA) do JPEG pomocí SkiaSharp (libjpeg-turbo).
/// Zero-copy přístup k pixel bufferu, 3-5x rychlejší než System.Drawing.
/// </summary>
public class ScreenEncoder : IDisposable
{
    private bool _disposed;
    private SKImageInfo _imageInfo;

    public int Width { get; private set; }
    public int Height { get; private set; }
    public int Fps { get; set; } = 20;
    public string Quality { get; set; } = "medium";

    public bool IsRunning => !_disposed;
    public string LastError => "";

    private static readonly Dictionary<string, int> QualityMap = new()
    {
        ["low"] = 30,
        ["medium"] = 50,
        ["high"] = 75
    };

    private int _jpegQuality = 50;

    public void Initialize(int width, int height)
    {
        Width = width;
        Height = height;
        _imageInfo = new SKImageInfo(Width, Height, SKColorType.Bgra8888, SKAlphaType.Premul);
        _jpegQuality = QualityMap.GetValueOrDefault(Quality, 50);

        Console.WriteLine($"[ScreenEncoder] SkiaSharp JPEG encoder initialized: {Width}x{Height}, quality: {Quality}");
    }

    private void UpdateEncoderParams()
    {
        _jpegQuality = QualityMap.GetValueOrDefault(Quality, 50);
    }

    public byte[]? EncodeFrame(byte[] rawBgraPixels)
    {
        if (_disposed) return null;

        try
        {
            var pinned = GCHandle.Alloc(rawBgraPixels, GCHandleType.Pinned);
            try
            {
                using var pixmap = new SKPixmap(_imageInfo, pinned.AddrOfPinnedObject(), Width * 4);
                using var data = pixmap.Encode(SKEncodedImageFormat.Jpeg, _jpegQuality);
                if (data == null) return null;
                return data.ToArray();
            }
            finally
            {
                pinned.Free();
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[ScreenEncoder] Error: {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// Enkóduje jednotlivý region z raw BGRA bufferu do JPEG.
    /// Zero-copy: pinne celý buffer a vytvoří SKPixmap s offsetem na region.
    /// </summary>
    public byte[]? EncodeRegion(byte[] rawBgraPixels, int srcWidth, DirtyRect region)
    {
        if (_disposed) return null;

        try
        {
            var regionInfo = new SKImageInfo(region.Width, region.Height, SKColorType.Bgra8888, SKAlphaType.Premul);
            var srcStride = srcWidth * 4;
            var regionStride = region.Width * 4;

            // Pokud region pokrývá celou šířku, můžeme pinout přímo
            if (region.X == 0 && region.Width == srcWidth)
            {
                var pinned = GCHandle.Alloc(rawBgraPixels, GCHandleType.Pinned);
                try
                {
                    var offset = region.Y * srcStride;
                    var ptr = pinned.AddrOfPinnedObject() + offset;
                    using var pixmap = new SKPixmap(regionInfo, ptr, srcStride);
                    using var data = pixmap.Encode(SKEncodedImageFormat.Jpeg, _jpegQuality);
                    if (data == null) return null;
                    return data.ToArray();
                }
                finally
                {
                    pinned.Free();
                }
            }

            // Region nenavazuje na celou šířku – kopírovat řádky do temp bufferu
            var regionPixels = new byte[region.Height * regionStride];
            for (int y = 0; y < region.Height; y++)
            {
                var srcOffset = (region.Y + y) * srcStride + region.X * 4;
                var dstOffset = y * regionStride;
                var copyLen = Math.Min(regionStride, rawBgraPixels.Length - srcOffset);
                if (copyLen <= 0) break;
                Buffer.BlockCopy(rawBgraPixels, srcOffset, regionPixels, dstOffset, copyLen);
            }

            var pinnedRegion = GCHandle.Alloc(regionPixels, GCHandleType.Pinned);
            try
            {
                using var pixmap = new SKPixmap(regionInfo, pinnedRegion.AddrOfPinnedObject(), regionStride);
                using var data = pixmap.Encode(SKEncodedImageFormat.Jpeg, _jpegQuality);
                if (data == null) return null;
                return data.ToArray();
            }
            finally
            {
                pinnedRegion.Free();
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[ScreenEncoder] EncodeRegion error: {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// Enkóduje seznam dirty regionů. Pokud dirty area > 50% obrazovky, vrátí null (použije se full frame).
    /// </summary>
    public List<(DirtyRect region, byte[] jpeg)>? EncodeRegions(byte[] rawBgraPixels, int srcWidth, int srcHeight, List<DirtyRect> regions)
    {
        long dirtyArea = 0;
        long totalArea = (long)srcWidth * srcHeight;
        foreach (var r in regions)
            dirtyArea += (long)r.Width * r.Height;

        if (dirtyArea > totalArea / 2)
            return null;

        var result = new List<(DirtyRect, byte[])>();
        foreach (var region in regions)
        {
            if (region.Width <= 0 || region.Height <= 0) continue;
            var jpeg = EncodeRegion(rawBgraPixels, srcWidth, region);
            if (jpeg != null)
                result.Add((region, jpeg));
        }

        return result.Count > 0 ? result : null;
    }

    public void ChangeQuality(string quality, int? fps = null)
    {
        Quality = quality;
        if (fps.HasValue) Fps = fps.Value;
        UpdateEncoderParams();
        Console.WriteLine($"[ScreenEncoder] Quality changed: {Quality} (JPEG {_jpegQuality}%), FPS: {Fps}");
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
    }
}
