"""Three new exact-identity pixel families retain original GIF pixels and timing."""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("wf_roster", ROOT / "tools/world_flipper_roster.py")
assert SPEC is not None and SPEC.loader is not None
ART = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ART)


class WorldFlipperRosterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.registry = ART.read_json(ART.REGISTRY)
        cls.upstream = ART.read_json(ART.UPSTREAM)
        cls.catalog = ART.read_json(ART.CATALOG)
        cls.manifest = ART.read_json(ART.OUTPUT / "manifest.json")

    def require_original_gif_cache(self) -> None:
        missing = [source["filename"] for source in self.registry["sources"] if not (ART.CACHE / source["filename"]).is_file()]
        if missing:
            self.skipTest(
                f"Original GIF cache is intentionally untracked; {len(missing)} source file(s) missing under {ART.CACHE}: "
                + ", ".join(missing)
            )

    def test_every_alias_is_the_exact_original_character_and_pinned_three_pose_family(self) -> None:
        ART.validate_registry(self.registry, self.upstream, self.catalog)
        expected = {"nasir": ("211012", "magic_sword_girl", "fire"), "mordiga": ("221008", "desert_wizard", "water"), "falsche": ("361001", "reaper_girl", "dark")}
        self.assertEqual(len(self.registry["sources"]), 9)
        self.assertEqual({hero["game_id"] for hero in self.registry["heroes"]}, set(expected))
        for hero in self.registry["heroes"]:
            self.assertEqual((hero["canonical_id"], hero["dev_name"], hero["element"]), expected[hero["game_id"]])
        for source in self.registry["sources"]:
            self.assertIn(self.registry["mirror_commit"], source["url"])
            self.assertEqual(source["frame_count"], 1 if source["pose"] == "neutral" else 4)
            self.assertEqual(source["durations_ms"], [20] if source["pose"] == "neutral" else [80, 100, 100, 100])
            self.assertTrue(source["genuine_transparency"])

    def test_actual_outputs_are_nine_rgba_pngs_with_one_independent_lf_manifest(self) -> None:
        self.assertEqual(len(self.manifest["assets"]), 9)
        self.assertEqual(self.manifest["source_registry_sha256"], ART.sha256(ART.json_bytes(self.registry)))
        for asset in self.manifest["assets"]:
            path = ROOT / asset["path"]
            self.assertEqual(ART.sha256(path.read_bytes()), asset["sha256"])
            self.assertEqual(asset["cell_size"], [128, 128])
            self.assertEqual(asset["foot_anchor"], [64, 125])
            self.assertEqual(asset["scale"], 3)
            with Image.open(path) as image:
                self.assertEqual(image.mode, "RGBA")
                self.assertEqual(list(image.size), asset["size"])
                self.assertEqual(ART.sha256(image.tobytes()), asset["rgba_sha256"])
                self.assertEqual(list(image.getchannel("A").getbbox()), asset["alpha_bounds"])
                self.assertEqual(image.getchannel("A").getextrema(), (0, 255))
                self.assertEqual(set(image.getchannel("A").tobytes()), {0, 255})
        self.assertNotIn(b"\r\n", ART.REGISTRY.read_bytes())
        self.assertEqual((ART.OUTPUT / "manifest.json").read_bytes(), ART.json_bytes(self.manifest))

    def test_all_twenty_seven_source_frames_preserve_whole_canvas_pixel_clusters(self) -> None:
        self.require_original_gif_cache()
        by_id = {source["id"]: source for source in self.registry["sources"]}
        visited = 0
        for hero in self.registry["heroes"]:
            with Image.open(ART.OUTPUT / hero["game_id"] / "atlas.png") as atlas:
                self.assertEqual(atlas.size, (512, 384))
                index = 0
                for pose in ART.POSES:
                    source = by_id[hero["source_ids"][pose]]
                    raw = (ART.CACHE / source["filename"]).read_bytes()
                    self.assertEqual(ART.sha256(raw), source["sha256"])
                    self.assertEqual(ART.git_blob_sha1(raw), source["git_blob_sha1"])
                    with Image.open(io.BytesIO(raw)) as gif:
                        offset_x = (128 - gif.width * 3) // 2
                        offset_y = 125 - gif.height * 3
                        for frame in range(gif.n_frames):
                            gif.seek(frame)
                            original = gif.convert("RGBA")
                            self.assertEqual(ART.sha256(original.tobytes()), source["frames"][frame]["rgba_sha256"])
                            x, y = index % 4 * 128, index // 4 * 128
                            cell = atlas.crop((x, y, x + 128, y + 128))
                            for sy in range(gif.height):
                                for sx in range(gif.width):
                                    rgba = original.getpixel((sx, sy))
                                    expected = rgba if rgba[3] else (0, 0, 0, 0)
                                    for dy in range(3):
                                        for dx in range(3):
                                            self.assertEqual(cell.getpixel((offset_x + sx * 3 + dx, offset_y + sy * 3 + dy)), expected)
                            bounds = cell.getchannel("A").getbbox()
                            self.assertIsNotNone(bounds)
                            self.assertLessEqual(bounds[3], 125)
                            self.assertEqual(cell.crop((0, 0, offset_x, 128)).getchannel("A").getextrema(), (0, 0))
                            self.assertEqual(cell.crop((0, 125, 128, 128)).getchannel("A").getextrema(), (0, 0))
                            index += 1
                            visited += 1
                for empty in (9, 10, 11):
                    x, y = empty % 4 * 128, empty // 4 * 128
                    self.assertIsNone(atlas.crop((x, y, x + 128, y + 128)).getchannel("A").getbbox())
        self.assertEqual(visited, 27)

    def test_animation_timing_and_pixel_portraits_are_explicit_adaptations(self) -> None:
        for hero in self.registry["heroes"]:
            selected = {asset["kind"]: asset for asset in self.manifest["assets"] if asset["game_id"] == hero["game_id"]}
            animations = selected["hero_atlas"]["animations"]
            self.assertEqual(animations["neutral"], {"first_frame": 0, "frame_count": 1, "durations_ms": [20]})
            self.assertEqual(animations["walk_front"]["first_frame"], 1)
            self.assertEqual(animations["walk_back"]["first_frame"], 5)
            for pose in ("walk_front", "walk_back"):
                self.assertEqual(animations[pose]["durations_ms"], [80, 100, 100, 100])
            portrait = selected["pixel_portrait_adaptation"]
            self.assertFalse(portrait["original_fullshot"])
            self.assertIn("not original full-shot", portrait["adaptation"])
            self.assertEqual((ART.OUTPUT / hero["game_id"] / "idle.png").read_bytes(), (ART.OUTPUT / hero["game_id"] / "portrait.png").read_bytes())
        self.assertTrue(any("skill FX" in line for line in self.manifest["limitations"]))

    def test_offline_rebuild_is_byte_identical_and_source_order_does_not_change_pixels(self) -> None:
        self.require_original_gif_cache()
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(ART.urllib.request, "urlopen") as network:
            output = Path(directory)
            rebuilt = ART.build(output, ART.CACHE, offline=True)
            self.assertEqual(ART.json_bytes(rebuilt), (ART.OUTPUT / "manifest.json").read_bytes())
            self.assertEqual(ART.build(output, ART.CACHE, offline=True, check=True), rebuilt)
            for asset in rebuilt["assets"]:
                relative = Path(asset["game_id"]) / Path(asset["path"]).name
                self.assertEqual((output / relative).read_bytes(), (ART.OUTPUT / relative).read_bytes())
            registry = copy.deepcopy(self.registry)
            registry["sources"].reverse()
            _, expected = ART.produce(self.registry, self.upstream, self.catalog, ART.CACHE)
            _, reordered = ART.produce(registry, self.upstream, self.catalog, ART.CACHE)
            self.assertEqual(expected, reordered)
            network.assert_not_called()

    def test_wrong_alias_pose_geometry_and_source_metadata_fail_before_output(self) -> None:
        for mutate in [
            lambda registry: registry["heroes"][0].update(canonical_id="221008"),
            lambda registry: registry["heroes"][0].update(dev_name="other_character"),
            lambda registry: registry["heroes"][0].update(game_id="../escape"),
            lambda registry: registry["sources"][0].update(sha256="0" * 64),
            lambda registry: registry["sources"][0].update(frame_count=4),
            lambda registry: registry["sources"][0].update(durations_ms=[0]),
            lambda registry: registry["sources"].pop(),
            lambda registry: registry["normalization"].update(scale=3.0),
            lambda registry: registry["normalization"].update(foot_anchor=[64.0, 125.0]),
        ]:
            registry = copy.deepcopy(self.registry)
            mutate(registry)
            with self.assertRaises((ValueError, KeyError)):
                ART.produce(registry, self.upstream, self.catalog, ART.CACHE)

    def test_bad_final_source_and_tampered_output_never_overwrite_a_valid_family(self) -> None:
        self.require_original_gif_cache()
        with tempfile.TemporaryDirectory() as directory:
            cache, output = Path(directory) / "raw", Path(directory) / "output"
            cache.mkdir()
            output.mkdir()
            sentinel = output / "sentinel.png"
            sentinel.write_bytes(b"existing output stays")
            for source in self.registry["sources"]:
                raw = (ART.CACHE / source["filename"]).read_bytes()
                if source is self.registry["sources"][-1]:
                    raw = raw[:-1] + bytes([raw[-1] ^ 1])
                (cache / source["filename"]).write_bytes(raw)
            with self.assertRaisesRegex(ValueError, "fixed SHA256/Git blob"):
                ART.build(output, cache, offline=True)
            self.assertEqual(sentinel.read_bytes(), b"existing output stays")
            self.assertEqual(list(output.iterdir()), [sentinel])
            ART.build(output, ART.CACHE, offline=True)
            (output / "nasir/idle.png").write_bytes(b"tampered")
            with self.assertRaisesRegex(ValueError, "deterministic offline rebuild"):
                ART.build(output, ART.CACHE, offline=True, check=True)

    def test_existing_eighty_five_pngs_keep_their_separate_original_manifests(self) -> None:
        records = ART.read_json(ROOT / "assets/worldflipper/manifest.json")["assets"] + ART.read_json(ROOT / "assets/worldflipper/stages/manifest.json")["assets"]
        self.assertEqual(len(records), 85)
        for record in records:
            self.assertNotIn("/roster/", record["path"])
            self.assertEqual(hashlib.sha256((ROOT / record["path"]).read_bytes()).hexdigest(), record["sha256"])


if __name__ == "__main__":
    unittest.main()
