#!/usr/bin/env python3
"""Fetch and verify the pinned official standard Windows or macOS Godot editor."""
from __future__ import annotations

import argparse
import platform
import subprocess
from pathlib import Path

from godot_download import MACOS_EDITOR, ROOT, VERSION, WINDOWS_EDITOR, extract_member, fetch_archive, validate_windows_x86_64


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("windows", "macos"), default=None)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--output", type=Path, default=ROOT / ".tools" / "godot")
    args = parser.parse_args()
    target_platform = args.platform or {"Windows": "windows", "Darwin": "macos"}.get(platform.system())
    if target_platform is None:
        parser.error("Host platform is unsupported; explicitly select --platform windows or --platform macos")
    if args.workers < 1:
        parser.error("--workers must be positive")
    asset = WINDOWS_EDITOR if target_platform == "windows" else MACOS_EDITOR
    archive = fetch_archive(asset, args.workers)
    args.output.mkdir(parents=True, exist_ok=True)
    if target_platform == "windows":
        for suffix in ("win64.exe", "win64_console.exe"):
            filename = f"Godot_v{VERSION}_{suffix}"
            executable = args.output / filename
            extract_member(archive, filename, executable)
            validate_windows_x86_64(executable)
        print(f"Verified official editor: {executable}", flush=True)
    else:
        # ditto preserves macOS bundle permissions and symbolic links.
        subprocess.run(["ditto", "-x", "-k", str(archive), str(args.output)], check=True)
        print(f"Verified official editor: {args.output / 'Godot.app'}", flush=True)


if __name__ == "__main__":
    main()
