<p align="center">
  <img src="assets/logo/export/mapcast-curseforge-256.png" width="128" alt="Mapcast logo">
</p>

<h1 align="center">Mapcast</h1>

<p align="center"><b>Your World of Warcraft map on a second monitor.</b><br>
An addon for <b>World of Warcraft Forever</b> plus a small Windows companion app.<br>
by Decoupled Lane Studio · MIT License</p>

---

## What it is

**Mapcast** (the addon) adds a standalone map window that behaves like the normal `M` world map. It shows your position arrow, party members, quest areas and POIs, flight points, dungeon entrances and fog of war, plus pins from other addons such as Questie, TomTom and HandyNotes. It follows you from zone to zone, zooms with the mouse wheel and stays open while you play.

**Mapcast Companion** (the Windows app) copies that map into its own window. You drag that window to your second monitor and leave it there. Addons can't open separate OS windows, so the companion fills that gap.

```
 Game window (monitor 1)                         Mapcast Companion (monitor 2)
+--------------------------------------+         +---------------------------+
|                                      |         |                           |
|                                      |  screen |      [ live map, big ]    |
|                          +--------+  | capture |                           |
|                          | Mapcast|=============>                           |
|                          +--------+  |         |                           |
+--------------------------------------+         +---------------------------+
```

## Screenshots

_Screenshots coming soon._ <!-- docs/screenshots/addon.png, docs/screenshots/companion.png -->

## Install

### The addon

- **CurseForge:** search for **Mapcast** in the CurseForge app (project 1795400) and install it for *World of Warcraft Forever*.
- **Manual:** download `Mapcast-<version>.zip` from [Releases](https://github.com/TankerALane/mapcast/releases) and unzip it into
  `World of Warcraft\_forever_\Interface\AddOns\` so that you end up with `...\AddOns\Mapcast\Mapcast.toc`.

### The companion (Windows 10 2004+ / Windows 11)

1. Download `MapcastCompanion-<version>-win-x64.exe` from [Releases](https://github.com/TankerALane/mapcast/releases).
2. Put it anywhere (it's portable, no installer) and run it.
3. Settings are stored in `%LOCALAPPDATA%\MapcastCompanion\settings.json`. Delete that folder to reset.

#### "Windows protected your PC" (SmartScreen)

The exe is **not code-signed**, because signing certificates cost money every year and this is a free hobby project. SmartScreen warns about unsigned downloads it hasn't seen many times before. To run it, click **More info → Run anyway**.

Why it's safe to run:

- **Open source.** All of the code is in [`companion/`](companion/).
- **Built in public.** Each release exe is built by GitHub Actions directly from the tagged source. The build log is public on the [Actions tab](https://github.com/TankerALane/mapcast/actions).
- **Checksummed.** Each release includes a `.sha256` file. Check that your download matches it:

  ```powershell
  Get-FileHash .\MapcastCompanion-v0.1.0-win-x64.exe -Algorithm SHA256
  # compare with the hash inside MapcastCompanion-v0.1.0-win-x64.exe.sha256
  ```

  If the hashes differ, don't run the file.

## How to use

1. Log in. Mapcast appears in the bottom-right corner. A one-time popup explains the companion and shows its download link.
2. In game, type **`/mapcast capture`**. The map switches to *capture mode*: a clean, fixed-size frame with a solid magenta border.
3. Start **Mapcast Companion**. It finds World of Warcraft and the magenta border automatically, then shows just the map.
4. Drag the companion window to your second monitor. Double-click it to go borderless; right-click it for every other option.

The game must run in **Windowed** or **Windowed (Fullscreen)** mode.

### Commands

| Command | What it does |
| --- | --- |
| `/mapcast` | Show or hide the map |
| `/mapcast show` / `hide` | Show or hide |
| `/mapcast lock` / `unlock` | Lock position and size (also hides the title bar until you hover) |
| `/mapcast follow` | Toggle auto-follow of your current zone |
| `/mapcast capture` | Toggle capture mode for the companion |
| `/mapcast reset` | Reset position, size and scale |
| `/mapcast span ...` | Span mode: the map fills your second monitor. The companion shows the exact command |
| `/mapcast offscreen top 600` | Off-screen mode: keep the map in a hidden 600 px strip at the top (or `bottom`) of the game window |
| `/mapcast normal` | Turn span / off-screen mode off |
| `/mapcast companion` | Show the companion download info again |
| `/mapcast options` | Open the options panel (also under *Options → AddOns → Mapcast*) |

Key bindings for show/hide, lock and capture mode are under *Key Bindings → AddOns → Mapcast*.

### On the map

- **Mouse wheel:** zoom. **Drag:** pan when zoomed in.
- **Left-click** a sub-zone to open it; **right-click** to go up a level. The **Zones** button browses continents and zones.
- Browsing pauses auto-follow. It resumes after 30 seconds (configurable), or right away when you click **Follow**.
- **Alt+drag** moves the frame while it's unlocked, which is handy in capture mode where there's no title bar.
- Pins are view-only: hovering shows the tooltip, clicking does nothing. That keeps Mapcast from interfering with the default map and the quest log.

### Span mode (recommended): a full, interactive map on your second monitor

The game window is stretched across your game monitor and the monitor next to it. Mapcast keeps the game on its own monitor and fills the other one with the map. Because the map is really part of the game window, it is drawn at full resolution and you control it with the mouse like any in-game map. There is no screen capture involved.

1. Set the game's *Display Mode* to **Windowed** (not Windowed Fullscreen).
2. In Mapcast Companion, right-click → **Game window → Span game onto *monitor***.
3. Type the command the companion shows you, for example `/mapcast span 0,9,2560,0 2560,0,0,9`. Mapcast remembers it, and you can close the companion.

- The monitors must sit next to each other with no third monitor in between.
- While the game has focus, the second monitor belongs to the game window. Click another window to bring it in front.
- The game renders a bigger window, so it may run a little slower.
- If the game shrinks its window back on its own (for example after a restart), run *Span game onto...* again.
- To undo: right-click → *Game window → Restore game window*, then `/mapcast normal`.

### Off-screen mode: no map on your game screen at all

Windows captures the *whole* game window, including parts that hang off the edge of your monitors. Off-screen mode uses that:

1. Set the game's *Display Mode* to **Windowed** (not Windowed Fullscreen).
2. In Mapcast Companion, right-click → **Game window → Hide the map off-screen**. The companion makes the game window taller than your monitor, so a strip of it (600 px by default) sits above (or below) the monitor where no screen shows it. The title bar goes up there too.
3. Type the command the companion shows you, for example **`/mapcast offscreen top 600`**.

Mapcast then puts the map in the hidden strip and keeps the rest of the game on your monitor: it insets the game UI and the 3D view to the visible part and adjusts the UI scale so everything stays the same size (the same mechanism the game uses for notched screens). These changes are made out of combat only.

- It needs free space above or below the monitor the game is on (no other monitor directly there). The companion checks that for you.
- The capture height plus border must fit in the strip (640×480 fits in 600).
- To undo: right-click → *Game window → Restore game window*, then `/mapcast normal`.
- Resizing the game window is the only thing the companion does to the game, and only when you choose a *Game window* option. It's the same as dragging the window's edges.

### Keeping the in-game frame out of the way

Without span or off-screen mode, the companion can only copy what is actually drawn on screen, so **the Mapcast frame has to stay visible in the game window.** You can make it less intrusive:

- It defaults to a screen corner. Put it wherever it bothers you least.
- In *Options → Mapcast → Capture mode*, set a **smaller capture size** (for example 320×240). The companion scales it up, so it looks softer on the second monitor.
- **Opacity** works too, but the companion sees the faded result, so the second-monitor image fades with it.
- *Layer: Behind everything* puts the frame under other UI. Anything that covers it (bags, tooltips) also appears on the second monitor.

## Passive capture / Terms of Service

Mapcast Companion is **strictly passive screen capture.** It uses the standard Windows Graphics Capture API, the same one OBS, Discord and the Windows Snipping Tool use, to copy pixels from the game window as Windows composites them.

The one exception is the optional *Game window* commands, which set the size and position of the game window (exactly what dragging its edges does) when you click it.

It does **not** read or write game memory, inject code or input, hook the game process, or automate gameplay in any way. The addon uses only the public World of Warcraft addon API. The two parts don't communicate except through what you can see on screen.

Mapcast is not affiliated with or endorsed by Blizzard Entertainment.

## Known limits

- **Exclusive fullscreen can't be captured.** Use Windowed or Windowed (Fullscreen).
- **Minimised game = frozen map.** Windows doesn't render minimised windows, so the companion shows the last frame until you restore the game.
- **The in-game frame must stay on screen** and uncovered, unless you use off-screen mode (see above).
- **Off-screen mode** needs Windowed mode and free desktop space above or below the game's monitor. A thin window border or shadow may show on a monitor next to the game. Cinematics briefly use the full window.
- **Third-party pins are copies.** Mapcast mirrors pins from addons built on HereBeDragons-Pins (Questie, TomTom, HandyNotes, GatherMate2, ...). Pins drawn some other way only appear on the `M` map. Mirrored pins show their addon's tooltip on hover, but clicks aren't forwarded.
- **Pin clicks are disabled** on the Mapcast map (see *On the map*).
- **Windows 11 capture border:** Windows may draw a thin yellow border around the game window while it is captured. Mapcast Companion asks Windows to hide it where that is supported.
- **HDR / colour filters:** the magenta marker is matched with some tolerance. If auto-detect still fails, right-click → *Region → Select region manually*.
- **Forever only.** The TOC targets the Forever client (Interface 16001).

## Troubleshooting

Run the companion with `--diagnose` to get a report and screenshots for a bug report:

```powershell
.\MapcastCompanion-v0.1.0-win-x64.exe --diagnose --out .\mapcast-diagnose
```

This writes `full.png` (what Windows gives the app), `map.png` (the detected map, if found) and `result.txt`.

## Building from source

- **Addon:** copy `addon/Mapcast` into your `Interface\AddOns` folder. There's no build step.
- **Companion:** install the .NET 10 SDK, then:

  ```powershell
  dotnet test companion/MapcastCompanion.Tests
  dotnet publish companion/MapcastCompanion -c Release -o publish
  ```

- **Logo exports:** `python assets/logo/render.py` (uses headless Chrome or Edge).
- **Releases:** pushing a `v*` tag runs [`.github/workflows/release.yml`](.github/workflows/release.yml). It builds the exe and its checksum, packages the addon with the BigWigs packager, uploads it to CurseForge, and publishes a GitHub Release.

## License

[MIT](LICENSE) © 2026 Decoupled Lane Studio
