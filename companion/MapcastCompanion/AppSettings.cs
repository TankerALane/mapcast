using System.Text.Json;

namespace MapcastCompanion;

/// <summary>User preferences, stored in %LOCALAPPDATA%\MapcastCompanion\settings.json.</summary>
public sealed class AppSettings
{
    public int Version { get; set; }               // 0 = file written before versioning
    public int[]? Bounds { get; set; }          // x, y, width, height of the viewer window
    public bool Borderless { get; set; }
    public bool TopMost { get; set; }               // off: a topmost viewer can hide the game's own dialogs
    public bool KeepAspect { get; set; } = true;
    public bool Smooth { get; set; } = true;
    public int Fps { get; set; } = 30;
    public bool AutoDetect { get; set; } = true;
    public int[]? ManualRegion { get; set; }    // x, y, width, height in captured-window pixels
    public string? TargetTitle { get; set; }    // null = find World of Warcraft automatically
    public int OffscreenStrip { get; set; } = 600;      // physical pixels hidden above/below the monitor
    public bool OffscreenPreferBottom { get; set; }      // default: hide the strip above the monitor
    public int[]? GameWindowBefore { get; set; }         // game window rect before "hide off-screen"

    private const int CurrentVersion = 2;

    private static string Dir => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MapcastCompanion");
    private static string FilePath => Path.Combine(Dir, "settings.json");

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                var s = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath), Options) ?? new AppSettings { Version = CurrentVersion };
                // Files from before Version existed deserialize with Version = 0: always-on-top defaulted to on then.
                if (s.Version < 2) s.TopMost = false;
                s.Version = CurrentVersion;
                return s;
            }
        }
        catch { /* corrupt file: start fresh */ }
        return new AppSettings { Version = CurrentVersion };
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Dir);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, Options));
        }
        catch { /* not fatal */ }
    }
}
