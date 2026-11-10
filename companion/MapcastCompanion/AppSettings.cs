using System.Text.Json;

namespace MapcastCompanion;

/// <summary>User preferences, stored in %LOCALAPPDATA%\MapcastCompanion\settings.json.</summary>
public sealed class AppSettings
{
    public int[]? Bounds { get; set; }          // x, y, width, height of the viewer window
    public bool Borderless { get; set; }
    public bool TopMost { get; set; } = true;
    public bool KeepAspect { get; set; } = true;
    public bool Smooth { get; set; } = true;
    public int Fps { get; set; } = 30;
    public bool AutoDetect { get; set; } = true;
    public int[]? ManualRegion { get; set; }    // x, y, width, height in captured-window pixels
    public string? TargetTitle { get; set; }    // null = find World of Warcraft automatically

    private static string Dir => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MapcastCompanion");
    private static string FilePath => Path.Combine(Dir, "settings.json");

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath), Options) ?? new AppSettings();
        }
        catch { /* corrupt file: start fresh */ }
        return new AppSettings();
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
