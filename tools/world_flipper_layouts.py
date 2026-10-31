"""Import verified official-demo terrain geometry without inventing missing JP maps.

Raw sources stay in the ignored cache. Coordinates follow the statically inspected
ZoneParser: adjacent open-wall vertices and rectangle/point coordinates use x6.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
from pathlib import Path
import struct
from typing import Any
from urllib.request import urlopen
import zlib

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "tools/world_flipper_layout_sources.json"
CACHE = ROOT / ".tools/wf-layout-research"
SCALE = 6
MAX_SOURCE_BYTES = 32 * 1024 * 1024
MAX_MASTER_BYTES = 8 * 1024 * 1024
PROP_PREFIXES = frozenset({
    "BUMPER", "BLOCK", "SLINGSHOT", "ONE_WAY_WALL", "SKILL_INVOKER",
    "TALKY_YAKUMONO", "ASSIST_CHARACTER", "DECORATION", "YUREMONO",
    "BREAKABLE_BLOCK", "BREAKABLE_DECORATION", "DASH_PANEL_FIXED",
    "DASH_PANEL_SMART", "DASH_PANEL_SERIAL", "DASH_PANEL_ROTATING",
    "DIRECT_INSTANT_ITEM", "WARPHOLE",
})
ZONE_KINDS = frozenset({
    "BOUNDS", "COFFIN", "CUSTOM_POSITION", "GATE", "GRAVITATIONAL_FIELD",
    "GUIDE", "TRANSIT", "WALL",
}) | frozenset(f"{prefix}{index}" for prefix in ("SPAWN", "FUNNEL_SPAWN") for index in range(1, 11))


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _inflate(data: bytes, maximum: int = MAX_MASTER_BYTES) -> bytes:
    stream = zlib.decompressobj()
    value = stream.decompress(data, maximum + 1)
    if len(value) > maximum or stream.unconsumed_tail or not stream.eof or stream.unused_data:
        raise ValueError("Invalid or oversized orderedmap zlib stream")
    return value


def decode_orderedmap(data: bytes) -> dict[str, list[str]]:
    """Decode the demo's indexed, independently zlib-compressed CSV rows."""
    if len(data) < 5 or len(data) > MAX_MASTER_BYTES:
        raise ValueError("Invalid orderedmap size")
    size = struct.unpack_from("<I", data)[0]
    if size < 1 or 4 + size > len(data):
        raise ValueError("Orderedmap header leaves the file")
    header = _inflate(data[4:4 + size])
    if len(header) < 4:
        raise ValueError("Truncated orderedmap header")
    count = struct.unpack_from("<I", header)[0]
    if count > (len(header) - 4) // 8:
        raise ValueError("Orderedmap index leaves the header")
    keys, values = header[4 + count * 8:], data[4 + size:]
    key_start = value_start = 0
    result: dict[str, list[str]] = {}
    decoded_bytes = 0
    for index in range(count):
        key_end, value_end = struct.unpack_from("<II", header, 4 + index * 8)
        if not key_start < key_end <= len(keys) or not value_start < value_end <= len(values):
            raise ValueError("Invalid orderedmap cumulative offsets")
        key = keys[key_start:key_end].decode("utf-8")
        if key in result:
            raise ValueError("Duplicate orderedmap key")
        raw_value = _inflate(values[value_start:value_end])
        decoded_bytes += len(raw_value)
        if decoded_bytes > MAX_MASTER_BYTES:
            raise ValueError("Orderedmap decoded rows exceed the size limit")
        rows = list(csv.reader(io.StringIO(raw_value.decode("utf-8"))))
        if len(rows) != 1:
            raise ValueError("Expected a single CSV row per orderedmap value")
        result[key] = rows[0]
        key_start, value_start = key_end, value_end
    if key_start != len(keys) or value_start != len(values):
        raise ValueError("Unindexed orderedmap data")
    return result


def checked_source(source: dict[str, Any], cache: Path, offline: bool) -> bytes:
    filename = source["cache_filename"]
    if not isinstance(filename, str) or Path(filename).name != filename or "/" in filename or "\\" in filename:
        raise ValueError("Unsafe source cache filename")
    expected_size = source["bytes"]
    if type(expected_size) is not int or not 0 < expected_size <= MAX_SOURCE_BYTES:
        raise ValueError("Invalid source size")
    path = cache / filename
    if path.exists():
        data = path.read_bytes()
    else:
        if offline:
            raise FileNotFoundError(f"Missing pinned source: {path}")
        if not source["url"].startswith("https://"):
            raise ValueError("Only pinned HTTPS sources are allowed")
        with urlopen(source["url"], timeout=45) as response:
            data = response.read(expected_size + 1)
    if len(data) != expected_size or hashlib.sha256(data).hexdigest() != source["sha256"]:
        raise ValueError(f"Pinned source checksum/size changed: {source['id']}")
    if not path.exists():
        cache.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    return data


def number(value: Any) -> float:
    if type(value) not in (int, float) or not math.isfinite(value):
        raise ValueError(f"Invalid finite geometry coordinate: {value!r}")
    return float(value)


def scaled(values: list[float]) -> list[float]:
    return [value * SCALE for value in values]


def normalize_geometry(raw: dict[str, Any]) -> list[dict[str, Any]]:
    """Retain original layer identities and all objects, including hidden markers.

    A prop's editor ellipse is not its physical collider. Those shapes require
    the original yakumono definition and remain explicitly unresolved here.
    """
    layers: list[dict[str, Any]] = []
    indices: set[int] = set()
    for source_order, layer in enumerate(raw["layers"]):
        if layer.get("type") != "objectgroup":
            raise ValueError("Uninspected terrain layer type; refuse to silently drop it")
        name = str(layer["name"])
        if not name.isdecimal() or int(name) in indices:
            raise ValueError("Invalid or duplicate terrain layer index")
        index = int(name)
        indices.add(index)
        result: dict[str, Any] = {
            "index": index, "source_order": source_order, "source_name": name,
            "source_visible": bool(layer.get("visible", True)),
            "source_offset": [number(layer.get("x", 0)), number(layer.get("y", 0))],
            "bounds": [], "walls": [], "markers": [], "props": [], "objects": [],
        }
        object_ids: set[int] = set()
        for obj in layer["objects"]:
            object_id = obj["id"]
            if type(object_id) is not int or object_id in object_ids:
                raise ValueError("Invalid or duplicate object ID in a terrain layer")
            object_ids.add(object_id)
            kind = str(obj["type"])
            prefix, _, resource = kind.partition("#")
            x, y = number(obj.get("x", 0)), number(obj.get("y", 0))
            width, height = number(obj.get("width", 0)), number(obj.get("height", 0))
            if width < 0 or height < 0:
                raise ValueError("Negative editor rectangle")
            rotation = number(obj.get("rotation", 0))
            base: dict[str, Any] = {
                "id": f"{index}:{object_id}", "object_id": object_id,
                "kind": kind, "name": str(obj.get("name", "")),
                "source_visible": bool(obj.get("visible", True)),
                "native_rect": [x, y, width, height], "source_rotation": rotation,
                "source_ellipse": bool(obj.get("ellipse", False)),
                "center": scaled([x + width / 2, y + height / 2]),
            }
            if "polyline" in obj:
                base["vertices"] = [scaled([x + number(p["x"]), y + number(p["y"])]) for p in obj["polyline"]]
            if kind == "WALL":
                vertices = base.get("vertices", [])
                if len(vertices) < 2:
                    raise ValueError("WALL needs at least two source vertices")
                for segment, (a, b) in enumerate(zip(vertices, vertices[1:])):
                    result["walls"].append({"id": f"{index}:{object_id}:{segment}",
                                            "object_id": object_id, "a": a, "b": b})
                base["interpretation"] = "open_wall_polyline"
            elif kind == "BOUNDS":
                result["bounds"].append({"object_id": object_id, "rect": scaled([x, y, width, height])})
                base["interpretation"] = "bounds_rectangle_not_implicit_walls"
            elif prefix in PROP_PREFIXES:
                result["props"].append({"id": base["id"], "object_id": object_id,
                                         "kind": prefix, "resource_id": resource.lower(),
                                         "center": base["center"], "collision_geometry": None})
                base["interpretation"] = "yakumono_anchor_shape_unresolved"
            else:
                recognized = kind in ZONE_KINDS
                result["markers"].append({"id": base["id"], "object_id": object_id,
                                           "kind": kind, "name": base["name"],
                                           "center": base["center"], "recognized_zone": recognized})
                base["interpretation"] = "zone_marker" if recognized else "source_metadata_not_collision"
            result["objects"].append(base)
        layers.append(result)
    return layers


def build(registry: dict[str, Any], catalog: dict[str, Any], cache: Path, offline: bool = True) -> dict[str, Any]:
    sources = {source["id"]: source for source in registry["sources"]}
    if len(sources) != len(registry["sources"]):
        raise ValueError("Duplicate source registry ID")
    blobs = {key: checked_source(source, cache, offline) for key, source in sources.items()}
    demo_layouts: dict[str, tuple[str, list[str]]] = {}
    demo_fields: dict[str, tuple[str, list[str]]] = {}
    for key, source in sources.items():
        if source["role"] in ("field_data", "field"):
            target = demo_layouts if source["role"] == "field_data" else demo_fields
            for row_id, row in decode_orderedmap(blobs[key]).items():
                if row_id in target:
                    raise ValueError("Ambiguous demo master binding")
                target[row_id] = (key, row)
    canonical_by_ref: dict[str, list[dict[str, Any]]] = {}
    for layout in catalog["maps"]["layouts"]:
        canonical_by_ref.setdefault(layout["terrain_ref"], []).append(layout)
    pathlist = set(blobs["jp_pathlist"].decode("utf-8").splitlines())
    png_sources = read_json(ROOT / registry["background_source_registry"])["sources"]
    result: list[dict[str, Any]] = []
    covered: set[str] = set()
    for key, source in sources.items():
        if source["role"] != "terrain":
            continue
        terrain_ref = source["terrain_ref"]
        bindings = [(row_id, source_id, row) for row_id, (source_id, row) in demo_layouts.items() if row[1] == terrain_ref]
        if len(bindings) != 1:
            raise ValueError(f"Terrain needs one verified demo binding: {key}")
        demo_id, binding_source, row = bindings[0]
        field_id = row[0]
        field_source, field_row = demo_fields[field_id]
        matches = canonical_by_ref.get(terrain_ref, [])
        for match in matches:
            if match["field_id"] != field_id:
                raise ValueError("Final-JP field differs from demo field; manual review required")
            covered.add(match["id"])
        raw = json.loads(blobs[key])
        atlas_id, parts_id = f"background_{field_id}_atlas", f"background_{field_id}_parts"
        background_url = "https://worldflipper.jp/demo/src/assets/production/" + field_row[0] + ".png"
        png = next((value for value in png_sources if value["url"] == background_url), None)
        if png is None:
            raise ValueError(f"Missing pinned background pixels for field {field_id}")
        frames = json.loads(blobs[atlas_id])
        result.append({
            "id": matches[0]["id"] if len(matches) == 1 else demo_id,
            "demo_layout_id": demo_id, "canonical_layout_ids": [match["id"] for match in matches],
            "field_id": field_id, "terrain_ref": terrain_ref, "source_id": key,
            "source_scope": "official_demo_matching_jp_reference" if matches else "official_demo_only",
            "binding_source_ids": [binding_source, field_source],
            "runtime_ready": False,
            "native_canvas": [number(raw["width"]), number(raw["height"])],
            "source_format_version": raw["version"],
            "background": {"ref": field_row[0], "foreground_ref": field_row[1],
                           "png_source_registry_id": png["id"], "png_url": png["url"],
                           "png_sha256": png["sha256"], "source_size": png["source_size"],
                           "atlas_source_id": atlas_id, "parts_source_id": parts_id,
                           "atlas_frames": frames,
                           "rotated_frames": any(frame.get("r", False) for frame in frames),
                           "has_multiple_parts": len(json.loads(blobs[parts_id])["i"]) > 1},
            "layers": normalize_geometry(raw),
        })
    result.sort(key=lambda value: value["id"])
    layouts = catalog["maps"]["layouts"]
    pending = [layout["id"] for layout in layouts if layout["id"] not in covered]
    return {
        "schema_version": 1, "source_registry": "tools/world_flipper_layout_sources.json",
        "archive": registry["archive"], "coordinate_evidence": registry["coordinate_evidence"],
        "scope": registry["scope"],
        "coverage": {"canonical_layouts": len(layouts), "canonical_fields": len(catalog["maps"]["fields"]),
                     "canonical_unique_terrain_refs": len(canonical_by_ref),
                     "canonical_refs_listed_in_pinned_pathlist": sum(layout["terrain_ref"] in pathlist for layout in layouts),
                     "canonical_layouts_with_geometry": len(covered), "canonical_pending_geometry": len(pending),
                     "official_demo_geometry_files": len(result),
                     "terrain_layers": sum(len(layout["layers"]) for layout in result),
                     "wall_segments": sum(len(layer["walls"]) for layout in result for layer in layout["layers"]),
                     "source_objects": sum(len(layer["objects"]) for layout in result for layer in layout["layers"])},
        "limitations": [
            "The pinned JP archive lists terrain names but does not contain their geometry or PNG binaries.",
            "A matching terrain_ref verifies identity, not byte equality with the final JP binary (unavailable).",
            "All eight terrain files and background pixels come from the public official demo.",
            "BOUNDS is preserved as a mapping envelope; its physical closure was not inferred.",
            "Prop collision shapes and interactive behavior require original yakumono definitions and are not inferred from editor ellipses.",
            "Layers are separate terrain phases; they must not be superimposed into one collision scene.",
            "Rotated atlas pieces and animated background parts must be assembled before runtime use.",
            "This data file does not wire any layout into the game's playable arena catalog.",
        ],
        "layouts": result, "pending_canonical_layout_ids": pending,
    }


def previews(document: dict[str, Any], directory: Path) -> None:
    """Overlay exact walls/anchors on native backgrounds, without invented colliders."""
    from PIL import Image, ImageDraw
    png_sources = {source["id"]: source for source in read_json(ROOT / "tools/world_flipper_maps_sources.json")["sources"]}
    directory.mkdir(parents=True, exist_ok=True)
    for layout in document["layouts"]:
        background = layout["background"]
        source = png_sources[background["png_source_registry_id"]]
        path = ROOT / ".tools/worldflipper/source" / source["filename"]
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != source["sha256"]:
            raise ValueError("Preview background source checksum changed")
        frame = background["atlas_frames"][0]
        with Image.open(io.BytesIO(data)) as atlas:
            base = atlas.convert("RGBA").crop((frame["x"], frame["y"], frame["x"] + frame["w"], frame["y"] + frame["h"]))
        if frame.get("r", False):
            base = base.transpose(Image.Transpose.ROTATE_90)
        for layer in layout["layers"]:
            image = base.copy()
            draw = ImageDraw.Draw(image)
            for bound in layer["bounds"]:
                x, y, width, height = [value / SCALE for value in bound["rect"]]
                draw.rectangle((x, y, x + width, y + height), outline="#a8c4dd", width=1)
            for wall in layer["walls"]:
                a, b = [[value / SCALE for value in wall[end]] for end in ("a", "b")]
                draw.line((*a, *b), fill="#ffdb47", width=2)
                for x, y in (a, b):
                    draw.rectangle((x - 1, y - 1, x + 1, y + 1), fill="#ffffff")
            for prop in layer["props"]:
                x, y = [value / SCALE for value in prop["center"]]
                draw.line((x - 2, y, x + 2, y), fill="#6affb5", width=1)
                draw.line((x, y - 2, x, y + 2), fill="#6affb5", width=1)
            image.resize((image.width * 2, image.height * 2), Image.Resampling.NEAREST).save(directory / f"{layout['id']}-layer-{layer['index']}.png")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=CACHE)
    parser.add_argument("--output", type=Path, default=ROOT / "data/worldflipper/layouts.json")
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--preview-dir", type=Path)
    args = parser.parse_args()
    document = build(read_json(REGISTRY), read_json(ROOT / "data/worldflipper/catalog.json"), args.cache, args.offline)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    if args.preview_dir:
        previews(document, args.preview_dir)
    print(json.dumps(document["coverage"], sort_keys=True))


if __name__ == "__main__":
    main()
