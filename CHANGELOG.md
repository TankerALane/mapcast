# Changelog

All notable changes to Mapcast and Mapcast Companion. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0]

First release.

### Mapcast (addon)
- Standalone, movable, resizable, scalable map window for World of Warcraft Forever.
- Built on Blizzard's own map canvas and data providers: player and party arrows, quest areas and POIs, flight points, dungeon entrances, fog of war, area POIs and more. The default `M` map is never touched.
- Copies pins from HereBeDragons-based addons (Questie, TomTom, HandyNotes, GatherMate2, ...), with their tooltips.
- Auto-follows your zone, keeps the arrow centred when zoomed, mouse-wheel zoom and drag pan, zone browser.
- Lock mode with minimal chrome, opacity, scale, pin size and layer options.
- Capture mode: a clean, pixel-exact frame with a magenta marker border for Mapcast Companion.
- `/mapcast` commands and key bindings.
- First-run popup and options panel with the companion download link.
- Off-screen mode (`/mapcast offscreen`): the map lives in a strip of the game window that no monitor shows, and the game UI and 3D view stay on the visible part.
- `/mapcast debug` reports what the pin mirror found.

### Mapcast Companion (Windows)
- Mirrors the Mapcast frame into its own window using Windows Graphics Capture.
- Finds the frame automatically from the marker border and follows it if you move it. Manual region selection is also available.
- Resizable, borderless and always-on-top modes; keep-aspect, smooth scaling and frame-rate options.
- *Off-screen map*: optionally extends the game window past its monitor so the map can be hidden (off-screen mode).
- `--diagnose` mode for bug reports.
- Portable self-contained single-file exe with a published SHA-256 checksum.
