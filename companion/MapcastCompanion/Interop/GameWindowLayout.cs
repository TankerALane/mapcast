using System.Runtime.InteropServices;

namespace MapcastCompanion.Interop;

public enum StripEdge { Top, Bottom }

/// <summary>
/// Off-screen mode: makes the game window taller than its monitor so that a strip
/// of it lies where no monitor shows it. Mapcast draws the map in that strip and
/// keeps the rest of the game UI on the visible part. Windows Graphics Capture
/// still captures the hidden strip.
///
/// This only sets the game window's size and position (the same thing dragging
/// its edges does). It does not read memory, send input or automate anything.
/// </summary>
public static class GameWindowLayout
{
    /// <summary>
    /// Picks an edge of <paramref name="monitor"/> where a band of <paramref name="extra"/>
    /// pixels (strip plus window frame) touches no monitor. Preferred edge first.
    /// </summary>
    public static StripEdge? ChooseEdge(Rectangle monitor, IReadOnlyList<Rectangle> monitors, int extra, StripEdge preferred)
    {
        foreach (var edge in preferred == StripEdge.Top
                     ? new[] { StripEdge.Top, StripEdge.Bottom }
                     : new[] { StripEdge.Bottom, StripEdge.Top })
        {
            var band = edge == StripEdge.Top
                ? new Rectangle(monitor.Left, monitor.Top - extra, monitor.Width, extra)
                : new Rectangle(monitor.Left, monitor.Bottom, monitor.Width, extra);
            if (!monitors.Any(m => m.IntersectsWith(band))) return edge;
        }
        return null;
    }

    /// <summary>The client rectangle (screen pixels) the game should have in off-screen mode.</summary>
    public static Rectangle TargetClient(Rectangle monitor, StripEdge edge, int strip) =>
        edge == StripEdge.Top
            ? new Rectangle(monitor.Left, monitor.Top - strip, monitor.Width, monitor.Height + strip)
            : new Rectangle(monitor.Left, monitor.Top, monitor.Width, monitor.Height + strip);

    public sealed record Result(bool Ok, string Message, StripEdge Edge = StripEdge.Top, Rectangle Client = default, string Command = "");

    /// <summary>Insets (left, top, right, bottom) of <paramref name="inner"/> inside <paramref name="outer"/>.</summary>
    public static string Insets(Rectangle outer, Rectangle inner) =>
        $"{inner.Left - outer.Left},{inner.Top - outer.Top},{outer.Right - inner.Right},{outer.Bottom - inner.Bottom}";

    /// <summary>
    /// Span mode: the client covers both monitors (their bounding box). Returns that box and the
    /// /mapcast command telling the addon where the game and map monitors are inside it,
    /// or null when the box would also cover part of another monitor.
    /// </summary>
    public static (Rectangle Client, string Command)? PlanSpan(Rectangle game, Rectangle map, IReadOnlyList<Rectangle> others)
    {
        var client = Rectangle.Union(game, map);
        if (others.Any(o => o.IntersectsWith(client))) return null;
        return (client, $"/mapcast span {Insets(client, game)} {Insets(client, map)}");
    }

    /// <summary>Spans the game window over its own monitor and <paramref name="mapScreen"/>.</summary>
    public static Result Span(IntPtr hwnd, Screen mapScreen, out Rectangle previous)
    {
        previous = GetWindowRectangle(hwnd);
        if (!CheckWindowed(hwnd, out var why)) return new Result(false, why);
        if (IsZoomed(hwnd)) { ShowWindow(hwnd, SW_RESTORE); previous = GetWindowRectangle(hwnd); }

        var game = Screen.FromHandle(hwnd).Bounds;
        var map = mapScreen.Bounds;
        if (game == map) return new Result(false, "The game is already on that monitor. Pick the monitor the map should go on.");
        var others = Screen.AllScreens.Select(s => s.Bounds).Where(b => b != game && b != map).ToList();
        var plan = PlanSpan(game, map, others);
        if (plan == null)
            return new Result(false, "A game window covering both of those monitors would also cover part of another monitor. " +
                "Pick a monitor directly next to the game's monitor.");
        return SetClient(hwnd, plan.Value.Client) is { } err
            ? new Result(false, err)
            : new Result(true, "", Client: plan.Value.Client, Command: plan.Value.Command);
    }

    private static bool CheckWindowed(IntPtr hwnd, out string why)
    {
        long style = GetWindowLongPtr(hwnd, GWL_STYLE).ToInt64();
        why = "";
        if ((style & WS_CAPTION) == WS_CAPTION) return true;
        why = "The game is in Windowed (Fullscreen) mode, which always fills one monitor.\n\n" +
              "In World of Warcraft open Options > Graphics, set Display Mode to \"Windowed\", then try again.";
        return false;
    }

    /// <summary>Sizes the window so its client area is <paramref name="client"/>. Returns an error or null.</summary>
    private static string? SetClient(IntPtr hwnd, Rectangle client)
    {
        long style = GetWindowLongPtr(hwnd, GWL_STYLE).ToInt64();
        long exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64();
        uint dpi = GetDpiForWindow(hwnd);
        if (dpi == 0) dpi = 96;
        var win = new RECT { Left = client.Left, Top = client.Top, Right = client.Right, Bottom = client.Bottom };
        AdjustWindowRectExForDpi(ref win, (uint)style, false, (uint)exStyle, dpi);
        if (!SetWindowPos(hwnd, IntPtr.Zero, win.Left, win.Top, win.Right - win.Left, win.Bottom - win.Top,
                SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER))
            return "Windows refused to resize the game window (error " + Marshal.GetLastWin32Error() +
                   "). If the game runs as administrator, run Mapcast Companion as administrator too.";
        return null;
    }

    /// <summary>Extends the window. <paramref name="previous"/> receives its old window rectangle.</summary>
    public static Result Extend(IntPtr hwnd, int strip, StripEdge preferred, out Rectangle previous)
    {
        previous = GetWindowRectangle(hwnd);
        long style = GetWindowLongPtr(hwnd, GWL_STYLE).ToInt64();
        long exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64();
        if ((style & WS_CAPTION) != WS_CAPTION)
            return new Result(false,
                "The game is in Windowed (Fullscreen) mode, which always fills the monitor.\n\n" +
                "In World of Warcraft open Options > Graphics, set Display Mode to \"Windowed\", then try again.");

        if (IsZoomed(hwnd)) { ShowWindow(hwnd, SW_RESTORE); previous = GetWindowRectangle(hwnd); }

        var screen = Screen.FromHandle(hwnd);
        var monitor = screen.Bounds;
        uint dpi = GetDpiForWindow(hwnd);
        if (dpi == 0) dpi = 96;

        // Frame size around the client area for this window's style.
        var probe = new RECT { Left = 0, Top = 0, Right = 100, Bottom = 100 };
        AdjustWindowRectExForDpi(ref probe, (uint)style, false, (uint)exStyle, dpi);
        int frameTop = -probe.Top, frameBottom = probe.Bottom - 100;

        var monitors = Screen.AllScreens.Select(s => s.Bounds).Where(b => b != monitor).ToList();
        var edge = ChooseEdge(monitor, monitors, strip + Math.Max(frameTop, frameBottom), preferred);
        if (edge == null)
            return new Result(false,
                $"There is another monitor directly above and below \"{screen.DeviceName}\", so there is nowhere to hide a strip.\n\n" +
                "Move the game to a monitor with free space above or below it in Windows display settings.");

        var client = TargetClient(monitor, edge.Value, strip);
        var win = new RECT { Left = client.Left, Top = client.Top, Right = client.Right, Bottom = client.Bottom };
        AdjustWindowRectExForDpi(ref win, (uint)style, false, (uint)exStyle, dpi);

        if (!SetWindowPos(hwnd, IntPtr.Zero, win.Left, win.Top, win.Right - win.Left, win.Bottom - win.Top,
                SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER))
            return new Result(false, "Windows refused to resize the game window (error " + Marshal.GetLastWin32Error() +
                "). If the game runs as administrator, run Mapcast Companion as administrator too.");

        return new Result(true, "", edge.Value, client);
    }

    /// <summary>Client rectangle of a window in screen pixels.</summary>
    public static Rectangle GetClientRectangle(IntPtr hwnd)
    {
        if (!GetClientRect(hwnd, out var r)) return Rectangle.Empty;
        var p = new POINT();
        ClientToScreen(hwnd, ref p);
        return new Rectangle(p.X, p.Y, r.Right - r.Left, r.Bottom - r.Top);
    }

    public static Rectangle GetWindowRectangle(IntPtr hwnd) =>
        GetWindowRect(hwnd, out var r) ? Rectangle.FromLTRB(r.Left, r.Top, r.Right, r.Bottom) : Rectangle.Empty;

    public static bool MoveTo(IntPtr hwnd, Rectangle r) =>
        SetWindowPos(hwnd, IntPtr.Zero, r.X, r.Y, r.Width, r.Height, SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER);

    // ------------------------------------------------------------------ native

    private const int GWL_STYLE = -16, GWL_EXSTYLE = -20, SW_RESTORE = 9;
    private const long WS_CAPTION = 0x00C00000;
    private const uint SWP_NOZORDER = 0x0004, SWP_NOACTIVATE = 0x0010, SWP_NOOWNERZORDER = 0x0200;

    [StructLayout(LayoutKind.Sequential)] private struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct POINT { public int X, Y; }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll")] private static extern bool IsZoomed(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hwnd, int cmd);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool AdjustWindowRectExForDpi(ref RECT rect, uint style, bool menu, uint exStyle, uint dpi);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr hwnd, ref POINT p);
}
