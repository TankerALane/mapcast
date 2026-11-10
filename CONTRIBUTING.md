# Contributing

Thanks for helping. Bug reports and pull requests are welcome.

## Reporting bugs

Open an [issue](https://github.com/TankerALane/mapcast/issues) and include:

- Your Forever client version and the Mapcast / Mapcast Companion versions.
- Any Lua error text. Turn on error display in game with `/console scriptErrors 1`, or use BugSack.
- For companion problems, the output of `MapcastCompanion.exe --diagnose` (see the README).

## Pull requests

- Keep changes focused, and explain *why* in the description.
- **Addon:** test in game, including that the default `M` map and the quest log still work in and out of combat. Don't add code that calls protected functions or modifies Blizzard frames and tables.
- **Companion:** run `dotnet test companion/MapcastCompanion.Tests`. The companion must stay **passive**: no memory reading, no input injection, no automation.
- The addon package must not contain executables (CurseForge rules).
- The marker colour lives in two places, `addon/Mapcast/Core.lua` and `MarkerDetector.cs`. Keep them in sync.

By contributing you agree that your contribution is licensed under the MIT License.
