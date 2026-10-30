"""Pinned JP equipment facts, explicit unsupported rules and pure rebuilding."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("original_equipment_rules", ROOT / "tools/world_flipper_equipment_rules.py")
assert SPEC is not None and SPEC.loader is not None
RULES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RULES)


class WorldFlipperEquipmentRulesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.lock = RULES.read_json(RULES.SOURCES)
        cls.data = RULES.read_json(RULES.OUTPUT)
        cls.items = {item["id"]: item for item in cls.data["equipment"]}
        cls.catalog = RULES.read_json(ROOT / "data/worldflipper/catalog.json")

    def test_exact_original_counts_and_canonical_identity_join(self) -> None:
        self.assertEqual(self.data["counts"], {"equipment": 426, "ability_rows": 886, "ability_row_width": 123,
            "enhanced_equipment": 29, "enhancement_rows": 108, "enhancement_row_width": 126, "stance_metadata": 424})
        self.assertEqual(set(self.items), {item["id"] for item in self.catalog["equipment"]})
        for original in self.catalog["equipment"]:
            item = self.items[original["id"]]
            self.assertEqual(item["dev_name"], original["dev_name"])
            self.assertEqual(item["name_jp"], original["name_jp"])
            self.assertEqual(item["ability_soul_id"], original["id"])
            self.assertEqual(item["image_resource_ref"], original["resource_ref"])
            self.assertEqual(item["base_stats"], original["base_stats"])
        self.assertFalse(self.data["complete_gameplay_implementation"])

    def test_all_primary_sources_are_pinned_to_the_final_jp_commit(self) -> None:
        self.assertEqual(self.lock["commit"], "1d45b529ef078ba9b1f876d4588debd0c8a9a214")
        self.assertEqual(self.lock["asset_version"], "1.780.40")
        self.assertEqual(self.lock["region"], "JP")
        self.assertEqual(len(self.lock["sources"]), 7)
        for source in self.lock["sources"]:
            self.assertIn(self.lock["commit"], source["url"])
            self.assertEqual(len(source["sha256"]), 64)
            self.assertEqual(Path(source["cache_filename"]).name, source["cache_filename"])
            self.assertGreater(source["bytes"], 0)
        ability = next(source for source in self.lock["sources"] if source["id"] == "ability_soul")
        self.assertEqual(ability["path"], "orderedmap/ability/ability_soul.json")
        self.assertEqual(ability["records"], 426)

    def test_soul_and_enhancement_formats_never_share_the_wrong_column_width(self) -> None:
        rows = []
        enhanced = []
        for item in self.items.values():
            rows.extend(item["rules"])
            enhanced.extend(item["enhancement"]["raw_rule_rows"])
        self.assertEqual(len(rows), 886)
        self.assertTrue(all(len(rule["raw_fields"]) == 123 for rule in rows))
        self.assertEqual(len(enhanced), 108)
        self.assertTrue(all(len(row) == 126 for row in enhanced))
        self.assertEqual(self.data["opcode_inventory"]["instant"]["32"], 210)
        with self.assertRaisesRegex(ValueError, "123-column"):
            RULES.parse_rule("unknown", ["0"] * 126)

    def test_camping_knife_and_moon_dance_read_real_original_parameters(self) -> None:
        bone = self.items["3010053"]["rules"]
        self.assertEqual(bone[0]["semantic"]["effect"], {"operation": "skill_charge_speed_ratio", "jp_opcode": 35,
            "target": {"kind": "party_group", "group": "Black"}, "amount_base": 0.05, "amount_maximum": 0.10, "unit": "ratio"})
        self.assertEqual(bone[1]["unlock_level"], 5)
        self.assertEqual(bone[1]["semantic"]["effect"]["amount_maximum"], 0.35)
        moon = self.items["5030036"]["rules"][0]["semantic"]
        self.assertEqual(moon["event"]["kind"], "party_group_count")
        self.assertEqual(moon["event"]["count_maximum"], 2.0)
        self.assertEqual(moon["event"]["stack_limit"], 3)
        self.assertAlmostEqual(moon["effect"]["stack_cap_maximum"], 0.6)
        self.assertEqual(moon["effect"]["target"]["group"], "Blue")

    def test_conditional_old_equipment_preserves_revive_power_flip_and_party_rules(self) -> None:
        staff = self.items["5060034"]["rules"]
        self.assertEqual(staff[0]["semantic"]["conditions"], [{"kind": "party_group_count_at_least", "group": "Black", "count": 6.0}])
        self.assertEqual(staff[0]["semantic"]["event"]["kind"], "character_revived")
        self.assertEqual(staff[0]["raw_fields"][24], "14")
        self.assertEqual(staff[0]["semantic"]["effect"]["stack_cap_maximum"], 2.0)
        bow = self.items["5040026"]["rules"]
        self.assertEqual(bow[0]["semantic"]["event"]["count_maximum"], 3.0)
        self.assertAlmostEqual(bow[0]["semantic"]["effect"]["stack_cap_maximum"], 1.4)
        self.assertEqual(bow[1]["unlock_level"], 3)
        self.assertEqual(bow[1]["semantic"]["effect"]["operation"], "skill_gauge_ratio")
        self.assertEqual(self.items["5020037"]["rules"][0]["semantic"]["effect"]["amount_maximum"], 1.6)
        self.assertEqual(self.items["4050031"]["rules"][1]["semantic"]["event"]["stack_limit"], 20)
        self.assertEqual(self.items["5030039"]["rules"][0]["semantic"]["effect"]["stack_cap_maximum"], 1.2)
        amulet = self.items["5090030"]["rules"][0]
        self.assertEqual(amulet["raw_fields"][24], "19")
        self.assertEqual(amulet["semantic"]["event"]["kind"], "skill_activation")
        self.assertEqual(amulet["semantic"]["effect"]["stack_cap_maximum"], 1.0)

    def test_elements_have_explicit_secondary_evidence_instead_of_target_guessing(self) -> None:
        expected = {"3010053": "dark", "5030036": "water", "5060034": "dark", "5040026": "light",
                    "5020037": "dark", "4050031": "light", "5030039": "light", "5090030": "water"}
        for identifier, element in expected.items():
            self.assertEqual(self.items[identifier]["element"], element)
            self.assertIn("secondary Wiki", self.items[identifier]["element_evidence"]["evidence_level"])
        for identifier, item in self.items.items():
            if identifier not in expected:
                self.assertIsNone(item["element"])
                self.assertEqual(item["element_evidence"]["status"], "unknown")

    def test_unreviewed_original_instructions_never_become_generic_runtime_effects(self) -> None:
        self.assertEqual(self.data["semantic_coverage"], {"reviewed_equipment": 8, "unsupported_equipment": 418, "reviewed_rows": 21, "unsupported_rows": 865})
        for item in self.items.values():
            for rule in item["rules"]:
                self.assertEqual(rule["runtime_support"], "not_claimed_by_extractor")
                if item["id"] not in RULES.REVIEWED_IDS:
                    self.assertIsNone(rule["semantic"])
                    self.assertEqual(rule["semantic_status"], "unsupported")
                    self.assertIn("No generic runtime rule", rule["unsupported_reason"])
        # Even a recognized opcode is unsupported outside its reviewed context.
        row = self.items["3010053"]["rules"][0]["raw_fields"]
        self.assertIsNone(RULES.parse_rule("not-a-reviewed-equipment", row)["semantic"])

    def test_only_the_active_trigger_branch_is_exposed_for_translation(self) -> None:
        for item in self.items.values():
            for rule in item["rules"]:
                mode = rule["trigger_mode_code"]
                self.assertEqual(list(rule["active_blocks"]), RULES.ACTIVE_BLOCKS[mode])
                for name, block in rule["active_blocks"].items():
                    start, end = RULES.BLOCKS[name]
                    self.assertEqual(block["raw_fields"], rule["raw_fields"][start:end])
                if mode == "1":
                    self.assertNotIn("instant_content", rule["active_blocks"])
                if mode == "2":
                    self.assertEqual(list(rule["active_blocks"]), ["opening"])

    def test_offline_loader_rejects_missing_and_corrupt_sources_without_network(self) -> None:
        raw = b'{"one": [["original"]]}\n'
        source = {"id": "fixture", "cache_filename": "fixture.json", "url": "https://example.invalid/original",
                  "sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw), "records": 1}
        with tempfile.TemporaryDirectory() as directory, patch.object(RULES.urllib.request, "urlopen") as network:
            cache = Path(directory)
            with self.assertRaises(FileNotFoundError):
                RULES.acquire(source, cache, True)
            path = cache / source["cache_filename"]
            path.write_bytes(raw)
            self.assertEqual(RULES.acquire(source, cache, True), {"one": [["original"]]})
            path.write_bytes(raw.replace(b"original", b"modified"))
            with self.assertRaisesRegex(ValueError, "checksum or size"):
                RULES.acquire(source, cache, True)
            network.assert_not_called()

    def test_full_offline_rebuild_is_byte_identical(self) -> None:
        if not all((RULES.CACHE / source["cache_filename"]).is_file() for source in self.lock["sources"]):
            self.skipTest("Pinned raw cache is absent; the CLI can acquire it before offline rebuilding")
        rebuilt = RULES.rebuild(self.lock, RULES.CACHE, True)
        self.assertEqual(RULES.encoded(rebuilt), RULES.OUTPUT.read_bytes())


if __name__ == "__main__":
    unittest.main()
