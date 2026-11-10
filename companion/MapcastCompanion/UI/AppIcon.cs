namespace MapcastCompanion.UI;

internal static class AppIcon
{
    private static Icon? _icon;

    public static Icon Load()
    {
        if (_icon != null) return _icon;
        using var s = typeof(AppIcon).Assembly.GetManifestResourceStream("MapcastCompanion.ico");
        _icon = s != null ? new Icon(s) : SystemIcons.Application;
        return _icon;
    }
}
