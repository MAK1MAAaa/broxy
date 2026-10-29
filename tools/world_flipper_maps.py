"""Rebuild large arenas from pinned original World Flipper battle-floor pixels."""

from __future__ import annotations

import argparse
from collections import deque
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = Path(__file__).with_name("world_flipper_maps_sources.json")
MAP_IDS = frozenset({"reliquary", "mire", "glacier", "ashland"})
PROP_IDS = frozenset({"monument", "planter", "bumper"})
SIZE = (3780, 2192)
WORLD_ORIGIN = (-1146, -767)
WALKABLE = (64, 232, 3508, 2032)
PREVIEW_CROP = (1146, 772, 1280, 720)
SCALE = 2
HALF_SIZE = (SIZE[0] // SCALE, SIZE[1] // SCALE)
HALF_WALKABLE = tuple(value // SCALE for value in WALKABLE)


def _checked_image(source: dict, path: Path) -> Image.Image:
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != source["sha256"]:
        raise ValueError(f"Map source checksum changed: {source['id']}")
    with Image.open(path) as image:
        if image.format != "PNG" or list(image.size) != source["source_size"]:
            raise ValueError(f"Unexpected map source PNG or canvas: {source['id']}")
        return image.convert("RGBA")


def _crop(image: Image.Image, rect: list[int]) -> Image.Image:
    if len(rect) != 4 or any(type(value) is not int for value in rect):
        raise ValueError(f"Invalid integer source crop: {rect}")
    x, y, width, height = rect
    if min(x, y) < 0 or min(width, height) < 1 or x + width > image.width or y + height > image.height:
        raise ValueError(f"Source crop leaves its image: {rect}")
    return image.crop((x, y, x + width, y + height))


def _mirror_tile(patch: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Make adjoining edges share native pixels, including at the repeated seam."""
    block = Image.new(patch.mode, (patch.width * 2, patch.height * 2))
    block.paste(patch, (0, 0))
    block.paste(ImageOps.mirror(patch), (patch.width, 0))
    block.paste(ImageOps.flip(block.crop((0, 0, block.width, patch.height))), (0, patch.height))
    result = Image.new(patch.mode, size)
    for y in range(0, size[1], block.height):
        for x in range(0, size[0], block.width):
            result.paste(block, (x, y))
    return result


def _zone_mask(zone: dict) -> tuple[Image.Image, tuple[int, int]]:
    """Keep the gameplay ellipse while giving its native texture a pixelated edge."""
    center = zone.get("center", [])
    radius = zone.get("radius", [])
    if len(center) != 2 or len(radius) != 2 or any(type(value) not in (int, float) for value in center + radius):
        raise ValueError(f"Invalid terrain coordinates: {zone}")
    if any(not math.isfinite(value) for value in center + radius) or min(radius) <= 0:
        raise ValueError(f"Invalid terrain radius: {zone}")
    cx, cy = ((center[index] - WORLD_ORIGIN[index]) / SCALE for index in range(2))
    rx, ry = (value / SCALE for value in radius)
    left, top = math.floor(cx - rx), math.floor(cy - ry)
    right, bottom = math.ceil(cx + rx), math.ceil(cy + ry)
    if left < HALF_WALKABLE[0] or top < HALF_WALKABLE[1] or right > HALF_WALKABLE[2] or bottom > HALF_WALKABLE[3]:
        raise ValueError(f"Slow terrain leaves the walkable floor: {zone}")
    mask = Image.new("L", (right - left, bottom - top))
    pixels = mask.load()
    for y in range(mask.height):
        for x in range(mask.width):
            distance = ((x + left + 0.5 - cx) / rx) ** 2 + ((y + top + 0.5 - cy) / ry) ** 2
            if distance >= 1.0:
                continue
            edge = min(1.0, (1.0 - math.sqrt(distance)) * min(rx, ry) / 3.0)
            grain = ((x * 17 + y * 29 + (x // 4) * 11) % 13) / 12.0
            pixels[x, y] = round((128 + grain * 26) * (0.65 + edge * 0.35))
    return mask, (left, top)


def _floor(raw: Image.Image, source: dict, definition: dict) -> Image.Image:
    patch = _crop(raw, source["crop"]).convert("RGB")
    image = _mirror_tile(patch, HALF_SIZE)
    zones = definition.get("zones", [])
    if zones:
        if "zone_crop" not in source:
            raise ValueError(f"Slow terrain needs a native floor variant: {source['id']}")
        variant = _mirror_tile(_crop(raw, source["zone_crop"]).convert("RGB"), HALF_SIZE)
        for zone in zones:
            mask, position = _zone_mask(zone)
            x, y = position
            image.paste(variant.crop((x, y, x + mask.width, y + mask.height)), position, mask)
    return image


def _margins(image: Image.Image, raw: Image.Image, source: dict) -> None:
    """All upright original wall fragments stay outside the combat rectangle."""
    left, top, right, bottom = HALF_WALKABLE
    backdrop = raw.convert("RGB").getpixel((0, 0))
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, image.width - 1, top - 1), fill=backdrop)
    draw.rectangle((0, bottom, image.width - 1, image.height - 1), fill=backdrop)
    draw.rectangle((0, top, left - 1, bottom - 1), fill=backdrop)
    draw.rectangle((right, top, image.width - 1, bottom - 1), fill=backdrop)
    crops = source["border_crops"]
    for side, x in (("left", left), ("right", right)):
        strip = _crop(raw, crops[side]).convert("RGB")
        if strip.width > left:
            raise ValueError(f"Original wall fragment exceeds the narrow art margin: {source['id']}")
        strip = _mirror_tile(strip, (strip.width, bottom - top))
        image.paste(strip, (x - strip.width if side == "left" else x, top))
    upper = _crop(raw, crops["top"]).convert("RGB")
    if upper.height > top or upper.height > image.height - bottom:
        raise ValueError(f"Original upper wall exceeds the art margin: {source['id']}")
    upper = _mirror_tile(upper, (right - left, upper.height))
    image.paste(upper, (left, top - upper.height))
    image.paste(ImageOps.flip(upper), (left, bottom))


def _largest_component(image: Image.Image) -> Image.Image:
    """Separate a connected original landmark from neighboring detached lanterns."""
    occupied = {(x, y) for y in range(image.height) for x in range(image.width) if image.getpixel((x, y))[3] > 0}
    largest: list[tuple[int, int]] = []
    while occupied:
        first = occupied.pop()
        queue = deque([first])
        found = [first]
        while queue:
            x, y = queue.popleft()
            for point in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if point in occupied:
                    occupied.remove(point)
                    queue.append(point)
                    found.append(point)
        if len(found) > len(largest):
            largest = found
    result = Image.new("RGBA", image.size)
    for point in largest:
        result.putpixel(point, image.getpixel(point))
    return result


def _landmarks(image: Image.Image, raw: Image.Image, source: dict) -> list[dict]:
    """Compose original foreground art only in the nonwalkable outer margin."""
    if source.get("scale") != SCALE:
        raise ValueError("Landmarks must use the same native integer2x scale as the floor")
    variants = {name: _crop(raw, crop) for name, crop in source["variants"].items()}
    records: list[dict] = []
    left, top, right, bottom = HALF_WALKABLE
    for placement in source["placements"]:
        value = variants[placement["variant"]]
        if placement.get("largest_component", False):
            value = _largest_component(value)
        rotation = placement.get("rotation_degrees", 0)
        if type(rotation) is not int or rotation not in (0, 90, 180, 270):
            raise ValueError("Landmarks may only use exact quarter turns")
        if rotation:
            value = value.transpose({90: Image.Transpose.ROTATE_90, 180: Image.Transpose.ROTATE_180, 270: Image.Transpose.ROTATE_270}[rotation])
        position = placement["position"]
        if len(position) != 2 or any(type(value) is not int or value % SCALE for value in position):
            raise ValueError("Landmark placements must stay on the native2x pixel grid")
        x, y = (coordinate // SCALE for coordinate in position)
        if min(x, y) < 0 or x + value.width > image.width or y + value.height > image.height:
            raise ValueError("Landmark leaves the exported art canvas")
        if x < right and x + value.width > left and y < bottom and y + value.height > top:
            raise ValueError("Upright landmark overlaps the walkable rectangle")
        image.paste(value.convert("RGB"), (x, y), value.getchannel("A"))
        records.append({"source_id": source["id"], "source_crop": source["variants"][placement["variant"]],
                        "rotation_degrees": rotation, "scale": SCALE, "art_rect": [x * SCALE, y * SCALE, value.width * SCALE, value.height * SCALE],
                        "alpha_selection": "largest original alpha component" if placement.get("largest_component", False) else "complete cropped original alpha",
                        "placement": "Strictly outside walkable_art_rect; does not imply a gameplay collider"})
    return records


def _record(image: Image.Image, output: Path, relative: str, source: dict, asset_id: str, normalization: str) -> dict:
    path = output / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=False)
    alpha = image.convert("RGBA").getchannel("A")
    return {
        "id": asset_id,
        "path": "assets/worldflipper/" + relative,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "size": list(image.size),
        "alpha_bounds": list(alpha.getbbox()),
        "filter": "nearest",
        "source_ids": [source["id"]],
        "source_crop": source["crop"],
        "source_scale": source["scale"],
        "normalization": normalization,
    }


def map_assets(sources: list[dict], paths: dict[str, Path], output: Path) -> list[dict]:
    """Validate original floor/foreground/prop sources and emit four arenas and props."""
    selected = [source for source in sources if source.get("kind") in {"arena_map", "arena_prop", "arena_landmark"}]
    maps = [source for source in selected if source["kind"] == "arena_map"]
    props = [source for source in selected if source["kind"] == "arena_prop"]
    landmarks = [source for source in selected if source["kind"] == "arena_landmark"]
    if len(maps) != len(MAP_IDS) or {source["game_id"] for source in maps} != MAP_IDS:
        raise ValueError("The original map family must cover all four existing arena IDs exactly once")
    if len(props) != len(PROP_IDS) or {source["game_id"] for source in props} != PROP_IDS:
        raise ValueError("The original prop family must contain one monument, planter and bumper")
    if len(landmarks) != len(MAP_IDS) or {source["game_id"] for source in landmarks} != MAP_IDS:
        raise ValueError("Every map requires its own pinned original foreground landmark")
    if len({source["id"] for source in selected}) != len(selected):
        raise ValueError("Every map and prop source needs a unique identity")
    definitions = {definition["id"]: definition for definition in json.loads((ROOT / "data/arenas.json").read_text(encoding="utf-8"))}
    images = {source["id"]: _checked_image(source, paths[source["id"]]) for source in selected}
    records: list[dict] = []
    for source in maps:
        if source["scale"] != SCALE:
            raise ValueError("Arena floor pixels must retain the native integer 2x scale")
        game_id = source["game_id"]
        raw = images[source["id"]]
        image = _floor(raw, source, definitions[game_id])
        _margins(image, raw, source)
        landmark_source = next(landmark for landmark in landmarks if landmark["game_id"] == game_id)
        landmark_records = _landmarks(image, images[landmark_source["id"]], landmark_source)
        image = image.resize(SIZE, Image.Resampling.NEAREST)
        record = _record(image, output, f"maps/{game_id}.png", source, source["id"], source["normalization"])
        record.update({"world_origin": list(WORLD_ORIGIN), "walkable_art_rect": list(WALKABLE),
                       "zone_count": len(definitions[game_id].get("zones", [])),
                       "zone_normalization": "Same-source floor texture through a low-contrast dithered mask; geometry read from data/arenas.json without changing movement values or coordinates",
                       "border_crops": source["border_crops"], "landmarks": landmark_records,
                       "normalized_repeat_size": [source["crop"][2] * 4, source["crop"][3] * 4]})
        record["source_ids"].append(landmark_source["id"])
        if "zone_crop" in source:
            record["zone_source_crop"] = source["zone_crop"]
        records.append(record)
        x, y, width, height = PREVIEW_CROP
        preview = image.crop((x, y, x + width, y + height))
        preview_record = _record(preview, output, f"maps/previews/{game_id}.png", source, source["id"] + "_preview",
                                 "Unscaled 1280x720 crop of the current start camera from the normalized arena")
        preview_record["arena_crop"] = list(PREVIEW_CROP)
        preview_record["source_ids"].append(landmark_source["id"])
        records.append(preview_record)
    for source in props:
        scale = source["scale"]
        if type(scale) is not int or not 1 <= scale <= 8:
            raise ValueError(f"Prop scale must be a small positive integer: {source['id']}")
        frame = _crop(images[source["id"]], source["crop"])
        if frame.getchannel("A").getextrema() != (0, 255):
            raise ValueError(f"The original prop frame must retain its clean transparency: {source['id']}")
        size = (frame.width * scale, frame.height * scale)
        if size[0] > 96 or size[1] > 84:
            raise ValueError(f"The prop would leave its standard canvas: {source['id']}")
        image = Image.new("RGBA", (96, 96))
        offset = ((96 - size[0]) // 2, 84 - size[1])
        image.alpha_composite(frame.resize(size, Image.Resampling.NEAREST), offset)
        record = _record(image, output, f"props/{source['game_id']}.png", source, source["id"], source["normalization"])
        record.update({"offset": list(offset), "foot_anchor": [48, 84]})
        records.append(record)
    return records


def main() -> None:
    from fetch_world_flipper_art import acquire

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true", help="Only use checksum-verified cached sources")
    args = parser.parse_args()
    sources: list[dict] = json.loads(REGISTRY.read_text(encoding="utf-8"))["sources"]
    (ROOT / ".tools/worldflipper/source").mkdir(parents=True, exist_ok=True)
    paths = {source["id"]: acquire(source, args.offline) for source in sources}
    records = map_assets(sources, paths, ROOT / "assets/worldflipper")
    print(json.dumps({"assets": records, "offline": args.offline}, ensure_ascii=False))


if __name__ == "__main__":
    main()
