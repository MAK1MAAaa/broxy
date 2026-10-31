"""Bind reviewed original JP rows to explicit project equipment adaptations.

This offline audit reparses every retained 123-column rule before deriving the
expected resource scopes and rank arrays. It checks source/data/art registration;
it does not execute Godot or certify complete original gameplay implementation.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import re
import struct
from pathlib import Path
from typing import Any, Mapping

ROOT = Path(__file__).resolve().parents[1]
ADAPTATIONS = "data/worldflipper/equipment_adaptations.json"
RULES_DOCUMENT = "data/worldflipper/equipment_rules.json"
SOURCE_LOCK = "tools/world_flipper_equipment_rules_sources.json"
ART_MANIFEST = "assets/worldflipper/equipment/manifest.json"
COMMIT = "1d45b529ef078ba9b1f876d4588debd0c8a9a214"
ABILITY_SOUL_SHA256 = "2f35cb8cd337cc3774a36a4c4577f2edc91e4b5942b3302115eb4a1448b0525f"
IDENTITIES = {
    "3040006": "bow_0006", "5010005": "sword_0005", "3050002": "book_0002",
    "3070006": "fist_0006", "1060001": "staff_0001",
}
RANK_MULTIPLIERS = [1, 2, 4]
POLICY = {
    "status": "partial_project_adaptation",
    "equipment_owner": {"default": "main", "scope": "explicit_inventory_owner_ref", "rear_identity": "actual_owned_skill_uid"},
    "rank": {"source_value": "primary_unlock_1_amount_base", "multipliers": RANK_MULTIPLIERS,
             "original_equipment_level_mapping": False, "independent_unlock_5_slot_applied": False,
             "reason": "Project backpack merge ranks preserve the existing1/2/4 rule; they are not original levels, maximum-strength interpolation or awakening."},
    "beneficiary": {"owner": "actual main actor only", "party_element": "actual casting character element, including each owned rear UID",
                    "weapon_element_is_actor_filter": False, "same_category_bucket": "legacy_plus_owner_plus_party_plus_element_additive_once"},
    "max_health": {"formula": "legacy_flat_max_health * (1 + sum_owner_ratios)", "new_equipment_heals": False, "new_equipment_revives": False},
    "staff": {"trigger": "successful_equipment_owner_main_R_only", "rear_cast_triggers_stack": False,
              "project_applies_to_current_cast": True, "original_same_cast_order_verified": False,
              "transaction": "pure_preview_then_complete_delivery_reservation_then_single_commit_then_locked_cooldown_before_external_events",
              "max_stacks_per_equipment_uid": 4, "party_bonus_cap": 8.0, "reset_boundary": "project_wave_begin_or_runtime_clear",
              "merge": "retain_target_uid_layers_without_summing_source", "sale": "inactive_immediately_new_uid_starts_zero",
              "locked_delivery": "later_sale_or_rank_change_does_not_rewrite_cast_parameters"},
    "original_progression_complete": False,
    "original_awakening_complete": False,
    "runtime_execution_verified_by_this_audit": False,
}


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def same(actual: Any, expected: Any, label: str) -> None:
    if canonical(actual) != canonical(expected):
        raise ValueError(label + " differs from reviewed source or project policy")


def decoder(root: Path) -> Any:
    specification = importlib.util.spec_from_file_location("equipment_bindings_source_decoder", root / "tools/world_flipper_equipment_rules.py")
    if specification is None or specification.loader is None:
        raise ValueError("Missing original equipment decoder")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


def unique(rows: list[dict[str, Any]], key: str, label: str) -> dict[str, dict[str, Any]]:
    result = {row[key]: row for row in rows}
    if len(result) != len(rows):
        raise ValueError("Duplicate " + label)
    return result


def _source_items(root: Path, document: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    source_decoder = decoder(root)
    lock = read_json(root / SOURCE_LOCK)
    for data in (document["source"], lock):
        same([data["commit"], data["asset_version"], data["region"]], [COMMIT, "1.780.40", "JP"], "Fixed original JP source")
    ability = next(row for row in lock["sources"] if row["id"] == "ability_soul")
    same([ability["path"], ability["url"], ability["sha256"]],
         ["orderedmap/ability/ability_soul.json", f"https://raw.githubusercontent.com/blead/wf-assets/{COMMIT}/orderedmap/ability/ability_soul.json", ABILITY_SOUL_SHA256], "Pinned original123-column table")
    items = unique(document["equipment"], "id", "canonical original equipment")
    for identifier in IDENTITIES:
        item = items[identifier]
        same(item["dev_name"], IDENTITIES[identifier], "Canonical/dev identity")
        same(item["ability_soul_id"], identifier, "Original ability_soul reference")
        rules = item["rules"]
        contexts = [f"{rule['slot']}:{rule['unlock_level']}" for rule in rules]
        same(sorted(contexts), sorted(source_decoder.REVIEWED_ROWS[identifier]), "Complete independent original rule slots")
        for rule in rules:
            reparsed = source_decoder.parse_rule(identifier, rule["raw_fields"])
            same(rule, reparsed, "Recomputed normalized rule " + identifier)
            same(rule["source_row_sha256"], source_decoder.row_fingerprint(rule["raw_fields"]), "Raw123-column SHA")
        same(item["enhancement"]["present"], False, "Separate126-column enhancement presence")
        same(item["enhancement"]["raw_rule_rows"], [], "Separate126-column enhancement rows")
    return items, lock


def _binding(semantic: dict[str, Any]) -> dict[str, Any]:
    effect = semantic["effect"]
    event = semantic["event"]
    target = effect["target"]
    amount = effect["amount_base"]
    if type(amount) not in (int, float) or effect["unit"] != "ratio":
        raise ValueError("A bound source requires its reviewed original ratio")
    rates = [amount * multiplier for multiplier in RANK_MULTIPLIERS]
    if event["kind"] == "skill_activation":
        same([event["actor_scope"], event["puller_code"], event["count_base"], event["count_maximum"], event["stack_limit"]],
             ["owner", "0", 1.0, 1.0, 4], "Staff source trigger")
        same([effect["operation"], target], ["skill_damage_ratio", {"kind": "party", "group": "(None)"}], "Staff source beneficiary")
        same(semantic["execution_order_evidence"]["same_cast_damage_order_verified"], False, "Unproven original same-cast ordering")
        return {"field": "equipment_effects", "value": {"kind": "cast_party_skill_damage", "amount_by_rank": rates,
                "max_stacks": event["stack_limit"], "applies_to_current_cast": True}}
    same(event["kind"], "initial", "Static source trigger")
    operation = effect["operation"]
    stat = {"attack_ratio": "damage", "skill_damage_ratio": "skill_damage", "max_health_ratio": "max_health_ratio"}.get(operation)
    if stat is None or semantic["conditions"]:
        raise ValueError("Unsupported source operation or original condition in scoped binding")
    if target == {"kind": "owner", "group": ""}:
        value = {"stat": stat, "target": "owner", "amount_by_rank": rates}
    elif target["kind"] == "party_group" and target["group"] in {"Red", "Black"}:
        value = {"stat": stat, "target": "party_element", "element": {"Red": "fire", "Black": "dark"}[target["group"]], "amount_by_rank": rates}
    else:
        raise ValueError("Unsupported source beneficiary in scoped binding")
    return {"field": "equipment_modifiers", "value": value}


def expected_document(root: Path = ROOT, rules_document: dict[str, Any] | None = None) -> dict[str, Any]:
    document = read_json(root / RULES_DOCUMENT) if rules_document is None else rules_document
    items, lock = _source_items(root, document)
    source = next(row for row in lock["sources"] if row["id"] == "ability_soul")
    manifest = read_json(root / ART_MANIFEST)
    assets = unique(manifest["assets"], "id", "equipment art asset")
    bindings = []
    all_items = document["equipment"]
    for identifier, game_id in IDENTITIES.items():
        item = items[identifier]
        rows = []
        indices = {"equipment_modifiers": 0, "equipment_effects": 0}
        for index, rule in enumerate(item["rules"]):
            primary = rule["unlock_level"] == 1
            binding = _binding(rule["semantic"]) if primary else None
            if binding is not None:
                binding["index"] = indices[binding["field"]]
                indices[binding["field"]] += 1
            rows.append({"slot": rule["slot"], "unlock_level": rule["unlock_level"],
                         "original_pointer": f"/{identifier}/{index}",
                         "normalized_pointer": f"/equipment/{all_items.index(item)}/rules/{index}",
                         "raw_field_count": 123, "source_row_sha256": rule["source_row_sha256"],
                         "semantic_sha256": digest(rule["semantic"]),
                         "original_operation": rule["semantic"]["effect"]["operation"],
                         "original_target": copy.deepcopy(rule["semantic"]["effect"]["target"]),
                         "original_amount_base": rule["semantic"]["effect"]["amount_base"],
                         "original_amount_maximum": rule["semantic"]["effect"]["amount_maximum"],
                         "status": "primary_unlock_1_project_binding" if primary else "independent_unlock_5_slot_unmapped",
                         "resource_binding": binding})
        asset = assets[game_id]
        gaps = ["original_level_progression_not_replayed", "original_equipment_base_stats_not_imported",
                "ordinary_weapon_attack_and_balance_are_project_adaptations"]
        if any(row["unlock_level"] == 5 for row in rows):
            gaps.append("independent_unlock_5_slot_unmapped")
        if identifier == "1060001":
            gaps.extend(["same_cast_damage_order_not_proven_by_source", "wave_reset_is_project_adaptation"])
        bindings.append({"canonical_id": identifier, "game_id": game_id, "dev_name": item["dev_name"],
                         "resource": f"data/weapons/{game_id}.tres", "status": "partial",
                         "original_progression_complete": False, "original_awakening_complete": False,
                         "separate_126_column_enhancement_present": False, "source_rules": rows,
                         "art": {"path": f"assets/worldflipper/equipment/{game_id}.png", "sha256": asset["sha256"],
                                 "canonical_equipment_id": identifier, "source_image_resource_ref": item["image_resource_ref"],
                                 "input_route": f"res://assets/icons/{game_id}.svg", "output_route": f"equipment/{game_id}.png",
                                 "final_jp_art_byte_identity_claimed": False}, "gaps": gaps})
    return {"schema_version": 1,
            "source": {"commit": COMMIT, "asset_version": "1.780.40", "region": "JP",
                       "rules_document": RULES_DOCUMENT, "source_lock": SOURCE_LOCK,
                       "ability_soul_url": source["url"], "ability_soul_sha256": source["sha256"]},
            "policy": copy.deepcopy(POLICY), "equipment": bindings,
            "counts": {"equipment": 5, "retained_source_rows": 9, "primary_project_bindings": 6, "unmapped_unlock_5_rows": 3},
            "complete_original_gameplay": False}


def _unique_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result = dict(pairs)
    if len(result) != len(pairs):
        raise ValueError("Duplicate resource JSON key")
    return result


def resource_property(text: str, name: str, default: Any = None) -> Any:
    matches = re.findall(rf"^{re.escape(name)}\s*=\s*(.+)$", text, re.MULTILINE)
    if not matches:
        return default
    if len(matches) != 1:
        raise ValueError("Duplicate resource property: " + name)
    value = matches[0].strip()
    if value.startswith("Array[Dictionary](") and value.endswith(")"):
        value = value[len("Array[Dictionary]("):-1]
    return json.loads(value, object_pairs_hook=_unique_pairs, parse_constant=lambda name: (_ for _ in ()).throw(ValueError("Non-finite resource number: " + name)))


def audit(root: Path = ROOT, *, adaptations: dict[str, Any] | None = None,
          rules_document: dict[str, Any] | None = None,
          resource_texts: Mapping[str, str] | None = None) -> dict[str, Any]:
    document = read_json(root / RULES_DOCUMENT) if rules_document is None else rules_document
    expected = expected_document(root, document)
    binding_document = read_json(root / ADAPTATIONS) if adaptations is None else adaptations
    same(binding_document, expected, "Equipment adaptation/source binding document")
    catalog = unique(read_json(root / "data/worldflipper/catalog.json")["equipment"], "id", "canonical catalog equipment")
    manifest = read_json(root / ART_MANIFEST)
    same(manifest["catalog_commit"], COMMIT, "Art catalog source commit")
    registry = read_json(root / manifest["source_registry"])
    same(manifest["source_registry_sha256"], hashlib.sha256((root / manifest["source_registry"]).read_bytes()).hexdigest(), "Art source registry SHA")
    sources = unique(registry["sources"], "game_id", "equipment icon source")
    assets = unique(manifest["assets"], "id", "equipment output")
    router = (root / "scripts/core/adventure_art.gd").read_text(encoding="utf-8")
    if not re.search(r'^const FAN_ROOT: String = "res://assets/worldflipper/"$', router, re.MULTILINE):
        raise ValueError("Production equipment art root differs")
    registration = (root / "scripts/data/game_catalog.gd").read_text(encoding="utf-8")
    block = re.search(r"^const WEAPON_DEFS:[^\n=]+\s*=\s*\[(.*?)^\]", registration, re.MULTILINE | re.DOTALL)
    if block is None:
        raise ValueError("Missing actual production weapon catalog")
    registered = re.findall(r'preload\("res://([^"]+)"\)', block[1])
    checked: dict[str, Any] = {}
    for item in expected["equipment"]:
        identifier, game_id, path = item["canonical_id"], item["game_id"], item["resource"]
        same([catalog[identifier]["dev_name"], catalog[identifier]["resource_ref"]], [game_id, item["art"]["source_image_resource_ref"]], "Canonical catalog/art identity")
        if registered.count(path) != 1:
            raise ValueError("Equipment must be registered exactly once in the actual weapon catalog: " + game_id)
        text = resource_texts[path] if resource_texts is not None and path in resource_texts else (root / path).read_text(encoding="utf-8")
        for field, value in {"id": game_id, "kind": "weapon", "source_id": identifier, "icon": game_id, "equipment_owner": "main"}.items():
            same(resource_property(text, field), value, "Resource " + field + " for " + game_id)
        same(resource_property(text, "equipment_bonuses", {}), {}, "No duplicate legacy/global stat route for " + game_id)
        for field in ("equipment_modifiers", "equipment_effects"):
            values = [row["resource_binding"]["value"] for row in item["source_rules"] if row["resource_binding"] is not None and row["resource_binding"]["field"] == field]
            same(resource_property(text, field, []), values, "Resource scope/rates " + field + " for " + game_id)
        art = item["art"]
        same([assets[game_id]["path"], assets[game_id]["canonical_equipment_id"], assets[game_id]["sha256"]], [art["path"], identifier, art["sha256"]], "Manifest equipment icon binding")
        same([sources[game_id]["canonical_id"], sources[game_id]["image_resource_ref"]], [identifier, art["source_image_resource_ref"]], "Original icon source identity")
        route = rf'^\s*{re.escape(json.dumps(art["input_route"]))}:\s*{re.escape(json.dumps(art["output_route"]))},?$'
        if len(re.findall(route, router, re.MULTILINE)) != 1:
            raise ValueError("Production equipment icon route differs: " + game_id)
        png = (root / art["path"]).read_bytes()
        if len(png) < 24 or png[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", png[16:24]) != (64, 64) or hashlib.sha256(png).hexdigest() != art["sha256"]:
            raise ValueError("Actual equipment icon bytes/size differ: " + game_id)
        checked[game_id] = {"canonical_id": identifier, "source_commit": COMMIT,
                            "rank_weights": list(RANK_MULTIPLIERS), "equipment_owner": "main",
                            "resource": path, "status": "partial", "source_rules": item["source_rules"],
                            "modifiers": [row["resource_binding"]["value"] for row in item["source_rules"] if row["resource_binding"] is not None and row["resource_binding"]["field"] == "equipment_modifiers"],
                            "effects": [row["resource_binding"]["value"] for row in item["source_rules"] if row["resource_binding"] is not None and row["resource_binding"]["field"] == "equipment_effects"],
                            "art": art, "gaps": item["gaps"],
                            "original_progression_complete": False, "original_awakening_complete": False}
    return {"passed": True, **expected["counts"], "bindings": checked, "runtime_execution_verified": False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--check", action="store_true", help="Validate without modifying sources (the only mode).")
    parser.add_argument("--json", action="store_true", help="Print the compact audit result.")
    args = parser.parse_args()
    try:
        result = audit(args.root.resolve())
    except (OSError, ValueError, KeyError, TypeError, struct.error) as error:
        parser.exit(1, "Equipment binding audit failed: " + str(error) + "\n")
    print(json.dumps(result, ensure_ascii=False, sort_keys=True) if args.json else
          "Equipment bindings:5 equipment /9 original rows /6 adapted bindings /3 retained unlock gaps; runtime execution not certified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
