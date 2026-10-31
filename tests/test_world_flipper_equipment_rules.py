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
                    "5020037": "dark", "4050031": "light", "5030039": "light", "5090030": "water",
                    "5010012": "fire", "5030005": "all", "5010004": "dark", "5020009": "thunder",
                    "5050009": "fire", "3010007": "water", "5020024": "all", "5010011": "light",
                    "3040006": "all", "5010005": "all", "3050002": "dark", "3070006": "fire", "1060001": "all"}
        for identifier, element in expected.items():
            self.assertEqual(self.items[identifier]["element"], element)
            self.assertIn("secondary Wiki", self.items[identifier]["element_evidence"]["evidence_level"])
        for identifier, item in self.items.items():
            if identifier not in expected:
                self.assertIsNone(item["element"])
                self.assertEqual(item["element_evidence"]["status"], "unknown")

    def test_unreviewed_original_instructions_never_become_generic_runtime_effects(self) -> None:
        self.assertEqual(self.data["semantic_coverage"], {"reviewed_equipment": 21, "unsupported_equipment": 405, "reviewed_rows": 44, "unsupported_rows": 842})
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

    def test_all_reviewed_semantics_lock_the_entire_original_row_not_only_an_opcode(self) -> None:
        self.assertEqual(sum(len(rows) for rows in RULES.REVIEWED_ROWS.values()), 44)
        for identifier in RULES.REVIEWED_IDS:
            for rule in self.items[identifier]["rules"]:
                row = rule["raw_fields"]
                self.assertEqual(rule["source_row_sha256"], RULES.row_fingerprint(row))
                self.assertEqual(rule["source_row_sha256"], RULES.REVIEWED_ROWS[identifier][f"{rule['slot']}:{rule['unlock_level']}"])
                for position in (3, 24, 44, 48, 81, 105, 122):
                    mutated = list(row)
                    mutated[position] = "unreviewed"
                    with self.assertRaisesRegex(ValueError, "complete JP equipment row changed"):
                        RULES.parse_rule(identifier, mutated)

    def test_pierce_during_rules_use_their_own_namespace_and_exact_targets(self) -> None:
        maltet = self.items["5030005"]["rules"][0]
        ameno = self.items["5010004"]["rules"][0]
        for rule in (maltet, ameno):
            self.assertEqual(rule["trigger_mode"], "during")
            self.assertEqual(rule["semantic"]["conditions"], [{"kind": "party_piercing_active", "jp_during_trigger_code": 30}])
            self.assertEqual(rule["semantic"]["effect"]["jp_opcode"], 0)
            self.assertEqual(rule["semantic"]["effect"]["opcode_namespace"], "during_content")
        self.assertEqual(maltet["semantic"]["effect"]["target"]["kind"], "owner")
        self.assertEqual(maltet["semantic"]["effect"]["amount_maximum"], 2.8)
        self.assertEqual(ameno["semantic"]["effect"]["target"]["kind"], "party")
        self.assertEqual(ameno["semantic"]["effect"]["amount_base"], 0.25)
        self.assertEqual(ameno["semantic"]["effect"]["amount_maximum"], 0.5)

    def test_prometheus_preserves_skill_damage_and_ball_flip_gauge_instead_of_haste(self) -> None:
        skill, gauge = self.items["5010012"]["rules"]
        self.assertEqual(skill["semantic"]["effect"]["operation"], "skill_damage_ratio")
        self.assertEqual(skill["semantic"]["effect"]["target"]["group"], "Red")
        self.assertEqual(skill["semantic"]["effect"]["stack_cap_maximum"], 1.0)
        self.assertEqual(gauge["semantic"]["event"]["kind"], "ball_flip_count")
        self.assertEqual(gauge["semantic"]["event"]["count_maximum"], 15.0)
        self.assertEqual(gauge["semantic"]["event"]["stack_limit"], 10)
        self.assertEqual(gauge["semantic"]["effect"]["operation"], "skill_gauge_ratio")
        self.assertEqual(gauge["semantic"]["effect"]["amount_maximum"], 0.1)

    def test_exact_slot_progression_replaces_senji_awakening_without_erasing_independent_slots(self) -> None:
        book = self.items["5050009"]
        level_one = RULES.select_reviewed_rules(book, 1)
        level_three = RULES.select_reviewed_rules(book, 3)
        level_five = RULES.select_reviewed_rules(book, 5)
        self.assertEqual(len(level_one), 1)
        self.assertEqual([row["unlock_level"] for row in level_three], [1, 3])
        self.assertEqual([row["unlock_level"] for row in level_five], [1, 5])
        self.assertEqual(level_five[1]["semantic"]["effect"]["target"]["kind"], "leader")
        self.assertEqual(level_five[1]["semantic"]["effect"]["amount_maximum"], 0.4)
        self.assertEqual(len(RULES.select_reviewed_rules(self.items["5020037"], 3)), 4)
        for level in (0, 6, True, 2.5):
            with self.assertRaises(ValueError):
                RULES.select_reviewed_rules(book, level)
        unreviewed = next(item for item in self.items.values() if item["id"] not in RULES.REVIEWED_IDS)
        with self.assertRaises(ValueError):
            RULES.select_reviewed_rules(unreviewed, 5)

    def test_new_threshold_health_and_punisher_rules_do_not_waive_original_conditions(self) -> None:
        thor = self.items["5020009"]["rules"]
        self.assertEqual(thor[0]["semantic"]["conditions"], [{"kind": "owner_in_group", "group": "Yellow"}])
        self.assertEqual(thor[0]["semantic"]["effect"]["operation"], "break_down_punisher_ratio")
        self.assertEqual(thor[1]["semantic"]["conditions"], [])
        self.assertEqual(thor[1]["semantic"]["effect"]["operation"], "paralysis_punisher_ratio")
        heal, rescue = self.items["5010011"]["rules"]
        self.assertEqual(heal["semantic"]["event"]["kind"], "owner_healed_count")
        self.assertEqual(heal["semantic"]["effect"]["stack_cap_maximum"], 0.5)
        self.assertEqual(rescue["semantic"]["event"]["comparison"], "<=")
        self.assertEqual(rescue["semantic"]["event"]["threshold_maximum"], 0.7)
        self.assertNotIn("count_maximum", rescue["semantic"]["event"])
        self.assertEqual(rescue["semantic"]["effect"]["amount_maximum"], 0.2)
        self.assertEqual(self.items["3010007"]["rules"][0]["semantic"]["effect"]["operation"], "max_health_ratio")
        self.assertEqual(self.items["5020024"]["rules"][0]["semantic"]["effect"]["amount_maximum"], 2.8)

    def test_every_enhancement_remains_explicitly_unsupported_with_full_row_fingerprints(self) -> None:
        rows = 0
        for item in self.items.values():
            enhanced = item["enhancement"]
            self.assertEqual(enhanced["raw_rule_sha256"], [RULES.row_fingerprint(row) for row in enhanced["raw_rule_rows"]])
            if enhanced["raw_rule_rows"]:
                self.assertEqual(enhanced["semantic_status"], "unsupported")
                rows += len(enhanced["raw_rule_rows"])
        self.assertEqual(rows, 108)

    def test_scoped_equipment_retains_owner_party_and_element_targets(self) -> None:
        for identifier, target, group, lower, upper in [
            ("3040006", "owner", "", 0.475, 0.95),
            ("3050002", "party_group", "Black", 0.225, 0.45),
            ("3070006", "party_group", "Red", 0.225, 0.45),
        ]:
            item = self.items[identifier]
            rules = RULES.select_reviewed_rules(item, 5)
            self.assertEqual(len(RULES.select_reviewed_rules(item, 1)), 1)
            self.assertEqual(len(rules), 2)
            self.assertEqual(rules[0]["semantic"]["conditions"], [])
            self.assertEqual(rules[0]["semantic"]["effect"]["target"], {"kind": target, "group": group})
            self.assertEqual(rules[0]["semantic"]["effect"]["operation"], "skill_damage_ratio")
            self.assertEqual(rules[0]["semantic"]["effect"]["amount_base"], lower)
            self.assertEqual(rules[0]["semantic"]["effect"]["amount_maximum"], upper)
            self.assertEqual(rules[1]["unlock_level"], 5)
            self.assertEqual(rules[1]["semantic"]["effect"]["amount_maximum"], 0.35 if identifier == "3040006" else 0.15)
            self.assertEqual(rules[1]["semantic"]["effect"]["target"], rules[0]["semantic"]["effect"]["target"])

    def test_durendal_keeps_independent_attack_and_percent_health_not_flat_health(self) -> None:
        attack, health = RULES.select_reviewed_rules(self.items["5010005"], 1)
        self.assertEqual([attack["slot"], health["slot"]], [0, 1])
        self.assertEqual(attack["semantic"]["effect"]["operation"], "attack_ratio")
        self.assertEqual(attack["semantic"]["effect"]["amount_base"], 1.6)
        self.assertEqual(attack["semantic"]["effect"]["amount_maximum"], 1.6)
        self.assertEqual(health["semantic"]["effect"]["operation"], "max_health_ratio")
        self.assertEqual(health["semantic"]["effect"]["amount_base"], 0.15)
        self.assertEqual(health["semantic"]["effect"]["unit"], "ratio")
        for rule in (attack, health):
            self.assertEqual(rule["semantic"]["effect"]["target"]["kind"], "owner")
            self.assertEqual(rule["semantic"]["event"]["kind"], "initial")

    def test_old_staff_owner_cast_and_party_stacks_do_not_claim_original_capture_order(self) -> None:
        self.assertEqual(len(self.items["1060001"]["rules"]), 1)
        rule = self.items["1060001"]["rules"][0]["semantic"]
        self.assertEqual(rule["event"]["kind"], "skill_activation")
        self.assertEqual(rule["event"]["actor_scope"], "owner")
        self.assertEqual(rule["event"]["count_base"], 1.0)
        self.assertEqual(rule["event"]["stack_limit"], 4)
        self.assertEqual(rule["effect"]["target"], {"kind": "party", "group": "(None)"})
        self.assertEqual(rule["effect"]["amount_base"], 0.05)
        self.assertEqual(rule["effect"]["amount_maximum"], 0.10)
        self.assertEqual(rule["effect"]["stack_cap_base"], 0.20)
        self.assertEqual(rule["effect"]["stack_cap_maximum"], 0.40)
        self.assertFalse(rule["execution_order_evidence"]["same_cast_damage_order_verified"])
        self.assertIn("explicit project adaptation", rule["execution_order_evidence"]["project_current_cast_policy"])

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
