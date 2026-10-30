"""Coverage claims must not turn archived identities into completed gameplay."""

from __future__ import annotations

import copy
import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("wf_coverage", ROOT / "tools/audit_world_flipper_coverage.py")
assert SPEC is not None and SPEC.loader is not None
COVERAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COVERAGE)


class WorldFlipperCoverageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.catalog = json.loads(COVERAGE.CATALOG.read_text(encoding="utf-8"))
        cls.ledger = json.loads(COVERAGE.LEDGER.read_text(encoding="utf-8"))

    def test_every_canonical_identity_is_explicitly_claimed_or_pending(self) -> None:
        checked = COVERAGE.audit(self.catalog, self.ledger)
        self.assertEqual(COVERAGE.encoded(checked), COVERAGE.LEDGER.read_bytes())
        for category, original in COVERAGE.canonical_sets(self.catalog).items():
            claimed = {item["canonical_id"] for item in checked["claims"][category]}
            pending = set(checked["pending_ids"][category])
            self.assertEqual(claimed | pending, set(original))
            self.assertFalse(claimed & pending)
            self.assertEqual(len(pending), checked["counts"][category]["pending"])
            self.assertEqual(len(original), checked["counts"][category]["canonical"])
        self.assertFalse(checked["fully_complete"])

    def test_all_four_existing_characters_keep_original_identity_and_explicit_gaps(self) -> None:
        claims = {item["game_id"]: item for item in self.ledger["claims"]["characters"]}
        for game_id, canonical_id in {"alk": "1", "clarisse": "111003", "celtie": "141001", "hanabi": "211003"}.items():
            self.assertEqual(claims[game_id]["canonical_id"], canonical_id)
            self.assertEqual(claims[game_id]["status"], "partial")
            self.assertTrue(claims[game_id]["remaining_gaps"])
        self.assertTrue(any("驱散" in gap for gap in claims["clarisse"]["remaining_gaps"]))

    def test_old_weapon_skins_cannot_count_as_implemented_original_equipment_effects(self) -> None:
        claims = {item["game_id"]: item for item in self.ledger["claims"]["equipment"]}
        old = {"bone": "3010053", "frost": "5030036", "ember": "5060034", "scatter": "5040026", "crescent": "5020037", "storm": "4050031", "comet": "5030039", "return_ring": "5090030"}
        for game_id, canonical_id in old.items():
            self.assertEqual(claims[game_id]["canonical_id"], canonical_id)
            self.assertEqual(claims[game_id]["status"], "partial")
            self.assertIn("原作装备被动尚未实现", claims[game_id]["remaining_gaps"])
        new = [item for item in claims.values() if item["game_id"] not in old]
        self.assertEqual(len(new), 8)
        self.assertTrue(all(item["status"] == "adapted_playable" for item in new))

    def test_map_background_reuse_is_not_reported_as_all_original_layouts(self) -> None:
        mapped = {item["game_id"]: item for item in self.ledger["claims"]["fields"]}
        self.assertEqual(mapped["reliquary"]["canonical_id"], "sand_ruins")
        self.assertEqual(mapped["mire"]["canonical_id"], "japan_shrine")
        self.assertEqual(mapped["ashland"]["canonical_id"], "sea_ship_boss")
        self.assertEqual(mapped["town"]["canonical_id"], "common_skill_preview")
        self.assertTrue(all(item["status"] == "partial" and item["remaining_gaps"] for item in mapped.values()))
        self.assertFalse(self.ledger["claims"]["layouts"])
        unmapped = {item["game_id"] for item in self.ledger["unmapped_game_content"]}
        self.assertEqual(unmapped, {"glacier", "throne", "tower_peak"})

    def test_invalid_identity_empty_source_and_false_completion_claims_fail(self) -> None:
        mutations = [
            lambda data: data["claims"]["characters"].append(copy.deepcopy(data["claims"]["characters"][0])),
            lambda data: data["claims"]["equipment"][0].update(canonical_id="unknown"),
            lambda data: data["claims"]["equipment"][0].update(source=""),
            lambda data: data["claims"]["characters"][0].update(status="complete"),
            lambda data: data["claims"]["characters"][0].update(canonical_id="111003"),
            lambda data: data["claims"]["fields"][0].update(source="https://example.invalid/incorrect.png"),
            lambda data: data["claims"]["equipment"][0].update(resource="../../outside-workspace.tres"),
        ]
        for mutation in mutations:
            data = copy.deepcopy(self.ledger)
            mutation(data)
            with self.assertRaises(ValueError):
                COVERAGE.audit(self.catalog, data)

    def test_runtime_verification_requires_a_real_successful_report(self) -> None:
        data = copy.deepcopy(self.ledger)
        data["runtime_evidence"] = None
        data["claims"]["equipment"][0]["runtime_verified"] = True
        with self.assertRaisesRegex(ValueError, "concrete validation report"):
            COVERAGE.audit(self.catalog, data)
        data["runtime_evidence"] = {"report": "reports/missing-validation.json", "sha256": "0" * 64}
        with self.assertRaisesRegex(ValueError, "missing, stale or unsuccessful"):
            COVERAGE.audit(self.catalog, data)


if __name__ == "__main__":
    unittest.main()
