"""Behavioral checks for the offline shop-observation analyzer (no Godot needed)."""

from __future__ import annotations

import contextlib
import copy
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import analyze_shop_runs as analysis


def run_record(seed: int = 2026, rune: str = "pierce") -> dict:
    return {
        "seed": seed, "rune": rune, "balance_version": "test+core", "policy_version": "test+policy",
        "won": False, "wave": 3, "gold": 119,
        "trace": [{"action": "wave_income", "wave": 1, "gold": 86},
                  {"action": "wave_income", "wave": 2, "gold": 158}],
    }


def event(phase: str, *, wave: int = 1, wallet: int = 10, rerolls: int = 0,
          reason: str | None = None, offers: list | None = None) -> dict:
    offers = copy.deepcopy(offers or [])
    evaluations = []
    for index, offer in enumerate(offers):
        eligible = not offer["sold"] and offer["price"] <= wallet
        evaluations.append({"index": index, **offer, "score": 100.0 if eligible else None,
                            "reason": "eligible" if eligible else ("sold" if offer["sold"] else "insufficient_wallet")})
    return {
        "wave": wave, "phase": phase, "reason": reason or phase, "wallet": wallet,
        "offers": offers, "evaluations": evaluations, "selected_offer_index": None,
        "rerolls": rerolls, "reroll_cost": 3, "reserve": 20, "loadout": [],
        "rune_bag": [], "relic_counts": {},
    }


def observed(run: dict, events: list) -> dict:
    result = copy.deepcopy(run)
    result["shop_observation_schema_version"] = analysis.OBSERVATION_SCHEMA
    result["shop_observations"] = events
    return result


TARGET = {"id": "pierce", "kind": "rune", "price": 20, "sold": False}
FILLERS = [{"id": identity, "kind": "weapon", "price": 1, "sold": False}
           for identity in ("bone", "frost", "ember")]


class ShopAnalysisTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.serial = 0

    def file(self, text: str) -> Path:
        self.serial += 1
        path = self.directory / f"runs-{self.serial}.jsonl"
        path.write_text(text, encoding="utf-8")
        return path

    def dataset(self, *runs: dict) -> dict:
        return analysis.load_runs(self.file("\n".join(json.dumps(run) for run in runs)))

    def test_engine_banner_and_legacy_unknown_stock(self) -> None:
        path = self.file("Godot Engine v4.7.2.stable.official - https://godotengine.org\n\n"
                         "OpenGL API 4.1 - Compatibility\n" + json.dumps(run_record()))
        report = analysis.analyze(analysis.load_runs(path))
        self.assertEqual(report["overall"]["losses"], 1)
        self.assertEqual(report["overall"]["first_target_equip_after_wave_counts"], {"never": 1})
        self.assertEqual(report["observation_coverage"]["observed"], 0)
        for shop in report["shops"]:
            self.assertEqual(shop["observation_status"], "unknown_unobserved")
            self.assertIsNone(shop["target_seen_in_recorded_stock_snapshots"])
            self.assertFalse(shop["stock_history_complete"])
        self.assertEqual(len(report["early_target_rune_cases"][0]["first_two_shops"]), 2)

    def test_rejects_bad_json_and_nonfinite_numbers(self) -> None:
        for text in ('{"seed":', 'unexpected diagnostic', '[]', '{"x": NaN}', '{"x": 1e999}',
                     '{"seed": 2026, "seed": 2027}'):
            with self.subTest(text=text), self.assertRaises(analysis.AnalysisError):
                analysis.load_runs(self.file(text))

    def test_duplicate_pair_rejected(self) -> None:
        with self.assertRaisesRegex(analysis.AnalysisError, "duplicate.*seed,rune"):
            self.dataset(run_record(), run_record())

    def test_mixed_versions_rejected(self) -> None:
        for field in ("balance_version", "policy_version", "shop_observation_schema_version"):
            first, second = run_record(), run_record(2027)
            if field == "shop_observation_schema_version":
                second = observed(second, [])
            else:
                second[field] += "+changed"
            with self.subTest(field=field), self.assertRaisesRegex(analysis.AnalysisError, "mixed"):
                self.dataset(first, second)

    def test_stock_presence_wallet_and_rejection_evidence(self) -> None:
        offers = [TARGET, *[{**offer, "sold": True} for offer in FILLERS]]
        events = [event("initial", offers=offers), event("decision", offers=offers),
                  event("stop_buying", reason="no_eligible_offer", offers=offers),
                  event("stop_reroll", reason="reserve_budget", offers=offers)]
        report = analysis.analyze(self.dataset(observed(run_record(), events)))
        shop = report["shops"][0]
        self.assertTrue(shop["target_seen_in_recorded_stock_snapshots"])
        self.assertTrue(shop["stock_history_complete"])
        self.assertEqual(len(shop["stock_snapshots"]), 1)
        self.assertEqual(len(shop["target_wallet_shortfall_occurrences"]), 4)
        self.assertEqual(shop["decision_rejection_reason_counts"], {"insufficient_wallet": 1, "sold": 3})
        target = shop["target_events"][1]["targets"][0]
        self.assertIsNone(target["score"])
        self.assertEqual(target["reason"], "insufficient_wallet")

    def test_partial_stock_snapshots_remain_incomplete(self) -> None:
        for count in (0, 1, 3):
            offers = [TARGET, *FILLERS][:count]
            with self.subTest(offer_count=count):
                events = [event("initial", offers=offers),
                          event("stop_reroll", reason="reserve_budget", offers=offers)]
                shop = analysis.analyze(self.dataset(observed(run_record(), events)))["shops"][0]
                self.assertFalse(shop["stock_history_complete"])
                self.assertEqual(shop["stock_snapshots"][0]["offer_count"], count)
                self.assertEqual(shop["observation_status"], "observed")
        events = [event("initial", offers=[TARGET, *FILLERS]),
                  event("reroll", rerolls=1, offers=FILLERS),
                  event("stop_reroll", rerolls=1, reason="reroll_limit", offers=FILLERS)]
        shop = analysis.analyze(self.dataset(observed(run_record(), events)))["shops"][0]
        self.assertFalse(shop["stock_history_complete"])

    def test_affordable_policy_rejection_and_late_first_equip(self) -> None:
        run = run_record(2032, "blast")
        target = {**TARGET, "id": "blast"}
        decision = event("decision", wave=2, wallet=30, offers=[target])
        decision["evaluations"][0].update(score=None, reason="rune_slots_reserved")
        run["trace"].append({"action": "equip", "wave": 3, "rune": "blast", "slot": 0})
        report = analysis.analyze(self.dataset(observed(run, [
            event("initial", wave=1), event("stop_reroll", wave=1, reason="reroll_limit"),
            event("initial", wave=2, wallet=30, offers=[target]), decision,
            event("stop_reroll", wave=2, reason="policy_saturated", wallet=30, offers=[target]),
        ])))
        case = report["early_target_rune_cases"][0]
        self.assertEqual(case["first_target_equip_after_wave"], 3)
        first, second = case["first_two_shops"]
        self.assertFalse(first["target_seen_in_recorded_stock_snapshots"])
        self.assertTrue(second["target_seen_in_recorded_stock_snapshots"])
        self.assertEqual(second["target_wallet_shortfall_occurrences"], [])
        self.assertEqual(second["decision_rejection_reason_counts"], {"rune_slots_reserved": 1})

    def test_missing_reroll_snapshot_does_not_claim_complete_stock_history(self) -> None:
        events = [event("initial"), event("stop_reroll", reason="reroll_limit", rerolls=2)]
        shop = analysis.analyze(self.dataset(observed(run_record(), events)))["shops"][0]
        self.assertFalse(shop["stock_history_complete"])
        self.assertFalse(shop["target_seen_in_recorded_stock_snapshots"])

    def test_stop_reroll_codes_counted_without_enum_assumptions(self) -> None:
        events = []
        reasons = ["reroll_limit", "policy_saturated", "insufficient_reroll_funds", "reserve_budget",
                   "runtime_reroll_rejected", "future_stop_reason"]
        for wave, reason in enumerate(reasons, 1):
            events.extend([event("initial", wave=wave), event("stop_reroll", wave=wave, reason=reason)])
        report = analysis.analyze(self.dataset(observed(run_record(), events)))
        self.assertEqual(report["stop_reroll_by_wave"]["5"], {"runtime_reroll_rejected": 1})
        self.assertEqual(report["late_stop_reroll_reason_counts"],
                         {"runtime_reroll_rejected": 1, "future_stop_reason": 1})

    def test_incomplete_evaluation_and_rejected_selection_rejected(self) -> None:
        for mutation in ("missing_evaluation", "selected_rejected", "wrong_offer", "nonfinite_score", "eligible_null", "rejected_number"):
            point = event("decision", offers=[TARGET])
            if mutation == "missing_evaluation":
                point["evaluations"] = []
            elif mutation == "selected_rejected":
                point["selected_offer_index"] = 0
            elif mutation == "wrong_offer":
                point["evaluations"][0]["id"] = "bounce"
            elif mutation == "nonfinite_score":
                point["evaluations"][0]["score"] = float("inf")
            elif mutation == "eligible_null":
                point["evaluations"][0]["reason"] = "eligible"
            else:
                point["evaluations"][0]["score"] = 20.0
            with self.subTest(mutation=mutation), self.assertRaises(analysis.AnalysisError):
                self.dataset(observed(run_record(), [point]))

    def test_baseline_allows_only_named_observation_and_policy_fields(self) -> None:
        old = run_record()
        new = observed(old, [])
        new["policy_version"] = "test+instrumented-policy"
        new["policy_change_note"] = "observation-only"
        result = analysis.analyze(self.dataset(new), self.dataset(old))["baseline_comparison"]
        self.assertTrue(result["trace_identical"])
        self.assertTrue(result["all_legacy_fields_identical"])
        self.assertEqual(result["before"]["legacy_fields_sha256"], result["after"]["legacy_fields_sha256"])
        self.assertNotEqual(result["before"]["file_sha256"], result["after"]["file_sha256"])
        self.assertNotEqual(result["before"]["policy_version"], result["after"]["policy_version"])

    def test_baseline_rejects_trace_outcome_unknown_field_and_numeric_type_changes(self) -> None:
        old = run_record()
        for mutation in ("trace", "outcome", "extra", "type", "balance"):
            new = observed(old, [])
            if mutation == "trace":
                new["trace"][0]["gold"] += 1
            elif mutation == "outcome":
                new["won"] = True
            elif mutation == "extra":
                new["unapproved_new_field"] = 1
            elif mutation == "type":
                new["trace"][0]["gold"] = 86.0
            else:
                new["balance_version"] += "+changed"
            with self.subTest(mutation=mutation), self.assertRaises(analysis.AnalysisError):
                analysis.analyze(self.dataset(new), self.dataset(old))

    def test_baseline_pair_keys_must_match_exactly(self) -> None:
        for new in (self.dataset(run_record(2027)), self.dataset(run_record(), run_record(2027))):
            with self.assertRaisesRegex(analysis.AnalysisError, "pair keys differ"):
                analysis.analyze(new, self.dataset(run_record()))

    def test_cli_is_deterministic_and_does_not_overwrite_input(self) -> None:
        path = self.file(json.dumps(run_record()))
        output = self.directory / "summary.json"
        args = [str(path), "--baseline", str(path), "--output", str(output)]
        self.assertEqual(analysis.main(args), 0)
        first = output.read_bytes()
        self.assertEqual(analysis.main(args), 0)
        self.assertEqual(first, output.read_bytes())
        before = path.read_bytes()
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as raised:
            analysis.main([str(path), "--output", str(path)])
        self.assertEqual(raised.exception.code, 2)
        self.assertEqual(before, path.read_bytes())


if __name__ == "__main__":
    unittest.main()
