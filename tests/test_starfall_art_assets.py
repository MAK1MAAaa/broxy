"""Validate the replacement art family against existing content and terrain geometry."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import random
import struct
import sys
import unittest
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from generate_starfall_art import build_vectors

SVG = "{http://www.w3.org/2000/svg}"


class StarfallArtTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vectors = build_vectors()
        cls.manifest = json.loads((ROOT / "assets/starfall/manifest.json").read_text(encoding="utf-8"))

    def test_every_existing_visual_has_one_replacement(self) -> None:
        legacy = json.loads((ROOT / "assets/manifest.json").read_text(encoding="utf-8"))
        expected = {row["path"].replace("assets/", "assets/starfall/", 1)
                    for row in legacy["assets"] if row["path"].endswith(".svg")}
        expected.remove("assets/starfall/menu_art.svg")
        expected.add("assets/starfall/menu_art.png")
        expected.update(f"assets/starfall/icons/skill_{name}.svg" for name in ("pulse", "starfall", "arc_slash"))
        actual = [row["path"] for row in self.manifest["assets"]]
        self.assertEqual(set(actual), expected)
        self.assertEqual(len(actual), len(expected))
        for row in self.manifest["assets"]:
            path = ROOT / row["path"]
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), row["sha256"])

    def test_regeneration_is_exact_without_consuming_shared_rng(self) -> None:
        before = random.getstate()
        repeated = build_vectors()
        self.assertEqual(random.getstate(), before)
        self.assertEqual(repeated, self.vectors)
        for asset in repeated:
            self.assertEqual((ROOT / "assets/starfall" / asset.name).read_bytes(), asset.encode())

    def test_pixel_geometry_is_local_and_fits_its_canvas(self) -> None:
        allowed = {"svg", "rect", "g", "ellipse"}
        for asset in self.vectors:
            xml = ElementTree.fromstring(asset.encode())
            self.assertEqual(xml.attrib["viewBox"], f"0 0 {asset.width} {asset.height}")
            self.assertGreater(len(list(xml.iter(SVG + "rect"))), 8)
            for node in xml.iter():
                self.assertIn(node.tag.removeprefix(SVG), allowed)
                self.assertFalse(any("href" in key for key in node.attrib))
                if node.tag == SVG + "rect":
                    x, y, width, height = (float(node.get(key, "0")) for key in ("x", "y", "width", "height"))
                    self.assertTrue(all(value.is_integer() for value in (x, y, width, height)))
                    self.assertGreater(width, 0)
                    self.assertGreater(height, 0)
                    self.assertGreaterEqual(min(x, y), 0)
                    self.assertLessEqual(x + width, asset.width)
                    self.assertLessEqual(y + height, asset.height)
                if node.tag == SVG + "ellipse":
                    self.assertTrue(asset.name.startswith("maps/"), "Only exact gameplay terrain boundaries use ellipses")

    def test_replacement_maps_show_the_actual_slow_ground(self) -> None:
        definitions = json.loads((ROOT / "data/arenas.json").read_text(encoding="utf-8"))
        for definition in definitions:
            if definition["id"] not in {"reliquary", "mire", "glacier", "ashland"}:
                continue
            name = "arena.svg" if definition["id"] == "reliquary" else f'maps/{definition["id"]}.svg'
            xml = ElementTree.parse(ROOT / "assets/starfall" / name).getroot()
            ellipses = list(xml.iter(SVG + "ellipse"))
            legacy_zones = definition["zones"][:definition["legacy_zone_count"]]
            self.assertEqual(len(ellipses), len(legacy_zones))
            for node, zone in zip(ellipses, legacy_zones):
                self.assertEqual(tuple(float(node.get(key)) for key in ("cx", "cy", "rx", "ry")),
                                 tuple(zone["center"] + zone["radius"]))
                self.assertNotIn(node.get("fill"), (None, "none"))
                self.assertNotIn(node.get("stroke"), (None, "none"))
            for node in xml.iter(SVG + "g"):
                if node.get("data-role") != "rim-decoration":
                    continue
                x, y, width, height = map(float, node.get("data-bounds").split(","))
                self.assertTrue(x + width <= 66 or x >= 1214 or y + height <= 140 or y >= 590)

    def test_menu_png_is_registered_with_generation_provenance(self) -> None:
        png = (ROOT / "assets/starfall/menu_art.png").read_bytes()
        self.assertEqual(png[:8], b"\x89PNG\r\n\x1a\n")
        width, height = struct.unpack(">II", png[16:24])
        self.assertGreaterEqual(min(width, height), 640)
        self.assertLessEqual(max(width, height), 2048)
        self.assertLess(len(png), 4 * 1024 * 1024)
        provenance = json.loads((ROOT / "assets/starfall/image-generation.json").read_text(encoding="utf-8"))
        self.assertFalse(provenance["external_game_assets_embedded"])
        self.assertIn("masked", provenance["prompt"].lower())


if __name__ == "__main__":
    unittest.main()
