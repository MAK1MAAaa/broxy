#!/bin/sh
set -eu
BROXY_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) BROXY_DEFAULT_GODOT="$BROXY_ROOT/.tools/godot/Godot_v4.7.2-stable_win64_console.exe" ;;
  *) BROXY_DEFAULT_GODOT="$BROXY_ROOT/.tools/godot/Godot.app/Contents/MacOS/Godot" ;;
esac
BROXY_GODOT=${GODOT_BIN:-"$BROXY_DEFAULT_GODOT"}
if [ ! -x "$BROXY_GODOT" ]; then
  echo "Godot not found. Run: python tools/fetch_godot.py, or set GODOT_BIN." >&2
  exit 1
fi
exec "$BROXY_GODOT" --path "$BROXY_ROOT" "$@"
