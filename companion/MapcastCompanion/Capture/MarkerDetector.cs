using System.Drawing;

namespace MapcastCompanion.Capture;

/// <summary>
/// Finds the Mapcast capture-mode frame: a rectangle outlined by a solid magenta
/// (#FF00FF) border. Returns the area INSIDE the border (the map itself).
///
/// Works on 32-bit BGRA pixels. The colour test is tolerant because Windows HDR,
/// gamma settings and colour filters can shift the exact values slightly.
/// The marker colour must match ns.MARKER_* in addon/Mapcast/Core.lua.
/// </summary>
public static class MarkerDetector
{
    public const int MinSide = 60;      // ignore anything smaller than this (px)
    private const int MinBand = 1;      // thinnest border we accept
    private const int MaxBand = 24;     // thickest border we accept

    public static bool IsMarker(byte b, byte g, byte r) =>
        r >= 190 && b >= 190 && g <= 70 && Math.Abs(r - b) <= 60;

    private readonly record struct Run(int Y, int X0, int X1);

    private sealed class Band
    {
        public int X0, X1, Y0, Y1;
        public int Thickness => Y1 - Y0 + 1;
    }

    /// <summary>
    /// Searches a BGRA image for the marker rectangle.
    /// </summary>
    /// <param name="pixels">Pointer to the first row.</param>
    /// <param name="width">Image width in pixels.</param>
    /// <param name="height">Image height in pixels.</param>
    /// <param name="stride">Bytes per row.</param>
    /// <returns>The inner rectangle, or null if no marker was found.</returns>
    public static unsafe Rectangle? Find(byte* pixels, int width, int height, int stride)
    {
        // 1. Long horizontal magenta runs, one per row (the longest).
        var bands = new List<Band>();
        Band? open = null;
        for (int y = 0; y < height; y++)
        {
            var run = LongestRun(pixels + (long)y * stride, width, y);
            if (run is { } r && r.X1 - r.X0 + 1 >= MinSide)
            {
                if (open != null && open.Y1 == y - 1 && Math.Abs(open.X0 - r.X0) <= 2 && Math.Abs(open.X1 - r.X1) <= 2)
                {
                    open.Y1 = y;
                    continue;
                }
                open = new Band { X0 = r.X0, X1 = r.X1, Y0 = y, Y1 = y };
                bands.Add(open);
            }
            else
            {
                open = null;
            }
        }

        // 2. Pair a top band with a bottom band of the same extent, then verify the sides.
        Rectangle? best = null;
        long bestArea = 0;
        foreach (var top in bands)
        {
            if (top.Thickness < MinBand || top.Thickness > MaxBand) continue;
            foreach (var bottom in bands)
            {
                if (bottom.Y0 <= top.Y1 + MinSide) continue;
                if (Math.Abs(bottom.X0 - top.X0) > 2 || Math.Abs(bottom.X1 - top.X1) > 2) continue;
                if (bottom.Thickness < MinBand || bottom.Thickness > MaxBand) continue;

                int x0 = Math.Max(top.X0, bottom.X0), x1 = Math.Min(top.X1, bottom.X1);
                int midY = (top.Y1 + bottom.Y0) / 2;
                int left = SideThickness(pixels, stride, width, x0, midY, +1);
                int right = SideThickness(pixels, stride, width, x1, midY, -1);
                if (left < MinBand || right < MinBand || left > MaxBand || right > MaxBand) continue;
                if (!VerifyColumn(pixels, stride, x0, top.Y1 + 1, bottom.Y0 - 1)) continue;
                if (!VerifyColumn(pixels, stride, x1, top.Y1 + 1, bottom.Y0 - 1)) continue;

                var inner = Rectangle.FromLTRB(x0 + left, top.Y1 + 1, x1 - right + 1, bottom.Y0);
                long area = (long)inner.Width * inner.Height;
                if (inner.Width >= MinSide / 2 && inner.Height >= MinSide / 2 && area > bestArea)
                {
                    best = inner;
                    bestArea = area;
                }
            }
        }
        return best;
    }

    /// <summary>Cheap check that a previously found inner rectangle still has its border.</summary>
    public static unsafe bool StillPresent(byte* pixels, int width, int height, int stride, Rectangle inner)
    {
        int top = inner.Top - 1, bottom = inner.Bottom, left = inner.Left - 1, right = inner.Right;
        if (top < 0 || left < 0 || bottom >= height || right >= width) return false;
        int hits = 0, total = 0;
        for (int i = 1; i <= 8; i++)
        {
            int x = inner.Left + inner.Width * i / 9;
            int y = inner.Top + inner.Height * i / 9;
            total += 4;
            if (Px(pixels, stride, x, top)) hits++;
            if (Px(pixels, stride, x, bottom)) hits++;
            if (Px(pixels, stride, left, y)) hits++;
            if (Px(pixels, stride, right, y)) hits++;
        }
        return hits >= total * 0.85;
    }

    private static unsafe bool Px(byte* pixels, int stride, int x, int y)
    {
        byte* p = pixels + (long)y * stride + x * 4;
        return IsMarker(p[0], p[1], p[2]);
    }

    private static unsafe Run? LongestRun(byte* row, int width, int y)
    {
        int bestStart = -1, bestLen = 0, start = -1;
        for (int x = 0; x <= width; x++)
        {
            bool m = x < width && IsMarker(row[x * 4], row[x * 4 + 1], row[x * 4 + 2]);
            if (m)
            {
                if (start < 0) start = x;
            }
            else if (start >= 0)
            {
                int len = x - start;
                if (len > bestLen) { bestLen = len; bestStart = start; }
                start = -1;
            }
        }
        return bestStart < 0 ? null : new Run(y, bestStart, bestStart + bestLen - 1);
    }

    private static unsafe int SideThickness(byte* pixels, int stride, int width, int x, int y, int dir)
    {
        int n = 0;
        while (x >= 0 && x < width && Px(pixels, stride, x, y) && n <= MaxBand + 1)
        {
            n++;
            x += dir;
        }
        return n;
    }

    private static unsafe bool VerifyColumn(byte* pixels, int stride, int x, int y0, int y1)
    {
        if (y1 < y0) return false;
        int hits = 0, total = 0;
        int step = Math.Max(1, (y1 - y0) / 64);
        for (int y = y0; y <= y1; y += step)
        {
            total++;
            if (Px(pixels, stride, x, y)) hits++;
        }
        return hits >= total * 0.9;
    }
}
