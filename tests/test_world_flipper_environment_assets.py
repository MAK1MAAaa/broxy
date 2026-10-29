"""Regress pinned environment assets and alpha cleanup without caches or network."""
from __future__ import annotations

from copy import deepcopy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets/worldflipper"
MAP_IDS = ("reliquary", "mire", "glacier", "ashland")
PROP_IDS = ("monument", "planter", "bumper")
PROP_ALPHA = {"monument": {0, 78, 255}, "planter": {0, 78, 255}, "bumper": {0, 138, 200, 255}}
SHADOW = (196, 196, 196, 255)
FACE_GRAY = (208, 208, 208, 255)
BLACK = (0, 0, 0, 255)


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rgba(path: Path) -> Image.Image:
    with Image.open(path) as image:
        return image.convert("RGBA")


def enemies_module():
    spec = importlib.util.spec_from_file_location("environment_test_enemies", ROOT / "tools/world_flipper_enemies.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class WorldFlipperEnvironmentAssets(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.enemy_sources = load_json(ROOT / "tools/world_flipper_enemies.json")["sources"]
        cls.environment_sources = load_json(ROOT / "tools/world_flipper_maps_sources.json")["sources"]
        cls.manifest = load_json(ART / "manifest.json")
        cls.assets = {asset["id"]: asset for asset in cls.manifest["assets"]}
        cls.enemies = enemies_module()

    def assert_integer_pixels(self, image: Image.Image, scale: int) -> None:
        self.assertEqual((image.width % scale, image.height % scale), (0, 0))
        reduced = image.resize((image.width // scale, image.height // scale), Image.Resampling.NEAREST)
        self.assertEqual(image.tobytes(), reduced.resize(image.size, Image.Resampling.NEAREST).tobytes())

    def test_alpha_masks_remove_only_matching_pixels_inside_the_source_rect(self) -> None:
        for source in self.enemy_sources:
            for rule in source.get("alpha_cleanup", []):
                with self.subTest(enemy=source["id"]):
                    image = Image.new("RGBA", tuple(source["source_size"]))
                    image.putpixel((0, 0), SHADOW)
                    image.putpixel((1, 1), BLACK)
                    image.putpixel((2, 2), FACE_GRAY)
                    image.putpixel((3, 3), (221, 87, 29, 255))
                    x, y, width, height = rule["rect"]
                    positions = [(column, row) for row in range(y, y + height) for column in range(x, x + width)]
                    removed = set(positions[:rule["expected_pixels"]])
                    for index, position in enumerate(positions):
                        image.putpixel(position, SHADOW if position in removed else (BLACK if index % 2 else FACE_GRAY))
                    before = image.tobytes()
                    cleaned = self.enemies._clean_alpha(source, image)
                    self.assertEqual(image.tobytes(), before)
                    for row in range(image.height):
                        for column in range(image.width):
                            position = (column, row)
                            self.assertEqual(cleaned.getpixel(position), (0, 0, 0, 0) if position in removed else image.getpixel(position))
                    self.assertEqual(cleaned.getpixel((0, 0)), SHADOW)
                    self.assertEqual(cleaned.getpixel((1, 1)), BLACK)
                    self.assertEqual(cleaned.getpixel((2, 2)), FACE_GRAY)

    def test_invalid_alpha_masks_fail_before_any_existing_output_is_overwritten(self) -> None:
        with tempfile.TemporaryDirectory(prefix="world-flipper-alpha-") as directory:
            temporary = Path(directory)
            sources = deepcopy(self.enemy_sources)
            paths: dict[str, Path] = {}
            palette = [0, 0, 0, 0, 0, 0, 196, 196, 196, 208, 208, 208] + [0] * (768 - 12)
            for source in sources:
                image = Image.new("P", tuple(source["source_size"]), 0)
                image.putpalette(palette)
                image.putpixel((0, 0), 2)
                image.putpixel((1, 1), 1)
                image.putpixel((2, 2), 3)
                for rule in source.get("alpha_cleanup", []):
                    x, y, width, height = rule["rect"]
                    positions = [(column, row) for row in range(y, y + height) for column in range(x, x + width)]
                    for position in positions[:rule["expected_pixels"]]:
                        image.putpixel(position, 2)
                path = temporary / source["filename"]
                image.save(path, format="GIF", transparency=0, duration=source["durations_ms"][0], optimize=False)
                source["sha256"] = sha(path)
                paths[source["id"]] = path
            output = temporary / "output"
            sprites = output / "sprites"
            valid = self.enemies.enemy_assets(sources, paths, output)
            self.assertEqual(len(valid), 5)
            originals = {path: path.read_bytes() for path in sprites.iterdir()}
            for mutation in ("count", "bounds", "color", "noninteger_rect", "zero_count"):
                with self.subTest(mutation=mutation):
                    invalid = deepcopy(sources)
                    rule = next(source for source in invalid if source["game_id"] == "caster")["alpha_cleanup"][0]
                    if mutation == "count":
                        rule["expected_pixels"] += 1
                    elif mutation == "bounds":
                        rule["rect"] = [2, 24, 99, 4]
                    elif mutation == "color":
                        rule["rgba"][3] = 256
                    elif mutation == "noninteger_rect":
                        rule["rect"][0] = 2.0
                    else:
                        rule["expected_pixels"] = 0
                    with self.assertRaises(ValueError):
                        self.enemies.enemy_assets(invalid, paths, output)
                    self.assertEqual({path: path.read_bytes() for path in originals}, originals)
                    self.assertEqual(set(sprites.iterdir()), set(originals))

    def test_master_records_match_every_png_and_pinned_source(self) -> None:
        self.assertEqual(len(self.manifest["assets"]), 49)
        self.assertEqual(len(self.assets), 49)
        self.assertEqual(len({asset["path"] for asset in self.assets.values()}), 49)
        registered: dict[str, dict] = {}
        for filename in ("world_flipper_sources.json", "world_flipper_enemies.json", "world_flipper_cover_sources.json", "world_flipper_maps_sources.json", "world_flipper_items_sources.json"):
            for source in load_json(ROOT / "tools" / filename)["sources"]:
                self.assertNotIn(source["id"], registered)
                registered[source["id"]] = source
        pinned = {source["id"]: source for source in self.manifest["sources"]}
        self.assertEqual(len(self.manifest["sources"]), 45)
        self.assertEqual(set(pinned), set(registered))
        for source_id, source in pinned.items():
            with self.subTest(source=source_id):
                self.assertEqual(source["sha256"], registered[source_id]["sha256"])
                self.assertEqual(source["source_size"], registered[source_id]["source_size"])
        for asset in self.assets.values():
            with self.subTest(asset=asset["id"]):
                path = ROOT / asset["path"]
                self.assertEqual(sha(path), asset["sha256"])
                image = rgba(path)
                self.assertEqual(list(image.size), asset["size"])
                self.assertEqual(list(image.getchannel("A").getbbox()), asset["alpha_bounds"])
                self.assertTrue(asset["source_ids"] and set(asset["source_ids"]).issubset(pinned))

    def test_four_maps_keep_double_pixels_and_four_previews_are_exact_camera_crops(self) -> None:
        for game_id in MAP_IDS:
            with self.subTest(map=game_id):
                image = rgba(ART / "maps" / (game_id + ".png"))
                preview = rgba(ART / "maps/previews" / (game_id + ".png"))
                self.assertEqual(image.size, (3780, 2104))
                self.assertEqual(image.getchannel("A").getextrema(), (255, 255))
                self.assert_integer_pixels(image, 2)
                self.assertEqual(preview.size, (1280, 720))
                self.assertEqual(preview.tobytes(), image.crop((1146, 684, 2426, 1404)).tobytes())
                self.assertEqual(self.assets["arena_" + game_id]["source_scale"], 2)
                self.assertEqual(self.assets["arena_" + game_id + "_preview"]["arena_crop"], [1146, 684, 1280, 720])

    def test_three_props_keep_integer_source_pixels_transparency_and_the_same_foot_anchor(self) -> None:
        for source in self.environment_sources:
            if source["kind"] != "arena_prop":
                continue
            with self.subTest(prop=source["game_id"]):
                record = self.assets[source["id"]]
                image = rgba(ROOT / record["path"])
                self.assertIn(source["game_id"], PROP_IDS)
                self.assertEqual(image.size, (96, 96))
                self.assertEqual(set(image.getchannel("A").tobytes()), PROP_ALPHA[source["game_id"]])
                self.assertEqual(record["foot_anchor"], [48, 84])
                scale = source["scale"]
                width, height = source["crop"][2] * scale, source["crop"][3] * scale
                x, y = (96 - width) // 2, 84 - height
                self.assertEqual(record["offset"], [x, y])
                frame = image.crop((x, y, x + width, y + height))
                self.assert_integer_pixels(frame, scale)
                reconstructed = Image.new("RGBA", (96, 96))
                reconstructed.alpha_composite(frame, (x, y))
                self.assertEqual(image.tobytes(), reconstructed.tobytes())
                self.assertEqual(image.getchannel("A").getbbox()[3], 84)

    def test_five_enemy_pngs_keep_integer_bodies_black_outlines_and_nonshadow_gray(self) -> None:
        for source in self.enemy_sources:
            with self.subTest(enemy=source["game_id"]):
                image = rgba(ART / "sprites" / (source["game_id"] + ".png"))
                self.assertEqual(image.size, tuple(source["canvas_size"]))
                self.assertEqual(set(image.getchannel("A").tobytes()), {0, 255})
                self.assertTrue(all(pixel[:3] == (0, 0, 0) for pixel in image.get_flattened_data() if pixel[3] == 0))
                x, y = source["offset"]
                scale = source["scale"]
                width, height = (extent * scale for extent in source["source_size"])
                body = image.crop((x, y, x + width, y + height))
                self.assert_integer_pixels(body, scale)
                reconstructed = Image.new("RGBA", image.size)
                reconstructed.alpha_composite(body, (x, y))
                self.assertEqual(image.tobytes(), reconstructed.tobytes())
                self.assertIn(BLACK, image.get_flattened_data())
                self.assertEqual(self.assets[source["id"]]["alpha_cleanup"], source.get("alpha_cleanup", []))
                if source["game_id"] == "boss":
                    self.assertEqual(sum(pixel == FACE_GRAY for pixel in image.get_flattened_data()), 40 * scale * scale)
                    self.assertEqual(image.getchannel("A").getbbox()[3], 146)
                elif source["game_id"] == "caster":
                    self.assertEqual(image.getchannel("A").getbbox()[3], 66)


if __name__ == "__main__":
    unittest.main()
