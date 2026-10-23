#!/bin/sh
set -eu
BROXY_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BROXY_GODOT=${GODOT_BIN:-"$BROXY_ROOT/.tools/godot/Godot.app/Contents/MacOS/Godot"}
if [ ! -x "$BROXY_GODOT" ]; then
  echo "Godot not found. Run: python3 tools/fetch_godot.py" >&2
  exit 1
fi
exec "$BROXY_GODOT" --path "$BROXY_ROOT" "$@"
