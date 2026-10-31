"""Normalize eight pinned original transparent armament sprites without cutouts."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = Path(__file__).with_name("world_flipper_weapon_expansion_sources.json")
IDS = frozenset({"sword_0012", "spear_0005", "sword_0004", "axe_0009", "book_0009", "sword_0007", "axe_0024", "sword_0011"})
SIZE = (64, 64)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def normalized_sprite(source: dict[str, Any], path: Path) -> tuple[Image.Image, tuple[int, int]]:
    if sha256(path) != source["sha256"]:
        raise ValueError("Original weapon checksum changed: " + source["id"])
    with Image.open(path) as raw:
        if raw.format != "PNG" or list(raw.size) != source["source_size"]:
            raise ValueError("Unexpected original weapon format or size: " + source["id"])
        frame = raw.convert("RGBA")
    if source["crop"] != [0, 0, frame.width, frame.height]:
        raise ValueError("Weapon sprites must preserve their complete original canvas")
    if frame.getchannel("A").getextrema() != (0, 255):
        raise ValueError("Original weapon must have a genuine transparent silhouette")
    scale = source["scale"]
    if type(scale) is not int or not 1 <= scale <= 3:
        raise ValueError("Weapon scaling must be an integer from one through three")
    extent = frame.width * scale, frame.height * scale
    if extent[0] > SIZE[0] or extent[1] > SIZE[1]:
        raise ValueError("Weapon scaling would clip the original canvas")
    offset = (SIZE[0] - extent[0]) // 2, (SIZE[1] - extent[1]) // 2
    result = Image.new("RGBA", SIZE)
    result.alpha_composite(frame.resize(extent, Image.Resampling.NEAREST), offset)
    return result, offset


def weapon_expansion_assets(sources: list[dict[str, Any]], paths: dict[str, Path], output: Path) -> list[dict[str, Any]]:
    selected = [source for source in sources if source.get("kind") == "weapon_expansion"]
    if len(selected) != len(IDS) or {source["game_id"] for source in selected} != IDS:
        raise ValueError("The expansion requires each of its eight original weapons exactly once")
    if len({source["id"] for source in selected}) != len(selected) or len({source["canonical_equipment_id"] for source in selected}) != len(selected):
        raise ValueError("Original weapon source and canonical IDs must be unique")
    normalized = [(source, *normalized_sprite(source, paths[source["id"]])) for source in selected]
    records = []
    for source, image, offset in normalized:
        relative = "icons/" + source["game_id"] + ".png"
        path = output / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        image.save(path, optimize=False)
        records.append({
            "id": source["game_id"], "path": "assets/worldflipper/" + relative, "sha256": sha256(path),
            "size": list(SIZE), "alpha_bounds": list(image.getchannel("A").getbbox()), "filter": "nearest",
            "source_ids": [source["id"]], "source_crop": source["crop"], "source_scale": source["scale"],
            "offset": list(offset), "item_kind": "weapon", "canonical_equipment_id": source["canonical_equipment_id"],
            "source_name": source["name"],
            "normalization": f"{source['scale']}x nearest, full original transparent canvas centered at {offset} inside 64x64; original colors and alpha preserved, no cutout, recoloring, labels or added frame",
        })
    return records


def main() -> int:
    from fetch_world_flipper_art import CACHE, acquire

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    sources = json.loads(REGISTRY.read_text(encoding="utf-8"))["sources"]
    CACHE.mkdir(parents=True, exist_ok=True)
    paths = {source["id"]: acquire(source, args.offline) for source in sources}
    records = weapon_expansion_assets(sources, paths, ROOT / "assets/worldflipper")
    record_path = ROOT / ".tools/wf-weapon-expansion/assets-raw.json"
    record_path.parent.mkdir(parents=True, exist_ok=True)
    record_path.write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"assets": len(records), "records": str(record_path), "offline": args.offline}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
