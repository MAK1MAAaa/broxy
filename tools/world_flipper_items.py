"""Normalize pinned original-game accessories, armament cores and skill symbols."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = Path(__file__).with_name("world_flipper_items_sources.json")
RELIC_IDS = frozenset({
    "damage", "haste", "speed", "vitality", "armor", "magnet", "moon_charm",
    "pilgrim", "bulwark", "hourglass", "blood_pact", "grave_candle", "fold_clasp", "echo_stone",
})
RUNE_IDS = frozenset({"pierce", "bounce", "blast"})
SKILL_IDS = frozenset({"skill_pulse", "skill_starfall", "skill_arc_slash"})
ICON_IDS = RELIC_IDS | RUNE_IDS | SKILL_IDS
SIZE = (64, 64)


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _source_frame(source: dict, path: Path) -> Image.Image:
    if _sha(path) != source["sha256"]:
        raise ValueError(f"Item source checksum changed: {source['id']}")
    with Image.open(path) as raw:
        if raw.format != "PNG" or list(raw.size) != source["source_size"]:
            raise ValueError(f"Unexpected item source PNG or canvas: {source['id']}")
        image = raw.convert("RGBA")
    crop = source["crop"]
    if len(crop) != 4 or any(type(value) is not int for value in crop):
        raise ValueError(f"Item crop requires four integer coordinates: {source['id']}")
    x, y, width, height = crop
    if min(x, y) < 0 or min(width, height) <= 0 or x + width > image.width or y + height > image.height:
        raise ValueError(f"Item source crop leaves its original image: {source['id']}")
    frame = image.crop((x, y, x + width, y + height))
    alpha = frame.getchannel("A")
    if alpha.getbbox() is None or alpha.getextrema() != (0, 255):
        raise ValueError(f"The original item must retain its transparent silhouette: {source['id']}")
    return frame


def item_assets(sources: list[dict], paths: dict[str, Path], output: Path) -> list[dict]:
    """Validate the entire item family before writing any existing output PNG."""
    selected = [source for source in sources if source.get("kind") == "item_icon"]
    if len(selected) != len(ICON_IDS) or {source["game_id"] for source in selected} != ICON_IDS:
        raise ValueError("The item family must cover fourteen relics, three runes and three skill symbols exactly once")
    if len({source["id"] for source in selected}) != len(selected):
        raise ValueError("Each original item source must have a distinct identity")
    normalized: list[tuple[dict, Image.Image, tuple[int, int]]] = []
    for source in selected:
        game_id = source["game_id"]
        expected_kind = "relic" if game_id in RELIC_IDS else "rune" if game_id in RUNE_IDS else "skill"
        if source.get("item_kind") != expected_kind:
            raise ValueError(f"Item category does not match its original game slot: {source['id']}")
        frame = _source_frame(source, paths[source["id"]])
        scale = source["scale"]
        if type(scale) is not int or not 1 <= scale <= 8:
            raise ValueError(f"An item scale must be a small positive integer: {source['id']}")
        extent = frame.width * scale, frame.height * scale
        if extent[0] > SIZE[0] or extent[1] > SIZE[1]:
            raise ValueError(f"The original item would be clipped in its runtime canvas: {source['id']}")
        offset = (SIZE[0] - extent[0]) // 2, (SIZE[1] - extent[1]) // 2
        image = Image.new("RGBA", SIZE)
        image.alpha_composite(frame.resize(extent, Image.Resampling.NEAREST), offset)
        normalized.append((source, image, offset))
    records: list[dict] = []
    for source, image, offset in normalized:
        relative = "icons/" + source["game_id"] + ".png"
        path = output / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        image.save(path, optimize=False)
        record = {
            "id": "item_icon_" + source["game_id"],
            "path": "assets/worldflipper/" + relative,
            "sha256": _sha(path),
            "size": list(SIZE),
            "alpha_bounds": list(image.getchannel("A").getbbox()),
            "filter": "nearest",
            "source_ids": [source["id"]],
            "source_crop": source["crop"],
            "source_scale": source["scale"],
            "offset": list(offset),
            "item_kind": source["item_kind"],
            "source_name": source["name"],
            "normalization": f"{source['scale']}x nearest, original RGBA colors and alpha preserved, centered at {offset} inside 64x64; no labels, frames or recoloring added",
        }
        if "atlas" in source:
            record["source_atlas"] = dict(source["atlas"])
        records.append(record)
    return records


def main() -> None:
    from fetch_world_flipper_art import acquire

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true", help="Use only checksum-verified cached sources")
    args = parser.parse_args()
    sources: list[dict] = json.loads(REGISTRY.read_text(encoding="utf-8"))["sources"]
    paths = {source["id"]: acquire(source, args.offline) for source in sources}
    records = item_assets(sources, paths, ROOT / "assets/worldflipper")
    record_path = ROOT / ".tools/worldflipper/item-asset-records.json"
    record_path.write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"assets": len(records), "records": str(record_path), "offline": args.offline}))


if __name__ == "__main__":
    main()
