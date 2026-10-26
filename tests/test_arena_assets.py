"""Keep authored map backgrounds aligned with the actual walkable terrain zones."""
from __future__ import annotations

import json
from pathlib import Path
import random
import re
import sys
import unittest
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import art_arenas
from generate_assets import DEFS

SVG = "{http://www.w3.org/2000/svg}"
MAP_IDS = ("mire", "glacier", "ashland")


class ArenaAssetTests(unittest.TestCase):
    def setUp(self) -> None:
        self.saved: list[tuple[str, int, int, str, str]] = []
        art_arenas.generate(lambda *arguments: self.saved.append(arguments))
        self.definitions = json.loads((ROOT / "data/arenas.json").read_text(encoding="utf-8"))

    def test_checked_in_maps_match_memory_generation(self) -> None:
        self.assertEqual([entry[0] for entry in self.saved], [f"maps/{id}.svg" for id in MAP_IDS])
        for name, width, height, body, _ in self.saved:
            with self.subTest(name=name):
                self.assertEqual((width, height), (1280, 720))
                expected = f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">\n{DEFS}\n{body}\n</svg>\n'
                self.assertEqual((ROOT / "assets" / name).read_text(encoding="utf-8"), expected)

    def test_generation_is_repeatable_and_does_not_touch_global_rng(self) -> None:
        before = random.getstate()
        repeated: list[tuple] = []
        art_arenas.generate(lambda *arguments: repeated.append(arguments))
        self.assertEqual(random.getstate(), before)
        self.assertEqual(repeated, self.saved)

    def test_all_gameplay_boundaries_are_visible_exact_ellipses(self) -> None:
        for definition in self.definitions:
            if definition["id"] not in MAP_IDS:
                continue
            xml = ElementTree.parse(ROOT / definition["texture"].removeprefix("res://")).getroot()
            shapes = [node for node in xml.iter(f"{SVG}ellipse")]
            for zone in definition["zones"]:
                with self.subTest(map=definition["id"], center=zone["center"]):
                    x, y = zone["center"]
                    rx, ry = zone["radius"]
                    matching = [node for node in shapes if tuple(float(node.get(key)) for key in ("cx", "cy", "rx", "ry")) == (x, y, rx, ry)]
                    self.assertEqual(len(matching), 1)
                    self.assertNotEqual(matching[0].get("fill"), "none")
                    self.assertNotEqual(matching[0].get("stroke"), "none")
                    self.assertGreater(float(matching[0].get("opacity", "1")), .9)
                    self.assertGreaterEqual(x-rx, 66)
                    self.assertLessEqual(x+rx, 1214)
                    self.assertGreaterEqual(y-ry, 140)
                    self.assertLessEqual(y+ry, 590)
                    self.assertGreater(((640-x)/rx)**2+((365-y)/ry)**2, 1, "The center spawn stays on normal ground")

    def test_map_svg_has_local_references_and_supported_shapes(self) -> None:
        forbidden = {"filter", "mask", "clipPath", "image", "text", "foreignObject", "script", "use"}
        for name, _, _, _, _ in self.saved:
            with self.subTest(name=name):
                source = (ROOT / "assets" / name).read_text(encoding="utf-8")
                xml = ElementTree.fromstring(source)
                self.assertEqual(xml.get("viewBox"), "0 0 1280 720")
                ids = [node.attrib["id"] for node in xml.iter() if "id" in node.attrib]
                self.assertEqual(len(ids), len(set(ids)))
                self.assertEqual(set(re.findall(r"url\(#([^)]*)\)", source))-set(ids), set())
                self.assertTrue(forbidden.isdisjoint(node.tag.removeprefix(SVG) for node in xml.iter()))
                self.assertFalse(any("href" in key for node in xml.iter() for key in node.attrib))

    def test_map_manifest_matches_dimensions_and_original_source(self) -> None:
        manifest = json.loads((ROOT / "assets/manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["terrain_revision"], "biomes-01")
        entries = [entry for entry in manifest["assets"] if entry["path"].startswith("assets/maps/")]
        self.assertEqual([entry["path"] for entry in entries], [f"assets/maps/{id}.svg" for id in MAP_IDS])
        for entry in entries:
            self.assertEqual(entry["size"], [1280, 720])
            self.assertEqual(entry["source"], "tools/art_arenas.py")
            self.assertEqual(entry["license"], "CC0-1.0")
            self.assertEqual(entry["pivot"], [.5, .5])


if __name__ == "__main__":
    unittest.main()
