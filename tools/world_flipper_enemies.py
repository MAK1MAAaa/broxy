"""Normalize the pinned original monster poses without changing game dimensions."""

from __future__ import annotations

import hashlib
from pathlib import Path

from PIL import Image

ENEMY_IDS = frozenset({"chaser", "rusher", "tank", "caster", "boss"})


def _clean_alpha(source: dict, pose: Image.Image) -> Image.Image:
    result = pose.copy()
    for rule in source.get("alpha_cleanup", []):
        rect = rule["rect"]
        color = rule["rgba"]
        expected = rule["expected_pixels"]
        if len(rect) != 4 or any(type(value) is not int for value in rect):
            raise ValueError(f"Invalid source-coordinate alpha mask: {source['id']}")
        x, y, width, height = rect
        if x < 0 or y < 0 or width < 1 or height < 1 or x + width > pose.width or y + height > pose.height:
            raise ValueError(f"Alpha mask escapes its original source: {source['id']}")
        if len(color) != 4 or any(type(value) is not int or value < 0 or value > 255 for value in color):
            raise ValueError(f"Invalid exact alpha-mask color: {source['id']}")
        if type(expected) is not int or expected < 1:
            raise ValueError(f"Invalid alpha-mask pixel count: {source['id']}")
        removed = 0
        for row in range(y, y + height):
            for column in range(x, x + width):
                if result.getpixel((column, row)) == tuple(color):
                    result.putpixel((column, row), (0, 0, 0, 0))
                    removed += 1
        if removed != expected:
            raise ValueError(f"Original ground-shadow mask changed: {source['id']}; expected {expected}, found {removed}")
    if result.getchannel("A").getbbox() is None:
        raise ValueError(f"Alpha cleanup removed the complete enemy: {source['id']}")
    return result


def _pose(source: dict, path: Path) -> Image.Image:
    source_id = str(source["id"])
    if hashlib.sha256(path.read_bytes()).hexdigest() != source["sha256"]:
        raise ValueError(f"Enemy source checksum changed: {source_id}")
    with Image.open(path) as image:
        if image.format != "GIF" or list(image.size) != source["source_size"]:
            raise ValueError(f"Unexpected enemy source format or canvas: {source_id}")
        if image.n_frames != source["frame_count"] or image.n_frames != 1:
            raise ValueError(f"An enemy static pose requires exactly one source frame: {source_id}")
        duration = int(image.info.get("duration", 0))
        if source["durations_ms"] != [duration]:
            raise ValueError(f"Unexpected enemy source timing: {source_id}")
        pose = image.convert("RGBA")
    alpha = pose.getchannel("A")
    if alpha.getextrema() != (0, 255) or any(value not in (0, 255) for value in alpha.tobytes()):
        raise ValueError(f"The enemy pose must retain crisp transparent source pixels: {source_id}")
    return _clean_alpha(source, pose)


def _normalize(source: dict, pose: Image.Image) -> Image.Image:
    source_id = str(source["id"])
    scale = source["scale"]
    canvas_size = tuple(source["canvas_size"])
    offset = tuple(source["offset"])
    if type(scale) is not int or scale < 1 or scale > 8:
        raise ValueError(f"The enemy scale must be a small positive integer: {source_id}")
    if len(canvas_size) != 2 or any(type(value) is not int or value <= 0 or value > 1024 for value in canvas_size):
        raise ValueError(f"Invalid enemy canvas: {source_id}")
    if len(offset) != 2 or any(type(value) is not int or value < 0 for value in offset):
        raise ValueError(f"Invalid enemy placement: {source_id}")
    scaled_size = (pose.width * scale, pose.height * scale)
    if offset[0] + scaled_size[0] > canvas_size[0] or offset[1] + scaled_size[1] > canvas_size[1]:
        raise ValueError(f"The original enemy pose would be clipped: {source_id}")
    result = Image.new("RGBA", canvas_size)
    result.alpha_composite(pose.resize(scaled_size, Image.Resampling.NEAREST), offset)
    return result


def enemy_assets(sources: list[dict], paths: dict[str, Path], output: Path) -> list[dict]:
    """Validate all five cached original poses, then write PNGs and manifest records."""
    enemies = [source for source in sources if source.get("kind") == "enemy"]
    game_ids = [str(source["game_id"]) for source in enemies]
    if len(game_ids) != len(ENEMY_IDS) or set(game_ids) != ENEMY_IDS:
        raise ValueError("The enemy family must cover the five existing enemy roles exactly once")
    images: list[tuple[dict, Image.Image]] = []
    for source in enemies:
        source_id = str(source["id"])
        if source_id != "enemy_" + str(source["game_id"]):
            raise ValueError(f"Enemy source identity does not match its game role: {source_id}")
        images.append((source, _normalize(source, _pose(source, paths[source_id]))))
    records: list[dict] = []
    for source, image in images:
        relative = "sprites/" + str(source["game_id"]) + ".png"
        path = output / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        image.save(path, optimize=False)
        records.append({
            "id": str(source["id"]),
            "path": "assets/worldflipper/" + relative,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "size": list(image.size),
            "alpha_bounds": list(image.getchannel("A").getbbox()),
            "filter": "nearest",
            "source_ids": [str(source["id"])],
            "alpha_cleanup": source.get("alpha_cleanup", []),
            "cleaned_source_pixels": sum(rule["expected_pixels"] for rule in source.get("alpha_cleanup", [])),
            "normalization": f"Exact source-coordinate ground-shadow alpha cleanup; {source['scale']}x nearest at {tuple(source['offset'])}; body colors and black outlines retained inside {image.width}x{image.height}",
        })
    return records
