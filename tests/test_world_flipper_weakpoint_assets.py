"""Complete original weak-point states and adapted runtime metadata regressions."""
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

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets/worldflipper"
PNG_SHA = "1b907a56c4b71f3a4bc92a01f7f653545f0833e98f7061908c0dfd337419e8ed"


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def processor():
    spec = importlib.util.spec_from_file_location("weakpoint_asset_test", ROOT / "tools/world_flipper_weakpoints.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def synthetic_source(directory: Path) -> tuple[list[dict], dict[str, Path]]:
    sources = deepcopy(read(ROOT / "tools/world_flipper_weakpoints_sources.json")["sources"])
    source = sources[0]
    image = Image.new("RGBA", tuple(source["source_size"]))
    draw = ImageDraw.Draw(image)
    for index, entry in enumerate(source["frames"].values()):
        x, y, width, height = (entry[key] for key in ("x", "y", "w", "h"))
        draw.rectangle((x, y, x + width - 1, y + height - 1), fill=(180, 25 + index * 20, 32, 255))
        image.putpixel((x + 2, y + 2), (255, 255, 255, 128))
    path = directory / source["filename"]
    image.save(path)
    source["sha256"] = sha(path)
    return sources, {source["id"]: path}


class WorldFlipperWeakpointAssets(unittest.TestCase):
    def test_source_and_runtime_atlas_keep_exact_original_identity(self) -> None:
        sources = read(ROOT / "tools/world_flipper_weakpoints_sources.json")["sources"]
        self.assertEqual(len(sources), 1)
        source = sources[0]
        self.assertEqual(source["kind"], "weakpoint_art")
        self.assertEqual(source["url"], "https://worldflipper.jp/demo/src/assets/production/battle/common/layer1.png")
        self.assertEqual(source["source_size"], [2808, 506])
        self.assertEqual(source["sha256"], "e133576809d7d3c3228ea7a26baa9f4389e412728f8358dfaa717e7b9a6006bb")
        self.assertEqual(source["atlas"]["sha256"], "9c0dd3f3f29c663358dbf9a096d10f58ee533fb1257066a9371e27b747a4ee40")
        self.assertEqual(set(source["frames"]), {"sight_a", "sight_b", "sight_c", "broken_a", "broken_b"})
        manifest = read(ART / "manifest.json")
        record = next(record for record in manifest["assets"] if record["id"] == "boss_weakpoint_states")
        self.assertEqual(record["source_ids"], [source["id"]])
        self.assertEqual(record["sha256"], PNG_SHA)
        self.assertEqual(sha(ROOT / record["path"]), PNG_SHA)
        self.assertEqual(record["frame_count"], 3)
        self.assertEqual(record["states"], ["white", "red", "broken"])

    def test_complete_targets_have_four_corners_cross_arms_and_safe_centered_bounds(self) -> None:
        with Image.open(ART / "boss/weakpoint-atlas.png") as raw:
            atlas = raw.convert("RGBA")
        self.assertEqual(atlas.size, (288, 96))
        for index in range(3):
            frame = atlas.crop((index * 96, 0, index * 96 + 96, 96))
            bounds = frame.getchannel("A").getbbox()
            self.assertTrue(min(bounds[:2]) > 0 and max(bounds[2:]) < 96)
            for x, y in ((16, 16), (48, 16), (16, 48), (48, 48)):
                self.assertIsNotNone(frame.crop((x, y, x + 32, y + 32)).getchannel("A").getbbox())
            if index < 2:
                self.assertEqual(frame.getchannel("A").tobytes(), frame.rotate(90).getchannel("A").tobytes())
                for x, y in ((20, 40), (44, 20), (56, 40), (44, 56)):
                    self.assertIsNotNone(frame.crop((x, y, x + 8, y + 8)).getchannel("A").getbbox())
        self.assertNotEqual(atlas.crop((0, 0, 96, 96)).tobytes(), atlas.crop((96, 0, 192, 96)).tobytes())
        self.assertNotEqual(atlas.crop((96, 0, 192, 96)).tobytes(), atlas.crop((192, 0, 288, 96)).tobytes())

    def test_runtime_metadata_declares_the_center_and_project_adaptation(self) -> None:
        metadata = read(ART / "boss/weakpoint-art.json")
        self.assertNotIn("draft_only", metadata)
        self.assertEqual(metadata["revision"], "world-flipper-fan-07")
        definition = metadata["assets"]["weakpoint"]
        self.assertEqual(definition["frame_size"], [96, 96])
        self.assertEqual(definition["center_anchor"], [48, 48])
        self.assertEqual(definition["columns"], 3)
        self.assertEqual(definition["states"], ["white", "red", "broken"])
        self.assertEqual(definition["path"], "res://assets/worldflipper/boss/weakpoint-atlas.png")
        self.assertIn("adaptations", metadata["timing_note"])
        self.assertIn("no original FPS", metadata["timing_note"])
        record = next(record for record in read(ART / "manifest.json")["metadata_files"] if record["path"].endswith("boss/weakpoint-art.json"))
        self.assertEqual(sha(ROOT / record["path"]), record["sha256"])

    def test_source_piece_rotation_trim_and_broken_composition_are_deterministic(self) -> None:
        module = processor()
        with tempfile.TemporaryDirectory(prefix="embers-weakpoint-") as directory:
            temporary = Path(directory)
            sources, paths = synthetic_source(temporary)
            source = sources[0]
            with Image.open(paths[source["id"]]) as raw:
                raw = raw.convert("RGBA")
            for entry in source["frames"].values():
                x, y, width, height = (entry[key] for key in ("x", "y", "w", "h"))
                expected = raw.crop((x, y, x + width, y + height))
                if entry.get("r"):
                    expected = expected.transpose(Image.Transpose.ROTATE_90)
                if "fw" in entry:
                    restored = Image.new("RGBA", (entry["fw"], entry["fh"]))
                    restored.alpha_composite(expected, (-entry.get("fx", 0), -entry.get("fy", 0)))
                    expected = restored
                self.assertEqual(module._frame(raw, entry).tobytes(), expected.tobytes())
            output = temporary / "runtime"
            records = module.weakpoint_assets(sources, paths, output)
            self.assertEqual(len(records), 1)
            saved = {path: path.read_bytes() for path in output.rglob("*") if path.is_file()}
            module.weakpoint_assets(sources + [{"id": "unrelated", "kind": "weapon"}], paths, output)
            self.assertEqual(saved, {path: path.read_bytes() for path in saved})

    def test_invalid_source_or_late_broken_matrix_never_overwrites_valid_outputs(self) -> None:
        module = processor()
        with tempfile.TemporaryDirectory(prefix="embers-weakpoint-invalid-") as directory:
            temporary = Path(directory)
            sources, paths = synthetic_source(temporary)
            output = temporary / "runtime"
            module.weakpoint_assets(sources, paths, output)
            saved = {path: path.read_bytes() for path in output.rglob("*") if path.is_file()}
            for mutation in ("sha", "crop", "rotation", "trim", "layout", "missing", "duplicate", "singular", "scale"):
                invalid = deepcopy(sources)
                source = invalid[0]
                if mutation == "sha":
                    source["sha256"] = "0" * 64
                elif mutation == "crop":
                    source["frames"]["broken_b"]["x"] = 100000
                elif mutation == "rotation":
                    source["frames"]["broken_b"]["r"] = 1
                elif mutation == "trim":
                    source["frames"]["broken_b"]["fw"] = -1
                elif mutation == "layout":
                    source["center_anchor"] = [0, 0]
                elif mutation == "missing":
                    source["frames"].pop("sight_c")
                elif mutation == "duplicate":
                    invalid.append(deepcopy(source))
                elif mutation == "singular":
                    source["parts"]["broken"]["bar_piece_matrices"][-1] = {key: 0 for key in ("a", "b", "c", "d", "x", "y")}
                else:
                    source["parts"]["broken"]["global_scale_fixed4096"] = -1
                with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                    module.weakpoint_assets(invalid, paths, output)
                self.assertEqual(saved, {path: path.read_bytes() for path in saved})

    def test_both_export_presets_include_the_atlas_and_runtime_metadata(self) -> None:
        filters = re.findall(r'^include_filter="([^"]+)"', (ROOT / "export_presets.cfg").read_text(encoding="utf-8"), re.M)
        self.assertEqual(len(filters), 2)
        for include in filters:
            for filename in ("weakpoint-atlas.png", "weakpoint-art.json"):
                path = "assets/worldflipper/boss/" + filename
                self.assertTrue(any(fnmatch.fnmatchcase(path, pattern) for pattern in include.split(",")), path)


if __name__ == "__main__":
    unittest.main()
