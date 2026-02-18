using System.Runtime.InteropServices;

namespace RemoteAgent.Service.ScreenCapture;

public class DesktopSwitcher
{
    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr OpenInputDesktop(uint dwFlags, bool fInherit, uint dwDesiredAccess);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool CloseDesktop(IntPtr hDesktop);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetThreadDesktop(IntPtr hDesktop);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool GetUserObjectInformation(IntPtr hObj, int nIndex, byte[] pvInfo, int nLength, out int lpnLengthNeeded);

    private const uint GENERIC_ALL = 0x10000000;
    private const int UOI_NAME = 2;

    private string _currentDesktopName;
    private bool _initialized;

    public DesktopSwitcher()
    {
        // Uložit aktuální desktop při vytvoření - zabránit falešné detekci změny
        _currentDesktopName = GetActiveDesktopName();
        _initialized = true;
    }

    public string GetActiveDesktopName()
    {
        var hDesktop = OpenInputDesktop(0, false, GENERIC_ALL);
        if (hDesktop == IntPtr.Zero)
            return "Default";

        try
        {
            var nameBuffer = new byte[256];
            if (GetUserObjectInformation(hDesktop, UOI_NAME, nameBuffer, nameBuffer.Length, out var needed))
            {
                return System.Text.Encoding.Unicode.GetString(nameBuffer, 0, needed).TrimEnd('\0');
            }
            return "Default";
        }
        finally
        {
            CloseDesktop(hDesktop);
        }
    }

    /// <summary>
    /// Periodická kontrola desktopu. Vrací true jen při skutečné změně.
    /// </summary>
    public bool CheckDesktopChange()
    {
        var currentName = GetActiveDesktopName();
        if (currentName != _currentDesktopName && _initialized)
        {
            Console.WriteLine($"[DesktopSwitcher] Desktop changed: {_currentDesktopName} -> {currentName}");
            _currentDesktopName = currentName;
            return true;
        }
        return false;
    }
}
