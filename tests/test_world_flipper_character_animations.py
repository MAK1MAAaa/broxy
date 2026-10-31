"""Exact canonical GIF identities, immutable bytes and genuine walking animation."""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("character_animations", ROOT / "tools/fetch_world_flipper_character_animations.py")
assert SPEC is not None and SPEC.loader is not None
ART = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ART)


class WorldFlipperCharacterAnimationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.registry = json.loads(ART.REGISTRY.read_text(encoding="utf-8"))
        cls.canonical = json.loads((ROOT / "data/worldflipper/catalog.json").read_text(encoding="utf-8"))

    def test_every_canonical_variant_has_an_explicit_exact_pose_status(self) -> None:
        ART.validate_registry(self.registry, self.canonical)
        self.assertEqual(len(self.registry["characters"]), 505)
        self.assertEqual(len(self.registry["sources"]), 1122)
        self.assertEqual(len(self.registry["missing"]), 131)
        self.assertEqual(self.registry["summary"]["verified_three_pose_characters"], 374)
        self.assertFalse(self.registry["summary"]["full_jp_animation_set_available"])
        self.assertEqual(sum(item["expected_bytes"] for item in self.registry["sources"]), 3527175)

    def test_seasonal_collaboration_and_final_missing_identities_are_not_substituted(self) -> None:
        characters = {item["dev_name"]: item for item in self.registry["characters"]}
        for dev_name in ["battle_maid_xm19", "wind_spgirl_1anv", "kunoichi_1anv", "rem", "emilia", "pecorine", "kinoko"]:
            self.assertTrue(characters[dev_name]["three_pose_sources_verified"], dev_name)
            self.assertTrue(characters[dev_name]["distinct_walking_animation_verified"], dev_name)
        for dev_name in ["megumin", "fire_dragon_zenith", "wind_spgirl_4anv"]:
            self.assertEqual(set(characters[dev_name]["missing_poses"]), ART.POSES)
            self.assertEqual(characters[dev_name]["source_ids"], {})
            self.assertFalse(characters[dev_name]["three_pose_sources_verified"])

    def test_registry_rejects_foreign_identity_unpinned_url_and_duplicate_source(self) -> None:
        mutations = []
        wrong_character = copy.deepcopy(self.registry)
        wrong_character["characters"][0]["dev_name"] = "other_character"
        mutations.append(wrong_character)
        wrong_url = copy.deepcopy(self.registry)
        wrong_url["sources"][0]["url"] = wrong_url["sources"][0]["url"].replace(ART.MIRROR_COMMIT, "main")
        mutations.append(wrong_url)
        duplicate = copy.deepcopy(self.registry)
        duplicate["sources"].append(copy.deepcopy(duplicate["sources"][0]))
        mutations.append(duplicate)
        substituted_pose = copy.deepcopy(self.registry)
        character = substituted_pose["characters"][0]
        character["source_ids"]["walk_front"] = character["source_ids"]["neutral"]
        mutations.append(substituted_pose)
        for registry in mutations:
            with self.assertRaises(ValueError):
                ART.validate_registry(registry, self.canonical)

    def test_cached_original_sources_rebuild_the_complete_verified_registry_offline(self) -> None:
        if not all((ART.CACHE / item["filename"]).is_file() for item in self.registry["sources"]):
            self.skipTest("Original GIF archival cache is local-only; fetch before the offline byte audit")
        rebuilt = copy.deepcopy(self.registry)
        rebuilt["sources"] = [ART.fetch_one(source, ART.CACHE, True) for source in self.registry["sources"]]
        self.assertEqual(ART.summarize(rebuilt), self.registry)
        for source in rebuilt["sources"]:
            raw = (ART.CACHE / source["filename"]).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(), source["sha256"])
            self.assertEqual(ART.git_blob_sha1(raw), source["git_blob_sha1"])

    def test_frame_metadata_preserves_real_transparency_duration_and_lowest_opaque_row(self) -> None:
        for source in self.registry["sources"]:
            self.assertTrue(source["genuine_transparency"])
            self.assertEqual(source["frame_count"], len(source["frames"]))
            self.assertEqual(source["durations_ms"], [frame["duration_ms"] for frame in source["frames"]])
            width, height = source["source_size"]
            for frame in source["frames"]:
                left, top, right, bottom = frame["alpha_bounds"]
                self.assertTrue(0 <= left < right <= width and 0 <= top < bottom <= height)
                low_left, low_top, low_right, low_bottom = frame["opaque_bottom_span"]
                self.assertTrue(left <= low_left < low_right <= right)
                self.assertEqual((low_top, low_bottom), (bottom - 1, bottom))
            if source["pose"] != "neutral":
                self.assertGreater(source["unique_rgba_frames"], 1)
                self.assertTrue(all(duration > 0 for duration in source["durations_ms"]))
                self.assertFalse(source["only_neutral_rgba_frames"])
                self.assertFalse(source["identical_to_neutral_bytes"])

    def test_missing_or_tampered_cache_never_becomes_a_verified_original(self) -> None:
        source = self.registry["sources"][0]
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            result = ART.fetch_one(source, cache, True)
            self.assertEqual(result["availability"], "unavailable_or_invalid")
            self.assertFalse((cache / source["filename"]).exists())
            (cache / source["filename"]).write_bytes(b"0" * source["expected_bytes"])
            result = ART.fetch_one(source, cache, True)
            self.assertEqual(result["availability"], "unavailable_or_invalid")
            self.assertIn("pinned Git blob", result["failure"])

    def test_repeated_neutral_frames_are_explicitly_rejected_as_walking(self) -> None:
        registry = copy.deepcopy(self.registry)
        character = registry["characters"][0]
        sources = {source["id"]: source for source in registry["sources"]}
        neutral = sources[character["source_ids"]["neutral"]]
        walk = sources[character["source_ids"]["walk_front"]]
        walk["frames"] = copy.deepcopy(neutral["frames"])
        walk["sha256"] = neutral["sha256"]
        summarized = ART.summarize(registry)
        self.assertIn(walk["id"], summarized["summary"]["walk_sources_repeating_only_neutral"])
        self.assertFalse(summarized["characters"][0]["distinct_walking_animation_verified"])
        self.assertEqual(summarized["summary"]["distinct_walking_characters"], 373)


if __name__ == "__main__":
    unittest.main()
