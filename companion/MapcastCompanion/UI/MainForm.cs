using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using MapcastCompanion.Capture;
using MapcastCompanion.Interop;

namespace MapcastCompanion.UI;

/// <summary>
/// The viewer window: shows the cropped Mapcast frame. Drag it to any monitor.
/// Right-click for all options. Double-click toggles borderless mode.
/// </summary>
public sealed class MainForm : Form
{
    private static readonly Color Navy = Color.FromArgb(0x08, 0x14, 0x20);
    private static readonly Color Cream = Color.FromArgb(0xF4, 0xF1, 0xEA);
    private static readonly Color Teal = Color.FromArgb(0x4C, 0xD3, 0xB6);

    private readonly AppSettings _settings;
    private readonly CaptureEngine? _engine;
    private readonly System.Windows.Forms.Timer _reconnect = new() { Interval = 2000 };
    private readonly ContextMenuStrip _menu = new();
    private Bitmap? _frame;
    private long _seenFrame = -1;
    private int _invalidatePending;
    private TargetWindow? _target;
    private string? _status;
    private bool _markerLost;

    public MainForm(AppSettings settings)
    {
        _settings = settings;
        Text = "Mapcast Companion";
        Icon = AppIcon.Load();
        BackColor = Navy;
        ForeColor = Cream;
        DoubleBuffered = true;
        SetStyle(ControlStyles.ResizeRedraw | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);
        MinimumSize = new Size(160, 120);
        StartPosition = FormStartPosition.Manual;
        RestoreBounds_();
        TopMost = _settings.TopMost;
        ApplyBorderless();
        BuildMenu();
        ContextMenuStrip = _menu;

        if (!CaptureEngine.IsSupported())
        {
            _status = "Windows Graphics Capture isn't available on this PC.\nWindows 10 version 2004 or newer is required.";
            return;
        }

        try
        {
            _engine = new CaptureEngine { TargetFps = _settings.Fps, AutoDetect = _settings.AutoDetect };
        }
        catch (Exception ex)
        {
            _status = "Could not start Direct3D for capture:\n" + ex.Message;
            return;
        }
        _engine.FrameReady += OnFrameReady;
        _engine.MarkerChanged += r => BeginInvokeSafe(() => OnMarkerChanged(r));
        _engine.TargetClosed += () => BeginInvokeSafe(OnTargetClosed);
        if (!_settings.AutoDetect && _settings.ManualRegion is { Length: 4 } m)
            _engine.Region = new Rectangle(m[0], m[1], m[2], m[3]);

        _reconnect.Tick += (_, _) => TryConnect();
        Shown += (_, _) => TryConnect();
    }

    // ---------------------------------------------------------------- capture

    private void TryConnect()
    {
        if (_engine == null) return;
        if (_target != null && WindowFinder.IsAlive(_target.Handle) && _engine.IsCapturing)
        {
            _reconnect.Stop();
            return;
        }
        _target = _settings.TargetTitle is { Length: > 0 } t ? WindowFinder.FindByTitle(t) : WindowFinder.FindWow();
        if (_target == null)
        {
            SetStatus(_settings.TargetTitle is { Length: > 0 }
                ? $"Waiting for a window named \"{_settings.TargetTitle}\"..."
                : "Waiting for World of Warcraft...\nRun the game in Windowed or Windowed (Fullscreen) mode.");
            _reconnect.Start();
            return;
        }
        try
        {
            _engine.Start(_target.Handle);
            _reconnect.Stop();
            SetStatus(_engine.AutoDetect
                ? "Looking for the Mapcast frame...\nIn game, type /mapcast capture to turn on capture mode,\nor right-click here and choose \"Select region manually\"."
                : null);
            if (_engine.AutoDetect) _markerLost = true;
        }
        catch (Exception ex)
        {
            SetStatus("Couldn't capture that window:\n" + ex.Message);
            _reconnect.Start();
        }
    }

    private void OnTargetClosed()
    {
        _target = null;
        SetStatus("The game window closed. Waiting for it to come back...");
        _reconnect.Start();
    }

    private void OnMarkerChanged(Rectangle? region)
    {
        if (region != null)
        {
            _markerLost = false;
            SetStatus(null);
        }
        else if (_engine?.AutoDetect == true)
        {
            _markerLost = true;
            SetStatus(_frame == null
                ? "Looking for the Mapcast frame...\nIn game, type /mapcast capture to turn on capture mode."
                : "Mapcast frame not visible.\nIs capture mode on, and is the frame on screen and not covered?");
        }
    }

    private void OnFrameReady()
    {
        if (Interlocked.Exchange(ref _invalidatePending, 1) == 1) return;
        BeginInvokeSafe(() =>
        {
            _invalidatePending = 0;
            if (_engine != null && _engine.CopyLatest(ref _frame, ref _seenFrame))
            {
                if (!_markerLost && _status != null) _status = null;
                Invalidate();
            }
        });
    }

    private void BeginInvokeSafe(Action a)
    {
        if (IsDisposed || !IsHandleCreated) return;
        try { BeginInvoke(a); } catch (ObjectDisposedException) { } catch (InvalidOperationException) { }
    }

    private void SetStatus(string? text)
    {
        _status = text;
        Invalidate();
    }

    // ---------------------------------------------------------------- painting

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.Clear(Navy);
        var client = ClientRectangle;

        if (_frame != null)
        {
            var dest = client;
            if (_settings.KeepAspect)
            {
                float scale = Math.Min((float)client.Width / _frame.Width, (float)client.Height / _frame.Height);
                int w = (int)Math.Round(_frame.Width * scale), h = (int)Math.Round(_frame.Height * scale);
                dest = new Rectangle(client.X + (client.Width - w) / 2, client.Y + (client.Height - h) / 2, w, h);
            }
            g.InterpolationMode = _settings.Smooth ? InterpolationMode.HighQualityBilinear : InterpolationMode.NearestNeighbor;
            g.PixelOffsetMode = PixelOffsetMode.Half;
            g.CompositingMode = CompositingMode.SourceCopy;
            g.DrawImage(_frame, dest);
            g.CompositingMode = CompositingMode.SourceOver;
            if (_markerLost && _status != null)
            {
                using var dim = new SolidBrush(Color.FromArgb(170, Navy));
                g.FillRectangle(dim, client);
            }
        }

        if (_status != null)
        {
            using var font = new Font("Segoe UI", 10f);
            using var brush = new SolidBrush(Cream);
            var fmt = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
            var rect = Rectangle.Inflate(client, -12, -12);
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            g.DrawString(_status, font, brush, rect, fmt);
            using var small = new Font("Segoe UI", 8f);
            using var hint = new SolidBrush(Teal);
            g.DrawString("Right-click for options", small, hint, new RectangleF(rect.X, rect.Bottom - 20, rect.Width, 20), fmt);
        }
    }

    // ---------------------------------------------------------------- menu

    private void BuildMenu()
    {
        _menu.Opening += (_, _) => RebuildMenu();
    }

    private void RebuildMenu()
    {
        _menu.Items.Clear();

        var region = new ToolStripMenuItem("Region");
        region.DropDownItems.Add(Check("Find Mapcast frame automatically", _settings.AutoDetect, () => SetAutoDetect(true)));
        region.DropDownItems.Add(new ToolStripMenuItem("Select region manually...", null, async (_, _) => await SelectRegionAsync()));
        region.DropDownItems.Add(new ToolStripMenuItem("Search for the frame again", null, (_, _) => { SetAutoDetect(true); _engine?.RequestDetect(); }));
        _menu.Items.Add(region);

        var source = new ToolStripMenuItem("Capture window");
        source.DropDownItems.Add(Check("World of Warcraft (automatic)", string.IsNullOrEmpty(_settings.TargetTitle), () => SetTarget(null)));
        source.DropDownItems.Add(new ToolStripSeparator());
        foreach (var w in WindowFinder.ListWindows().OrderBy(w => w.Title).Take(30))
        {
            var title = w.Title;
            source.DropDownItems.Add(Check(w.ToString(), _settings.TargetTitle == title, () => SetTarget(title)));
        }
        _menu.Items.Add(source);

        var off = new ToolStripMenuItem("Game window");
        var wow = (_target ?? WindowFinder.FindWow())?.Handle ?? IntPtr.Zero;
        var gameScreen = wow != IntPtr.Zero ? Screen.FromHandle(wow) : null;
        foreach (var scr in Screen.AllScreens.Where(s => gameScreen == null || s.DeviceName != gameScreen.DeviceName))
        {
            var target = scr;
            off.DropDownItems.Add(new ToolStripMenuItem($"Span game onto {DescribeScreen(scr, gameScreen)} (map there, fully interactive)", null,
                async (_, _) => await SpanAsync(target)) { Enabled = gameScreen != null });
        }
        off.DropDownItems.Add(new ToolStripMenuItem("Hide the map off-screen (extend game window)", null, async (_, _) => await ExtendGameWindowAsync()));
        off.DropDownItems.Add(new ToolStripMenuItem("Restore game window", null, (_, _) => RestoreGameWindow()) { Enabled = _settings.GameWindowBefore is { Length: 4 } });
        off.DropDownItems.Add(new ToolStripSeparator());
        foreach (var h in new[] { 400, 500, 600, 700, 800 })
            off.DropDownItems.Add(Check($"Strip height {h} px", _settings.OffscreenStrip == h, () => { _settings.OffscreenStrip = h; Save(); }));
        off.DropDownItems.Add(new ToolStripSeparator());
        off.DropDownItems.Add(Check("Hide above the monitor", !_settings.OffscreenPreferBottom, () => { _settings.OffscreenPreferBottom = false; Save(); }));
        off.DropDownItems.Add(Check("Hide below the monitor", _settings.OffscreenPreferBottom, () => { _settings.OffscreenPreferBottom = true; Save(); }));
        _menu.Items.Add(off);

        _menu.Items.Add(new ToolStripSeparator());
        _menu.Items.Add(Check("Borderless", _settings.Borderless, () => { _settings.Borderless = !_settings.Borderless; ApplyBorderless(); Save(); }));
        _menu.Items.Add(Check("Always on top", _settings.TopMost, () => { _settings.TopMost = !_settings.TopMost; TopMost = _settings.TopMost; Save(); }));
        _menu.Items.Add(Check("Keep aspect ratio", _settings.KeepAspect, () => { _settings.KeepAspect = !_settings.KeepAspect; Invalidate(); Save(); }));
        _menu.Items.Add(Check("Smooth scaling", _settings.Smooth, () => { _settings.Smooth = !_settings.Smooth; Invalidate(); Save(); }));
        var fps = new ToolStripMenuItem("Frame rate");
        foreach (var f in new[] { 10, 15, 30, 60 })
            fps.DropDownItems.Add(Check($"{f} fps", _settings.Fps == f, () => { _settings.Fps = f; if (_engine != null) _engine.TargetFps = f; Save(); }));
        _menu.Items.Add(fps);
        _menu.Items.Add(new ToolStripMenuItem("Fit window to map", null, (_, _) => FitToFrame()));

        _menu.Items.Add(new ToolStripSeparator());
        _menu.Items.Add(new ToolStripMenuItem("How it works...", null, (_, _) => ShowHelp()));
        _menu.Items.Add(new ToolStripMenuItem("About Mapcast Companion...", null, (_, _) => { using var a = new AboutForm(); a.ShowDialog(this); }));
        _menu.Items.Add(new ToolStripMenuItem("Exit", null, (_, _) => Close()));
    }

    private static ToolStripMenuItem Check(string text, bool on, Action click) =>
        new(text, null, (_, _) => click()) { Checked = on };

    private void SetAutoDetect(bool on)
    {
        _settings.AutoDetect = on;
        if (_engine != null)
        {
            _engine.AutoDetect = on;
            if (on) { _engine.Region = null; _markerLost = true; _engine.RequestDetect(); }
        }
        Save();
    }

    private void SetTarget(string? title)
    {
        _settings.TargetTitle = title;
        Save();
        _engine?.Stop();
        _target = null;
        TryConnect();
    }

    private async Task SelectRegionAsync()
    {
        if (_engine == null || !_engine.IsCapturing)
        {
            MessageBox.Show(this, "Start World of Warcraft first (Windowed or Windowed Fullscreen).", "Mapcast Companion");
            return;
        }
        var snapTask = _engine.SnapshotAsync();
        var done = await Task.WhenAny(snapTask, Task.Delay(3000));
        if (done != snapTask || snapTask.Result == null)
        {
            MessageBox.Show(this, "Couldn't get a picture of the game window. Make sure it isn't minimised.", "Mapcast Companion");
            return;
        }
        using var snap = snapTask.Result;
        using var dlg = new RegionSelectForm(snap);
        if (dlg.ShowDialog(this) == DialogResult.OK && dlg.Selection is { } sel)
        {
            _settings.AutoDetect = false;
            _settings.ManualRegion = new[] { sel.X, sel.Y, sel.Width, sel.Height };
            _engine.AutoDetect = false;
            _engine.Region = sel;
            _markerLost = false;
            SetStatus(null);
            Save();
        }
    }

    private async Task ExtendGameWindowAsync()
    {
        var target = _target ?? (_settings.TargetTitle is { Length: > 0 } t ? WindowFinder.FindByTitle(t) : WindowFinder.FindWow());
        if (target == null)
        {
            MessageBox.Show(this, "Start World of Warcraft first, in Windowed mode.", "Mapcast Companion");
            return;
        }
        int strip = _settings.OffscreenStrip;
        var preferred = _settings.OffscreenPreferBottom ? StripEdge.Bottom : StripEdge.Top;
        var result = GameWindowLayout.Extend(target.Handle, strip, preferred, out var before);
        if (!result.Ok)
        {
            MessageBox.Show(this, result.Message, "Mapcast Companion", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        RememberWindow(before);

        await Task.Delay(800); // let the game process the resize
        var client = GameWindowLayout.GetClientRectangle(target.Handle);
        string edge = result.Edge == StripEdge.Top ? "top" : "bottom";
        string command = $"/mapcast offscreen {edge} {strip}";
        if (client.Height < result.Client.Height - 2)
        {
            MessageBox.Show(this,
                $"The game window was asked to become {result.Client.Width} x {result.Client.Height} but it is {client.Width} x {client.Height}. " +
                "The game (or Windows) did not allow a window larger than the monitor, so off-screen mode can't work on this setup.\n\n" +
                "Use \"Restore game window\" to put it back.",
                "Mapcast Companion", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        ShowCommandDialog("Off-screen map",
            $"The game window now reaches {strip} px {(result.Edge == StripEdge.Top ? "above" : "below")} your monitor, where no screen shows it.",
            command,
            "Mapcast moves its map into the hidden strip and keeps the rest of the game on your monitor.");
        _engine?.RequestDetect();
    }

    private async Task SpanAsync(Screen mapScreen)
    {
        var target = _target ?? WindowFinder.FindWow();
        if (target == null)
        {
            MessageBox.Show(this, "Start World of Warcraft first, in Windowed mode.", "Mapcast Companion");
            return;
        }
        var result = GameWindowLayout.Span(target.Handle, mapScreen, out var before);
        if (!result.Ok)
        {
            MessageBox.Show(this, result.Message, "Mapcast Companion", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        RememberWindow(before);

        await Task.Delay(800);
        var client = GameWindowLayout.GetClientRectangle(target.Handle);
        if (client.Width < result.Client.Width - 2 || client.Height < result.Client.Height - 2)
        {
            MessageBox.Show(this,
                $"The game window was asked to become {result.Client.Width} x {result.Client.Height} but it is {client.Width} x {client.Height}. " +
                "The game (or Windows) did not allow a window that large.\n\nUse \"Restore game window\" to put it back.",
                "Mapcast Companion", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        ShowCommandDialog("Span game window",
            "The game window now covers both monitors.",
            result.Command,
            "Mapcast keeps the game on its monitor and fills the other one with an interactive map. " +
            "Mapcast remembers this; you can close Mapcast Companion now. To undo: Game window > Restore game window.");
    }

    // Remember the window's normal placement for "Restore", but not a layout we made ourselves.
    private void RememberWindow(Rectangle before)
    {
        var mon = Screen.FromRectangle(before).Bounds;
        bool normal = before.Width <= mon.Width + 100 && before.Height <= mon.Height + 100;
        if (_settings.GameWindowBefore == null || normal)
            _settings.GameWindowBefore = new[] { before.X, before.Y, before.Width, before.Height };
        Save();
    }

    private static string DescribeScreen(Screen s, Screen? game)
    {
        string where = "";
        if (game != null)
        {
            var g = game.Bounds; var b = s.Bounds;
            where = b.Left >= g.Right ? "right" : b.Right <= g.Left ? "left" : b.Bottom <= g.Top ? "above" : b.Top >= g.Bottom ? "below" : "";
        }
        string name = s.DeviceName.Replace(@"\\.\", "");
        return $"{name} ({(where.Length > 0 ? where + ", " : "")}{s.Bounds.Width}x{s.Bounds.Height})";
    }

    private void ShowCommandDialog(string title, string intro, string command, string note)
    {
        using var dlg = new Form
        {
            Text = title, FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false, MinimizeBox = false,
            StartPosition = FormStartPosition.CenterParent, ClientSize = new Size(480, 210), Icon = AppIcon.Load(), TopMost = true,
        };
        var label = new Label
        {
            Text = intro + "\n\nNow type this in the game chat (it is selected; press Ctrl+C to copy, then paste it in game with Ctrl+V):",
            Location = new Point(12, 12), Size = new Size(456, 70),
        };
        var box = new TextBox { Text = command, ReadOnly = true, Location = new Point(12, 88), Width = 456, Font = new Font("Consolas", 11f) };
        var info = new Label { Text = note, Location = new Point(12, 122), Size = new Size(456, 48) };
        var ok = new Button { Text = "OK", DialogResult = DialogResult.OK, Location = new Point(393, 175) };
        dlg.Controls.AddRange(new Control[] { label, box, info, ok });
        dlg.AcceptButton = ok;
        dlg.Shown += (_, _) => { box.Focus(); box.SelectAll(); };
        dlg.ShowDialog(this);
    }

    private void RestoreGameWindow()
    {
        var target = _target ?? WindowFinder.FindWow();
        if (target == null || _settings.GameWindowBefore is not { Length: 4 } b) return;
        GameWindowLayout.MoveTo(target.Handle, new Rectangle(b[0], b[1], b[2], b[3]));
        _settings.GameWindowBefore = null;
        Save();
        MessageBox.Show(this, "Game window restored. In game, type /mapcast normal to put the game and map back to normal.", "Mapcast Companion");
    }

    private void FitToFrame()
    {
        if (_frame == null) return;
        if (WindowState != FormWindowState.Normal) WindowState = FormWindowState.Normal;
        var chrome = Size - ClientSize;
        Size = new Size(_frame.Width + chrome.Width, _frame.Height + chrome.Height);
    }

    private void ShowHelp()
    {
        MessageBox.Show(this,
            "1. In World of Warcraft, type /mapcast capture. The Mapcast map gets a solid magenta border.\n" +
            "2. This window finds that border and shows just the map. Drag this window to your second monitor.\n" +
            "3. Double-click to toggle borderless. Drag anywhere to move it when borderless; drag the edges to resize.\n\n" +
            "The game must run in Windowed or Windowed (Fullscreen) mode. Exclusive fullscreen can't be captured, " +
            "and nothing is captured while the game is minimised.\n\n" +
            "The Mapcast frame must stay visible in the game window, because this app can only copy what is on screen. " +
            "Tuck it into a corner and use a smaller capture size in Mapcast's options to keep it out of the way, " +
            "or use Game window > Span (map on your second monitor, interactive) or Hide the map off-screen.\n\n" +
            "Mapcast Companion only captures the screen (and, if you ask it to, resizes the game window for the Game window options). " +
            "It never reads game memory, sends input, or automates anything.",
            "How Mapcast Companion works");
    }

    // ---------------------------------------------------------------- window behaviour

    private void ApplyBorderless()
    {
        FormBorderStyle = _settings.Borderless ? FormBorderStyle.None : FormBorderStyle.Sizable;
        Padding = Padding.Empty;
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (e.Button == MouseButtons.Left && e.Clicks == 1 && _settings.Borderless)
        {
            ReleaseCapture();
            SendMessage(Handle, WM_NCLBUTTONDOWN, (IntPtr)HTCAPTION, IntPtr.Zero);
        }
    }

    protected override void OnMouseDoubleClick(MouseEventArgs e)
    {
        base.OnMouseDoubleClick(e);
        if (e.Button != MouseButtons.Left) return;
        _settings.Borderless = !_settings.Borderless;
        ApplyBorderless();
        Save();
    }

    protected override void WndProc(ref Message m)
    {
        base.WndProc(ref m);
        // Borderless: let the edges resize the window.
        if (m.Msg == WM_NCHITTEST && _settings.Borderless && (int)m.Result == HTCLIENT)
        {
            const int grip = 8;
            var p = PointToClient(new Point(unchecked((short)(long)m.LParam), unchecked((short)((long)m.LParam >> 16))));
            bool l = p.X < grip, r = p.X >= ClientSize.Width - grip, t = p.Y < grip, b = p.Y >= ClientSize.Height - grip;
            if (t && l) m.Result = HTTOPLEFT;
            else if (t && r) m.Result = HTTOPRIGHT;
            else if (b && l) m.Result = HTBOTTOMLEFT;
            else if (b && r) m.Result = HTBOTTOMRIGHT;
            else if (l) m.Result = HTLEFT;
            else if (r) m.Result = HTRIGHT;
            else if (t) m.Result = HTTOP;
            else if (b) m.Result = HTBOTTOM;
        }
    }

    private void RestoreBounds_()
    {
        if (_settings.Bounds is { Length: 4 } b)
        {
            var rect = new Rectangle(b[0], b[1], b[2], b[3]);
            if (Screen.AllScreens.Any(s => s.WorkingArea.IntersectsWith(rect)))
            {
                Bounds = rect;
                return;
            }
        }
        var wa = Screen.PrimaryScreen?.WorkingArea ?? new Rectangle(0, 0, 1280, 720);
        Bounds = new Rectangle(wa.Right - 680, wa.Top + 80, 640, 520);
    }

    private void Save()
    {
        if (WindowState == FormWindowState.Normal)
            _settings.Bounds = new[] { Bounds.X, Bounds.Y, Bounds.Width, Bounds.Height };
        _settings.Save();
    }

    protected override void OnResizeEnd(EventArgs e) { base.OnResizeEnd(e); Save(); }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        Save();
        _reconnect.Stop();
        _engine?.Dispose();
        base.OnFormClosing(e);
    }

    private const int WM_NCLBUTTONDOWN = 0xA1, WM_NCHITTEST = 0x84;
    private const int HTCLIENT = 1, HTCAPTION = 2, HTLEFT = 10, HTRIGHT = 11, HTTOP = 12, HTTOPLEFT = 13,
        HTTOPRIGHT = 14, HTBOTTOM = 15, HTBOTTOMLEFT = 16, HTBOTTOMRIGHT = 17;

    [DllImport("user32.dll")] private static extern bool ReleaseCapture();
    [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam);
}
