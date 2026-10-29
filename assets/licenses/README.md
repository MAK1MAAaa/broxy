# Binary distribution notices

This application uses **Godot Engine 4.7.2-stable** under the MIT license. The engine and bundled third-party notices are preserved verbatim in:

- `Godot-LICENSE.txt`: https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/LICENSE.txt
- `Godot-COPYRIGHT.txt`: https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/COPYRIGHT.txt

These notices were obtained from the official `godotengine/godot` repository. The macOS build script copies this directory's notices to `Embers.app/Contents/Resources/licenses/` before code signing, so they are accessible through Finder's **Show Package Contents** without opening the game archive.

The Windows build script copies the same notices to `Embers-windows-x86_64/licenses/`, alongside `Embers.exe` and `Embers.pck`. Keep that directory when redistributing the extracted application or its ZIP archive.

The bundled **Fusion Pixel 12px proportional zh-Hans** font comes from [Fusion Pixel Font 2026.10.25](https://github.com/TakWolf/fusion-pixel-font/releases/tag/2026.10.25), under the SIL Open Font License 1.1. Its original copyright and license are in `assets/fonts/licenses/fusion-pixel/OFL.txt`. The same source directory preserves the release's upstream notices in `LICENSES/ark-pixel/OFL.txt`, `LICENSES/cubic-11/OFL.txt` (including its own upstream font notices), and `LICENSES/galmuri/LICENSE.txt`. Font provenance and checksums are recorded in `assets/fonts/PROVENANCE.md`.

Both export presets explicitly include all four font notices. The build scripts also copy them individually, retaining their subdirectories, to `licenses/fonts/fusion-pixel/` on Windows and `Embers.app/Contents/Resources/licenses/fonts/fusion-pixel/` on macOS before code signing. A build fails if any required notice is missing. Keep this entire directory with all distributions of the game.

The game's **WORLD FLIPPER** character and armament images are original game materials downloaded from the [Chinese BWIKI](https://wiki.biligame.com/worldflipper/), [World Flipper Wiki](https://worldflipper.wiki.gg/), and [character preservation site](https://vivaldi6352.github.io/). The original rights remain with **© Cygames, Inc. / Citail Inc.**; see the official [copyright notice](https://worldflipper.jp/copyright/) and [website terms](https://worldflipper.jp/about/). No open asset license was found for these images. A Wiki text license or an open-source tool license must not be treated as permission for the game images. This is an unofficial fan work and does not claim official authorization or endorsement.

`assets/worldflipper/manifest.json` records individual sources, checksums and processing. Both export presets include that manifest and `assets/worldflipper/NOTICE.txt`. Both build scripts fail before export when this notice is missing, and copy it to the external `licenses/World-Flipper-NOTICE.txt` (inside `Contents/Resources/` on macOS, before signing). Retain this notice with the distribution.

The project's original generated SVG artwork and synthesized WAV audio are dedicated under CC0-1.0; their provenance is recorded separately in `assets/PROVENANCE.md`. That dedication does not apply to the original WORLD FLIPPER materials. This document and the bundled notices do not assign an open-source license to the project's own game code or to third-party game images.
