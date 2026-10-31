"""Native JP planes, true open-wall geometry, and clean-checkout provenance."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import io
from pathlib import Path
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("wf_map_compiler", ROOT / "tools/compile_world_flipper_maps.py")
assert SPEC and SPEC.loader
TOOL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TOOL)


def static_parts() -> dict:
    return {"i": [{"s": False, "p": "exact/source/a"}], "g": [{"t": 20, "s": [{"s": 0, "i": 0, "l": [{"m": 255, "t": 20}]}]}],
            "m": [], "a": [1], "o": [], "t": [{"a": 4096, "b": 0, "c": 0, "d": 4096, "x": 0, "y": 0}], "c": [], "s": 6}


def static_timeline() -> dict:
    return {"sequences": [{"begin": 1, "end": 20, "name": "start", "kind": "loop"}],
            "sounds": [], "points": [], "circles": [], "rectangles": [], "matrices": []}


class NativeWorldFlipperMaps(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.library = TOOL.read_json(ROOT / TOOL.LIBRARY_PATH)
        cls.registry = TOOL.read_json(ROOT / TOOL.REGISTRY_PATH)
        cls.catalog = TOOL.read_json(ROOT / "data/worldflipper/catalog.json")

    def test_clean_checkout_audits_every_entry_without_raw_sources(self) -> None:
        result = TOOL.validate_library(self.library)
        self.assertTrue(result["ok"])
        self.assertFalse(result["raw_sources_required"])
        self.assertFalse(result["final_jp_byte_identity_verified"])
        self.assertEqual(result["cache_metadata_version"], "1.780.30")
        self.assertEqual(result["canonical_layouts"], 1422)
        self.assertEqual(result["terrain_resources"], 1230)
        self.assertEqual(result["terrain_layers"], 1465)
        self.assertEqual(result["ordinary_wall_segments"], 23394)
        self.assertEqual(result["field_sources"], 1802)

    def test_all_canonical_layouts_and_real_layers_survive_filtering(self) -> None:
        layouts = {row["id"]: row for row in self.catalog["maps"]["layouts"]}
        geometries = self.library["geometries"]
        seen = set()
        for entry in self.library["entries"]:
            self.assertNotIn(entry["id"], seen)
            seen.add(entry["id"])
            canonical = layouts[entry["canonical_layout_id"]]
            geometry = geometries[entry["geometry_ref"]]
            self.assertEqual(entry["field_id"], canonical["field_id"])
            self.assertEqual(geometry["terrain_ref"], canonical["terrain_ref"])
            self.assertEqual(entry["stage"]["layer_index"], geometry["layer_index"])
            self.assertEqual(entry["status"], "partial")
            self.assertIn("original_prop_art_and_mechanisms_not_implemented", entry["gaps"])
            self.assertEqual(entry["stage"]["play_bounds"], entry["play_bounds"])
        self.assertEqual({entry["canonical_layout_id"] for entry in self.library["entries"]}, set(layouts))
        self.assertGreater(len(seen), 1422)

    def test_world_transform_is_native_fourfold_without_stretch_or_refit(self) -> None:
        for entry in self.library["entries"]:
            if not entry["playable"]:
                continue
            x, y, width, height = entry["source_rect"]
            left, top, world_width, world_height = entry["play_bounds"]
            self.assertEqual(world_width, width * 4)
            self.assertEqual(world_height, height * 4)
            self.assertEqual((left + world_width / 2, top + world_height / 2), (640, 365))
            self.assertAlmostEqual(x * 6 * entry["logic_scale"] + entry["logic_offset"][0], left)
            self.assertAlmostEqual(y * 6 * entry["logic_scale"] + entry["logic_offset"][1], top)
            image = self.library["images"][entry["image_ref"]]
            self.assertGreaterEqual(x, 0)
            self.assertGreaterEqual(y, 0)
            self.assertLessEqual(x + width, image["size"][0])
            self.assertLessEqual(y + height, image["size"][1])
            bx, by, bw, bh = TOOL.LEGACY_BOUNDS
            self.assertGreaterEqual(left, bx)
            self.assertGreaterEqual(top, by)
            self.assertLessEqual(left + world_width, bx + bw)
            self.assertLessEqual(top + world_height, by + bh)

    def test_unresolved_geometry_is_indexed_and_excluded_from_play(self) -> None:
        blocked = [row for row in self.library["entries"] if "unresolved_numbered_or_one_way_wall" in row["gaps"]]
        self.assertTrue(blocked)
        self.assertTrue(all(not row["playable"] and row["texture_path"] == "" for row in blocked))
        classifications = [row["bounds_classification"] for row in self.library["geometries"].values()]
        self.assertEqual(classifications.count("single"), 1431)
        self.assertEqual(classifications.count("duplicate_identical"), 34)
        self.assertTrue(all("source_objects" not in row and "props" not in row for row in self.library["geometries"].values()))
        self.assertLess((ROOT / TOOL.LIBRARY_PATH).stat().st_size, 8 * 1024 * 1024)

    def test_only_exact_primitive_static_frame_is_accepted(self) -> None:
        atlas = [{"n": "exact/source/a", "x": 1, "y": 1, "w": 2, "h": 3}]
        self.assertEqual(TOOL.primitive_frame(static_parts(), static_timeline(), atlas), atlas[0])
        stopped = static_timeline(); stopped["sequences"][0]["kind"] = "stop"
        self.assertEqual(TOOL.primitive_frame(static_parts(), stopped, atlas), atlas[0])
        cases = []
        value = static_parts(); value["i"].append({"s": False, "p": "second"}); cases.append((value, static_timeline(), atlas))
        value = static_parts(); value["t"][0]["x"] = 4096; cases.append((value, static_timeline(), atlas))
        value = static_parts(); value["g"][0]["s"][0]["l"][0]["m"] = 128; cases.append((value, static_timeline(), atlas))
        value = static_timeline(); value["points"] = [{"x": 1}]; cases.append((static_parts(), value, atlas))
        value = static_timeline(); value["sequences"][0]["end"] = 10; cases.append((static_parts(), value, atlas))
        cases.append((static_parts(), static_timeline(), [{**atlas[0], "n": "other/source/a"}]))
        cases.append((static_parts(), static_timeline(), atlas + atlas))
        for parts, timeline, frames in cases:
            with self.subTest(parts=parts, timeline=timeline, frames=frames), self.assertRaises(ValueError):
                TOOL.primitive_frame(parts, timeline, frames)

    def test_atlas_border_trim_and_rotation_preserve_exact_source_pixels(self) -> None:
        source = Image.new("RGBA", (5, 5), (99, 17, 3, 0))
        source.putpixel((1, 1), (255, 0, 0, 255))
        source.putpixel((2, 1), (0, 255, 0, 255))
        source.putpixel((1, 2), (0, 0, 255, 255))
        source.putpixel((2, 2), (255, 255, 0, 255))
        frame = {"n": "x", "x": 1, "y": 1, "w": 2, "h": 2, "r": True, "fx": -1, "fy": -2, "fw": 4, "fh": 5}
        plane = TOOL.native_plane(source, frame)
        self.assertEqual(plane.size, (4, 5))
        self.assertEqual(plane.getpixel((1, 2)), (0, 255, 0, 255))
        self.assertEqual(plane.getpixel((2, 2)), (255, 255, 0, 255))
        self.assertEqual(plane.getpixel((1, 3)), (255, 0, 0, 255))
        self.assertEqual(plane.getpixel((0, 0)), (0, 0, 0, 0))
        with self.assertRaises(ValueError):
            TOOL.native_plane(source, {**frame, "x": 4})
        with self.assertRaises(ValueError):
            TOOL.native_plane(source, {**frame, "fw": 1})

    def test_png_lowercase_signature_repair_never_changes_rgba_or_accepts_crc_damage(self) -> None:
        source = Image.new("RGBA", (3, 2), (7, 19, 71, 112))
        buffer = io.BytesIO(); source.save(buffer, "PNG")
        raw = buffer.getvalue()
        repaired = TOOL.png_image(raw[:1] + b"png" + raw[4:])
        self.assertEqual(repaired.tobytes(), source.tobytes())
        for altered in (raw + b"trailing", raw[:-1], raw[:29] + bytes([raw[29] ^ 1]) + raw[30:]):
            with self.assertRaises(ValueError):
                TOOL.png_image(altered)

    def test_static_audit_rejects_changed_canonical_identity_walls_and_image_proof(self) -> None:
        for kind in ("canonical", "walls", "image", "bounds", "groups"):
            altered = copy.deepcopy(self.library)
            if kind == "canonical":
                altered["entries"][0]["canonical_layout_id"] = altered["entries"][1]["canonical_layout_id"]
            elif kind == "walls":
                geometry = next(row for row in altered["geometries"].values() if row["walls"])
                geometry["walls"][0]["a"][0] += 0.25
            elif kind == "image":
                image = next(iter(altered["images"].values()))
                image["primitive_proof"]["source_sha256"]["parts"] = "0" * 64
            elif kind == "bounds":
                altered["entries"][0]["play_bounds"][0] += 1
            else:
                altered["groups"][0]["count"] += 1
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                TOOL.validate_library(altered)

    def test_field_sources_include_platform_channel_without_invented_fallback_backgrounds(self) -> None:
        sources = TOOL.source_rows(self.registry)
        town = sources["battle/field/world_town/town_street/background/background.png"]
        self.assertIn("/production/android_upload/", town["zip_entry"]["name"])
        missing = [row for row in self.registry["background_availability"] if any(gap.startswith("missing_exact_background_") for gap in row["gaps"])]
        self.assertEqual({row["field_id"] for row in missing}, {"fake_princess_01_forest", "fake_princess_01_garden", "yokai_emaki_01_garden", "xmas19_gacha_skill_preview"})
        self.assertEqual(len({row["background_ref"] for row in missing}), 2)
        self.assertTrue(all(not row["playable"] for row in self.library["entries"] if row["field_id"] in {item["field_id"] for item in missing}))

    def test_group_counts_match_selectable_layers_and_main_chapters_keep_order(self) -> None:
        groups = self.library["groups"]
        self.assertEqual(sum(row["count"] for row in groups), sum(row["playable"] for row in self.library["entries"]))
        chapters = [row["id"] for row in groups if row["id"].startswith("主线")]
        populated = {entry["group"] for entry in self.library["entries"] if entry["playable"]}
        self.assertEqual(chapters, [f"主线 第{index}章" for index in range(1, 13) if f"主线 第{index}章" in populated])
        chapter12 = [row for row in self.library["entries"] if row["canonical_layout_id"].startswith("main_12_")]
        self.assertTrue(chapter12)
        self.assertTrue(all(not row["playable"] and "unresolved_numbered_or_one_way_wall" in row["gaps"] for row in chapter12))
        self.assertTrue(all(row["id"] == row["name"] and row["count"] > 0 for row in groups))


if __name__ == "__main__":
    unittest.main()
