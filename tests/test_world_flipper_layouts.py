"""Geometry and provenance checks that do not require network or raw-source caches."""

from __future__ import annotations

from copy import deepcopy
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[1]


def module():
    spec = importlib.util.spec_from_file_location("wf_layout_import", ROOT / "tools/world_flipper_layouts.py")
    assert spec and spec.loader
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def orderedmap(rows: list[tuple[str, str]]) -> bytes:
    keys, values, pairs = b"", b"", b""
    for key, value in rows:
        keys += key.encode("utf-8")
        values += zlib.compress(value.encode("utf-8"))
        pairs += struct.pack("<II", len(keys), len(values))
    header = zlib.compress(struct.pack("<I", len(rows)) + pairs + keys)
    return struct.pack("<I", len(header)) + header + values


def fixture() -> dict:
    return {"layers": [{"type": "objectgroup", "name": "1", "visible": False, "objects": [
        {"id": 435, "type": "BOUNDS", "visible": False, "x": 46, "y": 134, "width": 180, "height": 320},
        {"id": 734, "type": "WALL", "x": 54.3636, "y": 261.636,
         "polyline": [{"x": 0, "y": 0}, {"x": 0.545455, "y": -212.545}, {"x": 162.545, "y": -212.182}]},
        {"id": 2, "type": "BREAKABLE_DECORATION#BARREL", "x": 20, "y": 30,
         "width": 16, "height": 10, "ellipse": True},
        {"id": 3, "type": "RETURN_LANE_GUIDE", "x": 1, "y": 2,
         "polyline": [{"x": 0, "y": 0}, {"x": 50, "y": 50}]},
        {"id": 4, "type": "CUSTOM_POSITION", "name": "p0", "visible": False,
         "x": 127, "y": 110, "width": 16, "height": 16},
    ]}, {"type": "objectgroup", "name": "0", "objects": []}]}


class LayoutImport(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.tool = module()
        cls.document = json.loads((ROOT / "data/worldflipper/layouts.json").read_text(encoding="utf-8"))
        cls.registry = json.loads((ROOT / "tools/world_flipper_layout_sources.json").read_text(encoding="utf-8"))
        cls.catalog = json.loads((ROOT / "data/worldflipper/catalog.json").read_text(encoding="utf-8"))

    def test_open_polylines_preserve_scalar_coordinates_and_hidden_logic(self) -> None:
        layers = self.tool.normalize_geometry(fixture())
        self.assertEqual([layer["index"] for layer in layers], [1, 0])
        self.assertEqual([layer["source_order"] for layer in layers], [0, 1])
        self.assertEqual(layers[0]["bounds"][0]["rect"], [276, 804, 1080, 1920])
        self.assertEqual(len(layers[0]["walls"]), 2)  # Three vertices do not create a closing third segment.
        self.assertAlmostEqual(layers[0]["walls"][0]["a"][0], 326.1816, places=9)
        self.assertAlmostEqual(layers[0]["walls"][0]["b"][1], 294.546, places=9)
        custom = next(marker for marker in layers[0]["markers"] if marker["name"] == "p0")
        self.assertEqual(custom["center"], [810, 708])
        self.assertTrue(custom["recognized_zone"])
        self.assertFalse(layers[0]["source_visible"])
        self.assertEqual(len(layers[0]["objects"]), 5)

    def test_guide_and_editor_ellipse_do_not_invent_colliders(self) -> None:
        layer = self.tool.normalize_geometry(fixture())[0]
        prop = layer["props"][0]
        self.assertEqual(prop["center"], [168, 210])
        self.assertEqual(prop["resource_id"], "barrel")
        self.assertIsNone(prop["collision_geometry"])
        self.assertNotIn("radius", prop)
        guide = next(marker for marker in layer["markers"] if marker["kind"] == "RETURN_LANE_GUIDE")
        self.assertFalse(guide["recognized_zone"])
        self.assertEqual(len(layer["walls"]), 2)

    def test_geometry_rejects_ambiguous_or_nonfinite_sources(self) -> None:
        cases = []
        value = fixture(); value["layers"][0]["objects"][1]["polyline"][0]["x"] = float("nan"); cases.append(value)
        value = fixture(); value["layers"][0]["objects"][0]["x"] = True; cases.append(value)
        value = fixture(); value["layers"][1]["name"] = "1"; cases.append(value)
        value = fixture(); value["layers"][1]["type"] = "tilelayer"; cases.append(value)
        value = fixture(); value["layers"][0]["objects"][1]["polyline"] = [{"x": 0, "y": 0}]; cases.append(value)
        value = fixture(); value["layers"][0]["objects"][1]["id"] = 435; cases.append(value)
        for value in cases:
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.tool.normalize_geometry(value)

    def test_orderedmap_decodes_real_format_and_validates_indices(self) -> None:
        data = orderedmap([("stage_a", 'field_a,battle/terrain/a,"stage, name"'), ("stage_b", "field_b,battle/terrain/b,stage_b")])
        self.assertEqual(self.tool.decode_orderedmap(data)["stage_a"], ["field_a", "battle/terrain/a", "stage, name"])
        for malformed in (b"", data[:-1], data + b"garbage", struct.pack("<I", 0xffffffff) + data[4:], orderedmap([("same", "a"), ("same", "b")])):
            with self.subTest(data=malformed[:12]), self.assertRaises((ValueError, zlib.error)):
                self.tool.decode_orderedmap(malformed)
        header = zlib.compress(struct.pack("<III", 1, 9000, 1) + b"a")
        with self.assertRaises(ValueError):
            self.tool.decode_orderedmap(struct.pack("<I", len(header)) + header + b"x")
        with self.assertRaises(ValueError):
            self.tool._inflate(zlib.compress(b"a" * 21), 20)

    def test_cache_requires_exact_pinned_bytes_and_safe_paths(self) -> None:
        data = b"verified"
        source = {"id": "test", "cache_filename": "terrain.json", "bytes": len(data),
                  "sha256": hashlib.sha256(data).hexdigest(), "url": "https://example.invalid/never-fetched"}
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            (cache / "terrain.json").write_bytes(data)
            self.assertEqual(self.tool.checked_source(source, cache, True), data)
            (cache / "terrain.json").write_bytes(b"tampered")
            with self.assertRaises(ValueError):
                self.tool.checked_source(source, cache, True)
            invalid = deepcopy(source); invalid["cache_filename"] = "../outside.json"
            with self.assertRaises(ValueError):
                self.tool.checked_source(invalid, cache, True)

    def test_coverage_is_exact_and_does_not_claim_the_missing_1419_layouts(self) -> None:
        coverage = self.document["coverage"]
        self.assertEqual(coverage["canonical_layouts"], 1422)
        self.assertEqual(coverage["canonical_layouts_with_geometry"], 3)
        self.assertEqual(coverage["canonical_pending_geometry"], 1419)
        self.assertEqual(coverage["canonical_unique_terrain_refs"], 1230)
        self.assertEqual(coverage["official_demo_geometry_files"], 8)
        self.assertEqual(coverage["terrain_layers"], 11)
        self.assertEqual(coverage["wall_segments"], 176)
        self.assertEqual(coverage["source_objects"], 259)
        actual = {entry for layout in self.document["layouts"] for entry in layout["canonical_layout_ids"]}
        self.assertEqual(actual, {"main_2_9_5", "main_3_6_2", "main_6_6_2"})
        pending = set(self.document["pending_canonical_layout_ids"])
        self.assertFalse(actual & pending)
        self.assertEqual(actual | pending, {row["id"] for row in self.catalog["maps"]["layouts"]})
        self.assertTrue(all(not layout["runtime_ready"] for layout in self.document["layouts"]))

    def test_every_binding_and_background_links_to_pinned_evidence(self) -> None:
        sources = {source["id"]: source for source in self.registry["sources"]}
        self.assertEqual(len(sources), 28)
        expected_fields = {"main_2_9_5": "sand_ruins", "main_3_6_2": "sea_ship_boss", "main_6_6_2": "japan_shrine",
                           "tutorial_1": "light_castle_throne", "tutorial_3": "evil_tower", "tutorial_4": "evil_tower",
                           "tutorial_5": "evil_tower_top", "tutorial_8": "town_street"}
        for layout in self.document["layouts"]:
            with self.subTest(layout=layout["id"]):
                self.assertEqual(layout["field_id"], expected_fields[layout["id"]])
                self.assertEqual(sources[layout["source_id"]]["terrain_ref"], layout["terrain_ref"])
                self.assertTrue(all(source_id in sources for source_id in layout["binding_source_ids"]))
                self.assertEqual(len(layout["background"]["png_sha256"]), 64)
                for layer in layout["layers"]:
                    objects = {obj["object_id"]: obj for obj in layer["objects"]}
                    for wall in layer["walls"]:
                        self.assertEqual(objects[wall["object_id"]]["kind"], "WALL")
                    self.assertTrue(all(prop["collision_geometry"] is None for prop in layer["props"]))
        peak = next(layout for layout in self.document["layouts"] if layout["id"] == "tutorial_5")
        self.assertEqual([layer["index"] for layer in peak["layers"]], [1, 0])
        self.assertTrue(peak["background"]["rotated_frames"])
        self.assertTrue(peak["background"]["has_multiple_parts"])


if __name__ == "__main__":
    unittest.main()
