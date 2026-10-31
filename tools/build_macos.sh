#!/bin/sh
set -eu
BROXY_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BROXY_GODOT=${GODOT_BIN:-"$BROXY_ROOT/.tools/godot/Godot.app/Contents/MacOS/Godot"}
BROXY_APP=${BROXY_APP_PATH:-"$BROXY_ROOT/build/Embers.app"}
if [ -n "${BROXY_PYTHON:-}" ]; then
  BROXY_PYTHON_BIN=$BROXY_PYTHON
elif command -v python3 >/dev/null 2>&1; then
  BROXY_PYTHON_BIN=python3
else
  BROXY_PYTHON_BIN=python
fi
case "$BROXY_APP" in
  /*.app) ;;
  *) echo "BROXY_APP_PATH must be an absolute path ending in .app" >&2; exit 1 ;;
esac
if [ ! -x "$BROXY_GODOT" ] || [ ! -f "$BROXY_ROOT/.tools/macos.zip" ]; then
  echo "Required: official Godot editor and macOS template in .tools/. See README.md." >&2
  exit 1
fi
for BROXY_LICENSE in Godot-LICENSE.txt Godot-COPYRIGHT.txt README.md; do
  if [ ! -f "$BROXY_ROOT/assets/licenses/$BROXY_LICENSE" ]; then
    echo "Missing distribution notice: assets/licenses/$BROXY_LICENSE" >&2
    exit 1
  fi
done
BROXY_WORLDFLIPPER_NOTICE="$BROXY_ROOT/assets/worldflipper/NOTICE.txt"
if [ ! -f "$BROXY_WORLDFLIPPER_NOTICE" ]; then
  echo "Missing distribution notice: assets/worldflipper/NOTICE.txt" >&2
  exit 1
fi
for BROXY_FONT_LICENSE in OFL.txt LICENSES/ark-pixel/OFL.txt LICENSES/cubic-11/OFL.txt LICENSES/galmuri/LICENSE.txt; do
  if [ ! -f "$BROXY_ROOT/assets/fonts/licenses/fusion-pixel/$BROXY_FONT_LICENSE" ]; then
    echo "Missing distribution notice: assets/fonts/licenses/fusion-pixel/$BROXY_FONT_LICENSE" >&2
    exit 1
  fi
done
mkdir -p "$BROXY_ROOT/build"
"$BROXY_PYTHON_BIN" "$BROXY_ROOT/tools/build_dash_benchmark_manifest.py"
"$BROXY_GODOT" --headless --path "$BROXY_ROOT" --editor --import --quit
"$BROXY_PYTHON_BIN" "$BROXY_ROOT/tools/build_dash_benchmark_manifest.py" --check
"$BROXY_GODOT" --headless --path "$BROXY_ROOT" --export-release macOS "$BROXY_APP"
"$BROXY_PYTHON_BIN" "$BROXY_ROOT/tools/build_dash_benchmark_manifest.py" --check
# Notices remain directly readable in Finder without unpacking the game's PCK.
mkdir -p "$BROXY_APP/Contents/Resources/licenses"
cp "$BROXY_ROOT/assets/licenses/Godot-LICENSE.txt" "$BROXY_ROOT/assets/licenses/Godot-COPYRIGHT.txt" "$BROXY_ROOT/assets/licenses/README.md" "$BROXY_APP/Contents/Resources/licenses/"
cp "$BROXY_WORLDFLIPPER_NOTICE" "$BROXY_APP/Contents/Resources/licenses/World-Flipper-NOTICE.txt"
for BROXY_FONT_LICENSE in OFL.txt LICENSES/ark-pixel/OFL.txt LICENSES/cubic-11/OFL.txt LICENSES/galmuri/LICENSE.txt; do
  BROXY_FONT_DESTINATION="$BROXY_APP/Contents/Resources/licenses/fonts/fusion-pixel/$BROXY_FONT_LICENSE"
  mkdir -p "$(dirname -- "$BROXY_FONT_DESTINATION")"
  cp "$BROXY_ROOT/assets/fonts/licenses/fusion-pixel/$BROXY_FONT_LICENSE" "$BROXY_FONT_DESTINATION"
done
BROXY_EXECUTABLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$BROXY_APP/Contents/Info.plist")
BROXY_BINARY="$BROXY_APP/Contents/MacOS/$BROXY_EXECUTABLE"
# Official macOS templates contain Universal binaries. Ship the requested arm64 slice.
/usr/bin/lipo "$BROXY_BINARY" -thin arm64 -output "$BROXY_BINARY.arm64"
chmod +x "$BROXY_BINARY.arm64"
mv "$BROXY_BINARY.arm64" "$BROXY_BINARY"
/usr/libexec/PlistBuddy -c "Delete :LSArchitecturePriority:1" "$BROXY_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :LSMinimumSystemVersionByArchitecture:x86_64" "$BROXY_APP/Contents/Info.plist"
/usr/bin/codesign --force --deep --sign - "$BROXY_APP"
/usr/bin/codesign --verify --deep --strict "$BROXY_APP"
/usr/bin/plutil -lint "$BROXY_APP/Contents/Info.plist"
/usr/bin/lipo -info "$BROXY_BINARY"
echo "Built: $BROXY_APP"
