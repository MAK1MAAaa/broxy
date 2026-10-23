# Binary distribution notices

This application uses **Godot Engine 4.7.2-stable** under the MIT license. The engine and bundled third-party notices are preserved verbatim in:

- `Godot-LICENSE.txt`: https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/LICENSE.txt
- `Godot-COPYRIGHT.txt`: https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/COPYRIGHT.txt

These notices were obtained from the official `godotengine/godot` repository. The macOS build script copies this directory's notices to `Embers.app/Contents/Resources/licenses/` before code signing, so they are accessible through Finder's **Show Package Contents** without opening the game archive.

The Windows build script copies the same notices to `Embers-windows-x86_64/licenses/`, alongside `Embers.exe` and `Embers.pck`. Keep that directory when redistributing the extracted application or its ZIP archive.

The project's original generated SVG artwork and synthesized WAV audio are dedicated under CC0-1.0; their provenance is recorded separately in `assets/PROVENANCE.md`. This document and the bundled engine notices do not assign an open-source license to the project's own game code.
