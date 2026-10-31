"""Validate the three added official-demo arenas without network or source caches."""
from __future__ import annotations

from copy import deepcopy
import importlib.util
import json
import math
from pathlib import Path
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
NEW_IDS = ("town", "throne", "tower_peak")


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def maps_module():
    spec = importlib.util.spec_from_file_location("map_expansion_tools", ROOT / "tools/world_flipper_maps.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("Cannot load the production map normalizer")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class WorldFlipperMapExpansion(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.maps = maps_module()
        cls.sources = load_json(ROOT / "tools/world_flipper_maps_sources.json")["sources"]
        cls.arenas = {arena["id"]: arena for arena in load_json(ROOT / "data/arenas.json")}

    def test_three_added_maps_pin_the_actual_official_demo_fields(self) -> None:
        paths = {
            "town": "world_town/town_street",
            "throne": "world_light/light_castle_throne",
            "tower_peak": "world_evil/evil_tower_top",
        }
        for game_id, field in paths.items():
            with self.subTest(map=game_id):
                source = next(item for item in self.sources if item["id"] == "arena_" + game_id)
                self.assertEqual(source["url"], f"https://worldflipper.jp/demo/src/assets/production/battle/field/{field}/background/background.png")
                self.assertEqual(source["source_page"], "https://worldflipper.jp/demo/")
                self.assertEqual(len(source["sha256"]), 64)
                self.assertEqual(source["scale"], 2)
                self.assertIn(game_id, self.maps.MAP_IDS)
                for crop in [source["crop"], source["zone_crop"], *source["border_crops"].values()]:
                    x, y, width, height = crop
                    self.assertGreaterEqual(min(x, y), 0)
                    self.assertGreater(min(width, height), 0)
                    self.assertLessEqual(x + width, source["source_size"][0])
                    self.assertLessEqual(y + height, source["source_size"][1])

    def test_maps_keep_integer_pixels_and_exact_start_camera_previews(self) -> None:
        for game_id in NEW_IDS:
            with self.subTest(map=game_id):
                with Image.open(ROOT / "assets/worldflipper/maps" / f"{game_id}.png") as raw:
                    image = raw.convert("RGBA")
                with Image.open(ROOT / "assets/worldflipper/maps/previews" / f"{game_id}.png") as raw:
                    preview = raw.convert("RGBA")
                self.assertEqual(image.size, (3780, 2192))
                self.assertEqual(image.getchannel("A").getextrema(), (255, 255))
                reduced = image.resize((1890, 1096), Image.Resampling.NEAREST)
                self.assertEqual(image.tobytes(), reduced.resize(image.size, Image.Resampling.NEAREST).tobytes())
                self.assertEqual(preview.size, (1280, 720))
                self.assertEqual(preview.tobytes(), image.crop((1146, 772, 2426, 1492)).tobytes())

    def test_new_arena_routes_have_real_terrain_crates_and_open_gaps(self) -> None:
        for game_id in NEW_IDS:
            with self.subTest(map=game_id):
                arena = self.arenas[game_id]
                self.assertEqual(len(arena["zones"]), 6)
                self.assertEqual(len(arena["obstacles"]), 12)
                self.assertEqual(len(arena["crates"]), 12)
                self.assertEqual(arena["legacy_zone_count"], 0)
                self.assertGreater(arena["move_multiplier"], 0)
                self.assertLess(arena["move_multiplier"], 1)
                objects = arena["obstacles"] + arena["crates"]
                self.assertEqual(len({obj["id"] for obj in objects}), len(objects))
                for index, obj in enumerate(objects):
                    x, y = obj["center"]
                    radius = obj["radius"]
                    self.assertTrue(-1082 + radius <= x <= 2362 - radius)
                    self.assertTrue(-535 + radius <= y <= 1265 - radius)
                    for other in objects[:index]:
                        self.assertGreater(math.dist(obj["center"], other["center"]), radius + other["radius"] + 32)

    def test_every_added_upright_landmark_stays_outside_the_playable_floor(self) -> None:
        left, top, right, bottom = (64, 232, 3508, 2032)
        for source in self.sources:
            if source["kind"] != "arena_landmark" or source["game_id"] not in NEW_IDS:
                continue
            for placement in source["placements"]:
                with self.subTest(source=source["id"], placement=placement):
                    x, y = placement["position"]
                    crop = source["variants"][placement["variant"]]
                    width, height = crop[2] * 2, crop[3] * 2
                    self.assertEqual(x % 2 + y % 2, 0)
                    self.assertTrue(x + width <= left or x >= right or y + height <= top or y >= bottom)

    def test_carpet_band_uses_exact_native_source_pixels_at_world_center(self) -> None:
        raw = Image.new("RGBA", (8, 8), (14, 30, 52, 255))
        for y in range(4):
            for x in range(4):
                raw.putpixel((x + 4, y + 4), (160 + x, 34 + y, 50, 255))
        source = {"crop": [0, 0, 4, 4], "floor_bands": [{"source_crop": [4, 4, 4, 4], "axis": "vertical", "world_center": 640, "width": 192}]}
        untouched = deepcopy(source)
        image = self.maps._floor(raw, source, {"zones": []})
        x = (640 + 1146) // 2 - 48
        carpet = self.maps._mirror_tile(raw.crop((4, 4, 8, 8)).convert("RGB"), (96, 900))
        self.assertEqual(image.crop((x, 116, x + 96, 1016)).tobytes(), carpet.tobytes())
        self.assertEqual(image.getpixel((x - 1, 116)), (14, 30, 52))
        self.assertEqual(image.getpixel((x + 96, 116)), (14, 30, 52))
        self.assertEqual(source, untouched)

    def test_invalid_floor_bands_fail_instead_of_resampling_or_leaving_playable_space(self) -> None:
        source = {"crop": [0, 0, 4, 4], "floor_bands": [{"source_crop": [4, 4, 4, 4], "axis": "vertical", "world_center": 640, "width": 192}]}
        invalid = [{"axis": "diagonal"}, {"width": 0}, {"width": 3}, {"width": 1.5}, {"world_center": 641}, {"world_center": -2000}, {"width": 4000}, {"source_crop": [6, 6, 4, 4]}]
        for change in invalid:
            with self.subTest(change=change):
                value = deepcopy(source)
                value["floor_bands"][0].update(change)
                with self.assertRaises(ValueError):
                    self.maps._floor(Image.new("RGBA", (8, 8)), value, {"zones": []})


if __name__ == "__main__":
    unittest.main()
