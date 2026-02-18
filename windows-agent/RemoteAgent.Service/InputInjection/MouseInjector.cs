using System.Runtime.InteropServices;

namespace RemoteAgent.Service.InputInjection;

/// <summary>
/// Simulace myši pomocí SendInput API (user32.dll).
/// </summary>
public class MouseInjector
{
    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    private const uint INPUT_MOUSE = 0;
    private const uint MOUSEEVENTF_MOVE = 0x0001;
    private const uint MOUSEEVENTF_ABSOLUTE = 0x8000;
    private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    private const uint MOUSEEVENTF_LEFTUP = 0x0004;
    private const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    private const uint MOUSEEVENTF_RIGHTUP = 0x0010;
    private const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
    private const uint MOUSEEVENTF_MIDDLEUP = 0x0040;
    private const uint MOUSEEVENTF_WHEEL = 0x0800;
    private const uint MOUSEEVENTF_HWHEEL = 0x1000;

    public void MoveTo(double normalizedX, double normalizedY)
    {
        // Normalizované souřadnice 0.0-1.0 → absolutní 0-65535
        var absX = (int)(normalizedX * 65535);
        var absY = (int)(normalizedY * 65535);

        var input = new INPUT
        {
            type = INPUT_MOUSE,
            union = new InputUnion
            {
                mi = new MOUSEINPUT
                {
                    dx = absX,
                    dy = absY,
                    dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE
                }
            }
        };

        SendInput(1, new[] { input }, Marshal.SizeOf<INPUT>());
    }

    public void Click(string button, string action, double normalizedX, double normalizedY)
    {
        MoveTo(normalizedX, normalizedY);

        uint flags = (button, action) switch
        {
            ("left", "down") => MOUSEEVENTF_LEFTDOWN,
            ("left", "up") => MOUSEEVENTF_LEFTUP,
            ("right", "down") => MOUSEEVENTF_RIGHTDOWN,
            ("right", "up") => MOUSEEVENTF_RIGHTUP,
            ("middle", "down") => MOUSEEVENTF_MIDDLEDOWN,
            ("middle", "up") => MOUSEEVENTF_MIDDLEUP,
            _ => 0
        };

        if (flags == 0) return;

        var input = new INPUT
        {
            type = INPUT_MOUSE,
            union = new InputUnion { mi = new MOUSEINPUT { dwFlags = flags } }
        };

        SendInput(1, new[] { input }, Marshal.SizeOf<INPUT>());
    }

    public void Scroll(int deltaX, int deltaY)
    {
        if (deltaY != 0)
        {
            var input = new INPUT
            {
                type = INPUT_MOUSE,
                union = new InputUnion
                {
                    mi = new MOUSEINPUT { dwFlags = MOUSEEVENTF_WHEEL, mouseData = deltaY }
                }
            };
            SendInput(1, new[] { input }, Marshal.SizeOf<INPUT>());
        }

        if (deltaX != 0)
        {
            var input = new INPUT
            {
                type = INPUT_MOUSE,
                union = new InputUnion
                {
                    mi = new MOUSEINPUT { dwFlags = MOUSEEVENTF_HWHEEL, mouseData = deltaX }
                }
            };
            SendInput(1, new[] { input }, Marshal.SizeOf<INPUT>());
        }
    }

    // ── Struktury pro SendInput ──

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public InputUnion union;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public int mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }
}
