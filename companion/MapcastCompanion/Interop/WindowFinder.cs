using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace MapcastCompanion.Interop;

public sealed record TargetWindow(IntPtr Handle, string Title, string ProcessName, string? ExePath)
{
    public override string ToString() => string.IsNullOrEmpty(Title) ? ProcessName : $"{Title}  ({ProcessName})";
}

/// <summary>Finds top-level windows. Read-only: only window titles and process names are inspected.</summary>
public static class WindowFinder
{
    private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int max);
    [DllImport("user32.dll")] private static extern int GetWindowTextLength(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hwnd, uint cmd);
    [DllImport("user32.dll")] private static extern int GetWindowLong(IntPtr hwnd, int index);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out int value, int size);

    private const uint GW_OWNER = 4;
    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_TOOLWINDOW = 0x80;
    private const int DWMWA_CLOAKED = 14;

    public static bool IsAlive(IntPtr hwnd) => hwnd != IntPtr.Zero && IsWindow(hwnd);
    public static bool IsMinimized(IntPtr hwnd) => IsIconic(hwnd);

    /// <summary>All visible, captureable application windows (excluding this app).</summary>
    public static List<TargetWindow> ListWindows()
    {
        var list = new List<TargetWindow>();
        int self = Environment.ProcessId;
        EnumWindows((hwnd, _) =>
        {
            if (!IsWindowVisible(hwnd) || GetWindow(hwnd, GW_OWNER) != IntPtr.Zero) return true;
            if ((GetWindowLong(hwnd, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) != 0) return true;
            if (DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, out var cloaked, sizeof(int)) == 0 && cloaked != 0) return true;
            int len = GetWindowTextLength(hwnd);
            if (len == 0) return true;
            var sb = new StringBuilder(len + 1);
            GetWindowText(hwnd, sb, sb.Capacity);
            GetWindowThreadProcessId(hwnd, out var pid);
            if (pid == self) return true;
            string name = "?";
            string? path = null;
            try
            {
                using var p = Process.GetProcessById((int)pid);
                name = p.ProcessName;
                try { path = p.MainModule?.FileName; } catch { /* access denied for some processes */ }
            }
            catch { }
            list.Add(new TargetWindow(hwnd, sb.ToString(), name, path));
            return true;
        }, IntPtr.Zero);
        return list;
    }

    /// <summary>
    /// Finds the World of Warcraft window. Prefers the "_forever_" client when several are running.
    /// </summary>
    public static TargetWindow? FindWow()
    {
        var candidates = ListWindows()
            .Where(w => w.ProcessName.StartsWith("Wow", StringComparison.OrdinalIgnoreCase)
                        && w.Title.Contains("World of Warcraft", StringComparison.OrdinalIgnoreCase))
            .ToList();
        return candidates.FirstOrDefault(w => w.ExePath?.Contains("_forever_", StringComparison.OrdinalIgnoreCase) == true)
               ?? candidates.FirstOrDefault();
    }

    public static TargetWindow? FindByTitle(string titleContains) =>
        ListWindows().FirstOrDefault(w => w.Title.Contains(titleContains, StringComparison.OrdinalIgnoreCase));
}
