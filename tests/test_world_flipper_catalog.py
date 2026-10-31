"""Factual archive completeness and deterministic, fail-closed source loading."""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("world_flipper_catalog_import", ROOT / "tools/import_world_flipper_catalog.py")
assert SPEC is not None and SPEC.loader is not None
IMPORTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(IMPORTER)


class WorldFlipperCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.lock = IMPORTER.load_lock()
        cls.catalog = json.loads(IMPORTER.OUTPUT_PATH.read_text(encoding="utf-8"))

    def test_exact_final_jp_counts_and_identity(self) -> None:
        IMPORTER.validate_catalog(self.catalog, self.lock)
        self.assertEqual(self.catalog["counts"], {"characters": 505, "equipment": 426, "skill_groups": 570, "skills": 1062, "switched_skill_groups": 6, "fields": 247, "layouts": 1422, "floor_groups": 89, "chapters": 12})
        self.assertEqual(self.lock["commit"], "1d45b529ef078ba9b1f876d4588debd0c8a9a214")
        self.assertEqual(self.lock["asset_version"], "1.780.40")
        self.assertEqual(self.lock["region"], "JP")

    def test_source_urls_are_immutable_and_hashed(self) -> None:
        self.assertEqual(len(self.lock["sources"]), 13)
        for source in self.lock["sources"]:
            self.assertIn(self.lock["commit"], source["url"])
            self.assertNotIn("/master/", source["url"])
            self.assertEqual(len(source["sha256"]), 64)
            self.assertGreater(source["bytes"], 0)
            self.assertEqual(Path(source["cache_filename"]).name, source["cache_filename"])

    def test_seasonal_and_collaboration_variants_keep_distinct_original_ids(self) -> None:
        by_dev = {item["dev_name"]: item for item in self.catalog["characters"]}
        for dev in ["megumin", "rem", "wind_spgirl", "wind_spgirl_4anv", "fire_dragon", "fire_dragon_zenith", "stella_copy_4anv"]:
            self.assertIn(dev, by_dev)
        self.assertNotEqual(by_dev["wind_spgirl"]["id"], by_dev["wind_spgirl_4anv"]["id"])
        self.assertNotEqual(by_dev["fire_dragon"]["id"], by_dev["fire_dragon_zenith"]["id"])
        self.assertEqual(len(by_dev), 505)

    def test_every_character_skill_and_action_owner_is_resolved(self) -> None:
        characters = {item["id"]: item for item in self.catalog["characters"]}
        skills = {item["id"]: item for item in self.catalog["skills"]}
        for character in characters.values():
            skill = skills[character["main_skill_id"] + ":1"]
            self.assertIn(character["id"], skill["owner_character_ids"])
            self.assertEqual(character["element"], IMPORTER.ELEMENTS[character["element_code"]])
            self.assertEqual(character["rarity"], int(character["raw_fields"][2]))
            self.assertEqual(character["main_skill_id"], character["raw_fields"][8])
            self.assertNotIn("description", character)
        for skill in skills.values():
            self.assertEqual(len(skill["raw_fields"]), 24)
            self.assertEqual(skill["action_ref"], skill["raw_fields"][7])
            self.assertEqual(skill["action_file"]["path"], "assets/" + skill["action_ref"] + ".action.dsl.json")
            self.assertEqual(len(skill["action_file"]["git_blob_sha1"]), 40)
            self.assertEqual(skill["fact_parameters"], {"gauge_column_4": int(skill["raw_fields"][4]), "gauge_column_5": int(skill["raw_fields"][5]), "unit": "original_skill_gauge"})
            self.assertTrue(set(skill["owner_character_ids"]).issubset(characters))

    def test_equipment_has_original_identity_stats_and_uninterpreted_refs(self) -> None:
        by_dev = {item["dev_name"]: item for item in self.catalog["equipment"]}
        self.assertEqual(by_dev["spear_0005"]["id"], "5030005")
        self.assertEqual(by_dev["axe_0024"]["id"], "5020024")
        for item in by_dev.values():
            self.assertNotIn("implemented", item)
            self.assertNotIn("image_url", item)
            self.assertEqual(item["resource_ref"], item["raw_fields"]["6"])
            self.assertEqual(item["rarity"], int(item["raw_fields"]["11"]))
            self.assertNotIn("7", item["raw_fields"])
            self.assertNotIn("5", item["raw_fields"])
            self.assertTrue(item["base_stats"])

    def test_all_map_layouts_resolve_and_chapters_are_complete(self) -> None:
        maps = self.catalog["maps"]
        fields = {item["id"] for item in maps["fields"]}
        for layout in maps["layouts"]:
            self.assertIn(layout["field_id"], fields)
            self.assertEqual(layout["raw_fields"], [layout["field_id"], layout["terrain_ref"], layout["dev_name"]])
        self.assertEqual([int(item["id"]) for item in maps["chapters"]], list(range(1, 13)))
        self.assertEqual(sum(len(item["raw_rows"]) for item in maps["floor_groups"]), 250)
        self.assertIn("without guessing", self.catalog["field_mapping"]["floors"]["unknown_columns"])

    def test_validator_rejects_missing_duplicate_and_dangling_records(self) -> None:
        cases = [
            lambda data: data["characters"].pop(),
            lambda data: data["equipment"][0].update(id=data["equipment"][1]["id"]),
            lambda data: data["characters"][0].update(main_skill_id="not-an-original-skill"),
            lambda data: data["skills"][0].update(owner_character_ids=["unknown"]),
            lambda data: data["maps"]["layouts"][0].update(field_id="missing-field"),
            lambda data: data["source"].update(commit="master"),
        ]
        for mutation in cases:
            data = copy.deepcopy(self.catalog)
            mutation(data)
            with self.assertRaises(ValueError):
                IMPORTER.validate_catalog(data, self.lock)

    def test_offline_cache_load_is_pure_and_does_not_call_network(self) -> None:
        data = b'{"one": [["source"]]}\n'
        source = {"id": "fixture", "cache_filename": "fixture.json", "format": "json", "records": 1,
                  "url": "https://example.invalid/original.json", "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        with tempfile.TemporaryDirectory() as directory, patch.object(IMPORTER.urllib.request, "urlopen") as request:
            cache = Path(directory)
            path = cache / source["cache_filename"]
            path.write_bytes(data)
            self.assertEqual(IMPORTER.load_source(source, cache, offline=True), {"one": [["source"]]})
            self.assertEqual(path.read_bytes(), data)
            path.write_bytes(b"{}")
            with self.assertRaisesRegex(ValueError, "hash or size mismatch"):
                IMPORTER.load_source(source, cache, offline=True)
            path.unlink()
            with self.assertRaises(FileNotFoundError):
                IMPORTER.load_source(source, cache, offline=True)
            request.assert_not_called()

    def test_download_hash_failure_never_persists_untrusted_bytes(self) -> None:
        source = {"id": "fixture", "cache_filename": "fixture.json", "format": "json", "records": 0,
                  "url": "https://example.invalid/original.json", "bytes": 2, "sha256": "0" * 64}
        with tempfile.TemporaryDirectory() as directory, patch.object(IMPORTER.urllib.request, "urlopen") as request:
            request.return_value.__enter__.return_value.read.return_value = b"{}"
            with self.assertRaisesRegex(ValueError, "Downloaded source hash mismatch"):
                IMPORTER.load_source(source, Path(directory), offline=False)
            self.assertFalse((Path(directory) / source["cache_filename"]).exists())

    def test_normalized_output_is_deterministic_without_hidden_gameplay_status(self) -> None:
        self.assertEqual(IMPORTER.json_bytes(self.catalog), IMPORTER.OUTPUT_PATH.read_bytes())
        self.assertEqual(IMPORTER.json_bytes(self.catalog), IMPORTER.json_bytes(copy.deepcopy(self.catalog)))
        self.assertNotIn("implemented_ids", self.catalog)
        self.assertIn("does not mean gameplay implementation", self.catalog["scope"])


if __name__ == "__main__":
    unittest.main()
