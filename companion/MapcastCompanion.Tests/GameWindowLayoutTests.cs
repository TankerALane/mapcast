using System.Drawing;
using MapcastCompanion.Interop;
using Xunit;

public class GameWindowLayoutTests
{
    // A real three-monitor layout: primary in the middle, one to the right, one far left and higher.
    private static readonly Rectangle Primary = new(0, 0, 2560, 1440);
    private static readonly Rectangle Right = new(2560, -9, 2560, 1440);
    private static readonly Rectangle Left = new(-3840, -735, 2560, 1440);

    [Fact]
    public void PrefersTopWhenNothingIsAbove()
    {
        Assert.Equal(StripEdge.Top, GameWindowLayout.ChooseEdge(Primary, new[] { Right, Left }, 640, StripEdge.Top));
        Assert.Equal(StripEdge.Bottom, GameWindowLayout.ChooseEdge(Primary, new[] { Right, Left }, 640, StripEdge.Bottom));
    }

    [Fact]
    public void FallsBackToOtherEdge()
    {
        var above = new Rectangle(0, -1440, 2560, 1440);
        Assert.Equal(StripEdge.Bottom, GameWindowLayout.ChooseEdge(Primary, new[] { above }, 600, StripEdge.Top));
        var below = new Rectangle(0, 1440, 2560, 1440);
        Assert.Null(GameWindowLayout.ChooseEdge(Primary, new[] { above, below }, 600, StripEdge.Top));
    }

    [Fact]
    public void SpanOntoRightMonitor()
    {
        var plan = GameWindowLayout.PlanSpan(Primary, Right, new[] { Left });
        Assert.NotNull(plan);
        Assert.Equal(Rectangle.FromLTRB(0, -9, 5120, 1440), plan!.Value.Client);
        // game inset: 9 px at the top (right monitor sits 9 px higher), 2560 px on the right
        Assert.Equal("/mapcast span 0,9,2560,0 2560,0,0,9", plan.Value.Command);
    }

    [Fact]
    public void SpanRefusedWhenItWouldCoverAThirdMonitor()
    {
        // Spanning from the far-left monitor to the right one would also cover the primary in between.
        Assert.Null(GameWindowLayout.PlanSpan(Left, Right, new[] { Primary }));
    }

    [Fact]
    public void TargetClientCoversMonitorPlusStrip()
    {
        Assert.Equal(new Rectangle(0, -600, 2560, 2040), GameWindowLayout.TargetClient(Primary, StripEdge.Top, 600));
        Assert.Equal(new Rectangle(0, 0, 2560, 2040), GameWindowLayout.TargetClient(Primary, StripEdge.Bottom, 600));
    }
}
