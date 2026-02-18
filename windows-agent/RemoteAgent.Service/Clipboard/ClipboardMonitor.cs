using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Extensions.Logging;

namespace RemoteAgent.Service.Clipboard;

/// <summary>
/// Monitoruje Windows schránku pomocí GetClipboardSequenceNumber polling.
/// Běží jako SYSTEM service – používá P/Invoke pro přímý přístup ke schránce.
/// </summary>
public class ClipboardMonitor : IDisposable
{
    [DllImport("user32.dll")]
    private static extern bool OpenClipboard(IntPtr hWndNewOwner);

    [DllImport("user32.dll")]
    private static extern bool CloseClipboard();

    [DllImport("user32.dll")]
    private static extern IntPtr GetClipboardData(uint uFormat);

    [DllImport("user32.dll")]
    private static extern bool EmptyClipboard();

    [DllImport("user32.dll")]
    private static extern IntPtr SetClipboardData(uint uFormat, IntPtr hMem);

    [DllImport("user32.dll")]
    private static extern uint GetClipboardSequenceNumber();

    [DllImport("kernel32.dll")]
    private static extern IntPtr GlobalLock(IntPtr hMem);

    [DllImport("kernel32.dll")]
    private static extern bool GlobalUnlock(IntPtr hMem);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GlobalAlloc(uint uFlags, UIntPtr dwBytes);

    [DllImport("kernel32.dll")]
    private static extern UIntPtr GlobalSize(IntPtr hMem);

    private const uint CF_UNICODETEXT = 13;
    private const uint GMEM_MOVEABLE = 0x0002;

    private uint _lastSequenceNumber;
    private bool _suppressNextChange;
    private CancellationTokenSource? _cts;
    private readonly ILogger? _logger;

    public event Action<string>? OnClipboardChanged;

    public ClipboardMonitor(ILogger? logger = null)
    {
        _logger = logger;
        _lastSequenceNumber = GetClipboardSequenceNumber();
    }

    public void StartMonitoring(CancellationToken ct)
    {
        _cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        _ = Task.Run(() => MonitorLoop(_cts.Token), _cts.Token);
    }

    private async Task MonitorLoop(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(500, ct);

                var currentSeq = GetClipboardSequenceNumber();
                if (currentSeq != _lastSequenceNumber)
                {
                    _lastSequenceNumber = currentSeq;

                    if (_suppressNextChange)
                    {
                        _suppressNextChange = false;
                        continue;
                    }

                    var text = GetClipboardText();
                    if (!string.IsNullOrEmpty(text))
                    {
                        _logger?.LogDebug("Clipboard changed: {Length} chars", text.Length);
                        OnClipboardChanged?.Invoke(text);
                    }
                }
            }
            catch (OperationCanceledException) { break; }
            catch (Exception ex)
            {
                _logger?.LogWarning("Clipboard monitor error: {Error}", ex.Message);
            }
        }
    }

    public string? GetClipboardText()
    {
        if (!OpenClipboard(IntPtr.Zero))
            return null;

        try
        {
            var hData = GetClipboardData(CF_UNICODETEXT);
            if (hData == IntPtr.Zero)
                return null;

            var pData = GlobalLock(hData);
            if (pData == IntPtr.Zero)
                return null;

            try
            {
                return Marshal.PtrToStringUni(pData);
            }
            finally
            {
                GlobalUnlock(hData);
            }
        }
        finally
        {
            CloseClipboard();
        }
    }

    public void SetClipboardText(string text)
    {
        _suppressNextChange = true;

        if (!OpenClipboard(IntPtr.Zero))
        {
            _suppressNextChange = false;
            return;
        }

        try
        {
            EmptyClipboard();

            var bytes = Encoding.Unicode.GetBytes(text + "\0");
            var hGlobal = GlobalAlloc(GMEM_MOVEABLE, (UIntPtr)bytes.Length);
            if (hGlobal == IntPtr.Zero) return;

            var pGlobal = GlobalLock(hGlobal);
            if (pGlobal == IntPtr.Zero) return;

            try
            {
                Marshal.Copy(bytes, 0, pGlobal, bytes.Length);
            }
            finally
            {
                GlobalUnlock(hGlobal);
            }

            SetClipboardData(CF_UNICODETEXT, hGlobal);
            _logger?.LogDebug("Clipboard set: {Length} chars", text.Length);
        }
        finally
        {
            CloseClipboard();
        }
    }

    public void StopMonitoring()
    {
        _cts?.Cancel();
    }

    public void Dispose()
    {
        _cts?.Cancel();
        _cts?.Dispose();
    }
}
