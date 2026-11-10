using System.Diagnostics;
using System.Reflection;

namespace MapcastCompanion.UI;

public sealed class AboutForm : Form
{
    public const string RepoUrl = "https://github.com/TankerALane/mapcast";

    public AboutForm()
    {
        Text = "About Mapcast Companion";
        Icon = AppIcon.Load();
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = MinimizeBox = false;
        StartPosition = FormStartPosition.CenterParent;
        ClientSize = new Size(420, 250);
        BackColor = Color.FromArgb(0x0E, 0x1E, 0x2E);
        ForeColor = Color.FromArgb(0xF4, 0xF1, 0xEA);

        var version = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "0.0.0";
        var logo = new PictureBox { Image = AppIcon.Load().ToBitmap(), SizeMode = PictureBoxSizeMode.Zoom, Bounds = new Rectangle(20, 20, 64, 64) };
        var title = new Label { Text = "Mapcast Companion", Font = new Font("Segoe UI", 16f, FontStyle.Bold), AutoSize = true, Location = new Point(100, 22) };
        var meta = new Label
        {
            Text = $"Version {version}\nDecoupled Lane Studio\nMIT License",
            Font = new Font("Segoe UI", 9.5f), AutoSize = true, Location = new Point(102, 56),
        };
        var note = new Label
        {
            Text = "Passive screen capture only: no game memory reading, no input, no automation.",
            Font = new Font("Segoe UI", 9f), ForeColor = Color.FromArgb(0x4C, 0xD3, 0xB6),
            Location = new Point(20, 128), Size = new Size(380, 36),
        };
        var link = new LinkLabel
        {
            Text = RepoUrl, AutoSize = true, Location = new Point(20, 172), Font = new Font("Segoe UI", 9.5f),
            LinkColor = Color.FromArgb(0xE0, 0x90, 0x4F), ActiveLinkColor = Color.FromArgb(0xF4, 0xF1, 0xEA),
        };
        link.LinkClicked += (_, _) => Process.Start(new ProcessStartInfo(RepoUrl) { UseShellExecute = true });
        var ok = new Button { Text = "OK", DialogResult = DialogResult.OK, Bounds = new Rectangle(320, 208, 80, 28), ForeColor = Color.Black, BackColor = SystemColors.Control };
        AcceptButton = ok;
        Controls.AddRange(new Control[] { logo, title, meta, note, link, ok });
    }
}
