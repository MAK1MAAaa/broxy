"""Offline source-to-resource checks, including adversarial normalization changes."""

from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("equipment_bindings", ROOT / "tools/audit_world_flipper_equipment_bindings.py")
assert SPEC is not None and SPEC.loader is not None
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


class EquipmentBindingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.rules = AUDIT.read_json(ROOT / AUDIT.RULES_DOCUMENT)
        cls.document = AUDIT.read_json(ROOT / AUDIT.ADAPTATIONS)
        cls.originals = {item["id"]: item for item in cls.rules["equipment"]}
        cls.bindings = {item["game_id"]: item for item in cls.document["equipment"]}

    def audit(self, **kwargs: object) -> dict:
        return AUDIT.audit(root=ROOT, **kwargs)

    def change_resource(self, game_id: str, old: str, new: str) -> dict[str, str]:
        path = f"data/weapons/{game_id}.tres"
        text = (ROOT / path).read_text(encoding="utf-8")
        self.assertIn(old, text)
        return {path: text.replace(old, new, 1)}

    def test_real_bindings_are_offline_and_separate_adaptation_from_execution(self) -> None:
        with mock.patch("urllib.request.urlopen", side_effect=AssertionError("No network is allowed")):
            result = self.audit()
        self.assertTrue(result["passed"])
        self.assertEqual((result["equipment"], result["retained_source_rows"], result["primary_project_bindings"], result["unmapped_unlock_5_rows"]), (5, 9, 6, 3))
        self.assertEqual(set(result["bindings"]), {"bow_0006", "sword_0005", "book_0002", "fist_0006", "staff_0001"})
        self.assertFalse(result["runtime_execution_verified"])
        for game_id, binding in result["bindings"].items():
            self.assertEqual(binding["canonical_id"], self.bindings[game_id]["canonical_id"])
            self.assertEqual(binding["source_commit"], AUDIT.COMMIT)
            self.assertEqual(binding["rank_weights"], [1, 2, 4])
            self.assertEqual(binding["status"], "partial")
            self.assertFalse(binding["original_progression_complete"])
            self.assertFalse(binding["original_awakening_complete"])

    def test_primary_amounts_and_actual_beneficiaries_match_independent_original_columns(self) -> None:
        expected = {
            "3040006": [(0, "34", "0", "", "47500", "95000")],
            "5010005": [(0, "32", "0", "", "160000", "160000"), (1, "205", "0", "", "15000", "15000")],
            "3050002": [(0, "34", "5", "Black", "22500", "45000")],
            "3070006": [(0, "34", "5", "Red", "22500", "45000")],
            "1060001": [(0, "34", "5", "(None)", "5000", "10000")],
        }
        for identifier, facts in expected.items():
            rows = {row["slot"]: row for row in self.originals[identifier]["rules"] if row["unlock_level"] == 1}
            self.assertEqual(set(rows), {fact[0] for fact in facts})
            for slot, opcode, target, group, lower, upper in facts:
                raw = rows[slot]["raw_fields"]
                self.assertEqual(len(raw), 123)
                self.assertEqual((raw[44], raw[45], raw[46], raw[48], raw[49]), (opcode, target, group, lower, upper))
        resources = self.audit()["bindings"]
        self.assertEqual(resources["bow_0006"]["modifiers"], [{"stat": "skill_damage", "target": "owner", "amount_by_rank": [0.475, 0.95, 1.9]}])
        self.assertEqual(resources["book_0002"]["modifiers"][0]["element"], "dark")
        self.assertEqual(resources["fist_0006"]["modifiers"][0]["element"], "fire")

    def test_normalized_semantic_tampering_is_detected_by_reparsing_raw_fields(self) -> None:
        changed = copy.deepcopy(self.rules)
        item = next(item for item in changed["equipment"] if item["id"] == "3040006")
        item["rules"][0]["semantic"]["effect"]["amount_base"] = 99.0
        with self.assertRaisesRegex(ValueError, "Recomputed normalized rule"):
            self.audit(rules_document=changed)

    def test_all_nine_complete_original_row_hashes_reject_used_and_unused_column_changes(self) -> None:
        source_decoder = AUDIT.decoder(ROOT)
        for identifier in AUDIT.IDENTITIES:
            for index in range(len(self.originals[identifier]["rules"])):
                for column in (48, 81):
                    with self.subTest(equipment=identifier, rule=index, column=column):
                        changed = copy.deepcopy(self.rules)
                        item = next(item for item in changed["equipment"] if item["id"] == identifier)
                        rule = item["rules"][index]
                        rule["raw_fields"][column] = "tampered"
                        rule["source_row_sha256"] = source_decoder.row_fingerprint(rule["raw_fields"])
                        with self.assertRaisesRegex(ValueError, "complete JP equipment row changed"):
                            self.audit(rules_document=changed)

    def test_declared_original_row_digest_cannot_be_replaced_without_the_raw_evidence(self) -> None:
        changed = copy.deepcopy(self.rules)
        item = next(item for item in changed["equipment"] if item["id"] == "1060001")
        item["rules"][0]["source_row_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "Recomputed normalized rule"):
            self.audit(rules_document=changed)

    def test_resource_rank_numbers_cannot_drift_or_reuse_original_maximum_as_project_base(self) -> None:
        for game_id, old, new in [
            ("bow_0006", "[0.475, 0.95, 1.9]", "[0.95, 1.9, 3.8]"),
            ("sword_0005", "[0.15, 0.3, 0.6]", "[0.15, 0.15, 0.15]"),
            ("staff_0001", "[0.05, 0.1, 0.2]", "[0.05, 0.075, 0.1]"),
        ]:
            with self.subTest(game_id=game_id), self.assertRaisesRegex(ValueError, "Resource scope/rates"):
                self.audit(resource_texts=self.change_resource(game_id, old, new))

    def test_owner_and_element_target_tampering_cannot_become_a_global_bonus(self) -> None:
        for game_id, old, new in [
            ("bow_0006", 'equipment_owner = "main"', 'equipment_owner = ""'),
            ("bow_0006", '"target": "owner"', '"target": "party"'),
            ("book_0002", '"element": "dark"', '"element": "fire"'),
            ("fist_0006", '"target": "party_element"', '"target": "owner"'),
        ]:
            with self.subTest(game_id=game_id), self.assertRaises(ValueError):
                self.audit(resource_texts=self.change_resource(game_id, old, new))

    def test_extra_legacy_bonus_and_duplicate_fields_are_rejected(self) -> None:
        path = "data/weapons/bow_0006.tres"
        source = (ROOT / path).read_text(encoding="utf-8")
        for suffix in ['equipment_bonuses = {"skill_damage": 1.0}\n', 'equipment_owner = "main"\n']:
            with self.assertRaises(ValueError):
                self.audit(resource_texts={path: source + suffix})
        with self.assertRaises(ValueError):
            self.audit(resource_texts=self.change_resource("bow_0006", "[0.475, 0.95, 1.9]", "[true, 0.95, 1.9]"))

    def test_resource_canonical_identity_and_icon_cannot_be_swapped(self) -> None:
        for old, new in [('source_id = "3040006"', 'source_id = "5010005"'), ('icon = "bow_0006"', 'icon = "bone"')]:
            with self.assertRaises(ValueError):
                self.audit(resource_texts=self.change_resource("bow_0006", old, new))

    def test_unlock_five_awakening_remains_separate_and_is_never_claimed_implemented(self) -> None:
        for game_id, amount in [("bow_0006", 0.35), ("book_0002", 0.15), ("fist_0006", 0.15)]:
            binding = self.bindings[game_id]
            gaps = [row for row in binding["source_rules"] if row["unlock_level"] == 5]
            self.assertEqual(len(gaps), 1)
            self.assertEqual((gaps[0]["slot"], gaps[0]["original_amount_base"], gaps[0]["original_amount_maximum"]), (1, amount, amount))
            self.assertIsNone(gaps[0]["resource_binding"])
            self.assertEqual(gaps[0]["status"], "independent_unlock_5_slot_unmapped")
            self.assertIn("independent_unlock_5_slot_unmapped", binding["gaps"])
        changed = copy.deepcopy(self.document)
        changed["equipment"][0]["original_awakening_complete"] = True
        with self.assertRaises(ValueError):
            self.audit(adaptations=changed)
        changed = copy.deepcopy(self.rules)
        item = next(item for item in changed["equipment"] if item["id"] == "3040006")
        item["rules"] = item["rules"][:1]
        with self.assertRaisesRegex(ValueError, "Complete independent original rule slots"):
            self.audit(rules_document=changed)

    def test_project_rank_policy_cannot_claim_original_level_or_awakening_mapping(self) -> None:
        for path in [("policy", "original_progression_complete"), ("policy", "original_awakening_complete"), ("policy", "rank", "original_equipment_level_mapping")]:
            changed = copy.deepcopy(self.document)
            target = changed
            for key in path[:-1]:
                target = target[key]
            target[path[-1]] = True
            with self.assertRaises(ValueError):
                self.audit(adaptations=changed)

    def test_staff_same_cast_order_is_explicitly_project_policy_not_source_fact(self) -> None:
        original = self.originals["1060001"]["rules"][0]["semantic"]
        self.assertFalse(original["execution_order_evidence"]["same_cast_damage_order_verified"])
        self.assertEqual(original["event"]["actor_scope"], "owner")
        self.assertEqual(original["event"]["stack_limit"], 4)
        self.assertEqual(self.document["policy"]["staff"]["party_bonus_cap"], 8.0)
        self.assertTrue(self.document["policy"]["staff"]["project_applies_to_current_cast"])
        with self.assertRaises(ValueError):
            self.audit(resource_texts=self.change_resource("staff_0001", '"applies_to_current_cast": true', '"applies_to_current_cast": false'))
        with self.assertRaises(ValueError):
            self.audit(resource_texts=self.change_resource("staff_0001", '"max_stacks": 4', '"max_stacks": 8'))

    def test_registered_catalog_and_production_art_route_are_actual_inputs(self) -> None:
        original_read = Path.read_text
        replacements = {
            ROOT / "scripts/data/game_catalog.gd": ('\tpreload("res://data/weapons/bow_0006.tres"),\n', ""),
            ROOT / "scripts/core/adventure_art.gd": ('"equipment/bow_0006.png"', '"icons/bone.png"'),
        }
        for changed_path, (old, new) in replacements.items():
            text = original_read(changed_path, encoding="utf-8")
            self.assertIn(old, text)
            def read(path: Path, *args: object, **kwargs: object) -> str:
                return text.replace(old, new, 1) if path == changed_path else original_read(path, *args, **kwargs)
            with mock.patch.object(Path, "read_text", read), self.assertRaises(ValueError):
                self.audit()

    def test_actual_icon_bytes_are_checked_without_ignored_original_image_cache(self) -> None:
        original_read = Path.read_bytes
        target = ROOT / "assets/worldflipper/equipment/bow_0006.png"
        altered = bytearray(original_read(target))
        altered[-1] ^= 1
        def read(path: Path) -> bytes:
            return bytes(altered) if path == target else original_read(path)
        with mock.patch.object(Path, "read_bytes", read), self.assertRaisesRegex(ValueError, "Actual equipment icon bytes/size"):
            self.audit()

    def test_returned_review_documents_are_detached_from_fixed_project_policy(self) -> None:
        expected = AUDIT.expected_document(ROOT)
        expected["policy"]["rank"]["multipliers"][0] = 999
        self.assertEqual(AUDIT.expected_document(ROOT)["policy"]["rank"]["multipliers"], [1, 2, 4])
        self.assertTrue(self.audit()["passed"])


if __name__ == "__main__":
    unittest.main()
