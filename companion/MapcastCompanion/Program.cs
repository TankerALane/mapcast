using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using MapcastCompanion.Capture;
using MapcastCompanion.Interop;
using MapcastCompanion.UI;

namespace MapcastCompanion;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length > 0 && args[0].Equals("--diagnose", StringComparison.OrdinalIgnoreCase))
            return Diagnose(args);

        ApplicationConfiguration.Initialize();
        var settings = AppSettings.Load();
        Application.Run(new MainForm(settings));
        return 0;
    }

    /// <summary>
    /// MapcastCompanion.exe --diagnose [--window "title contains"] [--out folder]
    /// Captures one frame of the target window, looks for the Mapcast marker and writes
    /// full.png, map.png and result.txt. Useful for bug reports.
    /// </summary>
    private static int Diagnose(string[] args)
    {
        AttachConsole(-1);
        string? title = null;
        string outDir = Path.Combine(Environment.CurrentDirectory, "mapcast-diagnose");
        for (int i = 1; i < args.Length - 1; i++)
        {
            if (args[i] == "--window") title = args[++i];
            else if (args[i] == "--out") outDir = args[++i];
        }
        Directory.CreateDirectory(outDir);
        var log = new List<string> { $"Mapcast Companion diagnose {DateTime.Now:u}", $"OS: {Environment.OSVersion}" };
        void Log(string s) { log.Add(s); Console.WriteLine(s); }

        int code = 1;
        try
        {
            Log($"Graphics Capture supported: {CaptureEngine.IsSupported()}");
            var target = title != null ? WindowFinder.FindByTitle(title) : WindowFinder.FindWow();
            if (target == null)
            {
                Log(title != null ? $"No window matching \"{title}\"." : "World of Warcraft window not found.");
                return 2;
            }
            Log($"Target: \"{target.Title}\" process={target.ProcessName} minimized={WindowFinder.IsMinimized(target.Handle)}");

            using var engine = new CaptureEngine { AutoDetect = true };
            Rectangle? marker = null;
            using var found = new ManualResetEventSlim();
            engine.MarkerChanged += r => { marker = r; found.Set(); };
            engine.Start(target.Handle);
            var snap = engine.SnapshotAsync();
            if (!snap.Wait(5000) || snap.Result == null)
            {
                Log("No frames received within 5 s (window minimised or protected?).");
                return 3;
            }
            using var full = snap.Result;
            full.Save(Path.Combine(outDir, "full.png"), ImageFormat.Png);
            Log($"Frame: {full.Width}x{full.Height} -> full.png");

            found.Wait(3000);
            if (marker is { } m)
            {
                Log($"Marker found. Map region: x={m.X} y={m.Y} w={m.Width} h={m.Height}");
                using var crop = full.Clone(m, full.PixelFormat);
                crop.Save(Path.Combine(outDir, "map.png"), ImageFormat.Png);
                Log("Cropped map -> map.png");
                code = 0;
            }
            else
            {
                Log("Marker NOT found. Turn on capture mode in game (/mapcast capture) and keep the frame on screen.");
                code = 4;
            }
        }
        catch (Exception ex)
        {
            Log("Error: " + ex);
        }
        finally
        {
            File.WriteAllLines(Path.Combine(outDir, "result.txt"), log);
        }
        return code;
    }

    [DllImport("kernel32.dll")]
    private static extern bool AttachConsole(int processId);
}
