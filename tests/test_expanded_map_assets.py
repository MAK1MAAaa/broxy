"""Verify continuous map art, world transforms and authored terrain boundaries."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import random
import sys
import unittest
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from generate_expanded_maps import ARENA, ART_MARGINS, DESTINATION, IDS, MATERIALS, ORIGIN, SIZE, WALKABLE, build_maps

SVG = "{http://www.w3.org/2000/svg}"


class ExpandedMapAssetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.generated = build_maps()
        cls.definitions = json.loads((ROOT / "data/arenas.json").read_text(encoding="utf-8"))
        cls.manifest = json.loads((DESTINATION / "manifest.json").read_text(encoding="utf-8"))

    def test_checked_in_family_and_world_contract(self) -> None:
        self.assertEqual(tuple(kind for kind, _ in self.generated), IDS)
        self.assertEqual(ART_MARGINS, (64, 144, 272, 160))
        self.assertEqual(ORIGIN, (ARENA[0] - ART_MARGINS[0], ARENA[1] - ART_MARGINS[1]))
        self.assertEqual(SIZE, (ARENA[2] + ART_MARGINS[0] + ART_MARGINS[2], ARENA[3] + ART_MARGINS[1] + ART_MARGINS[3]))
        self.assertEqual(WALKABLE, (64, 144, 3508, 1944))
        self.assertTrue(self.manifest["legacy_assets_preserved"])
        self.assertEqual(self.manifest["art_revision"], "expanded-arena-02")
        for (kind, content), row in zip(self.generated, self.manifest["assets"]):
            with self.subTest(arena=kind):
                self.assertEqual((DESTINATION / f"{kind}.svg").read_bytes(), content)
                self.assertEqual(row["id"], kind)
                self.assertEqual(row["size"], list(SIZE))
                self.assertEqual(row["world_origin"], list(ORIGIN))
                self.assertEqual(row["walkable_bounds"], list(ARENA))
                self.assertEqual(row["art_margins"], list(ART_MARGINS))
                self.assertEqual(row["material"], MATERIALS[kind])
                self.assertEqual(row["license"], "CC0-1.0")
                self.assertTrue((ROOT / row["source"]).is_file())
                self.assertEqual(row["sha256"], hashlib.sha256(content).hexdigest())

    def test_exact_world_terrain_geometry(self) -> None:
        for definition, (kind, content) in zip(self.definitions, self.generated):
            shapes = list(ElementTree.fromstring(content).iter(SVG + "ellipse"))
            self.assertEqual(len(shapes), len(definition["zones"]), kind)
            for shape, zone in zip(shapes, definition["zones"]):
                expected = (zone["center"][0] - ORIGIN[0], zone["center"][1] - ORIGIN[1], *zone["radius"])
                self.assertEqual(tuple(float(shape.get(key)) for key in ("cx", "cy", "rx", "ry")), expected)
                self.assertNotIn(shape.get("fill"), (None, "none"))
                self.assertNotIn(shape.get("stroke"), (None, "none"))

    def test_pixels_fit_large_native_canvas_without_external_content(self) -> None:
        for kind, content in self.generated:
            xml = ElementTree.fromstring(content)
            self.assertEqual(xml.get("viewBox"), f"0 0 {SIZE[0]} {SIZE[1]}")
            self.assertLess(max(SIZE), 4096)
            self.assertLess(len(content), 1024 * 1024)
            for node in xml.iter():
                self.assertIn(node.tag.removeprefix(SVG), {"svg", "g", "rect", "ellipse"})
                self.assertFalse(any("href" in name for name in node.attrib))
                if node.tag != SVG + "rect":
                    continue
                x, y, width, height = (int(node.get(key)) for key in ("x", "y", "width", "height"))
                self.assertTrue(all(value % 4 == 0 for value in (x, y, width, height)), kind)
                self.assertGreater(min(width, height), 0)
                self.assertGreaterEqual(min(x, y), 0)
                self.assertLessEqual(x + width, SIZE[0])
                self.assertLessEqual(y + height, SIZE[1])

    def test_four_distant_landmarks_and_outer_only_upright_ornaments(self) -> None:
        for kind, content in self.generated:
            xml = ElementTree.fromstring(content)
            inlays = [node for node in xml.iter(SVG + "g") if node.get("data-role") == "floor-inlay"]
            self.assertEqual({node.get("data-direction") for node in inlays}, {"north", "south", "east", "west"}, kind)
            for node in inlays:
                x, y = map(int, node.get("data-world-center").split(","))
                self.assertGreater((x - 640) ** 2 + (y - 365) ** 2, 500 ** 2)
            ornaments = [node for node in xml.iter(SVG + "g") if node.get("data-role") == "rim-decoration"]
            self.assertGreater(len(ornaments), 20)
            for node in ornaments:
                x, y, width, height = map(int, node.get("data-bounds").split(","))
                left, top, right, bottom = WALKABLE
                self.assertTrue(x + width <= left or x >= right or y + height <= top or y >= bottom)

    def test_generation_is_deterministic_without_global_rng_side_effects(self) -> None:
        before = random.getstate()
        self.assertEqual(build_maps(), self.generated)
        self.assertEqual(random.getstate(), before)

    def test_biome_materials_are_flat_and_keep_the_combat_floor_unobstructed(self) -> None:
        material_ids: set[str] = set()
        ornament_ids: set[str] = set()
        for kind, content in self.generated:
            xml = ElementTree.fromstring(content)
            materials = [node for node in xml.iter(SVG + "g") if node.get("data-role") == "floor-material"]
            self.assertEqual(len(materials), 1)
            self.assertEqual(materials[0].get("data-flat"), "true")
            material_ids.add(materials[0].get("data-material"))
            left, top, right, bottom = WALKABLE
            for node in materials[0].iter(SVG + "rect"):
                x, y, width, height = (int(node.get(key)) for key in ("x", "y", "width", "height"))
                self.assertTrue(left <= x < x + width <= right and top <= y < y + height <= bottom, kind)
            ornaments = [node for node in xml.iter(SVG + "g") if node.get("data-role") == "rim-decoration"]
            ornament_ids.update(node.get("data-kind") for node in ornaments)
            for node in xml.iter(SVG + "rect"):
                red, green, blue = (int(node.get("fill")[index:index + 2], 16) for index in (1, 3, 5))
                self.assertFalse(red > 180 and red > green * 1.25 and red > blue * 1.25, "Background cannot impersonate a hostile red warning")
        self.assertEqual(len(material_ids), 4)
        self.assertEqual(len(ornament_ids), 4)


if __name__ == "__main__":
    unittest.main()
