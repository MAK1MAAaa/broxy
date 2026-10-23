#!/bin/sh
set -eu
BROXY_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BROXY_GODOT=${GODOT_BIN:-"$BROXY_ROOT/.tools/godot/Godot.app/Contents/MacOS/Godot"}
BROXY_APP=${BROXY_APP_PATH:-"$BROXY_ROOT/build/Embers.app"}
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
mkdir -p "$BROXY_ROOT/build"
"$BROXY_GODOT" --headless --path "$BROXY_ROOT" --editor --import --quit
"$BROXY_GODOT" --headless --path "$BROXY_ROOT" --export-release macOS "$BROXY_APP"
# Notices remain directly readable in Finder without unpacking the game's PCK.
mkdir -p "$BROXY_APP/Contents/Resources/licenses"
cp "$BROXY_ROOT/assets/licenses/Godot-LICENSE.txt" "$BROXY_ROOT/assets/licenses/Godot-COPYRIGHT.txt" "$BROXY_ROOT/assets/licenses/README.md" "$BROXY_APP/Contents/Resources/licenses/"
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
