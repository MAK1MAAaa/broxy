"""Original weapon identities, transparent art and deterministic normalization."""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import re
import tempfile
import unittest
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("weapon_expansion", ROOT / "tools/world_flipper_weapon_expansion.py")
assert SPEC is not None and SPEC.loader is not None
ART = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ART)


class WorldFlipperWeaponExpansionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sources = json.loads(ART.REGISTRY.read_text(encoding="utf-8"))["sources"]
        cls.canonical = json.loads((ROOT / "data/worldflipper/catalog.json").read_text(encoding="utf-8"))

    def test_exact_unique_identity_and_original_transparent_source_family(self) -> None:
        self.assertEqual(len(self.sources), 8)
        self.assertEqual({item["game_id"] for item in self.sources}, ART.IDS)
        self.assertEqual(len({item["id"] for item in self.sources}), 8)
        self.assertEqual(len({item["canonical_equipment_id"] for item in self.sources}), 8)
        original = {item["id"]: item for item in self.canonical["equipment"]}
        for source in self.sources:
            self.assertEqual(source["canonical_dev_name"], original[source["canonical_equipment_id"]]["dev_name"])
            self.assertEqual(source["game_id"], source["canonical_dev_name"])
            self.assertIn("worldflipper.wiki.gg/images/", source["url"])
            self.assertEqual(len(source["sha256"]), 64)
            self.assertEqual(source["crop"], [0, 0, *source["source_size"]])
            self.assertIs(type(source["scale"]), int)
            self.assertLessEqual(max(source["source_size"]) * source["scale"], 64)
            self.assertIn(source["scale"], [1, 2, 3])
        book = next(item for item in self.sources if item["game_id"] == "book_0009")
        self.assertIn("Senji_Ryakketsu.png", book["url"])
        self.assertNotIn("Old_Staff", book["url"])

    def test_runtime_pngs_are_rgba_transparent_and_fit_integer_bounds(self) -> None:
        for source in self.sources:
            with Image.open(ROOT / "assets/worldflipper/icons" / (source["game_id"] + ".png")) as image:
                self.assertEqual(image.mode, "RGBA")
                self.assertEqual(image.size, (64, 64))
                self.assertEqual(image.getchannel("A").getextrema(), (0, 255))
                extent = [value * source["scale"] for value in source["source_size"]]
                offset = [(64 - value) // 2 for value in extent]
                self.assertEqual(image.getchannel("A").getbbox(), (offset[0], offset[1], offset[0] + extent[0], offset[1] + extent[1]))

    def test_weapon_resources_join_canonical_ids_and_retain_real_effect_config(self) -> None:
        effects = {}
        bonuses = {}
        total_cells = 0
        for source in self.sources:
            dev = source["game_id"]
            text = (ROOT / "data/weapons" / (dev + ".tres")).read_text(encoding="utf-8")
            self.assertIn('id = "' + dev + '"', text)
            self.assertIn('source_id = "' + source["canonical_equipment_id"] + '"', text)
            self.assertIn('icon = "' + dev + '"', text)
            self.assertIn('kind = "weapon"', text)
            self.assertRegex(text, r'element = "(fire|water|thunder|wind|light|dark|physical)"')
            size = re.search(r"inventory_size = Vector2i\((\d+), (\d+)\)", text)
            self.assertIsNotNone(size)
            total_cells += int(size[1]) * int(size[2])
            match = re.search(r"equipment_effects = Array\[Dictionary\]\((\[.*\])\)", text)
            effects[dev] = json.loads(match[1]) if match else []
            match = re.search(r"equipment_bonuses = (\{.*\})", text)
            bonuses[dev] = json.loads(match[1]) if match else {}
        self.assertLessEqual(total_cells + 6, 36)
        self.assertEqual(effects["book_0009"], [{"kind": "ball_damage", "amount": 0.25}])
        self.assertEqual(bonuses["sword_0007"], {"max_health": 8.0})
        self.assertEqual(bonuses["axe_0024"], {"skill_damage": 0.28})
        self.assertEqual([item["kind"] for item in effects["sword_0011"]], ["rescue", "heal_damage"])

    def test_offline_full_family_rebuild_preserves_exact_png_bytes(self) -> None:
        paths = {source["id"]: ROOT / ".tools/worldflipper/source" / source["filename"] for source in self.sources}
        if not all(path.exists() for path in paths.values()):
            self.skipTest("Pinned original sprite cache is absent; run the art fetch tool to exercise its offline byte rebuild")
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            records = ART.weapon_expansion_assets(self.sources, paths, output)
            self.assertEqual(len(records), 8)
            for record in records:
                dev = record["id"]
                source = ROOT / "assets/worldflipper/icons" / (dev + ".png")
                rebuilt = output / "icons" / (dev + ".png")
                self.assertEqual(rebuilt.read_bytes(), source.read_bytes())
                self.assertEqual(record["sha256"], hashlib.sha256(source.read_bytes()).hexdigest())

    def test_invalid_hash_scale_and_crop_are_rejected_without_output(self) -> None:
        source = copy.deepcopy(self.sources[0])
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "source.png"
            image = Image.new("RGBA", (5, 5))
            image.putpixel((2, 2), (255, 96, 32, 255))
            image.save(path)
            source.update(sha256=hashlib.sha256(path.read_bytes()).hexdigest(), source_size=[5, 5], crop=[0, 0, 5, 5], scale=3)
            normalized, _ = ART.normalized_sprite(source, path)
            self.assertEqual(normalized.size, (64, 64))
            for change in [{"sha256": "0" * 64}, {"scale": 0}, {"scale": 1.5}, {"scale": 4}, {"crop": [0, 0, 1, 1]}, {"source_size": [6, 6]}]:
                with self.assertRaises(ValueError):
                    ART.normalized_sprite({**source, **change}, path)

    def test_family_validation_cannot_silently_drop_or_duplicate_a_weapon(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            for sources in [self.sources[:-1], [self.sources[0]] * 8]:
                with self.assertRaises(ValueError):
                    ART.weapon_expansion_assets(sources, {}, output)
                self.assertEqual(list(output.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
