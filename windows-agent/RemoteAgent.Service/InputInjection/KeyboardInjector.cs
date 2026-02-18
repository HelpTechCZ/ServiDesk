using System.Runtime.InteropServices;

namespace RemoteAgent.Service.InputInjection;

/// <summary>
/// Simulace klávesnice pomocí SendInput API.
/// Podpora Ctrl+Alt+Del přes SAS (Secure Attention Sequence).
/// </summary>
public class KeyboardInjector
{
    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    // SAS – Secure Attention Sequence pro Ctrl+Alt+Del
    [DllImport("sas.dll", SetLastError = true)]
    private static extern void SendSAS(bool asUser);

    private const uint INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYDOWN = 0x0000;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
    private const uint KEYEVENTF_UNICODE = 0x0004;

    // Běžné virtual key codes
    private const ushort VK_CONTROL = 0x11;
    private const ushort VK_MENU = 0x12;    // Alt
    private const ushort VK_DELETE = 0x2E;
    private const ushort VK_TAB = 0x09;
    private const ushort VK_F4 = 0x73;

    public void KeyDown(ushort virtualKeyCode)
    {
        var input = CreateKeyInput(virtualKeyCode, KEYEVENTF_KEYDOWN);
        SendInput(1, new[] { input }, Marshal.SizeOf<INPUT>());
    }

    public void KeyUp(ushort virtualKeyCode)
    {
        var input = CreateKeyInput(virtualKeyCode, KEYEVENTF_KEYUP);
        SendInput(1, new[] { input }, Marshal.SizeOf<INPUT>());
    }

    public void KeyPress(ushort virtualKeyCode)
    {
        KeyDown(virtualKeyCode);
        KeyUp(virtualKeyCode);
    }

    /// <summary>
    /// Unicode injection – posílá přímo Unicode znak nezávisle na Windows keyboard layoutu.
    /// Používá se pro české znaky (ě, š, č, ř, ž...) a další speciální znaky.
    /// </summary>
    public void UnicodeKeyDown(char c)
    {
        var input = new INPUT
        {
            type = INPUT_KEYBOARD,
            union = new InputUnion
            {
                ki = new KEYBDINPUT
                {
                    wVk = 0,
                    wScan = (ushort)c,
                    dwFlags = KEYEVENTF_UNICODE,
                    time = 0,
                    dwExtraInfo = IntPtr.Zero
                }
            }
        };
        SendInput(1, new[] { input }, Marshal.SizeOf<INPUT>());
    }

    public void UnicodeKeyUp(char c)
    {
        var input = new INPUT
        {
            type = INPUT_KEYBOARD,
            union = new InputUnion
            {
                ki = new KEYBDINPUT
                {
                    wVk = 0,
                    wScan = (ushort)c,
                    dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP,
                    time = 0,
                    dwExtraInfo = IntPtr.Zero
                }
            }
        };
        SendInput(1, new[] { input }, Marshal.SizeOf<INPUT>());
    }

    /// <summary>
    /// Zpracování speciálních kombinací kláves.
    /// </summary>
    public void SendSpecialKey(string combination)
    {
        switch (combination)
        {
            case "ctrl_alt_del":
                SendCtrlAltDel();
                break;

            case "alt_tab":
                KeyDown(VK_MENU);
                KeyPress(VK_TAB);
                KeyUp(VK_MENU);
                break;

            case "alt_f4":
                KeyDown(VK_MENU);
                KeyPress(VK_F4);
                KeyUp(VK_MENU);
                break;
        }
    }

    private void SendCtrlAltDel()
    {
        // SAS DLL je k dispozici na Windows 7+ v System32
        // Služba běžící pod SYSTEM má oprávnění ji volat
        try
        {
            EnsureSasRegistryKey();
            SendSAS(false);
        }
        catch (DllNotFoundException)
        {
            // sas.dll neexistuje – fallback přes SendInput
            SimulateCtrlAltDel();
        }
        catch (Exception)
        {
            SimulateCtrlAltDel();
        }
    }

    private void SimulateCtrlAltDel()
    {
        // SendInput nedokáže vyvolat pravý SAS, ale na některých
        // systémech otevře Task Manager nebo zamykací obrazovku
        KeyDown(VK_CONTROL);
        KeyDown(VK_MENU);
        KeyDown(VK_DELETE);
        Thread.Sleep(50);
        KeyUp(VK_DELETE);
        KeyUp(VK_MENU);
        KeyUp(VK_CONTROL);
    }

    private static void EnsureSasRegistryKey()
    {
        try
        {
            using var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(
                @"SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System", true);
            if (key != null)
            {
                var val = key.GetValue("SoftwareSASGeneration");
                if (val == null || (int)val < 3)
                {
                    // 3 = povoluje SAS z aplikací i služeb
                    key.SetValue("SoftwareSASGeneration", 3, Microsoft.Win32.RegistryValueKind.DWord);
                }
            }
        }
        catch { /* Service nemusí mít právo k zápisu */ }
    }

    private static INPUT CreateKeyInput(ushort vk, uint flags)
    {
        // Rozšířené klávesy (šipky, Insert, Delete, atd.)
        if (IsExtendedKey(vk))
            flags |= KEYEVENTF_EXTENDEDKEY;

        return new INPUT
        {
            type = INPUT_KEYBOARD,
            union = new InputUnion
            {
                ki = new KEYBDINPUT
                {
                    wVk = vk,
                    wScan = 0,
                    dwFlags = flags,
                    time = 0,
                    dwExtraInfo = IntPtr.Zero
                }
            }
        };
    }

    private static bool IsExtendedKey(ushort vk)
    {
        return vk is >= 0x21 and <= 0x2E  // PageUp, PageDown, End, Home, Arrows, Insert, Delete
            or 0x5B or 0x5C               // Win keys
            or 0x6F                       // Num /
            or 0x0D;                      // Num Enter (context-dependent)
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

    // MOUSEINPUT musí být v unii kvůli správné velikosti INPUT struktury pro SendInput
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
