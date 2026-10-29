"""Normalize the pinned original monster poses without changing game dimensions."""

from __future__ import annotations

import hashlib
from pathlib import Path

from PIL import Image

ENEMY_IDS = frozenset({"chaser", "rusher", "tank", "caster", "boss"})


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
    return pose


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
            "normalization": f"{source['scale']}x nearest at {tuple(source['offset'])}; complete original pose retained without recoloring inside {image.width}x{image.height}",
        })
    return records
