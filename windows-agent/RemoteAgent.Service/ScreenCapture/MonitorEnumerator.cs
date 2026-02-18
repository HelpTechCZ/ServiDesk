using SharpDX.DXGI;

namespace RemoteAgent.Service.ScreenCapture;

/// <summary>
/// Enumeruje dostupné monitory přes DXGI adapter.
/// </summary>
public static class MonitorEnumerator
{
    public class MonitorInfo
    {
        public int Index { get; set; }
        public string Name { get; set; } = "";
        public int Width { get; set; }
        public int Height { get; set; }
        public bool IsPrimary { get; set; }
    }

    public static List<MonitorInfo> GetMonitors()
    {
        var monitors = new List<MonitorInfo>();

        using var factory = new Factory1();
        using var adapter = factory.GetAdapter1(0);

        for (int i = 0; i < adapter.GetOutputCount(); i++)
        {
            using var output = adapter.GetOutput(i);
            var desc = output.Description;
            var bounds = desc.DesktopBounds;

            monitors.Add(new MonitorInfo
            {
                Index = i,
                Name = desc.DeviceName,
                Width = bounds.Right - bounds.Left,
                Height = bounds.Bottom - bounds.Top,
                IsPrimary = (bounds.Left == 0 && bounds.Top == 0)
            });
        }

        return monitors;
    }
}
