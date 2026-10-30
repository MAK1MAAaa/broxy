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
REVIEWED_ROWS: dict[str, dict[str, str]] = {
    "3010053": {"0:1": "cf36beb4a0e375cf7401d5580cf8806d8f83244af5f1f210a3af2f5c81bfc9a0", "1:5": "ca9c81655aed5fdc332385b4faeca71c5ec94df91a38f992e8308ea66afa377f"},
    "5030036": {"0:1": "99f7f57f65c21a53ee80150eb4537eb8ce78d999fd6510e1dcb8490136ccb035"},
    "5060034": {"0:1": "b846dae0b7a9aff950b58078a1975e8e6991566634faa85d461b020cac2731f2", "1:1": "38c3495bda3d0bf5d579632e7d692c051e464cfddb13db3f0619663ced3ccc58", "2:5": "bdf81e061ddd6bbe7c9f40f9d4a62a9990a998bd31c00d84921190e8ffca3b00", "3:5": "c455b948a35e0e25dac5f6be2e92152ce904f9138bfb2a40e0ee7c4cef877d9e"},
    "5040026": {"0:1": "30cc0d8b50ab1e0b9a7968d24bb2cbf8ebc27c8467279687b561687d58945fbe", "1:3": "276e02ce9044050a4f68ab27cccf07a5a5782cf10bc00a9bc911a3f2c35b9310", "2:5": "f4b6dd6f7e34d7695768ccbbfae2ae682a5347006376160a083cff12f2eeac5b", "3:5": "85f3ec7ce16a0bb5a1f9fb4d3cc1f273686b012839b49db888d738882d66b0cf"},
    "5020037": {"0:1": "46770bf5a0753f871e4407d6afce88fede68019595f006e64ee8871d9a826073", "1:3": "154424743c4f33f5b4fdaf367cd3c47161ae7abdada8a5dd168ca35926b2e337", "2:3": "a8be6573b2a29e7e7cf54dec0784377b71ad6d45a058e0c6b645a2da7df3f1d4", "3:3": "c2787e10c01706623f4b6c5d09c608355e0fc2b7ad65f5641bb6e5cb7e769793"},
    "4050031": {"0:1": "4b680bc331462ba52cc0ba600bc6695ecfcd7e76fe2f7d101b3d478c495d4a56", "1:1": "f83b1cb183266b07295371e8b0dd4e9ee189ea0787d3374882fd2abb62bb4754"},
    "5030039": {"0:1": "aaa28026b59cb2f07063b326705bde1b36368517d7c599ceb4c484b41f6f3ed6", "1:5": "87c9c9c9524b8b6539d7fbc98bd4bc5692d86f0e927e61e3ce834f9543dfd2fa"},
    "5090030": {"0:1": "7520485a0cc365d2107559f625ed2bb096ab74c5b8c3828d6af9e1b1be8b0209", "1:5": "aa576f7227fa6e6c960fb9c1728ca21c6018e53fb791c6a8ee8c7e762a7dd078"},
    "5010012": {"0:1": "9f5ff061da2426366ca82d211bad210e4ec2ab39cf24201ea9231da2fa2d719b", "1:1": "ab98b889ede35ed74712cbfd2fe0a864c29bebcfe9f0e1ccbda248f575197a3d"},
    "5030005": {"0:1": "ece567cf0e32c358de578b9524884c3e904c4964b0ec26859241d475d7e32e91"},
    "5010004": {"0:1": "30a6deaa402d28990fccd2bf4ddb6945203f86e1d1144b93308cd80880eda6bf"},
    "5020009": {"0:1": "1c8095cbaef496b7e6db235c6441a9da7f827ff5ac4d387b115e3fb0ea8805b1", "1:1": "2fd79ed4cbc0063dc63ea4500d848b44cc5c8c712fe1c7c9d87cea311678055e"},
    "5050009": {"0:1": "8dcf46af1c153338915af43989b4a1f069e97b7b1f52091d7da5f531ed6aa994", "1:3": "5f253814071b455699088f33bf44c8f7e02c19b056580d979325e2509678b04d", "1:5": "070eaa3b26988a2fe25304c278584ea85231737520f018fbff9bb94dae0f07d5"},
    "3010007": {"0:1": "e1cad829bba03cb560e2924f48037575bdf11dbf2670239923b203358e7ba1db", "1:5": "fd18a44614adf4b9a00ba04c4d1924198c52dc6616a8af64b8f7d501cf242312"},
    "5020024": {"0:1": "47951767c0ef29d59c6eb89b5418e0468dea0babc6c027aaad596801a5c9a428"},
    "5010011": {"0:1": "be1b9f30f5c1af8cd27a92ede6fc9434e2cb4bc01227c1d31a802dcd0d347a56", "1:1": "218012e49e772c6ba097d38c648d7985faacf018f4e2ffabd2cfddb312935432"},
}
REVIEWED_IDS = frozenset(REVIEWED_ROWS)
REVIEWED_OPS = {"32": "attack_ratio", "34": "skill_damage_ratio", "35": "skill_charge_speed_ratio",
                "55": "power_flip_damage_ratio", "67": "dark_resistance_down_immunity", "70": "lethargy_immunity",
                "53": "break_down_punisher_ratio", "118": "paralysis_punisher_ratio", "205": "max_health_ratio",
                "206": "restore_max_health_ratio", "209": "deal_max_health_ratio_damage", "211": "skill_gauge_ratio"}
REVIEWED_EVENTS = {"0": "initial", "2": "power_flip_count", "4": "ball_flip_count", "14": "character_revived",
                   "15": "owner_healed_count", "19": "skill_activation", "21": "owner_health_ratio_at_most",
                   "53": "party_group_count", "54": "owner_in_group_initial"}
ADDITIONAL_FACT_CHECKS = {
    "5010012": ("fire", "Prometheus_Blade", "1029", "e93f8cb871b9e0011069bdd847bf1bf4cc55adbc565a64808151ce4ee009051c"),
    "5030005": ("all", "Maltet", "5629", "e9a11de9873fc3c4eb9e6e49101df3e2b005c1e11c8a79fe3cf89e933ff80a96"),
    "5010004": ("dark", "Ame-no-Habakiri", "2832", "103e2e84c1f7c29434f3adbd6aff11b64a8c536e6620d837d54f3fc9b3e7cce4"),
    "5020009": ("thunder", "Thor%27s_Hammer", "5638", "cfd61cb2cf0252716dd9ce85872c2d87fd802361f6c308b6577eda05fdd4bde6"),
    "5050009": ("fire", "Senji_Ryakketsu", "4729", "57c1e9d631659c8722f98e7640f822aac247adfa3aeea21f72bffe15f1ce505a"),
    "3010007": ("water", "Cutlass", "6122", "352d4bc293948f1d9aab4f8ae5f7fb0818e8fb6bdf2e49c33c3295b25c4fccbb"),
    "5020024": ("all", "Parashu", "1223", "a1b0cd2444931a364ea848447624bbec860e9bf19b80be0ec186e7361375842c"),
    "5010011": ("light", "Heimdall%27s_Sword", "3166", "b73085fadbabd9d38ad80b558cd92f13627afc470974b35a0ed77142fb67ebf9"),
}


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


def row_fingerprint(row: list[str]) -> str:
    return hashlib.sha256(json.dumps(row, ensure_ascii=False, separators=(",", ":")).encode("utf-8")).hexdigest()


def select_reviewed_rules(item: dict[str, Any], original_level: int) -> list[dict[str, Any]]:
    """Choose original reviewed slot variants; never translate project ranks here."""
    if item["id"] not in REVIEWED_IDS or type(original_level) is not int or not 1 <= original_level <= 5:
        raise ValueError("Rule selection requires a reviewed original equipment and original level 1..5")
    selected: dict[int, dict[str, Any]] = {}
    contexts: set[tuple[int, int]] = set()
    for rule in item["rules"]:
        identity = (rule["slot"], rule["unlock_level"])
        if identity in contexts:
            raise ValueError("Duplicate original equipment slot/unlock context")
        contexts.add(identity)
        if rule["unlock_level"] <= original_level and (rule["slot"] not in selected or selected[rule["slot"]]["unlock_level"] < rule["unlock_level"]):
            selected[rule["slot"]] = rule
    return [selected[slot] for slot in sorted(selected)]


def _reviewed_operation(equipment_id: str, row: list[str]) -> dict[str, Any] | None:
    """Decode only the reviewed JP contexts, never a cross-region enum fallback."""
    if equipment_id not in REVIEWED_IDS:
        return None
    context = row[0] + ":" + row[1]
    if REVIEWED_ROWS[equipment_id].get(context) != row_fingerprint(row):
        raise ValueError("A reviewed complete JP equipment row changed; inspect its original facts again")
    if row[2] == "1":
        return {"conditions": [{"kind": "party_piercing_active", "jp_during_trigger_code": int(row[94])}],
            "event": {"kind": "while_condition", "accumulation_trigger_raw": row[82:94], "even_if_owner_dead": row[105] == "true"},
            "effect": {"operation": "attack_ratio", "jp_opcode": int(row[106] or "0"), "opcode_namespace": "during_content",
                "target": {"kind": "party" if row[107] == "5" else "owner", "group": row[108]},
                "amount_base": original_ratio(row[110]), "amount_maximum": original_ratio(row[111]), "unit": "ratio"},
            "evidence": "Exact pinned 123-column row and this equipment's sourced Pierce/penetration ability, not a shared cross-region enum."}
    opcode, event_code = row[44] or "0", row[24] or "0"
    if row[2] != "0" or opcode not in REVIEWED_OPS or event_code not in REVIEWED_EVENTS:
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
    if event_code == "54":
        conditions.append({"kind": "owner_in_group", "group": row[33]})
    target_code = row[45] or "0"
    targets = {"0": "owner", "1": "party_except_owner", "2": "leader", "5": "party_group"}
    if target_code not in targets:
        raise ValueError("A reviewed instruction gained an unsupported target")
    stacks = int(row[31]) if row[31] else None
    lower = original_ratio(row[48])
    upper = original_ratio(row[49])
    result = {
        "conditions": conditions,
        "event": {"kind": REVIEWED_EVENTS[event_code], "puller_code": row[25], "puller_group": row[26],
                  "count_base": original_ratio(row[27]), "count_maximum": original_ratio(row[28]), "stack_limit": stacks},
        "effect": {"operation": REVIEWED_OPS[opcode], "jp_opcode": int(opcode),
                   "target": {"kind": targets[target_code], "group": row[46]},
                   "amount_base": lower, "amount_maximum": upper, "unit": "ratio" if lower is not None else "flag"},
        "evidence": "Pinned JP numeric row, cross-checked against this exact equipment's sourced ability and awakening facts.",
    }
    if event_code == "21":
        result["event"].update(threshold_base=original_ratio(row[27]), threshold_maximum=original_ratio(row[28]), comparison="<=", threshold_unit="health_ratio")
        result["event"].pop("count_base")
        result["event"].pop("count_maximum")
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
        "source_row_sha256": row_fingerprint(row),
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
    for identifier, (element, page, revision, digest) in ADDITIONAL_FACT_CHECKS.items():
        secondary[identifier] = {"game_id": equipment[identifier][0][0], "canonical_equipment_id": identifier,
            "element": element, "url": "https://worldflipper.wiki.gg/wiki/" + page,
            "wiki_revision": revision, "revision_url": "https://worldflipper.wiki.gg/wiki/" + page + "?oldid=" + revision,
            "raw_html_sha256": digest,
            "evidence_level": "secondary Wiki cross-check; full original JP row fingerprint is pinned before this exact ability context is decoded"}
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
                "raw_rule_sha256": [row_fingerprint(row) for row in enhanced_rows],
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
        "semantic_review_policy": {"reviewed_equipment_ids": sorted(REVIEWED_IDS), "reviewed_row_fingerprints": REVIEWED_ROWS,
            "context": "Only these exact complete 123-column rows are semantically reviewed; an opcode is never sufficient to admit another row.",
            "original_progression": "For reviewed equipment, choose the highest unlocked original level per slot; original levels are not project backpack ranks.",
            "during_namespace": "The reviewed Pierce entries use during trigger c94=30 and during content c106=0; these are not instant event/effect enum numbers.",
            "enhancement": "All 108 enhancement rows remain unsupported; each full 126-column row is fingerprinted without being translated.",
            "runtime": "Semantic decoding does not grant an equipment item, waive an original condition or claim any gameplay implementation."},
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
