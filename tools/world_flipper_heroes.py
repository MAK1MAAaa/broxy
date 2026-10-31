"""Normalize pinned original hero animations and preserve byte-identical portraits."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".tools/worldflipper/source"
OUTPUT = ROOT / "assets/worldflipper"
REGISTRY = Path(__file__).with_name("world_flipper_heroes.json")
CELL_SIZE = 128
COLUMNS = 4
FEET_Y = 125
SCALE = 3
POSES = ("neutral", "walk_front", "walk_back")
HERO_IDS = ("clarisse", "celtie", "hanabi")
MAX_DOWNLOAD_BYTES = 8 * 1024 * 1024


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def acquire(source: dict, offline: bool = False) -> Path:
    filename = str(source["filename"])
    if Path(filename).name != filename:
        raise ValueError("Source filenames must remain inside the cache")
    path = CACHE / filename
    if path.exists():
        data = path.read_bytes()
    else:
        if offline:
            raise FileNotFoundError(f"Missing cached hero source: {path}")
        request = Request(str(source["url"]), headers={"User-Agent": "BroxyFanArtResearch/1.0"})
        with urlopen(request, timeout=40) as response:
            data = response.read(MAX_DOWNLOAD_BYTES + 1)
    if len(data) > MAX_DOWNLOAD_BYTES or _sha256(data) != source["sha256"]:
        raise ValueError(f"Hero source failed size or checksum validation: {filename}")
    if not path.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    return path


def _source_frames(source: dict, path: Path) -> tuple[list[Image.Image], list[int]]:
    if _sha256(path.read_bytes()) != source["sha256"]:
        raise ValueError(f"Unexpected hero source bytes: {source['id']}")
    frames: list[Image.Image] = []
    durations: list[int] = []
    with Image.open(path) as raw:
        if list(raw.size) != source["source_size"] or raw.n_frames != source["frame_count"]:
            raise ValueError(f"Unexpected hero source dimensions or frame count: {source['id']}")
        scaled_size = (raw.width * SCALE, raw.height * SCALE)
        offset = ((CELL_SIZE - scaled_size[0]) // 2, FEET_Y - scaled_size[1])
        if min(offset) < 0 or offset[0] + scaled_size[0] > CELL_SIZE:
            raise ValueError(f"Hero source does not fit its declared cell: {source['id']}")
        for index in range(raw.n_frames):
            raw.seek(index)
            rgba = raw.convert("RGBA")
            if set(rgba.getchannel("A").tobytes()) - {0, 255}:
                raise ValueError(f"Hero pixels contain interpolated alpha: {source['id']}/{index}")
            frame = Image.new("RGBA", (CELL_SIZE, CELL_SIZE))
            frame.alpha_composite(rgba.resize(scaled_size, Image.Resampling.NEAREST), offset)
            frames.append(frame)
            durations.append(int(raw.info.get("duration", 0)))
    if durations != source["durations_ms"]:
        raise ValueError(f"Unexpected hero source timing: {source['id']}")
    return frames, durations


def _image_metadata(path: Path, image: Image.Image, relative: str) -> dict:
    bounds = image.getchannel("A").getbbox()
    if bounds is None or image.getchannel("A").getextrema() != (0, 255):
        raise ValueError(f"Hero asset must retain a visible transparent silhouette: {relative}")
    return {
        "path": "assets/worldflipper/" + relative,
        "sha256": _sha256(path.read_bytes()),
        "size": list(image.size),
        "alpha_bounds": list(bounds),
    }


def _write_frame_asset(image: Image.Image, output: Path, relative: str) -> dict:
    path = output / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=False)
    return _image_metadata(path, image, relative)


def hero_assets(sources: list[dict], paths: dict[str, Path], output: Path) -> list[dict]:
    """Build separate 128px-cell atlases and byte-identical original portraits."""
    hero_sources = [source for source in sources if source.get("kind") in ("hero_animation", "hero_portrait")]
    if len(hero_sources) != 12 or len({source["id"] for source in hero_sources}) != 12:
        raise ValueError("The hero family requires twelve unique pinned sources")
    if {source.get("character_id") for source in hero_sources} != set(HERO_IDS):
        raise ValueError("The hero family requires Clarisse, Celtie and Hanabi")
    prepared: list[tuple[Image.Image, str, dict, bytes | None]] = []
    for character_id in HERO_IDS:
        selected = [source for source in hero_sources if source["character_id"] == character_id]
        if len(selected) != 4 or any(str(source["id"]) not in paths for source in selected):
            raise ValueError(f"The hero requires three animations and one portrait: {character_id}")
        animation_sources: dict[str, dict] = {}
        for source in selected:
            if source.get("kind") == "hero_animation":
                pose = str(source.get("pose", ""))
                if pose not in POSES or pose in animation_sources:
                    raise ValueError(f"Duplicate or unsupported hero pose: {character_id}/{pose}")
                animation_sources[pose] = source
        if set(animation_sources) != set(POSES):
            raise ValueError(f"The hero requires neutral and both walk cycles: {character_id}")
        frames: list[Image.Image] = []
        animations: dict[str, dict] = {}
        for pose in POSES:
            source = animation_sources[pose]
            pose_frames, durations = _source_frames(source, paths[str(source["id"])])
            expected_count = 1 if pose == "neutral" else 4
            if len(pose_frames) != expected_count:
                raise ValueError(f"Unexpected pose length: {character_id}/{pose}")
            animations[pose] = {"first_frame": len(frames), "frame_count": len(pose_frames), "durations_ms": durations}
            frames.extend(pose_frames)
        atlas = Image.new("RGBA", (CELL_SIZE * COLUMNS, CELL_SIZE * 3))
        for index, frame in enumerate(frames):
            atlas.alpha_composite(frame, ((index % COLUMNS) * CELL_SIZE, (index // COLUMNS) * CELL_SIZE))
        layout = {"character_id": character_id, "cell_size": [CELL_SIZE, CELL_SIZE], "foot_anchor": [CELL_SIZE // 2, FEET_Y], "feet_y": FEET_Y, "scale": SCALE, "filter": "nearest", "normalization": "3x nearest; center the complete source canvas horizontally and align its bottom at 125; do not crop or recenter individual frames"}
        idle = dict(layout, id=f"hero_{character_id}_idle", kind="hero_idle", columns=1, source_ids=[animation_sources["neutral"]["id"]], frame_count=1)
        prepared.append((frames[0], f"characters/{character_id}/idle.png", idle, None))
        motion = dict(layout, id=f"hero_{character_id}_atlas", kind="hero_atlas", columns=COLUMNS, source_ids=[animation_sources[pose]["id"] for pose in POSES], frame_count=len(frames), animations=animations)
        prepared.append((atlas, f"characters/{character_id}/atlas.png", motion, None))
        portraits = [source for source in selected if source.get("kind") == "hero_portrait"]
        if len(portraits) != 1:
            raise ValueError(f"The hero requires one pinned original portrait: {character_id}")
        source = portraits[0]
        original = paths[str(source["id"])].read_bytes()
        if _sha256(original) != source["sha256"]:
            raise ValueError(f"Unexpected portrait bytes: {character_id}")
        relative = f"portraits/{character_id}.png"
        with Image.open(paths[str(source["id"])]) as portrait:
            if list(portrait.size) != source["source_size"] or getattr(portrait, "n_frames", 1) != 1 or source["frame_count"] != 1 or portrait.mode != "RGBA":
                raise ValueError(f"Unexpected portrait image: {character_id}")
            prepared.append((portrait.copy(), relative, {"id": f"portrait_{character_id}", "kind": "hero_portrait", "character_id": character_id, "filter": "linear", "source_ids": [source["id"]], "normalization": "Original source bytes copied without alteration"}, original))
    for image, relative, _, _ in prepared:
        alpha = image.getchannel("A")
        if alpha.getbbox() is None or alpha.getextrema() != (0, 255):
            raise ValueError(f"Hero asset must retain a visible transparent silhouette: {relative}")
    assets: list[dict] = []
    for image, relative, metadata, original in prepared:
        if original is None:
            record = _write_frame_asset(image, output, relative)
        else:
            target = output / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(original)
            record = _image_metadata(target, image, relative)
        record.update(metadata)
        assets.append(record)
    return assets


def _contact_sheet(assets: list[dict], output: Path) -> Path:
    idles = [asset for asset in assets if asset["kind"] == "hero_idle"]
    sheet = Image.new("RGBA", (768, len(idles) * 168), (218, 232, 221, 255))
    draw = ImageDraw.Draw(sheet)
    for row, idle in enumerate(idles):
        character_id = str(idle["character_id"])
        with Image.open(output / f"characters/{character_id}/atlas.png") as atlas:
            for column, index in enumerate([0, 1, 2, 5, 6]):
                x, y = index % COLUMNS * CELL_SIZE, index // COLUMNS * CELL_SIZE
                sheet.alpha_composite(atlas.crop((x, y, x + CELL_SIZE, y + CELL_SIZE)), (96 + column * 132, row * 168 + 8))
        draw.text((8, row * 168 + 60), character_id, fill=(30, 55, 70))
    path = CACHE.parent / "heroes-contact.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(path)
    return path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true", help="Read checksum-verified cache files only")
    args = parser.parse_args()
    sources: list[dict] = json.loads(REGISTRY.read_text(encoding="utf-8"))["sources"]
    paths = {str(source["id"]): acquire(source, args.offline) for source in sources}
    assets = hero_assets(sources, paths, OUTPUT)
    print(json.dumps({"assets": assets, "contact": str(_contact_sheet(assets, OUTPUT)), "offline": args.offline}, ensure_ascii=False))


if __name__ == "__main__":
    main()
