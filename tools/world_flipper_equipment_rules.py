"""Extract original JP equipment rules without inventing unsupported mechanics.

Equipment.c10 references ability_soul, a 123-column rule table shared by weapons
and their cores. The image resource in equipment.c6 is not an ability DSL path.
Only explicitly reviewed JP rule contexts receive semantic operations; all other
instructions remain visible and unsupported. This module does not execute rules.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import urllib.request
from collections import Counter
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "tools/world_flipper_equipment_rules_sources.json"
OUTPUT = ROOT / "data/worldflipper/equipment_rules.json"
CACHE = ROOT / ".tools/wf-equipment-rules/raw"
MAX_SOURCE_BYTES = 16 * 1024 * 1024
BLOCKS: dict[str, tuple[int, int]] = {
    "precondition_1": (3, 10), "precondition_2": (10, 17), "precondition_3": (17, 24),
    "instant_trigger": (24, 36), "instant_precontent": (36, 43), "instant_delay": (43, 44),
    "instant_content": (44, 82), "during_accumulation_trigger": (82, 94), "during_trigger": (94, 105),
    "even_if_owner_dead": (105, 106), "during_content": (106, 120), "opening": (120, 123),
}
ACTIVE_BLOCKS = {
    "0": ["precondition_1", "precondition_2", "precondition_3", "instant_trigger", "instant_precontent", "instant_delay", "instant_content"],
    "1": ["precondition_1", "precondition_2", "precondition_3", "during_accumulation_trigger", "during_trigger", "even_if_owner_dead", "during_content"],
    "2": ["opening"],
}
MODES = {"0": "instant", "1": "during", "2": "opening"}
REVIEWED_IDS = frozenset({"3010053", "5030036", "5060034", "5040026", "5020037", "4050031", "5030039", "5090030"})
REVIEWED_OPS = {"32": "attack_ratio", "34": "skill_damage_ratio", "35": "skill_charge_speed_ratio",
                "55": "power_flip_damage_ratio", "67": "dark_resistance_down_immunity", "70": "lethargy_immunity",
                "209": "deal_max_health_ratio_damage", "211": "skill_gauge_ratio"}
REVIEWED_EVENTS = {"0": "initial", "2": "power_flip_count", "14": "character_revived", "19": "skill_activation", "53": "party_group_count"}


def encoded(value: Any) -> bytes:
    parts = []
    for key, content in value.items():
        if key == "equipment":
            body = "[\n" + ",\n".join("    " + json.dumps(item, ensure_ascii=False, separators=(",", ":")) for item in content) + "\n  ]"
        else:
            body = json.dumps(content, ensure_ascii=False, indent=2).replace("\n", "\n  ")
        parts.append("  " + json.dumps(key) + ": " + body)
    return ("{\n" + ",\n".join(parts) + "\n}\n").encode("utf-8")


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def acquire(source: dict[str, Any], cache: Path, offline: bool) -> Any:
    filename = str(source["cache_filename"])
    size = int(source["bytes"])
    if Path(filename).name != filename or not 0 < size <= MAX_SOURCE_BYTES:
        raise ValueError("Invalid source cache path or size")
    path = cache / filename
    if path.exists():
        if path.stat().st_size != size:
            raise ValueError("Source checksum or size mismatch: " + source["id"])
        data = path.read_bytes()
    elif offline:
        raise FileNotFoundError("Missing offline original table: " + str(path))
    else:
        request = urllib.request.Request(source["url"], headers={"User-Agent": "broxy-original-equipment-rules/1"})
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read(size + 1)
    if len(data) != size or hashlib.sha256(data).hexdigest() != source["sha256"]:
        raise ValueError("Source checksum or size mismatch: " + source["id"])
    result = json.loads(data)
    if len(result) != source["records"]:
        raise ValueError("Original table record count changed")
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    return result


def original_row(value: Any, width: int) -> list[str]:
    if not isinstance(value, list) or len(value) != width or not all(isinstance(item, str) for item in value):
        raise ValueError(f"Expected an original {width}-column string row")
    return value


def original_ratio(value: str) -> float | None:
    return int(value) / 100000.0 if value else None


def _reviewed_operation(equipment_id: str, row: list[str]) -> dict[str, Any] | None:
    """Decode only the reviewed JP contexts, never a cross-region enum fallback."""
    if equipment_id not in REVIEWED_IDS:
        return None
    if row[2] != "0" or row[44] not in REVIEWED_OPS or row[24] not in REVIEWED_EVENTS:
        raise ValueError("A reviewed JP equipment instruction changed; manual review is required")
    if row[10] not in ["", "0"] or row[17] not in ["", "0"]:
        raise ValueError("A reviewed instruction gained unsupported extra conditions")
    conditions = []
    if row[3] == "2":
        conditions.append({"kind": "party_group_count_at_least", "group": row[8], "count": original_ratio(row[6])})
    elif row[3] == "3":
        conditions.append({"kind": "owner_in_group", "group": row[8]})
    elif row[3] not in ["", "0"]:
        raise ValueError("A reviewed instruction gained an unsupported precondition")
    target_code = row[45] or "0"
    targets = {"0": "owner", "1": "party_except_owner", "5": "party_group"}
    if target_code not in targets:
        raise ValueError("A reviewed instruction gained an unsupported target")
    stacks = int(row[31]) if row[31] else None
    lower = original_ratio(row[48])
    upper = original_ratio(row[49])
    result = {
        "conditions": conditions,
        "event": {"kind": REVIEWED_EVENTS[row[24]], "puller_code": row[25], "puller_group": row[26],
                  "count_base": original_ratio(row[27]), "count_maximum": original_ratio(row[28]), "stack_limit": stacks},
        "effect": {"operation": REVIEWED_OPS[row[44]], "jp_opcode": int(row[44]),
                   "target": {"kind": targets[target_code], "group": row[46]},
                   "amount_base": lower, "amount_maximum": upper, "unit": "ratio" if lower is not None else "flag"},
        "evidence": "Pinned JP numeric row, cross-checked against this exact equipment's sourced ability and awakening facts.",
    }
    if stacks is not None and stacks > 0 and lower is not None and upper is not None:
        result["effect"]["stack_cap_base"] = int(row[48]) * stacks / 100000.0
        result["effect"]["stack_cap_maximum"] = int(row[49]) * stacks / 100000.0
    return result


def parse_rule(equipment_id: str, value: Any) -> dict[str, Any]:
    row = original_row(value, 123)
    semantic = _reviewed_operation(equipment_id, row)
    active = ACTIVE_BLOCKS.get(row[2], [])
    return {
        "slot": int(row[0]), "unlock_level": int(row[1]), "trigger_mode_code": row[2],
        "trigger_mode": MODES.get(row[2], "unsupported"),
        "active_blocks": {name: {"column_start": BLOCKS[name][0], "column_end_exclusive": BLOCKS[name][1],
                                  "raw_fields": row[slice(*BLOCKS[name])]} for name in active},
        "semantic_status": "reviewed_original_parameters" if semantic is not None else "unsupported",
        "semantic": semantic,
        "unsupported_reason": "" if semantic is not None else "No reviewed JP semantic mapping for this complete equipment instruction. No generic runtime rule is substituted.",
        "runtime_support": "not_claimed_by_extractor", "raw_fields": row,
    }


def _stats(raw: dict[str, Any]) -> list[dict[str, int]]:
    result = []
    for level, rows in sorted(raw.items(), key=lambda pair: int(pair[0])):
        if len(rows) != 1:
            raise ValueError("Unexpected original stat curve shape")
        row = original_row(rows[0], 2)
        result.append({"level": int(level), "hp": int(row[0]), "atk": int(row[1])})
    return result


def normalize(tables: dict[str, Any], lock: dict[str, Any]) -> dict[str, Any]:
    equipment = tables["equipment"]
    secondary = {item["canonical_equipment_id"]: item for item in lock["secondary_identity_checks"]}
    if set(equipment) != set(tables["ability_soul"]) or set(equipment) != set(tables["status"]):
        raise ValueError("Equipment, ability_soul and original stats must join without missing IDs")
    results = []
    for identifier, rows in sorted(equipment.items(), key=lambda pair: int(pair[0])):
        if len(rows) != 1:
            raise ValueError("Unexpected original equipment metadata row count")
        metadata = original_row(rows[0], 16)
        soul_id = metadata[10]
        rules = [parse_rule(identifier, row) for row in tables["ability_soul"][soul_id]]
        enhanced_rows = tables["enhancement_ability"].get(identifier, [])
        for row in enhanced_rows:
            original_row(row, 126)
        original_element = secondary.get(identifier)
        results.append({
            "id": identifier, "dev_name": metadata[0], "name_jp": metadata[1], "rarity": int(metadata[11]),
            "game_id": original_element["game_id"] if original_element else None,
            "element": original_element["element"] if original_element else None,
            "element_evidence": original_element if original_element else {"status": "unknown", "reason": "No element column is declared in the original equipment metadata; no element is guessed from effect targets."},
            "ability_soul_id": soul_id, "image_resource_ref": metadata[6], "non_playable_dev_tag": metadata[0].startswith("non_playable_"),
            "base_stats": _stats(tables["status"][identifier]),
            "metadata_fields": {str(index): value for index, value in enumerate(metadata) if index not in [5, 7]},
            "rules": rules,
            "semantic_status": "reviewed_original_parameters" if all(rule["semantic"] is not None for rule in rules) else "unsupported",
            "enhancement": {"present": identifier in tables["enhancement"],
                "metadata_fields": [{str(index): value for index, value in enumerate(row) if index != 6} for row in tables["enhancement"].get(identifier, [])],
                "raw_rule_rows": enhanced_rows, "semantic_status": "unsupported" if enhanced_rows else "not_present",
                "base_stats": _stats(tables["enhancement_status"][identifier]) if identifier in tables["enhancement_status"] else []},
            "stance_metadata_rows": tables["stance_detail"].get(identifier, []),
        })
    rules = [rule for item in results for rule in item["rules"]]
    counts = {
        "equipment": len(results), "ability_rows": len(rules), "ability_row_width": 123,
        "enhanced_equipment": len(tables["enhancement"]), "enhancement_rows": sum(len(rows) for rows in tables["enhancement_ability"].values()),
        "enhancement_row_width": 126, "stance_metadata": len(tables["stance_detail"]),
    }
    if counts != lock["expected_counts"]:
        raise ValueError("Pinned original equipment counts changed")
    return {
        "schema_version": 1, "source": {key: lock[key] for key in ["repository", "commit", "asset_version", "region", "license_status"]},
        "source_format": "orderedmap/ability/ability_soul.json is the original numeric equipment rule table, not a downloaded animation DSL.",
        "field_mapping": {"equipment": {"10": "ability_soul_id", "6": "image_resource_ref"},
            "ability_soul": {"width": 123, "head": {"0": "slot", "1": "unlock_level", "2": "trigger_mode_code"},
                "blocks": {name: list(bounds) for name, bounds in BLOCKS.items()},
                "active_block_policy": "Decode only blocks selected by c2; inactive columns remain raw, never executable fallback content.",
                "strength_units": "Only reviewed ratio operations divide their original strength by 100000. Unknown commands keep raw strings and no invented units."},
            "equipment_enhancement_ability": {"width": 126, "policy": "Retained unmodified; its column layout is distinct from 123-column equipment rules."},
            "enum_region_warning": "CN instant trigger codes are not JP-compatible; no full CN enum table is applied to JP data."},
        "counts": counts,
        "semantic_coverage": {"reviewed_equipment": sum(item["semantic_status"] == "reviewed_original_parameters" for item in results),
            "unsupported_equipment": sum(item["semantic_status"] == "unsupported" for item in results),
            "reviewed_rows": sum(rule["semantic"] is not None for rule in rules), "unsupported_rows": sum(rule["semantic"] is None for rule in rules)},
        "opcode_inventory": {mode: dict(sorted(Counter(rule["raw_fields"][44 if mode == "instant" else 106 if mode == "during" else 120] for rule in rules if rule["trigger_mode"] == mode).items(), key=lambda pair: int(pair[0]))) for mode in MODES.values()},
        "equipment": results,
        "complete_gameplay_implementation": False,
    }


def rebuild(lock: dict[str, Any], cache: Path, offline: bool) -> dict[str, Any]:
    return normalize({source["id"]: acquire(source, cache, offline) for source in lock["sources"]}, lock)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path, default=SOURCES)
    parser.add_argument("--cache", type=Path, default=CACHE)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        result = rebuild(read_json(args.sources), args.cache, args.offline)
        data = encoded(result)
        if args.check:
            if not args.output.exists() or args.output.read_bytes() != data:
                raise ValueError("Tracked original equipment rules differ from the deterministic rebuild")
        else:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_bytes(data)
        print(json.dumps({"counts": result["counts"], "semantic_coverage": result["semantic_coverage"], "sha256": hashlib.sha256(data).hexdigest(), "checked": args.check}))
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"Equipment rule extraction failed: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
