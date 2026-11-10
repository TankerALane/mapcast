using System.Drawing;
using MapcastCompanion.Capture;
using Xunit;

public unsafe class MarkerDetectorTests
{
    private const int W = 800, H = 600, Stride = W * 4;

    private static byte[] Blank(byte r = 30, byte g = 40, byte b = 50)
    {
        var px = new byte[Stride * H];
        for (int i = 0; i < px.Length; i += 4) { px[i] = b; px[i + 1] = g; px[i + 2] = r; px[i + 3] = 255; }
        return px;
    }

    private static void Fill(byte[] px, Rectangle r, byte red, byte green, byte blue)
    {
        for (int y = r.Top; y < r.Bottom; y++)
            for (int x = r.Left; x < r.Right; x++)
            {
                int i = y * Stride + x * 4;
                px[i] = blue; px[i + 1] = green; px[i + 2] = red;
            }
    }

    private static byte[] WithMarker(Rectangle inner, int border, byte red = 255, byte green = 0, byte blue = 255)
    {
        var px = Blank();
        Fill(px, Rectangle.Inflate(inner, border, border), red, green, blue);
        Fill(px, inner, 90, 120, 60); // map content
        return px;
    }

    private static Rectangle? Find(byte[] px)
    {
        fixed (byte* p = px) return MarkerDetector.Find(p, W, H, Stride);
    }

    [Theory]
    [InlineData(4)]
    [InlineData(1)]
    [InlineData(10)]
    public void FindsInnerRectangle(int border)
    {
        var inner = new Rectangle(200, 120, 320, 240);
        Assert.Equal(inner, Find(WithMarker(inner, border)));
    }

    [Fact]
    public void ToleratesSlightColourShift()
    {
        var inner = new Rectangle(50, 60, 400, 300);
        Assert.Equal(inner, Find(WithMarker(inner, 4, 235, 30, 228)));
    }

    [Fact]
    public void ReturnsNullWithoutMarker() => Assert.Null(Find(Blank()));

    [Fact]
    public void IgnoresStrayMagentaLines()
    {
        var px = Blank();
        Fill(px, new Rectangle(10, 500, 400, 3), 255, 0, 255);
        Fill(px, new Rectangle(10, 550, 400, 3), 255, 0, 255);
        Assert.Null(Find(px));
    }

    [Fact]
    public void StillPresentDetectsMovedFrame()
    {
        var inner = new Rectangle(200, 120, 320, 240);
        var px = WithMarker(inner, 4);
        fixed (byte* p = px)
        {
            Assert.True(MarkerDetector.StillPresent(p, W, H, Stride, inner));
            Assert.False(MarkerDetector.StillPresent(p, W, H, Stride, new Rectangle(220, 120, 320, 240)));
        }
    }
}
