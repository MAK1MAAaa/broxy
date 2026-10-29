"""Pinned hero-art identity, transparent animation and offline processor regressions."""
from __future__ import annotations

from copy import deepcopy
import fnmatch
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
HEROES = {
    "clarisse": ("克拉莉丝", "613f839669c13805af11a7b5498cebf4fdf8dc81cc48b9e0cfec0e11058f5c80", "0f269e154bc221f3985fc372953a0a07bf5933df640f2a097016c1b7759dd718"),
    "celtie": ("希尔媞", "d2ba5a249b51c0df5bd74e30c822393db21374318e9a7eb5268bb71a5db29fa2", "d3905f8017533f5592faa511d844d1d2f88802d6b8fe8cdf21f817672223935b"),
    "hanabi": ("花火", "ef21a79538ece64b707de8a75ccd4de7dc1c68b5b7034e0722c24e5995c49511", "0f5c4d815a1a2dc56c7ccbdf27c47345afc447b628a19216986dbeb9f0e1da30"),
}
POSES = ("neutral", "walk_front", "walk_back")


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def processor():
    spec = importlib.util.spec_from_file_location("hero_asset_test_module", ROOT / "tools/world_flipper_heroes.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def synthetic_sources(directory: Path) -> tuple[list[dict], dict[str, Path]]:
    """Create independent asymmetric canvases, including transparent unused source rows."""
    sources = deepcopy(read(ROOT / "tools/world_flipper_heroes.json")["sources"])
    paths: dict[str, Path] = {}
    for source in sources:
        path = directory / source["filename"]
        if source["kind"] == "hero_portrait":
            source["source_size"] = [13, 17]
            image = Image.new("RGBA", (13, 17))
            ImageDraw.Draw(image).rectangle((1, 2, 9, 13), fill=(91, 40, 140, 255))
            image.putpixel((10, 14), (91, 40, 140, 128))
            image.save(path)
        else:
            frames: list[Image.Image] = []
            for index in range(source["frame_count"]):
                image = Image.new("RGBA", tuple(source["source_size"]))
                ImageDraw.Draw(image).rectangle((2 + index, 3, 11 + index, 15), fill=(22 + index * 41, 81, 144, 255))
                image.putpixel((1, 1 + index), (91, 40, 140, 255))
                frames.append(image)
            frames[0].save(path, save_all=True, append_images=frames[1:], duration=source["durations_ms"], loop=0, disposal=2, optimize=False)
        source["sha256"] = sha(path)
        paths[source["id"]] = path
    return sources, paths


class WorldFlipperHeroAssets(unittest.TestCase):
    def test_registry_and_master_manifest_cover_exactly_the_new_hero_family(self) -> None:
        sources = read(ROOT / "tools/world_flipper_heroes.json")["sources"]
        self.assertEqual(len(sources), 12)
        self.assertEqual(len({source["id"] for source in sources}), 12)
        manifest = read(ROOT / "assets/worldflipper/manifest.json")
        self.assertEqual(manifest["revision"], "world-flipper-fan-06")
        self.assertEqual(len(manifest["sources"]), 67)
        self.assertEqual(len(manifest["assets"]), 64)
        self.assertEqual([source for source in manifest["sources"] if source["kind"].startswith("hero_")], sources)
        for hero, (name, _, _) in HEROES.items():
            selected = [source for source in sources if source["character_id"] == hero]
            self.assertEqual(len(selected), 4)
            self.assertEqual({source["pose"] for source in selected}, {*POSES, "portrait"})
            for source in selected:
                self.assertIn(name, source["name"])
                self.assertTrue(source["url"].startswith("https://"))
                self.assertEqual(source["source_page"], "https://wiki.biligame.com/worldflipper/" + name)
                self.assertRegex(source["sha256"], r"^[0-9a-f]{64}$")
                self.assertEqual(Path(source["filename"]).name, source["filename"])
                if source["pose"] in ("walk_front", "walk_back"):
                    self.assertEqual(source["frame_count"], 4)
                    self.assertEqual(source["durations_ms"], [80, 100, 100, 100])

    def test_shipped_pixel_frames_keep_original_identity_and_native_foot_motion(self) -> None:
        records = {record["id"]: record for record in read(ROOT / "assets/worldflipper/manifest.json")["assets"]}
        for hero, (_, idle_sha, atlas_sha) in HEROES.items():
            with self.subTest(hero=hero):
                idle_path = ROOT / f"assets/worldflipper/characters/{hero}/idle.png"
                atlas_path = idle_path.with_name("atlas.png")
                self.assertEqual(sha(idle_path), idle_sha)
                self.assertEqual(sha(atlas_path), atlas_sha)
                with Image.open(idle_path) as raw:
                    idle = raw.convert("RGBA")
                with Image.open(atlas_path) as raw:
                    atlas = raw.convert("RGBA")
                self.assertEqual(idle.size, (128, 128))
                self.assertEqual(atlas.size, (512, 384))
                self.assertEqual(atlas.crop((0, 0, 128, 128)).tobytes(), idle.tobytes())
                for index in range(9):
                    x, y = index % 4 * 128, index // 4 * 128
                    frame = atlas.crop((x, y, x + 128, y + 128))
                    self.assertEqual(set(frame.getchannel("A").tobytes()), {0, 255})
                    self.assertEqual(frame.getchannel("A").getbbox()[3], 125 if index == 0 or index % 2 == 0 else 119)
                self.assertIsNone(atlas.crop((128, 256, 512, 384)).getchannel("A").getbbox())
                for kind, digest in (("idle", idle_sha), ("atlas", atlas_sha)):
                    record = records[f"hero_{hero}_{kind}"]
                    self.assertEqual(record["sha256"], digest)
                    self.assertEqual(record["cell_size"], [128, 128])
                    self.assertEqual(record["foot_anchor"], [64, 125])
                    self.assertEqual(record["filter"], "nearest")
                motion = records[f"hero_{hero}_atlas"]
                self.assertEqual(motion["frame_count"], 9)
                self.assertEqual(motion["columns"], 4)
                self.assertEqual([motion["animations"][pose]["first_frame"] for pose in POSES], [0, 1, 5])
                self.assertEqual(motion["animations"]["walk_front"]["durations_ms"], [80, 100, 100, 100])

    def test_portraits_are_unmodified_pinned_original_pngs(self) -> None:
        manifest = read(ROOT / "assets/worldflipper/manifest.json")
        records = {record["id"]: record for record in manifest["assets"]}
        for source in read(ROOT / "tools/world_flipper_heroes.json")["sources"]:
            if source["kind"] != "hero_portrait":
                continue
            record = records[source["id"]]
            path = ROOT / record["path"]
            self.assertEqual(sha(path), source["sha256"])
            self.assertEqual(record["sha256"], source["sha256"])
            self.assertEqual(record["filter"], "linear")
            self.assertEqual(record["source_ids"], [source["id"]])
            with Image.open(path) as raw:
                self.assertEqual(raw.mode, "RGBA")
                self.assertEqual(list(raw.size), source["source_size"])
                self.assertEqual(raw.getchannel("A").getextrema(), (0, 255))
                self.assertGreater(len(set(raw.getchannel("A").tobytes())), 2)

    def test_processor_preserves_full_source_canvas_and_frame_order(self) -> None:
        module = processor()
        self.assertEqual(module.ROOT, ROOT)
        with tempfile.TemporaryDirectory(prefix="embers-heroes-") as directory:
            temporary = Path(directory)
            sources, paths = synthetic_sources(temporary)
            output = temporary / "runtime"
            records = module.hero_assets(sources, paths, output)
            self.assertEqual(len(records), 9)
            for hero in HEROES:
                with Image.open(output / f"characters/{hero}/atlas.png") as raw:
                    atlas = raw.convert("RGBA")
                index = 0
                for pose in POSES:
                    source = next(source for source in sources if source.get("character_id") == hero and source["pose"] == pose)
                    with Image.open(paths[source["id"]]) as raw:
                        offset = ((128 - raw.width * 3) // 2, 125 - raw.height * 3)
                        for local in range(source["frame_count"]):
                            raw.seek(local)
                            expected = Image.new("RGBA", (128, 128))
                            expected.alpha_composite(raw.convert("RGBA").resize((raw.width * 3, raw.height * 3), Image.Resampling.NEAREST), offset)
                            x, y = index % 4 * 128, index // 4 * 128
                            self.assertEqual(atlas.crop((x, y, x + 128, y + 128)).tobytes(), expected.tobytes())
                            index += 1
                portrait = next(source for source in sources if source["character_id"] == hero and source["kind"] == "hero_portrait")
                self.assertEqual((output / f"portraits/{hero}.png").read_bytes(), paths[portrait["id"]].read_bytes())
            saved = {record["path"]: record["sha256"] for record in records}
            mixed = list(reversed(sources)) + [{"id": "unrelated_weapon", "kind": "weapon"}]
            rebuilt = module.hero_assets(mixed, paths, output)
            self.assertEqual({record["path"]: record["sha256"] for record in rebuilt}, saved)

    def test_invalid_late_inputs_do_not_overwrite_any_valid_hero_asset(self) -> None:
        module = processor()
        with tempfile.TemporaryDirectory(prefix="embers-hero-invalid-") as directory:
            temporary = Path(directory)
            sources, paths = synthetic_sources(temporary)
            output = temporary / "runtime"
            module.hero_assets(sources, paths, output)
            saved = {path: path.read_bytes() for path in output.rglob("*.png")}
            for mutation in ("sha", "portrait_size", "animation_size", "timing", "frame_count", "pose", "missing", "duplicate", "kind", "character"):
                with self.subTest(mutation=mutation):
                    invalid = deepcopy(sources)
                    if mutation == "sha":
                        invalid[-1]["sha256"] = "0" * 64
                    elif mutation == "portrait_size":
                        invalid[-1]["source_size"][0] += 1
                    elif mutation == "animation_size":
                        invalid[-2]["source_size"][0] += 1
                    elif mutation == "timing":
                        invalid[-2]["durations_ms"][0] += 10
                    elif mutation == "frame_count":
                        invalid[-2]["frame_count"] = 3
                    elif mutation == "pose":
                        invalid[-2]["pose"] = "neutral"
                    elif mutation == "missing":
                        invalid.pop()
                    elif mutation == "duplicate":
                        invalid[-1] = deepcopy(invalid[0])
                    elif mutation == "kind":
                        invalid[-1]["kind"] = "weapon"
                    else:
                        invalid[-1]["character_id"] = "../hanabi"
                    with self.assertRaises(ValueError):
                        module.hero_assets(invalid, paths, output)
                    self.assertEqual({path: path.read_bytes() for path in saved}, saved)

    def test_offline_acquisition_rejects_missing_corrupt_or_escaping_sources(self) -> None:
        module = processor()
        source = deepcopy(read(ROOT / "tools/world_flipper_heroes.json")["sources"][0])
        with tempfile.TemporaryDirectory(prefix="embers-hero-cache-") as directory, patch.object(module, "CACHE", Path(directory)):
            with self.assertRaises(FileNotFoundError):
                module.acquire(source, offline=True)
            (Path(directory) / source["filename"]).write_bytes(b"corrupt")
            with self.assertRaises(ValueError):
                module.acquire(source, offline=True)
            source["filename"] = "../outside.gif"
            with self.assertRaises(ValueError):
                module.acquire(source, offline=True)

    def test_both_export_presets_include_the_nine_raw_pngs(self) -> None:
        text = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
        filters = re.findall(r'^include_filter="([^"]+)"', text, re.M)
        self.assertEqual(len(filters), 2)
        paths = [f"assets/worldflipper/characters/{hero}/{kind}.png" for hero in HEROES for kind in ("idle", "atlas")]
        paths.extend(f"assets/worldflipper/portraits/{hero}.png" for hero in HEROES)
        for include in filters:
            patterns = include.split(",")
            for path in paths:
                self.assertTrue(any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns), path)


if __name__ == "__main__":
    unittest.main()
