#!/usr/bin/env python3
"""Verify the complete official templates archive and extract Windows x86_64 templates.

The 1.2 GiB archive and resumable range cache remain under .tools/downloads/.
No Godot configuration or user-wide export template installation is modified.
"""
from __future__ import annotations

import argparse
from pathlib import Path

from godot_download import EXPORT_TEMPLATES, ROOT, extract_member, fetch_archive, validate_windows_x86_64


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--output", type=Path, default=ROOT / ".tools")
    args = parser.parse_args()
    if args.workers < 1:
        parser.error("--workers must be positive")
    archive = fetch_archive(EXPORT_TEMPLATES, args.workers)
    for mode in ("release", "debug"):
        filename = f"windows_{mode}_x86_64.exe"
        output = args.output / filename
        extract_member(archive, f"templates/{filename}", output)
        validate_windows_x86_64(output)
        print(f"Verified Windows x86_64 {mode} template: {output}", flush=True)


if __name__ == "__main__":
    main()
