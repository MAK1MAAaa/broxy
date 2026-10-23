#!/usr/bin/env python3
"""Analyze recorded shop decisions without inferring unobserved stock or replaying policy."""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import sys
from typing import Any


OBSERVATION_SCHEMA = "shop-observations-v1"
IGNORED_FIELDS = {
    "shop_observation_schema_version", "shop_observations", "policy_change_note", "policy_version"
}
PHASES = {"initial", "reroll", "decision", "stop_buying", "stop_reroll", "purchase_rejected"}
LATE_SHOP_MIN_WAVE = 5


class AnalysisError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AnalysisError(message)


def canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def fingerprint(value: Any) -> str:
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def _object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON field: {key}")
        result[key] = value
    return result


def _nonfinite(value: str) -> None:
    raise AnalysisError(f"non-finite JSON number: {value}")


def _finite_float(value: str) -> float:
    result = float(value)
    require(math.isfinite(result), f"non-finite JSON number: {value}")
    return result


def number(value: Any) -> bool:
    return type(value) in (int, float) and math.isfinite(value)


def _validate_event(event: Any, context: str) -> None:
    require(isinstance(event, dict), f"{context}: event must be an object")
    required = {
        "wave", "phase", "reason", "wallet", "offers", "evaluations", "selected_offer_index",
        "rerolls", "reroll_cost", "reserve", "loadout", "rune_bag", "relic_counts",
    }
    require(required <= event.keys(), f"{context}: missing event fields {sorted(required - event.keys())}")
    require(type(event["wave"]) is int and event["wave"] > 0, f"{context}: invalid wave")
    require(isinstance(event["phase"], str) and event["phase"] in PHASES, f"{context}: unknown phase")
    require(isinstance(event["reason"], str) and bool(event["reason"]), f"{context}: missing reason code")
    for field in ("wallet", "reroll_cost"):
        require(number(event[field]) and event[field] >= 0, f"{context}: invalid {field}")
    require(type(event["rerolls"]) is int and event["rerolls"] >= 0, f"{context}: invalid rerolls")
    require(event["reserve"] is None or number(event["reserve"]), f"{context}: invalid reserve")
    for field in ("offers", "evaluations", "loadout", "rune_bag"):
        require(isinstance(event[field], list), f"{context}: {field} must be an array")
    require(isinstance(event["relic_counts"], dict), f"{context}: relic_counts must be an object")
    offers = event["offers"]
    for offer in offers:
        require(isinstance(offer, dict), f"{context}: offer must be an object")
        require({"id", "kind", "price", "sold"} <= offer.keys(), f"{context}: incomplete offer")
        require(all(isinstance(offer[k], str) and offer[k] for k in ("id", "kind")), f"{context}: invalid offer identity")
        require(number(offer["price"]) and offer["price"] >= 0, f"{context}: invalid price")
        require(type(offer["sold"]) is bool, f"{context}: sold must be boolean")
    indices: set[int] = set()
    for evaluation in event["evaluations"]:
        require(isinstance(evaluation, dict), f"{context}: evaluation must be an object")
        fields = {"index", "id", "kind", "price", "sold", "score", "reason"}
        require(fields <= evaluation.keys(), f"{context}: incomplete evaluation")
        index = evaluation["index"]
        require(type(index) is int and 0 <= index < len(offers) and index not in indices,
                f"{context}: invalid/duplicate evaluation index")
        indices.add(index)
        require(all(evaluation[k] == offers[index][k] for k in ("id", "kind", "price", "sold")),
                f"{context}: evaluation does not match offer {index}")
        require(evaluation["score"] is None or number(evaluation["score"]), f"{context}: invalid score")
        require(isinstance(evaluation["reason"], str) and bool(evaluation["reason"]), f"{context}: missing evaluation reason")
        require((evaluation["score"] is not None) == (evaluation["reason"] == "eligible"),
                f"{context}: eligible needs a numeric score; rejection needs null")
    require(indices == set(range(len(offers))), f"{context}: evaluations must cover every offer")
    selected = event["selected_offer_index"]
    require(selected is None or (type(selected) is int and selected in indices), f"{context}: invalid selected_offer_index")
    if selected is not None:
        evaluation = next(item for item in event["evaluations"] if item["index"] == selected)
        require(evaluation["score"] is not None, f"{context}: selected offer has rejected score")


def load_runs(path: Path) -> dict[str, Any]:
    raw = path.read_bytes()
    records: dict[tuple[int, str], dict[str, Any]] = {}
    for line_number, line in enumerate(raw.decode("utf-8-sig").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("Godot Engine v") or line.startswith("OpenGL API "):
            continue
        context = f"{path}:{line_number}"
        try:
            run = json.loads(line, object_pairs_hook=_object, parse_constant=_nonfinite, parse_float=_finite_float)
        except (ValueError, AnalysisError) as error:
            raise AnalysisError(f"{context}: invalid JSON: {error}") from error
        require(isinstance(run, dict), f"{context}: run must be a JSON object")
        require(type(run.get("seed")) is int and isinstance(run.get("rune"), str) and bool(run["rune"]),
                f"{context}: invalid (seed,rune)")
        key = (run["seed"], run["rune"])
        require(key not in records, f"{context}: duplicate (seed,rune) {key}")
        require(type(run.get("won")) is bool and type(run.get("wave")) is int and run["wave"] > 0, f"{context}: invalid outcome")
        require(isinstance(run.get("trace"), list) and all(isinstance(x, dict) for x in run["trace"]),
                f"{context}: trace must be an object array")
        for event in run["trace"]:
            require(type(event.get("wave")) is int and event["wave"] > 0, f"{context}: invalid trace wave")
            if event.get("action") == "equip":
                require(isinstance(event.get("rune"), str), f"{context}: invalid trace equip rune")
        for field in ("balance_version", "policy_version"):
            require(isinstance(run.get(field), str) and bool(run[field]), f"{context}: missing {field}")
        schema = run.get("shop_observation_schema_version")
        require(schema in (None, OBSERVATION_SCHEMA), f"{context}: unknown observation schema")
        if schema is None:
            require("shop_observations" not in run, f"{context}: observations need a schema version")
        else:
            require(isinstance(run.get("shop_observations"), list), f"{context}: missing shop_observations")
            for index, event in enumerate(run["shop_observations"]):
                _validate_event(event, f"{context} observation[{index}]")
        records[key] = run
    require(bool(records), f"{path}: no run records")
    for field in ("balance_version", "policy_version", "shop_observation_schema_version"):
        require(len({run.get(field) for run in records.values()}) == 1, f"{path}: mixed {field}")
    return {"path": str(path), "sha256": hashlib.sha256(raw).hexdigest(), "records": records}


def legacy_fields(run: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in run.items() if key not in IGNORED_FIELDS}


def first_difference(before: Any, after: Any, path: str = "$") -> str | None:
    if type(before) is not type(after):
        return path + " (type)"
    if isinstance(before, dict):
        if before.keys() != after.keys():
            return path + " (keys)"
        for key in sorted(before):
            difference = first_difference(before[key], after[key], path + "." + key)
            if difference:
                return difference
    elif isinstance(before, list):
        if len(before) != len(after):
            return path + " (length)"
        for index, (left, right) in enumerate(zip(before, after)):
            difference = first_difference(left, right, f"{path}[{index}]")
            if difference:
                return difference
    elif before != after:
        return path
    return None


def metadata(dataset: dict[str, Any]) -> dict[str, Any]:
    records = dataset["records"]
    first = next(iter(records.values()))
    return {
        "path": dataset["path"], "file_sha256": dataset["sha256"], "runs": len(records),
        "balance_version": first["balance_version"], "policy_version": first["policy_version"],
        "shop_observation_schema_version": first.get("shop_observation_schema_version"),
        "legacy_fields_sha256": fingerprint([legacy_fields(records[key]) for key in sorted(records)]),
    }


def compare_baseline(current: dict[str, Any], baseline: dict[str, Any]) -> dict[str, Any]:
    after, before = current["records"], baseline["records"]
    require(after.keys() == before.keys(),
            f"baseline pair keys differ: missing={sorted(before.keys() - after.keys())}, extra={sorted(after.keys() - before.keys())}")
    for key in sorted(before):
        require(before[key]["balance_version"] == after[key]["balance_version"], f"{key}: balance_version changed")
        difference = first_difference(legacy_fields(before[key]), legacy_fields(after[key]))
        require(difference is None, f"{key}: baseline old field changed at {difference}")
    return {
        "paired_runs": len(before), "all_legacy_fields_identical": True,
        "trace_identical": True, "ignored_top_level_fields": sorted(IGNORED_FIELDS),
        "before": metadata(baseline), "after": metadata(current),
    }


def first_equip(run: dict[str, Any]) -> int | None:
    return next((event["wave"] for event in run["trace"]
                 if event.get("action") == "equip" and event.get("rune") == run["rune"]), None)


def analyze_shop(run: dict[str, Any], wave: int) -> dict[str, Any]:
    events = [(index, event) for index, event in enumerate(run.get("shop_observations", [])) if event["wave"] == wave]
    snapshots, target_events, shortfalls, stops = [], [], [], []
    rejection_reasons: Counter[str] = Counter()
    for event_index, event in events:
        evaluations = {item["index"]: item for item in event["evaluations"]}
        targets = []
        for index, offer in enumerate(event["offers"]):
            evaluation = evaluations[index]
            if event["phase"] == "decision" and evaluation["score"] is None:
                rejection_reasons[evaluation["reason"]] += 1
            if offer["kind"] != "rune" or offer["id"] != run["rune"]:
                continue
            target = {"index": index, "price": offer["price"], "sold": offer["sold"],
                      "affordable": event["wallet"] >= offer["price"], "score": evaluation["score"],
                      "reason": evaluation["reason"], "selected": event["selected_offer_index"] == index}
            targets.append(target)
            if not offer["sold"] and not target["affordable"]:
                shortfalls.append({"event_index": event_index, "phase": event["phase"], "rerolls": event["rerolls"],
                                   "wallet": event["wallet"], "price": offer["price"], "index": index})
        point = {"event_index": event_index, "phase": event["phase"], "reason": event["reason"],
                 "wallet": event["wallet"], "rerolls": event["rerolls"],
                 "offer_count": len(event["offers"]), "targets": targets}
        if targets:
            target_events.append(point)
        if event["phase"] in ("initial", "reroll"):
            snapshots.append(point)
        if event["phase"] == "stop_reroll":
            stops.append({key: event[key] for key in ("reason", "wallet", "rerolls", "reroll_cost", "reserve", "relic_counts")})
    observed = bool(events)
    snapshot_rerolls = {point["rerolls"] for point in snapshots}
    max_rerolls = max((event["rerolls"] for _, event in events), default=-1)
    complete = observed and any(point["phase"] == "initial" and point["rerolls"] == 0 for point in snapshots)
    complete = complete and all(point["offer_count"] == 4 for point in snapshots)
    complete = complete and snapshot_rerolls == set(range(max_rerolls + 1))
    complete = complete and events[-1][1]["phase"] in ("stop_reroll", "purchase_rejected")
    seen = any(not target["sold"] for point in snapshots for target in point["targets"]) if snapshots else None
    return {
        "seed": run["seed"], "rune": run["rune"], "wave": wave,
        "observation_status": "observed" if observed else "unknown_unobserved",
        "stock_history_complete": bool(complete), "target_seen_in_recorded_stock_snapshots": seen,
        "stock_snapshots": snapshots, "target_events": target_events,
        "target_wallet_shortfall_occurrences": shortfalls,
        "decision_rejection_reason_counts": dict(sorted(rejection_reasons.items())), "stop_reroll": stops,
    }


def analyze(dataset: dict[str, Any], baseline: dict[str, Any] | None = None) -> dict[str, Any]:
    comparison = compare_baseline(dataset, baseline) if baseline else None
    runs = [dataset["records"][key] for key in sorted(dataset["records"])]
    shops, early_cases = [], []
    first_equips: Counter[str] = Counter()
    death_waves: Counter[str] = Counter()
    stops_by_wave: dict[str, Counter[str]] = {}
    late_stops: Counter[str] = Counter()
    for run in runs:
        equipped = first_equip(run)
        first_equips["never" if equipped is None else str(equipped)] += 1
        if not run["won"]:
            death_waves[str(run["wave"])] += 1
        waves = {event["wave"] for event in run["trace"] if event.get("action") == "wave_income"}
        waves.update(event["wave"] for event in run.get("shop_observations", []))
        run_shops = [analyze_shop(run, wave) for wave in sorted(waves)]
        shops.extend(run_shops)
        if equipped is None or equipped > 2:
            early_cases.append({"seed": run["seed"], "rune": run["rune"], "won": run["won"],
                                "death_wave": None if run["won"] else run["wave"],
                                "first_target_equip_after_wave": equipped,
                                "first_two_shops": [shop for shop in run_shops if shop["wave"] <= 2]})
        for shop in run_shops:
            for stop in shop["stop_reroll"]:
                stops_by_wave.setdefault(str(shop["wave"]), Counter())[stop["reason"]] += 1
                if shop["wave"] >= LATE_SHOP_MIN_WAVE:
                    late_stops[stop["reason"]] += 1
    wins = sum(run["won"] for run in runs)
    report = {
        "analysis_schema_version": "shop-analysis-v1", "input": metadata(dataset),
        "overall": {"runs": len(runs), "wins": wins, "losses": len(runs) - wins,
                    "robot_win_fraction": wins / len(runs), "death_wave_counts": dict(sorted(death_waves.items())),
                    "first_target_equip_after_wave_counts": dict(sorted(first_equips.items()))},
        "observation_coverage": {"shops": len(shops), "observed": sum(shop["observation_status"] == "observed" for shop in shops),
                                 "complete_stock_histories": sum(shop["stock_history_complete"] for shop in shops)},
        "shops": shops, "early_target_rune_cases": early_cases,
        "stop_reroll_by_wave": {wave: dict(sorted(counts.items())) for wave, counts in sorted(stops_by_wave.items())},
        "late_shop_min_wave": LATE_SHOP_MIN_WAVE, "late_stop_reroll_reason_counts": dict(sorted(late_stops.items())),
        "limitations": [
            "Fixed-policy robot outcomes are not human win rate or population difficulty.",
            "Unobserved shops have unknown stock; not seen in recorded snapshots is not proof of absence in missing snapshots.",
            "Repeated target events describe observations, not independent stock rolls; only initial/reroll are stock snapshots.",
            "Scores and reasons are reported as recorded; this tool does not rerun policy or infer unrecorded decisions.",
            "Late unspent gold can reflect policy saturation; stop_reroll reason is not a causal economy verdict.",
        ],
    }
    if comparison:
        report["baseline_comparison"] = comparison
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Godot simulation JSONL (engine banner accepted)")
    parser.add_argument("--baseline", type=Path, help="strict paired old-field/trace equivalence baseline")
    parser.add_argument("--output", type=Path, help="write JSON report; default: stdout")
    args = parser.parse_args(argv)
    try:
        report = analyze(load_runs(args.input), load_runs(args.baseline) if args.baseline else None)
        rendered = json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n"
        if args.output:
            require(args.output.resolve() != args.input.resolve(), "output must not overwrite input")
            require(not args.baseline or args.output.resolve() != args.baseline.resolve(), "output must not overwrite baseline")
            args.output.write_text(rendered, encoding="utf-8")
        else:
            sys.stdout.write(rendered)
    except (AnalysisError, OSError, UnicodeError, ValueError) as error:
        parser.exit(2, f"error: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
