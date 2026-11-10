namespace MapcastCompanion.UI;

/// <summary>Shows a still of the game window; the user drags a rectangle around the map.</summary>
public sealed class RegionSelectForm : Form
{
    private readonly Bitmap _image;
    private readonly PictureBox _view = new() { Dock = DockStyle.Fill, SizeMode = PictureBoxSizeMode.Zoom, BackColor = Color.Black };
    private Point? _dragStart;
    private Rectangle _dragRect; // in view coordinates

    public Rectangle? Selection { get; private set; } // in image coordinates

    public RegionSelectForm(Bitmap image)
    {
        _image = image;
        Text = "Drag a rectangle around the Mapcast map, then press OK";
        Icon = AppIcon.Load();
        StartPosition = FormStartPosition.CenterParent;
        var wa = Screen.FromPoint(Cursor.Position).WorkingArea;
        Size = new Size((int)(wa.Width * 0.8), (int)(wa.Height * 0.8));
        _view.Image = image;
        _view.Cursor = Cursors.Cross;
        _view.MouseDown += (_, e) => { if (e.Button == MouseButtons.Left) { _dragStart = e.Location; _dragRect = Rectangle.Empty; } };
        _view.MouseMove += (_, e) =>
        {
            if (_dragStart is not { } s) return;
            _dragRect = Rectangle.FromLTRB(Math.Min(s.X, e.X), Math.Min(s.Y, e.Y), Math.Max(s.X, e.X), Math.Max(s.Y, e.Y));
            _view.Invalidate();
        };
        _view.MouseUp += (_, _) => { _dragStart = null; UpdateSelection(); };
        _view.Paint += (_, e) =>
        {
            if (_dragRect.Width < 2 || _dragRect.Height < 2) return;
            using var pen = new Pen(Color.FromArgb(0x4C, 0xD3, 0xB6), 2);
            e.Graphics.DrawRectangle(pen, _dragRect);
        };

        var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, FlowDirection = FlowDirection.RightToLeft, Height = 40, Padding = new Padding(6) };
        var cancel = new Button { Text = "Cancel", DialogResult = DialogResult.Cancel, Width = 90 };
        var ok = new Button { Text = "OK", DialogResult = DialogResult.OK, Width = 90 };
        buttons.Controls.Add(cancel);
        buttons.Controls.Add(ok);
        AcceptButton = ok;
        CancelButton = cancel;
        Controls.Add(_view);
        Controls.Add(buttons);
    }

    private void UpdateSelection()
    {
        if (_dragRect.Width < 4 || _dragRect.Height < 4) { Selection = null; return; }
        // Map from the zoomed PictureBox back to image pixels.
        float scale = Math.Min((float)_view.ClientSize.Width / _image.Width, (float)_view.ClientSize.Height / _image.Height);
        float ox = (_view.ClientSize.Width - _image.Width * scale) / 2f;
        float oy = (_view.ClientSize.Height - _image.Height * scale) / 2f;
        int x0 = (int)Math.Round((_dragRect.Left - ox) / scale), y0 = (int)Math.Round((_dragRect.Top - oy) / scale);
        int x1 = (int)Math.Round((_dragRect.Right - ox) / scale), y1 = (int)Math.Round((_dragRect.Bottom - oy) / scale);
        var r = Rectangle.FromLTRB(x0, y0, x1, y1);
        r.Intersect(new Rectangle(Point.Empty, _image.Size));
        Selection = r.Width > 4 && r.Height > 4 ? r : null;
    }
}
