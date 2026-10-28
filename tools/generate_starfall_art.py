#!/usr/bin/env python3
"""Build the presentation-only pixel reskin without overwriting legacy art or audio."""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import struct
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "assets/starfall"


@dataclass(frozen=True)
class VectorAsset:
    name: str
    width: int
    height: int
    body: str
    role: str

    def encode(self) -> bytes:
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.width}" height="{self.height}" '
                f'viewBox="0 0 {self.width} {self.height}" shape-rendering="crispEdges">\n'
                f'{self.body}\n</svg>\n').encode("utf-8")


def build_vectors() -> list[VectorAsset]:
    from starfall_environment import generate as environment
    from starfall_icons import generate as icons
    from starfall_sprites import generate as sprites

    result: list[VectorAsset] = []

    def collect(name: str, width: int, height: int, body: str, role: str) -> None:
        if name.startswith("/") or ".." in Path(name).parts or not name.endswith(".svg"):
            raise ValueError(f"Unsafe generated asset path: {name}")
        asset = VectorAsset(name, width, height, body, role)
        ElementTree.fromstring(asset.encode())
        if any(previous.name == name for previous in result):
            raise ValueError(f"Duplicate generated asset: {name}")
        result.append(asset)

    sprites(collect)
    environment(collect)
    icons(collect)
    return result


def main() -> None:
    DESTINATION.mkdir(parents=True, exist_ok=True)
    entries: list[dict] = []
    for asset in build_vectors():
        target = DESTINATION / asset.name
        target.parent.mkdir(parents=True, exist_ok=True)
        content = asset.encode()
        target.write_bytes(content)
        source = "starfall_sprites.py" if asset.name.startswith("sprites/") else "starfall_environment.py" if asset.name == "arena.svg" or asset.name.startswith("maps/") else "starfall_icons.py"
        entries.append({"path": target.relative_to(ROOT).as_posix(), "size": [asset.width, asset.height],
                        "pivot": [0.5, 0.5], "role": asset.role, "source": "tools/" + source,
                        "license": "CC0-1.0", "sha256": hashlib.sha256(content).hexdigest()})
    menu = DESTINATION / "menu_art.png"
    content = menu.read_bytes()
    if content[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("Copy the selected generated menu illustration before building the manifest")
    entries.append({"path": "assets/starfall/menu_art.png", "size": list(struct.unpack(">II", content[16:24])),
                    "pivot": [0.5, 0.5], "role": "Existing masked caster and ritual courtyard menu illustration",
                    "source": "image-generation.json", "license": "Project generated artwork; see PROVENANCE.md",
                    "sha256": hashlib.sha256(content).hexdigest()})
    manifest = {"schema_version": 1, "art_revision": "starfall-01", "purpose": "Reskin of the existing Embers of the Occult game",
                "generator": "python tools/generate_starfall_art.py", "filter": "nearest for art; existing antialiased UI font",
                "legacy_manifest": "assets/manifest.json", "assets": entries}
    (DESTINATION / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"Generated {len(entries) - 1} pixel SVGs; registered one menu PNG; legacy assets/audio untouched")


if __name__ == "__main__":
    main()
