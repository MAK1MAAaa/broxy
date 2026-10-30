"""Bind strict source timelines to explicitly chosen project balance and resources."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
ADAPTATIONS = ROOT / "data/worldflipper/roster_adaptations.json"
PROFILES = ROOT / "data/worldflipper/action_profiles.json"
ALIASES = ROOT / "tools/world_flipper_roster.json"
SOURCE_LOCK = ROOT / "tools/world_flipper_skill_action_sources.json"
SPEC = importlib.util.spec_from_file_location("wf_roster_action_compiler", ROOT / "tools/compile_world_flipper_actions.py")
assert SPEC is not None and SPEC.loader is not None
COMPILER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COMPILER)
ART_SPEC = importlib.util.spec_from_file_location("wf_roster_asset_validator", ROOT / "tools/world_flipper_roster.py")
assert ART_SPEC is not None and ART_SPEC.loader is not None
ART = importlib.util.module_from_spec(ART_SPEC)
ART_SPEC.loader.exec_module(ART)


def read(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def literal(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(", ", ": "), allow_nan=False)


def validate_inputs(document: dict[str, Any], catalog: dict[str, Any], aliases: dict[str, Any],
                    lock: dict[str, Any], index: dict[str, Any], animations: dict[str, Any],
                    cache: Path) -> None:
    """Rebuild the index from verified raw bytes before trusting a ready profile."""
    ART.validate_registry(aliases, animations, catalog)
    rebuilt = COMPILER.build(catalog, index, lock, animations, cache)
    if COMPILER.DSL.json_bytes(document) != COMPILER.DSL.json_bytes(rebuilt):
        raise ValueError("Compiled profiles differ from their verified source reconstruction")


def _finite(value: Any, label: str) -> float:
    if type(value) not in (int, float) or not math.isfinite(value):
        raise ValueError(label + " must be a finite number, not a boolean")
    return float(value)


def _validate_identity(binding: dict[str, Any], profile: dict[str, Any], skill: dict[str, Any],
                       source_commit: str) -> None:
    aliases = [hero for hero in read(ALIASES)["heroes"] if hero["game_id"] == binding["id"]]
    if len(aliases) != 1:
        raise ValueError("A character binding requires exactly one independent original-art alias")
    alias = aliases[0]
    if alias["canonical_id"] != binding["canonical_id"] or alias["element"] != profile["element"] or alias["display_name"] != binding["name"]:
        raise ValueError("Character skill identity differs from its independent original-art alias")
    if skill["id"] != binding["profile_id"] or binding["canonical_id"] not in skill["owner_character_ids"] or profile["action_ref"] != skill["action_ref"]:
        raise ValueError("Character skill differs from its canonical owner/action identity")
    lock = read(SOURCE_LOCK)
    if source_commit != lock["commit"]:
        raise ValueError("Character source commit differs from the immutable action-source lock")
    action_file = skill["action_file"]
    sources = [source for source in lock["sources"] if source["path"] == action_file["path"]]
    if len(sources) != 1:
        raise ValueError("Character action requires exactly one locked original source")
    source, locked = profile["root_source"], sources[0]
    if source["status"] != "pending" or source["json_pointer"] != "/11" or source["repository_path"] != action_file["path"] or source["git_blob_sha1"] != action_file["git_blob_sha1"]:
        raise ValueError("Character action evidence differs from its canonical source")
    if any(source[key] != locked[key] for key in ("git_blob_sha1", "sha256", "url")) or source["url"] != COMPILER.DSL.action_url(lock["repository_full_name"], source_commit, action_file["path"]):
        raise ValueError("Character action evidence differs from the fixed blob/SHA/URL")


def _phase(phase: dict[str, Any], root_source: dict[str, Any], scale: float) -> dict[str, Any]:
    shape = phase["shape_source"]
    if not isinstance(shape, list) or len(shape) != 2 or shape[0] != "Circle" or not isinstance(shape[1], list) or len(shape[1]) != 1 or not isinstance(shape[1][0], dict):
        raise ValueError("A new source geometry needs its own explicit runtime adapter")
    radius_range = shape[1][0]
    radius = _finite(radius_range["max"], "Circle radius")
    if radius <= 0 or _finite(radius_range["min"], "Circle radius") != radius:
        raise ValueError("A source circle requires one positive fixed radius")
    delay = _finite(phase["delay"], "Phase delay")
    duration = _finite(phase["duration"], "Phase duration")
    weight = _finite(phase["damage_weight"], "Phase damage weight")
    hits = phase["hits"]
    if not 0 <= delay <= 30 or not 0 < duration <= 10 or type(hits) is not int or not 1 <= hits <= 32 or not 0 < weight <= 1:
        raise ValueError("Source phase exceeds the fixed runtime time/hit/damage budgets")
    source_delay = _finite(phase["delay_source_units"], "Source delay")
    source_duration = _finite(phase["lifetime_source_units"], "Source duration")
    if delay != source_delay * COMPILER.SECONDS_PER_UNIT or duration != source_duration * COMPILER.SECONDS_PER_UNIT or type(phase["maximum_hits"]) is not int or hits != phase["maximum_hits"]:
        raise ValueError("Source timing/hit evidence differs from its runtime phase")
    capture = phase["capture_policy"]
    anchor = "fixed" if capture == "cast" else capture
    if capture not in ("cast", "caster_at_activation", "caster") or phase["anchor"] != anchor or phase["shape"] != "circle":
        raise ValueError("Source phase requires an explicit geometry/anchor adapter")
    offset = phase["origin_offset_source"]
    if not isinstance(offset, list) or len(offset) != 2 or offset != phase["offset_source"]:
        raise ValueError("Source phase offset differs from its retained original evidence")
    x, y = (_finite(value, "Source offset") for value in offset)
    if max(abs(x * scale), abs(y * scale)) > 10240:
        raise ValueError("Source phase exceeds the fixed runtime offset budget")
    source = phase["source"]
    if source["json_pointer"] != phase["pointer"] or any(source[key] != root_source[key] for key in ("status", "repository_path", "git_blob_sha1", "sha256", "url")):
        raise ValueError("Phase evidence differs from its locked root action")
    return {"delay": phase["delay"], "duration": phase["duration"], "hits": hits,
            "damage_weight": phase["damage_weight"], "shape": "circle", "radius": radius * scale,
            "anchor": anchor, "forward_offset": -y * scale, "lateral_offset": x * scale}


def resource(binding: dict[str, Any], profile: dict[str, Any], skill: dict[str, Any], source_commit: str) -> bytes:
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,47}", binding["id"]):
        raise ValueError("A character binding requires a safe game identity")
    if profile["runtime_profile_ready"] is not True or profile["blockers"] or profile["canonical_id"] != binding["canonical_id"] or profile["skill_id"] != binding["profile_id"] or profile["status"] != "pending" or profile["complete_original_action"] is not False:
        raise ValueError("Only reviewed, source-bound representative profiles can be registered")
    _validate_identity(binding, profile, skill, source_commit)
    if type(binding["geometry_scale"]) not in [int, float]:
        raise ValueError("Geometry scale must be numeric")
    scale = float(binding["geometry_scale"])
    if not math.isfinite(scale) or not 0 < scale <= 1:
        raise ValueError("Geometry requires an explicit finite project scale")
    if any(type(binding[key]) not in [float, int] or not math.isfinite(binding[key]) or binding[key] <= 0 for key in ["damage", "cooldown"]):
        raise ValueError("Project damage and cooldown must be explicit positive finite values")
    if not isinstance(profile["timeline"], list) or not 1 <= len(profile["timeline"]) <= 8:
        raise ValueError("Source profile exceeds the fixed phase pool")
    phases = [_phase(phase, profile["root_source"], scale) for phase in profile["timeline"]]
    if not math.isclose(sum(phase["damage_weight"] for phase in phases), 1.0, rel_tol=0.0, abs_tol=1e-7):
        raise ValueError("Phase damage weights must sum to one")
    parameters = {"id": "hero_" + binding["id"], "name": binding["skill_name"], "element": profile["element"],
                  "shape": "circle", "delivery": "areas", "visual_family": binding["visual_family"],
                  "origin_mode": "player", "radius": max(p["radius"] for p in phases),
                  "damage": float(binding["damage"]), "cooldown": float(binding["cooldown"]), "timeline": phases}
    source = profile["root_source"]
    evidence = {"catalog_skill_id": profile["skill_id"], "action_ref": profile["action_ref"],
                "git_blob_sha1": source["git_blob_sha1"], "action_sha256": source["sha256"],
                "source_commit": source_commit, "profile_registry": "data/worldflipper/action_profiles.json",
                "geometry_scale": scale, "time_adaptation": "one source unit = 1/60 project seconds; original FPS unverified",
                "source_pointers": [phase["pointer"] for phase in profile["timeline"]],
                "source_gauge_parameters": skill["fact_parameters"],
                "source_command_gaps": profile["source_command_gaps"]}
    properties = {"id": binding["id"], "display_name": binding["name"], "element": profile["element"],
                  "starter_weapon": binding["starter"], "idle_path": f"res://assets/worldflipper/roster/{binding['id']}/idle.png",
                  "atlas_path": f"res://assets/worldflipper/roster/{binding['id']}/atlas.png",
                  "portrait_path": f"res://assets/worldflipper/roster/{binding['id']}/portrait.png",
                  "frame_size": 128, "base_bonuses": {}, "main_skill": parameters, "action_evidence": evidence,
                  "source_id": binding["canonical_id"], "source_skill_name": binding["skill_name"],
                  "source_skill_weight": int(skill["fact_parameters"]["gauge_column_5"]), "source_url": binding["source_page"],
                  "adaptation_notes": "原动作时间、命中上限与偏移分别追踪；统一0.5几何缩放、自由移动朝向、伤害和冷却为本作适配。原作能力、等级成长与FX尚未完整移植，StopBall及不透明字段不视为已经实现。"}
    header = '[gd_resource type="Resource" script_class="HeroDef" load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://scripts/data/hero_def.gd" id="1"]\n\n[resource]\nscript = ExtResource("1")\nfoot_anchor = Vector2(64, 125)\n'
    return (header + "".join(f"{key} = {literal(value)}\n" for key, value in properties.items())).encode("utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--cache", type=Path, default=COMPILER.DSL.DEFAULT_CACHE)
    args = parser.parse_args()
    document = read(PROFILES)
    catalog = read(ROOT / "data/worldflipper/catalog.json")
    validate_inputs(document, catalog, read(ALIASES), read(SOURCE_LOCK), read(COMPILER.DSL.DEFAULT_INDEX),
                    read(ROOT / "tools/world_flipper_character_animation_sources.json"), args.cache)
    profiles = {p["skill_id"]: p for p in document["profiles"]}
    skills = {s["id"]: s for s in catalog["skills"]}
    outputs: dict[str, str] = {}
    prepared: dict[Path, bytes] = {}
    for binding in read(ADAPTATIONS)["characters"]:
        content = resource(binding, profiles[binding["profile_id"]], skills[binding["profile_id"]], document["source_commit"])
        path = ROOT / "data/heroes" / (binding["id"] + ".tres")
        if path in prepared:
            raise ValueError("Duplicate character binding would overwrite a prepared resource")
        prepared[path] = content
        outputs[binding["id"]] = hashlib.sha256(content).hexdigest()
    for path, content in prepared.items():
        if args.check:
            if path.read_bytes() != content:
                raise ValueError("Character resource differs from its source compilation: " + str(path))
        else:
            path.write_bytes(content)
    print(json.dumps({"checked": args.check, "resources": outputs}))


if __name__ == "__main__":
    main()
