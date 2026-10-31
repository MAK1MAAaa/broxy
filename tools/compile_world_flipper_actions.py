"""Build pending, source-bound action plans; never claim parsed actions are playable.

The first lowering deliberately accepts only static, unconditional damage areas.
Every other opcode, layout, condition, movement or target rule remains explicit.
Raw source bytes are verified by the existing immutable action-source lock.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
from collections import Counter
from pathlib import Path
from typing import Any, Literal, TypedDict

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("wf_action_extractor", ROOT / "tools/world_flipper_skill_actions.py")
assert SPEC is not None and SPEC.loader is not None
DSL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DSL)
OUTPUT = ROOT / "data/worldflipper/action_profiles.json"
SECONDS_PER_UNIT = 1.0 / 60.0
PRESENTATION = frozenset({"ShowEffect", "HideEffect", "ShakeCamera"})
SOURCE_POLICY = frozenset({"StopBall", "HideCharacter"})
STATIC_LOWERING = PRESENTATION | SOURCE_POLICY | {"Wait", "CreateReferencePoint", "CreateHitArea", "CreateNormalAttack"}
EXISTING_PARTIAL_FAMILIES = frozenset({"Wait", "CreateHitArea", "CreateNormalAttack", "CreateCondition", "DeleteCondition", "CreateBombMultiball", "CreateReferencePoint", "FindAllSubjects", "FindNearSubjects"})
REPRESENTATIVES = ("211012", "221008", "241003", "361001", "311005", "331011", "311009", "141002", "331001", "442006", "311004", "331003")
REVIEWED_CASTER_SOURCES = frozenset({"d3190d57a947e3b5cb673d8beb39bd17c2c945f4", "60e4cdcc28a7b0934edd56f0299271450f2b8967"})
MECHANISMS: dict[str, str] = {
    "211012": "Wait28; forward offset220 Circle210; lifetime20; one unconditional fire hit. StopBall65 remains an explicit movement-policy gap.",
    "221008": "Cast-time reference offset120; Wait38; Circle300; lifetime50; one unconditional water hit.",
    "241003": "Four-direction cross slash. Rectangle200x2000, Bottom anchor, Circle placement(4,0), lifetime30, one hit per original region. Requires explicit multi-instance placement and directional anchoring.",
    "361001": "Dark aura around the caster: Circle200, lifetime600, maximum30 hits. The original text requires the aura to travel with the caster; a fixed circle is insufficient.",
    "311005": "Proportional healing with fire-element healing bonus plus timed attack power. Preserve party, multiball and participant target distinctions before single-player adaptation.",
    "331011": "Leader-only skill-gauge charge plus timed skill damage; this is not general cooldown reduction for every backpack skill.",
    "311009": "Field-wide attack decrease, fire-resistance decrease and one positive-condition dispel. There is no CreateNormalAttack and no invented damage.",
    "141002": "Proportional healing with wind-element healing bonus plus party/multiball floating. Floating needs a meaningful production controller, not an attack buff substitute.",
    "331001": "Nearest-target movement for90 source units plus Circle200/15hits. Original text specifies damage scaling by the caster's positive-condition count; it is not combo scaling.",
    "442006": "Eight Circle100 vortex regions with Circle placement(8,200), lifetime120, maximum20 hits; one centered circle would omit the actual geometry.",
    "311004": "Forward Rectangle150x495/Bottom, lifetime35, maximum8 hits; attack carries race filter[8194,8197,8200] and additional0.25 range. Text confirms beast/plant/dragon advantage, but numeric race mapping remains pending.",
    "331003": "Wait30 creates a caster reference, whose nested Wait24 creates a forward Circle200/lifetime30/single thunder hit. Nested clock origin needs explicit scope policy, not silently treating both waits as absolute.",
}


class SourceEvidence(TypedDict):
    status: Literal["pending"]
    repository_path: str
    git_blob_sha1: str
    sha256: str
    url: str
    json_pointer: str


def evidence(source: dict[str, Any], pointer: str) -> SourceEvidence:
    return {"status": "pending", "repository_path": source["path"], "git_blob_sha1": source["git_blob_sha1"],
            "sha256": source["sha256"], "url": source["url"], "json_pointer": pointer}


def _fixed(value: Any) -> float | None:
    if not isinstance(value, list) or len(value) != 1 or not isinstance(value[0], dict):
        return None
    low, high = value[0].get("min"), value[0].get("max")
    if isinstance(low, bool) or not isinstance(low, (int, float)) or low != high or not math.isfinite(float(low)):
        return None
    return float(low)


def _prune_blocks(value: Any, pointer: str) -> Any:
    if isinstance(value, list):
        if value and value[0] == "Block":
            return {"source_block_pointer": pointer}
        return [_prune_blocks(child, f"{pointer}/{index}") for index, child in enumerate(value)]
    if isinstance(value, dict):
        return {key: _prune_blocks(child, pointer + "/" + key.replace("~", "~0").replace("/", "~1")) for key, child in value.items()}
    return value


def lower_static_action(record: dict[str, Any], reviewed_caster_anchor: bool = False) -> dict[str, Any]:
    """Fail closed on non-static gameplay; return only pending representative IR."""
    instructions = record["instructions"]
    issues: list[dict[str, str]] = []
    regions = [node for node in instructions if node["name"] == "CreateHitArea"]
    references = {node["raw_payload"][10]: node for node in instructions if node["name"] == "CreateReferencePoint"}
    phases: list[dict[str, Any]] = []

    def block(code: str, pointer: str) -> None:
        issues.append({"code": code, "pointer": pointer})

    for node in instructions:
        if node["name"] not in STATIC_LOWERING:
            block("unsupported_gameplay_opcode:" + node["name"], node["pointer"])
    if not 1 <= len(regions) <= 8:
        block("requires_one_to_eight_direct_regions", "/11")
    for reference in references.values():
        p = reference["raw_payload"]
        if p[1] != -18 or p[2] != ["AB"] or p[5] != 0 or p[6:8] != [False, False] or p[8] != ["Single"]:
            block("reference_transform_not_decoded", reference["pointer"])
    area_attacks: set[str] = set()
    for region in regions:
        p, pointer, waits = region["raw_payload"], region["pointer"], region["wait_context"]
        if len(waits) > 1 or any(not isinstance(wait["delay_raw"], (int, float)) or isinstance(wait["delay_raw"], bool) or not math.isfinite(float(wait["delay_raw"])) or not 0 <= wait["delay_raw"] <= 1800 or wait["selector_raw"] != "*" for wait in waits):
            block("nested_or_variable_wait_requires_clock_policy", pointer)
        if any(scope["instruction"] == "CreateHitArea" for scope in region["scope"]):
            block("nested_hit_callback_region_requires_trigger_runtime", pointer)
        caster_anchor = reviewed_caster_anchor and p[2] == -18 and p[4:7] == [0, 0, 0] and p[7:9] == [True, True]
        if p[3] != ["AB"] or p[6] != 0 or (p[7:9] != [False, False] and not caster_anchor):
            block("nondefault_coordinate_rotation_or_binding_flags", pointer)
        if p[10:12] != [["Center"], ["Center"]]:
            block("directional_alignment_requires_explicit_origin_transform", pointer + "/10")
        if p[12] != ["Single"]:
            block("multi_instance_placement_requires_geometry_runtime", pointer + "/12")
        reference = references.get(p[2])
        if p[2] != -18 and reference is None:
            block("subject_scope_not_decoded", pointer + "/2")
        dimensions = [_fixed(value) for value in p[9][1:]] if isinstance(p[9], list) else []
        shape = p[9][0] if isinstance(p[9], list) and p[9] else None
        if shape not in {"Circle", "Rectangle"} or len(dimensions) != (1 if shape == "Circle" else 2) or any(value is None or value <= 0 for value in dimensions):
            block("nonconstant_or_unsupported_shape", pointer + "/9")
        lifetime = p[13][1] if isinstance(p[13], list) and len(p[13]) == 2 else None
        if p[13][0] != "SpecifyHitAreaLifetimeDirectly" or isinstance(lifetime, bool) or not isinstance(lifetime, (int, float)) or not math.isfinite(float(lifetime)) or not 0 < lifetime <= 600:
            block("unsupported_lifetime_policy_or_budget", pointer + "/13")
        hits = p[14][1] if isinstance(p[14], list) and len(p[14]) == 2 else None
        if p[14][0] != "CalculatedUsingMaxNumOfHits" or isinstance(hits, bool) or not isinstance(hits, int) or not 1 <= hits <= 32:
            block("unsupported_hit_policy_or_budget", pointer + "/14")
        attacks = [node for node in instructions if node["name"] == "CreateNormalAttack" and node["pointer"].startswith(pointer + "/23/")]
        if len(attacks) != 1:
            block("hit_callback_requires_exactly_one_unconditional_attack", pointer + "/23")
            continue
        attack = attacks[0]
        area_attacks.add(attack["pointer"])
        direct_scope = [*region["scope"], {"owner": pointer, "instruction": "CreateHitArea",
                                          "parameter_index": 23, "role": "hit_callback"}]
        if attack["scope"] != direct_scope or attack["wait_context"] != waits:
            block("hit_callback_requires_direct_unconditional_attack", attack["pointer"])
            continue
        q = attack["raw_payload"]
        if q[1] != p[22] or q[2] != 255 or q[3] is not None or q[4] is not None or q[7] != [{"max": 0, "min": 0}] or any(q[8:13]):
            block("conditional_or_flagged_attack_requires_dedicated_rule", attack["pointer"])
        coefficients = q[6]
        if not isinstance(coefficients, list) or len(coefficients) != 1 or not isinstance(coefficients[0], dict):
            block("attack_coefficient_shape_not_decoded", attack["pointer"] + "/6")
            continue
        low, high = coefficients[0].get("min"), coefficients[0].get("max")
        if not isinstance(low, (int, float)) or not isinstance(high, (int, float)) or not math.isfinite(float(low)) or not math.isfinite(float(high)) or not 0 < low <= high:
            block("nonfinite_or_nonpositive_attack_coefficient", attack["pointer"] + "/6")
            continue
        raw_offset = [p[4], p[5]]
        capture = "caster" if caster_anchor else "caster_at_activation"
        if reference is not None:
            ref = reference["raw_payload"]
            raw_offset = [p[4] + ref[3], p[5] + ref[4]]
            capture = "cast" if not reference["wait_context"] else "caster_at_activation"
        phases.append({"pointer": pointer, "wait_pointers": [wait["pointer"] for wait in waits],
                       "delay_source_units": waits[0]["delay_raw"] if len(waits) == 1 else 0,
                       "shape_source": p[9], "coordinate_tag_source": p[3], "alignment_source": p[10:12],
                       "placement_source": p[12], "offset_source": raw_offset, "capture_policy": capture,
                       "lifetime_source_units": lifetime, "maximum_hits": hits,
                       "coefficient_bounds_source": coefficients, "attack_pointer": attack["pointer"],
                       "opaque_parameter_15_source": p[15], "original_damage_total_weight": high * hits if isinstance(hits, int) else 0})
    for node in instructions:
        if node["name"] == "CreateNormalAttack" and node["pointer"] not in area_attacks:
            block("attack_outside_known_hit_callback", node["pointer"])
    if issues:
        return {"runtime_profile_ready": False, "blockers": issues, "timeline": []}
    total_weight = sum(phase["original_damage_total_weight"] for phase in phases)
    for phase in phases:
        phase["delay_project_seconds"] = phase["delay_source_units"] * SECONDS_PER_UNIT
        phase["duration_project_seconds"] = phase["lifetime_source_units"] * SECONDS_PER_UNIT
        phase["damage_weight"] = phase["original_damage_total_weight"] / total_weight
        phase["delay"] = phase["delay_project_seconds"]
        phase["duration"] = phase["duration_project_seconds"]
        phase["hits"] = phase["maximum_hits"]
        phase["shape"] = phase["shape_source"][0].lower()
        phase["anchor"] = "fixed" if phase["capture_policy"] == "cast" else phase["capture_policy"]
        phase["origin_offset_source"] = phase["offset_source"]
        phase["interval_project_seconds"] = phase["duration"] / phase["hits"]
        phase["cadence_policy"] = "Explicit project uniform duration/max-hits adaptation; original parameter15 hit cadence remains undecoded."
        phase["geometry_scale"] = None
        phase["project_damage"] = None
    return {"runtime_profile_ready": True, "blockers": [], "timeline": phases}


def _animations(character_id: str, registry: dict[str, Any]) -> dict[str, Any]:
    character = next(row for row in registry["characters"] if row["id"] == character_id)
    sources = {row["id"]: row for row in registry["sources"]}
    return {"three_pose_sources_verified": character["three_pose_sources_verified"],
            "mirror_commit": registry["mirror_commit"],
            "poses": [{"pose": pose, "cache_path": ".tools/wf-character-assets/raw/" + sources[identifier]["filename"],
                       "url": sources[identifier]["url"], "git_blob_sha1": sources[identifier]["git_blob_sha1"],
                       "sha256": sources[identifier].get("sha256"), "frame_count": sources[identifier].get("frame_count"),
                       "unique_rgba_frames": sources[identifier].get("unique_rgba_frames")}
                      for pose, identifier in character["source_ids"].items()]}


def build(catalog: dict[str, Any], index: dict[str, Any], lock: dict[str, Any], registry: dict[str, Any], cache: Path) -> dict[str, Any]:
    if catalog["source"]["commit"] != lock["commit"] or index["source"]["commit"] != lock["commit"]:
        raise ValueError("All action inputs must share the immutable JP source commit")
    if index["source"]["manifest_sha256"] != hashlib.sha256(DSL.json_bytes(lock)).hexdigest():
        raise ValueError("Normalized action index and source lock hashes differ")
    sources = {source["path"]: source for source in lock["sources"]}
    records = {}
    for path, source in sources.items():
        document, _ = DSL.load_action(source, lock, cache, True)
        records[path] = DSL.extract_action(document)
    caster_paths = {row["action_file"]["path"] for row in catalog["skills"] if row["group_id"] == "reaper_girl" and row["action_file"]["git_blob_sha1"] in REVIEWED_CASTER_SOURCES}
    lowered = {path: lower_static_action(record, path in caster_paths) for path, record in records.items()}
    actions = {row["action_ref"]: row for row in index["actions"]}
    variant_index = {row["skill_id"]: row for row in index["skills"]}
    skills = {row["id"]: row for row in catalog["skills"]}
    variants = []
    blocker_counts: Counter[str] = Counter()
    for skill in catalog["skills"]:
        path = skill["action_file"]["path"]
        if skill["action_file"]["git_blob_sha1"] != sources[path]["git_blob_sha1"] or variant_index[skill["id"]]["root_action_ref"] != skill["action_ref"]:
            raise ValueError("A catalog skill differs from its locked action identity")
        plan = lowered[path]
        missing = sorted(set(variant_index[skill["id"]]["all_opcodes"]) - EXISTING_PARTIAL_FAMILIES - PRESENTATION - SOURCE_POLICY)
        blockers = sorted({row["code"] for row in plan["blockers"]})
        blocker_counts.update(blockers)
        variants.append({"skill_id": skill["id"], "status": "pending", "runtime_profile_ready": plan["runtime_profile_ready"],
                         "root_action_ref": skill["action_ref"], "dependency_action_refs": variant_index[skill["id"]]["dependency_action_refs"],
                         "blockers": blockers, "missing_primitive_families": missing})
    profiles = []
    ready_characters = []
    for character in catalog["characters"]:
        skill = skills.get(character["main_skill_id"] + ":2") or skills[character["main_skill_id"] + ":1"]
        path = skill["action_file"]["path"]
        plan = lowered[path]
        if plan["runtime_profile_ready"]:
            ready_characters.append(character["id"])
        if character["id"] not in REPRESENTATIVES and not plan["runtime_profile_ready"]:
            continue
        record = records[path]
        nodes = [{"opcode": node["name"], "source": evidence(sources[path], node["pointer"]),
                  "scope": node["scope"], "wait_context": node["wait_context"],
                  "arguments_source": [_prune_blocks(value, f"{node['pointer']}/{index}") for index, value in enumerate(node["raw_payload"][1:], 1)]}
                 for node in record["instructions"]]
        gaps = [{"opcode": node["name"], "pointer": node["pointer"],
                 "reason": "Source movement/visibility requires an explicit project adaptation policy; no original command replay is claimed." if node["name"] in SOURCE_POLICY else "Original effect reference/camera command is not replayed; production presentation needs an explicit project adaptation policy."}
                for node in record["instructions"] if node["name"] in SOURCE_POLICY | PRESENTATION]
        profiles.append({"canonical_id": character["id"], "dev_name": character["dev_name"], "name_jp": character["name_jp"],
                         "element": character["element"], "rarity": character["rarity"], "skill_id": skill["id"],
                         "skill_name_jp": character["skill_plus_name_jp"] if skill["rank"] == 2 else character["skill_name_jp"],
                         "status": "pending", "complete_original_action": False, "coverage_level": "representative_area_damage_only", **plan,
                         "root_source": evidence(sources[path], "/11"), "action_ref": skill["action_ref"],
                         "dependencies": [{"action_ref": ref, "source": evidence(sources[actions[ref]["source_path"]], "/11")}
                                          for ref in variant_index[skill["id"]]["dependency_action_refs"]],
                         "mechanism": MECHANISMS.get(character["id"], "Requires individual source review"),
                         "animations": _animations(character["id"], registry), "source_command_gaps": gaps,
                         "remaining_gaps": ["Pending engine implementation and actual gameplay validation.",
                             "Original clock units are unverified; one source unit to1/60 project seconds is an explicit project adaptation.",
                             "Uniform geometry scale, damage and cooldown must be explicitly approved; original rank coefficient bounds are not project damage.",
                             "Original visual-effect assets, StopBall/HideCharacter and opaque positional fields are not silently treated as implemented."],
                         "nodes": nodes})
        for phase in profiles[-1]["timeline"]:
            phase["source"] = evidence(sources[path], phase["pointer"])
    opcodes = set(index["inventory"]["instruction_counts"])
    return {"schema_version": 1, "status": "pending", "source_commit": lock["commit"],
            "input_hashes": {"catalog": hashlib.sha256(DSL.json_bytes(catalog)).hexdigest(),
                             "action_sources": hashlib.sha256(DSL.json_bytes(lock)).hexdigest(),
                             "skill_actions": hashlib.sha256(DSL.json_bytes(index)).hexdigest(),
                             "animation_sources": hashlib.sha256(DSL.json_bytes(registry)).hexdigest()},
            "scope": "Source-bound pending compilation plans. Profile readiness is not engine integration, runtime verification, full original behavior, or playable-character coverage.",
            "time_policy": {"original_units_verified": False, "project_seconds_per_source_unit": SECONDS_PER_UNIT,
                            "nested_waits": "blocked until their clock origin is explicitly reviewed"},
            "runtime_routes": {"existing_partial_mechanism_families": sorted(EXISTING_PARTIAL_FAMILIES),
                               "project_presentation_policy": sorted(PRESENTATION), "movement_or_visibility_policy_required": sorted(SOURCE_POLICY),
                               "missing_primitive_families": sorted(opcodes - EXISTING_PARTIAL_FAMILIES - PRESENTATION - SOURCE_POLICY),
                               "general_dsl_interpreter_implemented": False},
            "counts": {"catalog_variants": len(variants), "verified_source_actions": len(records), "source_opcode_types": len(opcodes),
                       "static_representative_ready_variants": sum(row["runtime_profile_ready"] for row in variants),
                       "static_representative_ready_characters": len(ready_characters), "profile_records": len(profiles),
                       "implemented_by_this_compiler": 0},
            "ready_character_ids": ready_characters, "variant_blocker_counts": dict(sorted(blocker_counts.items())),
            "variants": variants, "profiles": sorted(profiles, key=lambda row: row["canonical_id"])}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=DSL.DEFAULT_CACHE)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    read = lambda path: json.loads(path.read_text(encoding="utf-8"))
    result = build(read(DSL.DEFAULT_CATALOG), read(DSL.DEFAULT_INDEX), read(DSL.DEFAULT_MANIFEST),
                   read(ROOT / "tools/world_flipper_character_animation_sources.json"), args.cache)
    content = DSL.json_bytes(result)
    if args.check:
        if not args.output.is_file() or args.output.read_bytes() != content:
            print("Pending action profiles differ")
            return 1
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(content)
    print(json.dumps(result["counts"]))
    print(f"Pending source plans: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
