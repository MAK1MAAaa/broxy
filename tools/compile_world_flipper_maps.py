"""Compile verified JP native background planes and open terrain walls.

The pinned cache reports 1.780.30. Matching final-catalog logical references do
not establish final 1.780.40 asset identity or complete original stage gameplay.
"""
from __future__ import annotations

import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import importlib.util
import io
import json
import math
from pathlib import Path
import re
import struct
from typing import Any
import zlib

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = Path("tools/world_flipper_map_library_sources.json")
LIBRARY_PATH = Path("data/worldflipper/map_library.json")
ASSETS_PATH = Path("assets/worldflipper/fields")
EXTENSIONS = {"png": ".png", "atlas": ".atlas.amf3.deflate", "parts": ".parts.amf3.deflate", "timeline": ".timeline.amf3.deflate"}
LOGIC_SCALE = 2.0 / 3.0
WORLD_CENTER = (640.0, 365.0)
LEGACY_BOUNDS = (-1082.0, -535.0, 3444.0, 1800.0)
MAX_BATCH = 64 * 1024 * 1024
MAX_PIXELS = 32 * 1024 * 1024
PARTIAL_GAPS = ["original_stage_enemy_scripts_not_implemented", "original_prop_art_and_mechanisms_not_implemented", "final_1_780_40_asset_bytes_not_verified"]


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def canonical_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n").encode("utf-8")


def digest(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes((json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8"))


def dependency(name: str, root: Path = ROOT) -> Any:
    spec = importlib.util.spec_from_file_location("wf_map_" + name, root / "tools" / (name + ".py"))
    if spec is None or spec.loader is None:
        raise ValueError("Missing map compiler dependency")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def finite_numbers(value: Any, length: int) -> list[float]:
    if not isinstance(value, list) or len(value) != length or any(type(item) not in (int, float) or not math.isfinite(item) for item in value):
        raise ValueError("Invalid finite geometry vector")
    return [float(item) for item in value]


def png_image(raw: bytes) -> Image.Image:
    """Repair only the original lowercase signature, checking every PNG CRC."""
    if raw[:1] != b"\x89" or raw[1:4] not in (b"PNG", b"png") or raw[4:8] != b"\r\n\x1a\n":
        raise ValueError("Unknown original PNG signature")
    data = raw[:1] + b"PNG" + raw[4:]
    offset = 8
    ended = False
    while offset < len(data):
        if offset + 12 > len(data):
            raise ValueError("Truncated PNG chunk")
        length = struct.unpack_from(">I", data, offset)[0]
        end = offset + 12 + length
        if end > len(data) or zlib.crc32(data[offset + 4:end - 4]) & 0xffffffff != struct.unpack_from(">I", data, end - 4)[0]:
            raise ValueError("PNG chunk CRC/length mismatch")
        tag = data[offset + 4:offset + 8]
        offset = end
        if tag == b"IEND":
            ended = True
            break
    if not ended or offset != len(data):
        raise ValueError("Missing IEND or trailing PNG bytes")
    with Image.open(io.BytesIO(data)) as image:
        if not 0 < image.width * image.height <= MAX_PIXELS:
            raise ValueError("PNG exceeds pixel limit")
        image.verify()
    with Image.open(io.BytesIO(data)) as image:
        return image.convert("RGBA")


def primitive_frame(parts: Any, timeline: Any, atlas: Any) -> dict[str, Any]:
    """Whitelist the source's single opaque static identity-transformed plane."""
    if not isinstance(parts, dict) or set(parts) != {"i", "g", "m", "a", "o", "t", "c", "s"}:
        raise ValueError("unsupported_parts_schema")
    if parts["m"] != [] or parts["a"] != [1] or parts["o"] != [] or parts["c"] != [] or parts["s"] != 6:
        raise ValueError("nonprimitive_parts_controls")
    if parts["t"] != [{"a": 4096, "b": 0, "c": 0, "d": 4096, "x": 0, "y": 0}]:
        raise ValueError("nonidentity_or_multiple_plane_transforms")
    images, groups = parts["i"], parts["g"]
    if len(images) != 1 or set(images[0]) != {"s", "p"} or images[0]["s"] is not False or not isinstance(images[0]["p"], str) or len(groups) != 1:
        raise ValueError("multiple_or_external_background_planes")
    duration = groups[0].get("t")
    expected = {"t": duration, "s": [{"s": 0, "i": 0, "l": [{"m": 255, "t": duration}]}]}
    if type(duration) is not int or duration < 1 or groups[0] != expected:
        raise ValueError("animated_or_nonopaque_background_plane")
    if not isinstance(timeline, dict) or set(timeline) != {"sequences", "sounds", "points", "circles", "rectangles", "matrices"}:
        raise ValueError("unsupported_timeline_schema")
    if any(timeline[key] for key in ("sounds", "points", "circles", "rectangles", "matrices")):
        raise ValueError("nonprimitive_background_timeline")
    sequences = timeline["sequences"]
    if len(sequences) != 1 or sequences[0] not in ({"begin": 1, "end": duration, "name": "start", "kind": "loop"},
                                                  {"begin": 1, "end": duration, "name": "start", "kind": "stop"}):
        raise ValueError("nonprimitive_background_sequence")
    frames = [frame for frame in atlas if isinstance(frame, dict) and frame.get("n") == images[0]["p"]] if isinstance(atlas, list) else []
    if len(frames) != 1:
        raise ValueError("missing_or_ambiguous_exact_atlas_frame")
    frame = frames[0]
    if set(frame) - {"n", "x", "y", "w", "h", "r", "fx", "fy", "fw", "fh"}:
        raise ValueError("unsupported_atlas_frame_fields")
    for key in ("x", "y", "w", "h"):
        if type(frame.get(key)) is not int or frame[key] < (1 if key in ("w", "h") else 0):
            raise ValueError("noninteger_atlas_frame")
    if "r" in frame and type(frame["r"]) is not bool:
        raise ValueError("unsupported_atlas_rotation")
    optional = {"fx", "fy", "fw", "fh"} & set(frame)
    if optional and optional != {"fx", "fy", "fw", "fh"}:
        raise ValueError("partial_atlas_canvas")
    if any(type(frame[key]) is not int for key in optional):
        raise ValueError("noninteger_atlas_canvas")
    return dict(frame)


def native_plane(image: Image.Image, frame: dict[str, Any]) -> Image.Image:
    x, y, width, height = (frame[key] for key in ("x", "y", "w", "h"))
    if x + width > image.width or y + height > image.height:
        raise ValueError("Atlas frame leaves source PNG")
    plane = image.crop((x, y, x + width, y + height))
    if frame.get("r", False):
        plane = plane.transpose(Image.Transpose.ROTATE_90)
    if "fw" in frame:
        fw, fh, left, top = frame["fw"], frame["fh"], -frame["fx"], -frame["fy"]
        if fw <= 0 or fh <= 0 or fw * fh > MAX_PIXELS or min(left, top) < 0 or left + plane.width > fw or top + plane.height > fh:
            raise ValueError("Atlas trimmed frame leaves authored canvas")
        canvas = Image.new("RGBA", (fw, fh))
        canvas.paste(plane, (left, top))
        plane = canvas
    return plane


def source_rows(registry: dict[str, Any], root: Path = ROOT) -> dict[str, dict[str, Any]]:
    rows: dict[str, dict[str, Any]] = {}
    transport = dependency("world_flipper_jp_archive", root)
    base = read_json(root / "tools/world_flipper_jp_archive_sources.json")
    catalog = read_json(root / "data/worldflipper/catalog.json")
    transport.validate_registry(base, catalog)
    if any(registry[key] != base[key] for key in ("archive", "central_directory", "cache_metadata", "comparison_catalog")) or registry["base_terrain_registry_sha256"] != digest(base):
        raise ValueError("Field sources do not share the pinned verified JP archive identity")
    uses: dict[str, list[dict[str, Any]]] = {}
    for field in catalog["maps"]["fields"]:
        references: dict[str, list[int]] = {}
        for column, reference in enumerate(field["raw_fields"]):
            if reference.startswith("battle/"):
                references.setdefault(reference, []).append(column)
        for reference, columns in sorted(references.items()):
            use = {"field_id": field["id"], "reference": reference, "original_field_columns": columns,
                   "role": "background" if reference == field["background_ref"] else "foreground" if reference == field["foreground_ref"] else "added" if reference == field["added_ref"] else "other_field_object"}
            for extension in EXTENSIONS.values():
                uses.setdefault(reference + extension, []).append(use)
    for row in registry["sources"]:
        logical = row["logical_path"]
        if logical in rows or row["kind"] not in EXTENSIONS or not logical.endswith(EXTENSIONS[row["kind"]]) or transport.salted_sha1(logical) != row["salted_sha1"]:
            raise ValueError("Duplicate or mismatched exact field source")
        entry = row["zip_entry"]
        if not re.fullmatch(r"[0-9a-f]{64}", row["raw_sha256"]) or not entry["name"].endswith("/" + row["salted_sha1"][:2] + "/" + row["salted_sha1"][2:]):
            raise ValueError("Unverified source bytes or ZIP logical identity")
        if "/production/upload/" not in entry["name"] and "/production/android_upload/" not in entry["name"]:
            raise ValueError("Unexpected source platform channel")
        if not 0 < entry["size"] <= transport.MAX_SOURCE or not 0 < entry["compressed_size"] <= transport.MAX_SOURCE:
            raise ValueError("Oversized field source")
        if row["field_uses"] != uses.get(logical):
            raise ValueError("Field source raw column/role/identity binding mismatch")
        rows[logical] = row
    if sum(row["zip_entry"]["compressed_size"] + transport.HEADER_PADDING for row in rows.values()) > MAX_BATCH:
        raise ValueError("Field source batch exceeds64MiB")
    return rows


def raw_source(source: dict[str, Any], cache: Path) -> bytes:
    raw = (cache / "raw" / source["salted_sha1"]).read_bytes()
    if len(raw) != source["zip_entry"]["size"] or f"{zlib.crc32(raw) & 0xffffffff:08x}" != source["zip_entry"]["crc32"] or hashlib.sha256(raw).hexdigest() != source["raw_sha256"]:
        raise ValueError("Pinned original source checksum changed: " + source["logical_path"])
    return raw


def decode_source(source: dict[str, Any], cache: Path, transport: Any) -> Any:
    value, evidence = transport.decode_amf3(raw_source(source, cache))
    if not evidence["fully_consumed"]:
        raise ValueError("Incomplete original AMF3 decode")
    return value


def geometry_row(source: dict[str, Any], layer: dict[str, Any]) -> dict[str, Any]:
    rectangles = [obj["rect"] for obj in layer["bounds"]]
    unique = {tuple(row) for row in rectangles}
    classification = "none" if not rectangles else "single" if len(rectangles) == 1 else "duplicate_identical" if len(unique) == 1 else "conflicting"
    bounds = list(next(iter(unique))) if len(unique) == 1 else None
    gaps: list[str] = []
    if bounds is None:
        gaps.append("missing_or_conflicting_bounds")
    else:
        native = [number / 6 for number in bounds]
        if any(not math.isclose(number, round(number), abs_tol=1e-7) for number in native):
            gaps.append("noninteger_native_crop")
        if native[2] <= 0 or native[3] <= 0:
            gaps.append("nonpositive_native_bounds")
        bx, by, bw, bh = LEGACY_BOUNDS
        width, height = native[2] * 4, native[3] * 4
        left, top = WORLD_CENTER[0] - width / 2, WORLD_CENTER[1] - height / 2
        if left < bx or top < by or left + width > bx + bw or top + height > by + bh:
            gaps.append("outside_legacy_world_bounds")
    special = [obj for obj in layer["objects"] if obj["kind"] in {"WALL1", "WALL2"} or obj["kind"].startswith("ONE_WAY_WALL")]
    if special:
        gaps.append("unresolved_numbered_or_one_way_wall")
    if any(obj["source_rotation"] != 0 or obj["source_ellipse"] for obj in layer["objects"] if obj["kind"] == "BOUNDS"):
        gaps.append("nonaxis_bounds")
    if layer["source_offset"] != [0.0, 0.0]:
        gaps.append("nonzero_layer_offset")
    return {"terrain_ref": source["logical_path"].removesuffix(".amf3.deflate"), "layer_index": layer["index"],
            "terrain_source_id": source["salted_sha1"], "terrain_raw_sha256": source["raw_sha256"],
            "source_bounds": bounds, "bounds_classification": classification, "source_offset": layer["source_offset"],
            "walls": layer["walls"], "source_geometry_sha256": digest(layer), "props_count": len(layer["props"]),
            "prop_kind_counts": dict(sorted(Counter(prop["kind"] for prop in layer["props"]).items())),
            "marker_kind_counts": dict(sorted(Counter(marker["kind"] for marker in layer["markers"]).items())),
            "source_object_count": len(layer["objects"]), "special_wall_kind_counts": dict(sorted(Counter(obj["kind"] for obj in special).items())), "gaps": gaps}


def group_name(layout: str) -> tuple[str, str]:
    match = re.fullmatch(r"main_(\d+)_(\d+)_(\d+)", layout)
    if match:
        chapter, section, stage = map(int, match.groups())
        return f"主线 第{chapter}章", f"主线 {chapter}-{section}-{stage}"
    return "其他原作关卡", layout


def groups_for(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    counts = Counter(entry["group"] for entry in entries if entry["playable"])
    order = [f"主线 第{index}章" for index in range(1, 13)]
    names = [name for name in order if name in counts] + sorted(set(counts) - set(order))
    return [{"id": name, "name": name, "count": counts[name]} for name in names]


def entry_row(layout: dict[str, Any], field: dict[str, Any], key: str, geometry: dict[str, Any], plane: dict[str, Any]) -> dict[str, Any]:
    index = geometry["layer_index"]
    group, label = group_name(layout["id"])
    gaps = list(geometry["gaps"]) + list(plane["gaps"])
    source_rect: list[float] = []
    bounds: list[float] = []
    offset: list[float] = []
    if geometry["source_bounds"] is not None:
        source_rect = [number / 6 for number in geometry["source_bounds"]]
        sx, sy, width, height = source_rect
        bounds = [WORLD_CENTER[0] - width * 2, WORLD_CENTER[1] - height * 2, width * 4, height * 4]
        offset = [bounds[0] - sx * 4, bounds[1] - sy * 4]
        size = plane.get("size", [])
        if size and (min(sx, sy) < 0 or sx + width > size[0] or sy + height > size[1]):
            gaps.append("native_background_does_not_cover_bounds")
    playable = not gaps
    stage = {"layout_id": layout["id"], "terrain_ref": layout["terrain_ref"], "field_id": field["id"], "layer_index": index,
             "source_label": f"JP {layout['id']} · L{index}", "source_id": "jp_archive_terrain_" + geometry["terrain_source_id"],
             "native_bounds": source_rect, "play_bounds": bounds, "logic_scale": LOGIC_SCALE, "logic_offset": offset,
             "wall_segment_count": len(geometry["walls"]), "unresolved_prop_count": geometry["props_count"], "cache_metadata_version": "1.780.30"}
    return {"id": f"wf_{layout['id']}_l{index}", "canonical_layout_id": layout["id"], "field_id": field["id"],
            "name": f"{label} · 第{index + 1}层", "group": group, "playable": playable, "status": "partial",
            "texture_path": plane.get("texture_path", "") if playable else "", "image_ref": plane.get("image_ref", "") if playable else "",
            "source_rect": source_rect, "play_bounds": bounds, "geometry_ref": key, "logic_scale": LOGIC_SCALE, "logic_offset": offset,
            "stage": stage, "gaps": sorted(set(gaps + PARTIAL_GAPS))}


def library_counts(library: dict[str, Any]) -> dict[str, Any]:
    entries, geometries = library["entries"], library["geometries"]
    return {"canonical_layouts": len({entry["canonical_layout_id"] for entry in entries}), "terrain_resources": len({row["terrain_source_id"] for row in geometries.values()}),
            "terrain_layers": len(geometries), "ordinary_wall_segments": sum(len(row["walls"]) for row in geometries.values()),
            "entries": len(entries), "playable_entries": sum(entry["playable"] for entry in entries),
            "playable_canonical_layouts": len({entry["canonical_layout_id"] for entry in entries if entry["playable"]}),
            "playable_fields": len({entry["field_id"] for entry in entries if entry["playable"]}), "shared_native_images": len(library["images"])}


def build(root: Path = ROOT, field_cache: Path | None = None, terrain_cache: Path | None = None) -> tuple[dict[str, Any], dict[str, bytes]]:
    registry = read_json(root / REGISTRY_PATH)
    base = read_json(root / "tools/world_flipper_jp_archive_sources.json")
    catalog = read_json(root / "data/worldflipper/catalog.json")
    transport, normalizer = dependency("world_flipper_jp_archive", root), dependency("world_flipper_layouts", root)
    transport.validate_registry(base, catalog)
    sources = source_rows(registry, root)
    field_cache = field_cache or root / ".tools/wf-map-bulk-next"
    terrain_cache = terrain_cache or root / ".tools/wf-full-map-research/jp-archive"
    images: dict[str, Any] = {}
    output: dict[str, bytes] = {}
    planes: dict[str, Any] = {}
    for reference in sorted({field["background_ref"] for field in catalog["maps"]["fields"]}):
        missing = [kind for kind, extension in EXTENSIONS.items() if reference + extension not in sources]
        if missing:
            planes[reference] = {"gaps": ["missing_exact_background_" + kind for kind in missing]}
            continue
        quartet = {kind: sources[reference + extension] for kind, extension in EXTENSIONS.items()}
        values = {kind: decode_source(row, field_cache, transport) for kind, row in quartet.items() if kind != "png"}
        try:
            frame = primitive_frame(values["parts"], values["timeline"], values["atlas"])
        except ValueError as error:
            planes[reference] = {"gaps": [str(error)]}
            continue
        image = native_plane(png_image(raw_source(quartet["png"], field_cache)), frame)
        image_id = "bg_" + quartet["png"]["salted_sha1"]
        texture_path = "res://" + (ASSETS_PATH / (image_id + ".png")).as_posix()
        buffer = io.BytesIO()
        image.save(buffer, format="PNG", optimize=False, compress_level=9)
        png = buffer.getvalue()
        proof = {"background_ref": reference, "frame": frame, "parts": values["parts"], "timeline": values["timeline"],
                 "source_ids": {kind: row["salted_sha1"] for kind, row in quartet.items()}, "source_sha256": {kind: row["raw_sha256"] for kind, row in quartet.items()}}
        row = {"texture_path": texture_path, "size": list(image.size), "source_ref": reference, "source_ids": proof["source_ids"],
               "rgba_sha256": hashlib.sha256(image.tobytes()).hexdigest(), "png_sha256": hashlib.sha256(png).hexdigest(), "primitive_proof": proof}
        if image_id in images and images[image_id] != row:
            raise ValueError("One original PNG unexpectedly maps to two different planes")
        images[image_id] = row
        output[(ASSETS_PATH / (image_id + ".png")).as_posix()] = png
        planes[reference] = {"gaps": [], "image_ref": image_id, "texture_path": texture_path, "size": list(image.size)}
    geometries: dict[str, Any] = {}
    terrain_keys: dict[str, list[str]] = {}
    for source in base["sources"]:
        if source["kind"] != "terrain":
            continue
        for layer in normalizer.normalize_geometry(decode_source(source, terrain_cache, transport)):
            key = source["salted_sha1"] + ":" + str(layer["index"])
            geometries[key] = geometry_row(source, layer)
            terrain_keys.setdefault(geometries[key]["terrain_ref"], []).append(key)
    for keys in terrain_keys.values():
        keys.sort(key=lambda key: geometries[key]["layer_index"])
    fields = {field["id"]: field for field in catalog["maps"]["fields"]}
    entries = [entry_row(layout, fields[layout["field_id"]], key, geometries[key], planes[fields[layout["field_id"]]["background_ref"]])
               for layout in catalog["maps"]["layouts"] for key in terrain_keys[layout["terrain_ref"]]]
    library = {"schema_version": 1, "revision": "jp-cache-1.780.30-native-planes-v1", "source": {"registry": REGISTRY_PATH.as_posix(), "registry_sha256": digest(registry),
               "catalog_maps_sha256": digest(catalog["maps"]), "cache_metadata_version": "1.780.30", "final_jp_byte_identity_verified": False},
               "render_policy": {"source_native_scale": 4, "source_logic_scale": 6, "logic_scale": LOGIC_SCALE, "world_center": list(WORLD_CENTER), "primitive_static_planes_only": True,
                                 "props_collision_invented": False, "numbered_or_one_way_walls_supported": False},
               "groups": groups_for(entries), "images": images, "geometries": geometries, "entries": entries,
               "limitations": PARTIAL_GAPS + ["animated_or_composite_background_planes_excluded", "unresolved_special_wall_layers_excluded", "noninteger_or_uncovered_native_crops_excluded"]}
    library["counts"] = library_counts(library)
    expected = registry.get("compiled_certificates")
    certificates = {"geometries": {key: digest(row) for key, row in geometries.items()}, "planes": planes,
                    "images": {key: digest(row) for key, row in images.items()}}
    if expected is not None and expected != certificates:
        raise ValueError("Rebuilt original source certificates differ from the pinned registry")
    return library, output


def validate_library(library: dict[str, Any], root: Path = ROOT) -> dict[str, Any]:
    """Audit committed runtime data without ignored sources or network access."""
    registry = read_json(root / REGISTRY_PATH)
    base = read_json(root / "tools/world_flipper_jp_archive_sources.json")
    catalog = read_json(root / "data/worldflipper/catalog.json")
    sources = source_rows(registry, root)
    expected_source = {"registry": REGISTRY_PATH.as_posix(), "registry_sha256": digest(registry), "catalog_maps_sha256": digest(catalog["maps"]), "cache_metadata_version": "1.780.30", "final_jp_byte_identity_verified": False}
    if library["schema_version"] != 1 or library["source"] != expected_source or library["render_policy"].get("props_collision_invented") is not False:
        raise ValueError("Runtime library lost its exact pinned provenance or policy")
    certificates = registry["compiled_certificates"]
    terrain_sources = {row["salted_sha1"]: row for row in base["sources"] if row["kind"] == "terrain"}
    if set(library["geometries"]) != set(certificates["geometries"]):
        raise ValueError("Missing or unexpected shared geometry")
    terrain_keys: dict[str, list[str]] = {}
    for key, geometry in library["geometries"].items():
        if digest(geometry) != certificates["geometries"][key]:
            raise ValueError("Shared wall/BOUNDS/source metadata differs from verified original geometry")
        source = terrain_sources.get(geometry["terrain_source_id"])
        if source is None or key != source["salted_sha1"] + ":" + str(geometry["layer_index"]) or geometry["terrain_raw_sha256"] != source["raw_sha256"] or geometry["terrain_ref"] + ".amf3.deflate" != source["logical_path"]:
            raise ValueError("Terrain logical identity/source bytes mismatch")
        for wall in geometry["walls"]:
            if "object_id" not in wall or not isinstance(wall["id"], str):
                raise ValueError("Original wall identity missing")
            finite_numbers(wall["a"], 2)
            finite_numbers(wall["b"], 2)
        terrain_keys.setdefault(geometry["terrain_ref"], []).append(key)
    for keys in terrain_keys.values():
        keys.sort(key=lambda key: library["geometries"][key]["layer_index"])
    if set(library["images"]) != set(certificates["images"]):
        raise ValueError("Missing or unexpected shared native image")
    for key, image in library["images"].items():
        if digest(image) != certificates["images"][key]:
            raise ValueError("Native plane proof differs from pinned source evidence")
        proof = image["primitive_proof"]
        primitive_frame(proof["parts"], proof["timeline"], [proof["frame"]])
        for kind, suffix in EXTENSIONS.items():
            source = sources[image["source_ref"] + suffix]
            if image["source_ids"][kind] != source["salted_sha1"] or proof["source_sha256"][kind] != source["raw_sha256"]:
                raise ValueError("Native plane original source binding mismatch")
        expected_path = "res://" + (ASSETS_PATH / (key + ".png")).as_posix()
        if image["texture_path"] != expected_path:
            raise ValueError("Native image path leaves asset directory")
        png = (root / ASSETS_PATH / (key + ".png")).read_bytes()
        rgba = png_image(png)
        if list(rgba.size) != image["size"] or hashlib.sha256(png).hexdigest() != image["png_sha256"] or hashlib.sha256(rgba.tobytes()).hexdigest() != image["rgba_sha256"]:
            raise ValueError("Native PNG file/size/RGBA checksum mismatch")
    fields = {field["id"]: field for field in catalog["maps"]["fields"]}
    expected_entries = [entry_row(layout, fields[layout["field_id"]], key, library["geometries"][key], certificates["planes"][fields[layout["field_id"]]["background_ref"]])
                        for layout in catalog["maps"]["layouts"] for key in terrain_keys[layout["terrain_ref"]]]
    if library["entries"] != expected_entries:
        raise ValueError("Entry canonical layout/field/layer/crop/scale/playability binding mismatch")
    if library["groups"] != groups_for(expected_entries) or library["counts"] != library_counts(library):
        raise ValueError("Runtime map counts/groups are inconsistent")
    manifest = read_json(root / ASSETS_PATH / "manifest.json")
    if manifest != {"schema_version": 1, "source_registry": REGISTRY_PATH.as_posix(), "images": library["images"]}:
        raise ValueError("Runtime image manifest/source proof mismatch")
    return {"ok": True, **library["counts"], "field_sources": len(sources), "cache_metadata_version": "1.780.30", "final_jp_byte_identity_verified": False, "raw_sources_required": False}


def audit(root: Path = ROOT) -> dict[str, Any]:
    return validate_library(read_json(root / LIBRARY_PATH), root)


def download_fields(root: Path, cache: Path, workers: int) -> None:
    if not 1 <= workers <= 3:
        raise ValueError("Use1..3 bounded download workers")
    registry = read_json(root / REGISTRY_PATH)
    sources = source_rows(registry, root)
    transport = dependency("world_flipper_jp_archive", root)
    entries = transport.checked_index(registry, cache, False)
    transport.checked_cache_metadata(registry, cache, False)
    for source in sources.values():
        if entries.get(source["zip_entry"]["name"]) != source["zip_entry"]:
            raise ValueError("Field entry differs from pinned actual ZIP directory")
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [pool.submit(transport.checked_source, source, registry, cache, False) for source in sources.values()]
        for future in as_completed(futures):
            result = future.result()
            if "decode_error" in result or ("decode" in result and not result["decode"]["fully_consumed"]):
                raise ValueError("Downloaded AMF3 source failed complete decode")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit", action="store_true", help="Check committed data and native PNGs without raw sources")
    parser.add_argument("--check", action="store_true", help="Rebuild offline and compare committed outputs")
    parser.add_argument("--download", action="store_true", help="Fetch only the bounded exact field entries before building")
    parser.add_argument("--field-cache", type=Path, default=ROOT / ".tools/wf-map-bulk-next")
    parser.add_argument("--terrain-cache", type=Path, default=ROOT / ".tools/wf-full-map-research/jp-archive")
    parser.add_argument("--workers", type=int, default=3)
    args = parser.parse_args()
    if args.audit:
        print(json.dumps(audit(), ensure_ascii=False))
        return
    if args.download:
        download_fields(ROOT, args.field_cache, args.workers)
    library, images = build(ROOT, args.field_cache, args.terrain_cache)
    manifest = {"schema_version": 1, "source_registry": REGISTRY_PATH.as_posix(), "images": library["images"]}
    if args.check:
        if library != read_json(ROOT / LIBRARY_PATH) or manifest != read_json(ROOT / ASSETS_PATH / "manifest.json") or any((ROOT / path).read_bytes() != png for path, png in images.items()):
            raise ValueError("Offline rebuild differs from committed map library/assets")
    else:
        for path, png in images.items():
            target = ROOT / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(png)
        write_json(ROOT / ASSETS_PATH / "manifest.json", manifest)
        (ROOT / LIBRARY_PATH).parent.mkdir(parents=True, exist_ok=True)
        (ROOT / LIBRARY_PATH).write_bytes(canonical_bytes(library))
    print(json.dumps(validate_library(library), ensure_ascii=False))


if __name__ == "__main__":
    main()
