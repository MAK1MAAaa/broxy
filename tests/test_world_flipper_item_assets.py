"""Source-game item identity and deterministic sprite normalization regressions."""
from __future__ import annotations

from copy import deepcopy
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class WorldFlipperItemAssets(unittest.TestCase):
    def test_every_catalog_item_has_one_source_and_its_runtime_icon(self) -> None:
        sources = read(ROOT / "tools/world_flipper_items_sources.json")["sources"]
        expected: dict[str, str] = {}
        for directory, kind in (("relics", "relic"), ("runes", "rune"), ("skills", "skill")):
            for path in (ROOT / "data" / directory).glob("*.tres"):
                icon = re.search(r'^icon = "([^"]+)"', path.read_text(encoding="utf-8"), re.M).group(1)
                expected[icon] = kind
        self.assertEqual(len(expected), 20)
        self.assertEqual({source["game_id"]: source["item_kind"] for source in sources}, expected)
        self.assertEqual(len(sources), len({source["id"] for source in sources}))
        manifest = read(ROOT / "assets/worldflipper/manifest.json")
        assets = {asset["id"]: asset for asset in manifest["assets"]}
        for source in sources:
            with self.subTest(icon=source["game_id"]):
                self.assertTrue(source["url"].startswith("https://"))
                self.assertTrue(source["source_page"].startswith("https://"))
                record = assets["item_icon_" + source["game_id"]]
                self.assertEqual(record["source_ids"], [source["id"]])
                self.assertEqual(sha(ROOT / record["path"]), record["sha256"])
                self.assertEqual(record["item_kind"], source["item_kind"])

    def test_normalized_items_preserve_integer_pixels_and_transparent_margins(self) -> None:
        for source in read(ROOT / "tools/world_flipper_items_sources.json")["sources"]:
            with self.subTest(icon=source["game_id"]):
                with Image.open(ROOT / "assets/worldflipper/icons" / (source["game_id"] + ".png")) as raw:
                    image = raw.convert("RGBA")
                self.assertEqual(image.size, (64, 64))
                scale = source["scale"]
                width, height = (value * scale for value in source["crop"][2:])
                left, top = (64 - width) // 2, (64 - height) // 2
                frame = image.crop((left, top, left + width, top + height))
                reduced = frame.resize((width // scale, height // scale), Image.Resampling.NEAREST)
                self.assertEqual(frame.tobytes(), reduced.resize(frame.size, Image.Resampling.NEAREST).tobytes())
                self.assertEqual(image.getchannel("A").getextrema(), (0, 255))
                self.assertTrue(all(pixel[:3] == (0, 0, 0) for pixel in image.get_flattened_data() if pixel[3] == 0))
                rebuilt = Image.new("RGBA", (64, 64))
                rebuilt.alpha_composite(frame, (left, top))
                self.assertEqual(image.tobytes(), rebuilt.tobytes())

    def test_projectile_frames_equal_the_corresponding_complete_weapon_icons(self) -> None:
        manifest = read(ROOT / "assets/worldflipper/manifest.json")
        record = next(asset for asset in manifest["assets"] if asset["id"] == "weapon_projectiles")
        self.assertEqual(record["weapon_ids"], ["bone", "frost", "ember", "scatter", "crescent", "storm", "comet", "return_ring"])
        with Image.open(ROOT / record["path"]) as raw:
            atlas = raw.convert("RGBA")
        self.assertEqual(atlas.size, (512, 64))
        for index, weapon in enumerate(record["weapon_ids"]):
            with Image.open(ROOT / "assets/worldflipper/icons" / (weapon + ".png")) as image:
                self.assertEqual(atlas.crop((index * 64, 0, (index + 1) * 64, 64)).tobytes(), image.convert("RGBA").tobytes())

    def test_invalid_sources_fail_without_overwriting_a_valid_item_family(self) -> None:
        spec = importlib.util.spec_from_file_location("item_asset_test_module", ROOT / "tools/world_flipper_items.py")
        self.assertIsNotNone(spec)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        sources = deepcopy(read(ROOT / "tools/world_flipper_items_sources.json")["sources"])
        with tempfile.TemporaryDirectory(prefix="embers-items-") as directory:
            temporary = Path(directory)
            paths: dict[str, Path] = {}
            for source in sources:
                image = Image.new("RGBA", tuple(source["source_size"]))
                x, y, width, height = source["crop"]
                ImageDraw.Draw(image).rectangle((x + 1, y + 1, x + width - 2, y + height - 2), fill=(28, 85, 117, 255))
                image.putpixel((x + width // 2, y + height // 2), (140, 90, 40, 128))
                path = temporary / (source["id"] + ".png")
                image.save(path)
                source["sha256"] = sha(path)
                paths[source["id"]] = path
            output = temporary / "runtime"
            records = module.item_assets(sources, paths, output)
            self.assertEqual(len(records), 20)
            saved = {path: path.read_bytes() for path in (output / "icons").glob("*.png")}
            for mutation in ("sha", "crop", "scale", "missing", "duplicate", "kind"):
                with self.subTest(mutation=mutation):
                    invalid = deepcopy(sources)
                    if mutation == "sha":
                        invalid[-1]["sha256"] = "0" * 64
                    elif mutation == "crop":
                        invalid[-1]["crop"][0] = 10000
                    elif mutation == "scale":
                        invalid[-1]["scale"] = 0
                    elif mutation == "missing":
                        invalid.pop()
                    elif mutation == "duplicate":
                        invalid[-1] = deepcopy(invalid[0])
                    else:
                        invalid[-1]["item_kind"] = "weapon"
                    with self.assertRaises(ValueError):
                        module.item_assets(invalid, paths, output)
                    self.assertEqual({path: path.read_bytes() for path in saved}, saved)


if __name__ == "__main__":
    unittest.main()
