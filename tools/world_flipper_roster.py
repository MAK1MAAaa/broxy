"""Normalize exact original character GIF poses into an independent roster family.

Whole source canvases retain 3x nearest pixels and their original per-frame timing.
Pixel portraits are explicit idle adaptations, not original full-shot artwork.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import urllib.request
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "tools/world_flipper_roster.json"
UPSTREAM = ROOT / "tools/world_flipper_character_animation_sources.json"
CATALOG = ROOT / "data/worldflipper/catalog.json"
CACHE = ROOT / ".tools/wf-character-assets/raw"
OUTPUT = ROOT / "assets/worldflipper/roster"
PREFIX = "assets/worldflipper/roster"
POSES = ("neutral", "walk_front", "walk_back")
PROFILE = {"cell_size": 128, "columns": 4, "rows": 3, "scale": 3, "foot_anchor": [64, 125],
           "portrait_policy": "pixel_idle_adaptation_not_original_fullshot"}
EXPECTED_DURATIONS = {"neutral": [20], "walk_front": [80, 100, 100, 100], "walk_back": [80, 100, 100, 100]}


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def git_blob_sha1(value: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(value)).encode("ascii") + b"\0" + value).hexdigest()


def validate_registry(registry: dict[str, Any], upstream: dict[str, Any], catalog: dict[str, Any]) -> None:
    if registry["schema_version"] != 1 or registry["normalization"] != PROFILE:
        raise ValueError("The approved whole-canvas roster normalization profile changed")
    if any(type(registry["normalization"][key]) is not int for key in ("cell_size", "columns", "rows", "scale")) or any(type(value) is not int for value in registry["normalization"]["foot_anchor"]):
        raise ValueError("Roster cell dimensions and scale must be integers")
    if registry["upstream_registry_sha256"] != sha256(json_bytes(upstream)) or registry["mirror_commit"] != upstream["mirror_commit"] or registry["catalog_commit"] != catalog["source"]["commit"]:
        raise ValueError("Roster source registries differ from the locked animation/catalogue evidence")
    originals = {item["id"]: item for item in catalog["characters"]}
    archived = {item["id"]: item for item in upstream["sources"]}
    heroes, sources = registry["heroes"], registry["sources"]
    if not 0 < len(heroes) <= 505 or len(sources) != len(heroes) * 3:
        raise ValueError("Each roster character needs exactly three original poses")
    if len({hero["game_id"] for hero in heroes}) != len(heroes) or len({hero["canonical_id"] for hero in heroes}) != len(heroes) or len({source["id"] for source in sources}) != len(sources):
        raise ValueError("Duplicate roster character/source identity")
    linked: set[str] = set()
    by_id = {source["id"]: source for source in sources}
    for hero in heroes:
        if not re.fullmatch(r"[a-z][a-z0-9_]{0,47}", hero["game_id"]):
            raise ValueError("Unsafe roster game identity")
        original = originals[hero["canonical_id"]]
        if hero["dev_name"] != original["dev_name"] or hero["rarity"] != original["rarity"] or hero["element"] != original["element"] or hero["name_jp"] != original["name_jp"] or not hero["display_name"] or not hero["source_page"].startswith("https://wiki.biligame.com/worldflipper/"):
            raise ValueError("Roster alias differs from its canonical original character")
        if set(hero["source_ids"]) != set(POSES):
            raise ValueError("Roster alias is missing an original pose")
        for pose, identifier in hero["source_ids"].items():
            source = by_id[identifier]
            if source != archived[identifier] or source["canonical_character_id"] != hero["canonical_id"] or source["pose"] != pose or source["dev_name"] != hero["dev_name"]:
                raise ValueError("Roster source is not the exact archived character pose")
            if source["availability"] != "verified_original" or source["durations_ms"] != EXPECTED_DURATIONS[pose] or source["frame_count"] != len(EXPECTED_DURATIONS[pose]):
                raise ValueError("Unsupported original roster frame count or timing")
            if source["filename"] != f"{hero['canonical_id']}-{pose}.gif":
                raise ValueError("Unsafe or incorrect original GIF cache name")
            linked.add(identifier)
    if linked != set(by_id):
        raise ValueError("Unlinked roster animation source")


def acquire(source: dict[str, Any], cache: Path, offline: bool) -> bytes:
    path = cache / source["filename"]
    expected = source["expected_bytes"]
    if Path(source["filename"]).name != source["filename"] or type(expected) is not int or not 0 < expected <= 65536:
        raise ValueError("Invalid original GIF path or byte budget")
    if path.is_file():
        if path.stat().st_size != expected:
            raise ValueError("Original roster GIF size changed")
        raw = path.read_bytes()
    elif offline:
        raise FileNotFoundError("Missing original roster GIF: " + str(path))
    else:
        request = urllib.request.Request(source["url"], headers={"User-Agent": "broxy-original-roster/1"})
        with urllib.request.urlopen(request, timeout=40) as response:
            raw = response.read(expected + 1)
    if len(raw) != expected or sha256(raw) != source["sha256"] or git_blob_sha1(raw) != source["git_blob_sha1"]:
        raise ValueError("Original roster GIF differs from its fixed SHA256/Git blob")
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)
    return raw


def normalized_frames(source: dict[str, Any], raw: bytes) -> tuple[list[Image.Image], list[dict[str, Any]]]:
    if sha256(raw) != source["sha256"] or git_blob_sha1(raw) != source["git_blob_sha1"]:
        raise ValueError("Original GIF bytes changed before frame normalization")
    prepared: list[Image.Image] = []
    metadata: list[dict[str, Any]] = []
    with Image.open(io.BytesIO(raw)) as gif:
        if gif.format != "GIF" or list(gif.size) != source["source_size"] or gif.n_frames != source["frame_count"]:
            raise ValueError("Original GIF dimensions/format/frame count changed")
        width, height = gif.width * PROFILE["scale"], gif.height * PROFILE["scale"]
        offset = [(PROFILE["cell_size"] - width) // 2, PROFILE["foot_anchor"][1] - height]
        if min(offset) < 0 or offset[0] + width > PROFILE["cell_size"]:
            raise ValueError("Complete source canvas does not fit its approved roster cell")
        for index in range(gif.n_frames):
            gif.seek(index)
            rgba = gif.convert("RGBA")
            alpha = rgba.getchannel("A")
            bounds = alpha.getbbox()
            expected = source["frames"][index]
            duration = int(gif.info.get("duration", 0))
            if alpha.getextrema() != (0, 255) or set(alpha.tobytes()) - {0, 255} or bounds is None or list(bounds) != expected["alpha_bounds"] or sha256(rgba.tobytes()) != expected["rgba_sha256"] or duration != source["durations_ms"][index]:
                raise ValueError("Original GIF frame pixels, alpha, bounds or timing changed")
            bottom = bounds[3] - 1
            row = [x for x in range(gif.width) if alpha.getpixel((x, bottom)) > 0]
            if [min(row), bottom, max(row) + 1, bottom + 1] != expected["opaque_bottom_span"]:
                raise ValueError("Original GIF lowest opaque row changed")
            frame = Image.new("RGBA", (PROFILE["cell_size"], PROFILE["cell_size"]))
            frame.alpha_composite(rgba.resize((width, height), Image.Resampling.NEAREST), offset)
            prepared.append(frame)
            metadata.append({"source_frame": index, "source_rgba_sha256": expected["rgba_sha256"], "duration_ms": duration,
                "source_canvas": source["source_size"], "source_canvas_offset": offset,
                "alpha_bounds": list(frame.getchannel("A").getbbox()), "rgba_sha256": sha256(frame.tobytes())})
    return prepared, metadata


def produce(registry: dict[str, Any], upstream: dict[str, Any], catalog: dict[str, Any], cache: Path, offline: bool = True) -> tuple[dict[str, Any], dict[str, bytes]]:
    """Validate the complete family before producing any filesystem output."""
    validate_registry(registry, upstream, catalog)
    frames = {source["id"]: normalized_frames(source, acquire(source, cache, offline)) for source in registry["sources"]}
    assets: list[dict[str, Any]] = []
    images: dict[str, bytes] = {}
    for hero in registry["heroes"]:
        all_frames: list[Image.Image] = []
        frame_metadata: list[dict[str, Any]] = []
        animations = {}
        for pose in POSES:
            pose_frames, pose_metadata = frames[hero["source_ids"][pose]]
            animations[pose] = {"first_frame": len(all_frames), "frame_count": len(pose_frames), "durations_ms": [frame["duration_ms"] for frame in pose_metadata]}
            all_frames.extend(pose_frames)
            frame_metadata.extend({**record, "source_id": hero["source_ids"][pose]} for record in pose_metadata)
        atlas = Image.new("RGBA", (PROFILE["cell_size"] * PROFILE["columns"], PROFILE["cell_size"] * PROFILE["rows"]))
        for index, frame in enumerate(all_frames):
            atlas.alpha_composite(frame, ((index % PROFILE["columns"]) * PROFILE["cell_size"], (index // PROFILE["columns"]) * PROFILE["cell_size"]))
        for kind, image in (("idle", all_frames[0]), ("atlas", atlas), ("portrait", all_frames[0])):
            relative = f"{hero['game_id']}/{kind}.png"
            stream = io.BytesIO()
            image.save(stream, format="PNG", optimize=False)
            payload = stream.getvalue()
            images[relative] = payload
            record = {"id": f"roster_{hero['game_id']}_{kind}", "game_id": hero["game_id"], "canonical_id": hero["canonical_id"],
                "kind": "pixel_portrait_adaptation" if kind == "portrait" else "hero_" + kind,
                "path": PREFIX + "/" + relative, "size": list(image.size), "sha256": sha256(payload),
                "rgba_sha256": sha256(image.tobytes()), "alpha_bounds": list(image.getchannel("A").getbbox()),
                "cell_size": [128, 128], "foot_anchor": [64, 125], "scale": 3, "filter": "nearest",
                "source_ids": [hero["source_ids"][pose] for pose in POSES] if kind == "atlas" else [hero["source_ids"]["neutral"]]}
            if kind == "atlas":
                record.update(columns=4, rows=3, frame_count=9, animations=animations, frames=frame_metadata, transparent_tail_cells=[9, 10, 11])
            if kind == "portrait":
                record.update(original_fullshot=False, adaptation="Complete original neutral pixel canvas at 3x nearest, identical to idle; not original full-shot art")
            assets.append(record)
    manifest = {"schema_version": 1, "revision": "world-flipper-roster-01", "source_registry": "tools/world_flipper_roster.json",
        "source_registry_sha256": sha256(json_bytes(registry)), "mirror_commit": registry["mirror_commit"],
        "catalog_commit": registry["catalog_commit"], "normalization": PROFILE,
        "scope": "Original neutral/front/back pixel poses only; independent roster family, not all characters or original skill FX.",
        "limitations": ["Portrait PNGs are explicit neutral-pixel adaptations, not original full-shot illustrations.",
            "Original skill FX/cutins, dedicated attack/hurt/death animations and full original character mechanics are not provided by this family.",
            "Whole source canvases retain their original size and movement; no per-frame cropping, recoloring, invented frames or alpha cutout.",
            "Foot anchor is the agreed source-canvas placement, not an inferred anatomical foot measurement."],
        "license_status": registry["license_status"], "heroes": registry["heroes"], "sources": registry["sources"], "assets": assets}
    return manifest, images


def build(output: Path, cache: Path, offline: bool = True, check: bool = False) -> dict[str, Any]:
    manifest, images = produce(read_json(REGISTRY), read_json(UPSTREAM), read_json(CATALOG), cache, offline)
    products = {**images, "manifest.json": json_bytes(manifest)}
    if check:
        if any(not (output / name).is_file() or (output / name).read_bytes() != payload for name, payload in products.items()):
            raise ValueError("Roster outputs differ from their deterministic offline rebuild")
    else:
        for name, payload in products.items():
            path = output / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(payload)
    return manifest


def contact_sheet(manifest: dict[str, Any], output: Path) -> Path:
    sheet = Image.new("RGBA", (128 * 9 + 100, 148 * len(manifest["heroes"])), "#dce6e0")
    draw = ImageDraw.Draw(sheet)
    for row, hero in enumerate(manifest["heroes"]):
        draw.text((6, row * 148 + 60), hero["game_id"], fill="#18344c")
        with Image.open(output / hero["game_id"] / "atlas.png") as atlas:
            for index in range(9):
                x, y = index % 4 * 128, index // 4 * 128
                sheet.alpha_composite(atlas.crop((x, y, x + 128, y + 128)), (100 + index * 128, row * 148))
    path = ROOT / ".tools/wf-character-assets/roster-contact.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(path)
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=CACHE)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--contact-sheet", action="store_true", help="Write an ignored native-scale preview after rebuilding")
    args = parser.parse_args()
    try:
        manifest = build(args.output, args.cache, args.offline, args.check)
        summary = {"heroes": len(manifest["heroes"]), "original_gifs": len(manifest["sources"]), "pngs": len(manifest["assets"]), "checked": args.check}
        if args.contact_sheet:
            summary["contact_sheet"] = str(contact_sheet(manifest, args.output))
        print(json.dumps(summary))
        return 0
    except (OSError, KeyError, TypeError, ValueError) as error:
        parser.exit(1, f"Roster asset build failed: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
