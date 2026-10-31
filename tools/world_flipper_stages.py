"""Place exact official-demo BOUNDS crops and geometry at one uniform game scale.

The original playable pixels are nearest-scaled 4x without tiling or stretching.
The surrounding matte/frame is an explicit presentation adaptation, not new map
geometry. No existing map PNG or the global fan-art manifest is rewritten.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ORIGIN = (-1146, -767)
SIZE = (3780, 2192)
CENTER = (640, 365)
PIXEL_SCALE = 4
LOGIC_SCALE = 2 / 3
PREVIEW = (1146, 772, 1280, 720)
STAGES = {
    "jp_sand_2_9_5": ("main_2_9_5", "沙漠遗迹 2-9-5", "9b9066"),
    "jp_shrine_6_6_2": ("main_6_6_2", "竹林神社 6-6-2", "7c9c78"),
    "jp_ship_3_6_2": ("main_3_6_2", "海盗船 3-6-2", "729799"),
}


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def geometry(layout: dict[str, Any]) -> dict[str, Any]:
    layer = next(value for value in layout["layers"] if value["index"] == 0)
    if len(layer["bounds"]) != 1:
        raise ValueError("A stage needs one verified source BOUNDS rectangle")
    logic = layer["bounds"][0]["rect"]
    native = [value / 6 for value in logic]
    if any(not value.is_integer() for value in native):
        raise ValueError("Stage source crop must use exact integer pixels")
    native = [int(value) for value in native]
    width, height = native[2] * PIXEL_SCALE, native[3] * PIXEL_SCALE
    play = [CENTER[0] - width / 2, CENTER[1] - height / 2, width, height]
    offset = [play[0] - logic[0] * LOGIC_SCALE, play[1] - logic[1] * LOGIC_SCALE]
    return {"layout_id": layout["id"], "demo_layout_id": layout["demo_layout_id"],
            "field_id": layout["field_id"], "layer_index": 0,
            "source_id": layout["source_id"], "logic_scale": LOGIC_SCALE,
            "logic_offset": offset, "native_bounds": native, "play_bounds": play,
            "wall_segment_count": len(layer["walls"]),
            "source_label": layout["id"],
            "unresolved_prop_count": len(layer["props"])}


def arena_definition(stage_id: str, layout: dict[str, Any]) -> dict[str, Any]:
    _, name, color = STAGES[stage_id]
    return {"id": stage_id, "name": name, "texture": f"res://assets/worldflipper/stages/{stage_id}.png",
            "preview_color": color, "terrain_name": "", "move_multiplier": 1.0,
            "legacy_zone_count": 0, "zones": [], "obstacles": [], "crates": [],
            "stage": geometry(layout)}


def render_stage(image: Image.Image, native_bounds: list[int]) -> Image.Image:
    x, y, width, height = native_bounds
    if x < 0 or y < 0 or min(width, height) <= 0 or x + width > image.width or y + height > image.height:
        raise ValueError("The verified source BOUNDS leaves its upright background")
    crop = image.crop((x, y, x + width, y + height)).convert("RGB")
    crop = crop.resize((width * PIXEL_SCALE, height * PIXEL_SCALE), Image.Resampling.NEAREST)
    # Theme-derived outer mat; it cannot be mistaken for additional walkable floor.
    sample = image.convert("RGB").resize((1, 1), Image.Resampling.BOX).getpixel((0, 0))
    dark = tuple(max(5, int(component * 0.17)) for component in sample)
    line = tuple(min(255, component + 3) for component in dark)
    canvas = Image.new("RGB", SIZE, dark)
    draw = ImageDraw.Draw(canvas)
    left = int(CENTER[0] - crop.width / 2 - ORIGIN[0])
    top = int(CENTER[1] - crop.height / 2 - ORIGIN[1])
    # Sparse aligned pixel seams live wholly outside the untouched source crop.
    for column in range(0, SIZE[0], 128):
        draw.line((column, 0, column, SIZE[1] - 1), fill=line, width=4)
    for row in range(0, SIZE[1], 128):
        draw.line((0, row, SIZE[0] - 1, row), fill=line, width=4)
    frame_dark = tuple(max(3, int(component * 0.28)) for component in sample)
    frame_light = tuple(max(12, int(component * 0.60)) for component in sample)
    for margin, color in ((28, frame_dark), (16, frame_light), (8, dark)):
        draw.rectangle((left - margin, top - margin, left + crop.width + margin - 1, top + crop.height + margin - 1), fill=color)
    canvas.paste(crop, (left, top))
    return canvas


def build(output: Path, source_cache: Path) -> dict[str, Any]:
    normalized = load(ROOT / "data/worldflipper/layouts.json")
    by_id = {layout["id"]: layout for layout in normalized["layouts"]}
    registry = load(ROOT / "tools/world_flipper_layout_sources.json")
    source_by_id = {source["id"]: source for source in registry["sources"]}
    pngs = {source["id"]: source for source in load(ROOT / "tools/world_flipper_maps_sources.json")["sources"]}
    assets, stages = [], []
    used_sources: dict[str, dict[str, Any]] = {}
    output.mkdir(parents=True, exist_ok=True)
    (output / "previews").mkdir(exist_ok=True)
    for stage_id, (layout_id, _, _) in STAGES.items():
        layout = by_id[layout_id]
        stage = geometry(layout)
        stage["id"] = stage_id
        png_source = pngs[layout["background"]["png_source_registry_id"]]
        data = (source_cache / png_source["filename"]).read_bytes()
        if sha(data) != png_source["sha256"]:
            raise ValueError(f"Stage background source checksum changed: {stage_id}")
        with Image.open(source_cache / png_source["filename"]) as atlas:
            frame = layout["background"]["atlas_frames"][0]
            image = atlas.convert("RGB").crop((frame["x"], frame["y"], frame["x"] + frame["w"], frame["y"] + frame["h"]))
            if frame.get("r", False):
                image = image.transpose(Image.Transpose.ROTATE_90)
            canvas = render_stage(image, stage["native_bounds"])
        layer = next(value for value in layout["layers"] if value["index"] == 0)
        stage["props"] = [{**prop, "center": [prop["center"][axis] * LOGIC_SCALE + stage["logic_offset"][axis] for axis in range(2)]} for prop in layer["props"]]
        stage["markers"] = [{**marker, "center": [marker["center"][axis] * LOGIC_SCALE + stage["logic_offset"][axis] for axis in range(2)]} for marker in layer["markers"]]
        source_ids = [png_source["id"], layout["source_id"], *layout["binding_source_ids"],
                      layout["background"]["atlas_source_id"], "demo_runtime"]
        used_sources[png_source["id"]] = png_source
        for source_id in source_ids[1:]:
            used_sources[source_id] = source_by_id[source_id]
        for preview in (False, True):
            relative = f"previews/{stage_id}.png" if preview else f"{stage_id}.png"
            path = output / relative
            x, y, width, height = PREVIEW
            rendered = canvas.crop((x, y, x + width, y + height)) if preview else canvas
            rendered.save(path, optimize=True)
            assets.append({"id": stage_id + ("_preview" if preview else ""),
                           "path": "assets/worldflipper/stages/" + relative,
                           "game_id": stage_id, "size": list(rendered.size),
                           "sha256": sha(path.read_bytes()), "source_ids": source_ids,
                           "world_origin": list(ORIGIN), "play_bounds": stage["play_bounds"],
                           "native_bounds": stage["native_bounds"], "source_pixel_scale": PIXEL_SCALE,
                           "preview_crop": list(PREVIEW) if preview else None})
        stages.append(stage)
    manifest = {"revision": "world-flipper-original-stages-01", "archive": registry["archive"],
                "geometry_registry": "data/worldflipper/layouts.json", "source_registry": "tools/world_flipper_layout_sources.json",
                "scope": "Three playable adaptations of actual official-demo layer-0 geometry whose terrain refs exactly match the pinned JP catalog; not all JP maps.",
                "adaptation": {"logic_scale": LOGIC_SCALE, "source_pixel_scale": PIXEL_SCALE,
                               "world_center": list(CENTER), "native_crop": "Verified layer-0 BOUNDS; no tiling, stretching, or wall closure",
                               "outside_crop": "Theme-derived dark pixel mat and decorative frame; not playable original terrain",
                               "props": "Source anchors only. Collision/interactive definitions are unresolved and no substitute obstacles or crates are generated."},
                "sources": list(used_sources.values()), "stages": stages, "assets": assets}
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-cache", type=Path, default=ROOT / ".tools/worldflipper/source")
    parser.add_argument("--output", type=Path, default=ROOT / "assets/worldflipper/stages")
    args = parser.parse_args()
    result = build(args.output, args.source_cache)
    print(f"Built {len(result['stages'])} original-geometry stages and {len(result['assets'])} PNGs")


if __name__ == "__main__":
    main()
