"""Audit actual game mappings against every canonical JP archive identity.

The ledger separates archived, partially adapted and verified playable content.
Its pending ID arrays are derived from the complete catalog, not hand-counted.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import math
import re
from collections import Counter
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "data/worldflipper/catalog.json"
LEDGER = ROOT / "data/worldflipper/implementation.json"
CATEGORIES = ("characters", "equipment", "skills", "fields", "layouts", "chapters")
STATUSES = frozenset({"partial", "adapted_playable", "complete"})
HERO_GAPS = {
    "alk": ["原作多队伍参战者强化改为单人攻击增益", "角色原作能力与技能等级成长尚未完整移植"],
    "clarisse": ["驱散仅覆盖本作临时正面强化，原作完整强化类型尚未逐项移植", "背包pulse仍为本作击退prototype，尚未与原作炼金爆发对齐", "角色原作能力与技能等级成长尚未完整移植"],
    "celtie": ["原作连击以当前球化连击代理，矩形尺寸为自由移动适配", "背包arc_slash仍为此前prototype，尚未与原作矩形剑斩时序完全对齐", "角色原作能力与技能等级成长尚未完整移植"],
    "hanabi": ["原作协力球的MB反射仍为本作适配，限时炸弹不参加常规弹板反射", "背包starfall仍为此前落星prototype，未复用主角投弹时序", "角色原作能力与技能等级成长尚未完整移植"],
}
HERO_NOTES = {
    "alk": "原动作前摇44单位后启用持续20单位的单击圆区，施放时攻击强化已生效；时间按每单位1/60秒适配，攻击增益与R锁定伤害各计算一次。",
    "clarisse": "原动作4击及11击两段爆区共15击、逐次命中火弱点、独立一次临时正面强化驱散及火属性技伤增益已接入；时间、几何和数值为本作适配。",
    "celtie": "原动作前摇25单位后启用持续31单位的前后双向矩形单击区，施放时锁定当前球化连击增伤；矩形范围与时间为本作适配。",
    "hanabi": "前摇55单位、五枚移动炸弹及碰撞后持续30单位的单击爆区已接入；施放时同时预约炸弹和爆区，碰敌、弱点、障碍或到期激活，按真实UID记录命中。",
}
LAYOUT_TARGETS = {
    "jp_sand_2_9_5": "main_2_9_5", "jp_shrine_6_6_2": "main_6_6_2", "jp_ship_3_6_2": "main_3_6_2",
}
LAYOUT_GAPS = [
    "原作props碰撞形状与机关交互未获得定义，未用编辑器椭圆或装饰物猜测碰撞",
    "仅接入layer 0；原作机关、阶段切换、门、墓地及敌人关卡序列尚未完整移植",
    "以BOUNDS矩形限场及外框展示为本作适配，不代表原作存在四面实体封墙",
    "官方试玩与最终日服terrain_ref一致，但最终日服terrain二进制未获得，无法证明逐字节一致",
]
LAYOUT_REGISTRY_SHA256 = "8fc238a6f7ca57a8278358790dc6aff014123b061ef0cbbadf2ad33e6848056d"
LAYOUT_DOCUMENT_SHA256 = "a2ab5d9efd542015189228fc1097a613bb191de29246ea181ee734d52a21e7a1"


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def encoded(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def string_property(path: Path, key: str) -> str:
    match = re.search(r"^" + re.escape(key) + r' = ("(?:[^"\\]|\\.)*")$', path.read_text(encoding="utf-8"), re.MULTILINE)
    return json.loads(match[1]) if match else ""


def canonical_sets(catalog: dict[str, Any]) -> dict[str, dict[str, dict[str, Any]]]:
    return {name: {item["id"]: item for item in (catalog[name] if name in ["characters", "equipment", "skills"] else catalog["maps"][name])} for name in CATEGORIES}


def resolve_source(items: dict[str, dict[str, Any]], source_id: str) -> str:
    if source_id in items:
        return source_id
    matches = [item["id"] for item in items.values() if item.get("dev_name") == source_id]
    if len(matches) == 1:
        return matches[0]
    raise ValueError("Unknown or empty original source ID: " + repr(source_id))


def unique_records(rows: list[dict[str, Any]], label: str) -> dict[str, dict[str, Any]]:
    result = {row["id"]: row for row in rows}
    if len(result) != len(rows):
        raise ValueError("Duplicate " + label + " identity")
    return result


def validate_layout_context(catalog: dict[str, Any], root: Path) -> dict[str, dict[str, Any]]:
    """Check pinned geometry and authored transforms without requiring ignored caches."""
    from PIL import Image

    registry = read_json(root / "tools/world_flipper_layout_sources.json")
    document = read_json(root / "data/worldflipper/layouts.json")
    manifest = read_json(root / "assets/worldflipper/stages/manifest.json")
    if hashlib.sha256(encoded(registry)).hexdigest() != LAYOUT_REGISTRY_SHA256:
        raise ValueError("The pinned 28-source layout registry changed; inspect its source evidence")
    if hashlib.sha256(encoded(document)).hexdigest() != LAYOUT_DOCUMENT_SHA256:
        raise ValueError("Pinned original geometry differs from the reviewed normalized source document")
    sources = unique_records(registry["sources"], "layout source")
    if len(sources) != 28 or Counter(row["role"] for row in sources.values()) != Counter({"terrain": 8, "atlas": 7, "parts": 7, "field_data": 2, "field": 2, "runtime": 1, "pathlist": 1}):
        raise ValueError("The complete 28-source original geometry manifest is required")
    for archive in (registry["archive"], document["archive"], manifest["archive"]):
        if archive["commit"] != catalog["source"]["commit"] or archive["asset_version"] != catalog["source"]["asset_version"] or archive.get("region") != "JP":
            raise ValueError("Layout sources differ from the pinned final JP archive")
    if document["source_registry"] != "tools/world_flipper_layout_sources.json" or document["coordinate_evidence"]["logic_units_per_native_unit"] != 6:
        raise ValueError("Original terrain coordinate evidence is missing")
    if manifest["geometry_registry"] != "data/worldflipper/layouts.json" or manifest["source_registry"] != document["source_registry"] or manifest["adaptation"]["logic_scale"] != 2 / 3 or manifest["adaptation"]["source_pixel_scale"] != 4 or manifest["adaptation"]["world_center"] != [640, 365]:
        raise ValueError("Stage manifest transform differs from the reviewed uniform native 4x mapping")
    canonical = canonical_sets(catalog)
    layouts = unique_records(document["layouts"], "normalized layout")
    arenas = unique_records(read_json(root / "data/arenas.json"), "playable arena")
    stages = unique_records(manifest["stages"], "manifest stage")
    if set(stages) != set(LAYOUT_TARGETS) or {key for key, arena in arenas.items() if "stage" in arena} != set(LAYOUT_TARGETS):
        raise ValueError("Playable original layouts differ from the three reviewed stage mappings")
    pngs = unique_records(read_json(root / "tools/world_flipper_maps_sources.json")["sources"], "background source")
    used: set[str] = set()
    expected_assets: set[str] = set()
    checked: dict[str, dict[str, Any]] = {}
    assets = unique_records(manifest["assets"], "stage PNG")
    for game_id, layout_id in LAYOUT_TARGETS.items():
        arena, stage, layout = arenas[game_id], arenas[game_id]["stage"], layouts[layout_id]
        entry = canonical["layouts"][layout_id]
        source = sources[layout["source_id"]]
        field = canonical["fields"][entry["field_id"]]
        if layout["canonical_layout_ids"] != [layout_id] or layout["terrain_ref"] != entry["terrain_ref"] or source.get("terrain_ref") != entry["terrain_ref"] or layout["field_id"] != entry["field_id"]:
            raise ValueError("Playable layout has no exact canonical terrain/field binding")
        layers = {layer["index"]: layer for layer in layout["layers"]}
        if len(layers) != len(layout["layers"]) or 0 not in layers or len(layers[0]["bounds"]) != 1 or not layers[0]["walls"] or not layers[0]["objects"]:
            raise ValueError("Original layer-0 WALL/BOUNDS geometry is missing")
        layer = layers[0]
        bounds = layer["bounds"][0]["rect"]
        native = [value / 6 for value in bounds]
        if any(type(value) not in (float, int) or not math.isfinite(value) or not float(value).is_integer() for value in native):
            raise ValueError("Native source BOUNDS must describe exact integer pixels")
        native = [int(value) for value in native]
        width, height = native[2] * 4, native[3] * 4
        play = [640 - width / 2, 365 - height / 2, width, height]
        expected = {"layout_id": layout_id, "demo_layout_id": layout["demo_layout_id"], "field_id": entry["field_id"], "layer_index": 0,
                    "source_id": source["id"], "logic_scale": 2 / 3,
                    "logic_offset": [play[0] - bounds[0] * (2 / 3), play[1] - bounds[1] * (2 / 3)],
                    "native_bounds": native, "play_bounds": play, "wall_segment_count": len(layer["walls"]),
                    "source_label": layout_id, "unresolved_prop_count": len(layer["props"])}
        if (width, height) != (720, 1280) or stage != expected or any(arena.get(key) for key in ("obstacles", "crates", "zones")):
            raise ValueError("Stage layer, WALL count, BOUNDS or uniform transform differs from original geometry")
        background = layout["background"]
        png = pngs[background["png_source_registry_id"]]
        if background["ref"] != field["background_ref"] or background["foreground_ref"] != field["foreground_ref"] or background["png_url"] != png["url"] or background["png_sha256"] != png["sha256"] or background["source_size"] != png["source_size"]:
            raise ValueError("Stage background has no exact canonical field/source match")
        source_ids = [png["id"], source["id"], *layout["binding_source_ids"], background["atlas_source_id"], "demo_runtime"]
        if any(identifier not in sources for identifier in source_ids[1:]):
            raise ValueError("A terrain binding/atlas source is absent from the 28-source registry")
        used.update(source_ids)
        expected_stage = {**expected, "id": game_id}
        for key in ("props", "markers"):
            expected_stage[key] = [{**value, "center": [value["center"][axis] * (2 / 3) + expected["logic_offset"][axis] for axis in range(2)]} for value in layer[key]]
        if stages[game_id] != expected_stage or arena["texture"] != f"res://assets/worldflipper/stages/{game_id}.png":
            raise ValueError("Stage manifest no longer represents the real playable geometry or texture")
        for preview in (False, True):
            identifier = game_id + ("_preview" if preview else "")
            expected_assets.add(identifier)
            asset = assets[identifier]
            relative = "assets/worldflipper/stages/" + ("previews/" if preview else "") + game_id + ".png"
            expected_size = [1280, 720] if preview else [3780, 2192]
            if asset["game_id"] != game_id or asset["path"] != relative or asset["source_ids"] != source_ids or asset["world_origin"] != [-1146, -767] or asset["play_bounds"] != play or asset["native_bounds"] != native or asset["source_pixel_scale"] != 4 or asset["size"] != expected_size or asset["preview_crop"] != ([1146, 772, 1280, 720] if preview else None):
                raise ValueError("Stage PNG provenance differs from its original crop and geometry")
            path = root / relative
            if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != asset["sha256"]:
                raise ValueError("Stage PNG is missing or differs from its source manifest")
            with Image.open(path) as image:
                if list(image.size) != expected_size or image.format != "PNG":
                    raise ValueError("Stage PNG dimensions do not match the uniform source transform")
        checked[game_id] = {"canonical_id": layout_id, "source": source["url"]}
    manifest_sources = unique_records(manifest["sources"], "stage manifest source")
    if set(assets) != expected_assets or set(manifest_sources) != used or any(manifest_sources[key] != (pngs[key] if key in pngs else sources[key]) for key in used):
        raise ValueError("Stage manifest source subset/assets differ from the pinned geometry and background records")
    cache = root / ".tools/wf-layout-research"
    if all((cache / source["cache_filename"]).is_file() for source in sources.values()):
        spec = importlib.util.spec_from_file_location("coverage_layout_rebuild", root / "tools/world_flipper_layouts.py")
        if spec is None or spec.loader is None:
            raise ValueError("Missing original geometry rebuilder")
        importer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(importer)
        importer.ROOT = root
        if importer.build(registry, catalog, cache, offline=True) != document:
            raise ValueError("Original geometry does not rebuild from all 28 pinned source bytes")
    return checked


def bootstrap(catalog: dict[str, Any], root: Path = ROOT) -> dict[str, Any]:
    original = canonical_sets(catalog)
    claims: dict[str, list[dict[str, Any]]] = {category: [] for category in CATEGORIES}
    for path in sorted((root / "data/heroes").glob("*.tres")):
        game_id = string_property(path, "id")
        canonical_id = resolve_source(original["characters"], string_property(path, "source_id"))
        resource = path.relative_to(root).as_posix()
        gaps = HERO_GAPS.get(game_id, ["原作角色技能与能力的逐项差异尚待核对"])
        common = {"game_id": game_id, "resource": resource, "source": string_property(path, "source_url"),
                  "status": "partial", "runtime_verified": False, "remaining_gaps": gaps,
                  "notes": HERO_NOTES.get(game_id, string_property(path, "adaptation_notes"))}
        claims["characters"].append({"canonical_id": canonical_id, **copy.deepcopy(common)})
        skill_group = original["characters"][canonical_id]["main_skill_id"]
        for skill in original["skills"].values():
            if skill["group_id"] == skill_group:
                claims["skills"].append({"canonical_id": skill["id"], **copy.deepcopy(common),
                    "game_id": "hero_" + game_id, "notes": "同一R技能对应原作技能组；原作等级变体尚未独立实现。" + common["notes"]})
    old_sources = read_json(root / "tools/world_flipper_sources.json")["sources"]
    new_sources = read_json(root / "tools/world_flipper_weapon_expansion_sources.json")["sources"]
    source_pages = {item["game_id"]: item["source_page"] for item in old_sources + new_sources if item.get("kind") in ["weapon", "weapon_expansion"]}
    expanded = {item["game_id"] for item in new_sources}
    for path in sorted((root / "data/weapons").glob("*.tres")):
        game_id = string_property(path, "id")
        canonical_id = resolve_source(original["equipment"], string_property(path, "source_id"))
        claims["equipment"].append({"canonical_id": canonical_id, "game_id": game_id,
            "resource": path.relative_to(root).as_posix(), "source": source_pages.get(game_id, ""),
            "status": "adapted_playable" if game_id in expanded else "partial", "runtime_verified": False,
            "notes": "原作身份与透明图已接入；基础投射、装备被动及数值采用本作规则。" if game_id in expanded else "沿用原作外观及此前本游戏攻击方式，不代表原作装备能力已经实现。",
            "remaining_gaps": ["原作觉醒能力、角色属性条件与完整成长曲线尚未逐项移植"] if game_id in expanded else ["原作装备被动尚未实现"]})
    unmapped = []
    for source in read_json(root / "tools/world_flipper_maps_sources.json")["sources"]:
        if source.get("kind") != "arena_map":
            continue
        ref = source["url"].split("/production/")[-1].removesuffix(".png")
        matches = [item for item in original["fields"].values() if item["background_ref"] == ref]
        preferred = {"mire": "japan_shrine", "town": "common_skill_preview"}.get(source["game_id"])
        selected = next((item for item in matches if item["id"] == preferred), None) if preferred else matches[0] if len(matches) == 1 else None
        common = {"game_id": source["game_id"], "resource": "tools/world_flipper_maps_sources.json", "source": source["url"], "runtime_verified": False}
        if selected is None:
            unmapped.append({"category": "fields", **common, "status": "demo_only_unmapped", "reason": "官方试玩图的完整背景资源key不在当前锁定的日服最终field表中；保留可玩场景，但不虚构canonical映射。"})
            continue
        claims["fields"].append({"canonical_id": selected["id"], **common, "status": "partial",
            "notes": "仅按相同完整背景资源key对齐场景美术，绝不将共享该背景的其他活动地图一并算作已实现。",
            "remaining_gaps": ["当前为3444×1800重构竞技场，尚未实现原作地形、关卡路径和机关的1:1布局"]})
    geometry_sources = {source["id"]: source for source in read_json(root / "tools/world_flipper_layout_sources.json")["sources"]}
    for arena in read_json(root / "data/arenas.json"):
        if "stage" not in arena:
            continue
        stage = arena["stage"]
        claims["layouts"].append({"canonical_id": stage["layout_id"], "game_id": arena["id"], "resource": "data/arenas.json",
            "source": geometry_sources[stage["source_id"]]["url"], "status": "partial", "runtime_verified": False,
            "notes": "已接入原始layer 0的%d条WALL与BOUNDS、对应完整背景裁切及720×1280可玩区域；原logic坐标统一缩放2/3，对应native像素整数4倍，未叠加其他图层或猜测props碰撞。" % stage["wall_segment_count"],
            "remaining_gaps": list(LAYOUT_GAPS)})
    return {"schema_version": 1, "scope": "Japanese final archive coverage; catalogued identities are not implemented gameplay. Runtime verification is recorded separately from adaptation status.",
            "claims": claims, "unmapped_game_content": unmapped, "runtime_evidence": None}


def audit(catalog: dict[str, Any], ledger: dict[str, Any], root: Path = ROOT) -> dict[str, Any]:
    original = canonical_sets(catalog)
    result = copy.deepcopy(ledger)
    if set(result["claims"]) != set(CATEGORIES):
        raise ValueError("Coverage categories must include every canonical target")
    try:
        layout_bindings = validate_layout_context(catalog, root) if result["claims"]["layouts"] else {}
    except (OSError, KeyError, TypeError, StopIteration) as error:
        raise ValueError("Original layout evidence is missing or malformed: " + str(error)) from error
    counts = {}
    pending = {}
    for category, items in original.items():
        claimed: set[str] = set()
        game_ids: set[str] = set()
        status_counts: Counter[str] = Counter()
        verified = 0
        for entry in result["claims"][category]:
            identifier = entry["canonical_id"]
            if identifier not in items or identifier in claimed:
                raise ValueError("Unknown or duplicate canonical claim: " + category + "/" + identifier)
            claimed.add(identifier)
            if category != "skills" and entry["game_id"] in game_ids:
                raise ValueError("Duplicate game identity within coverage category")
            game_ids.add(entry["game_id"])
            if entry["status"] not in STATUSES or type(entry["runtime_verified"]) is not bool:
                raise ValueError("Unsupported coverage or verification status")
            if not entry.get("source") or not entry.get("resource") or not entry.get("notes"):
                raise ValueError("A coverage claim requires explicit source, resource and notes")
            resource = (root / entry["resource"]).resolve()
            if not resource.is_relative_to(root.resolve()) or not resource.is_file():
                raise ValueError("Coverage resource is missing or leaves the workspace")
            if entry["status"] == "complete" and (entry["remaining_gaps"] or not entry["runtime_verified"] or any(term in entry["notes"] for term in ["未实现", "尚未", "缺少", "未移植", "不完整"])):
                raise ValueError("A complete claim cannot conceal remaining gaps or unverified runtime behavior")
            if category in ["characters", "equipment"]:
                actual = resolve_source(items, string_property(resource, "source_id"))
                if actual != identifier or string_property(resource, "id") != entry["game_id"]:
                    raise ValueError("Coverage identity differs from its actual game resource")
            elif category == "skills":
                actor = resolve_source(original["characters"], string_property(resource, "source_id"))
                if actor not in items[identifier]["owner_character_ids"]:
                    raise ValueError("Covered skill is not owned by the mapped original character")
            elif category == "fields":
                background_ref = entry["source"].split("/production/")[-1].removesuffix(".png")
                if items[identifier]["background_ref"] != background_ref:
                    raise ValueError("Map coverage has no exact original background resource match")
            elif category == "layouts":
                binding = layout_bindings.get(entry["game_id"])
                if entry["resource"] != "data/arenas.json" or binding is None or binding["canonical_id"] != identifier or entry["source"] != binding["source"]:
                    raise ValueError("Covered layout differs from its real canonical geometry resource or exact terrain source")
                if entry["status"] != "partial" or not entry["remaining_gaps"] or not all(any(term in gap for gap in entry["remaining_gaps"]) for term in ("碰撞", "机关", "敌人", "日服")):
                    raise ValueError("Original-layout adaptations must retain partial status and unresolved source/gameplay differences")
            elif category == "chapters":
                raise ValueError("Original chapters have no implemented game-resource validator yet; keep their identities pending")
            status_counts[entry["status"]] += 1
            verified += int(entry["runtime_verified"])
        pending[category] = sorted(set(items) - claimed, key=lambda value: (0, int(value)) if value.isdigit() else (1, value))
        counts[category] = {"canonical": len(items), "pending": len(pending[category]), "partial": status_counts["partial"],
                            "adapted_playable": status_counts["adapted_playable"], "complete": status_counts["complete"], "runtime_verified": verified}
    seen_unmapped = set()
    for item in result["unmapped_game_content"]:
        identity = (item["category"], item["game_id"])
        if identity in seen_unmapped or item.get("status") != "demo_only_unmapped" or not item.get("source") or not item.get("reason"):
            raise ValueError("Invalid, duplicate or overclaimed unmapped content")
        seen_unmapped.add(identity)
        if item["game_id"] in {entry["game_id"] for entry in result["claims"][item["category"]]}:
            raise ValueError("A game map cannot be both mapped and unmapped")
    evidence = result.get("runtime_evidence")
    if any(value["runtime_verified"] for value in counts.values()):
        if not evidence or not evidence.get("report") or not evidence.get("sha256"):
            raise ValueError("Verified runtime claims require a concrete validation report")
        report = root / evidence["report"]
        if not report.is_file() or hashlib.sha256(report.read_bytes()).hexdigest() != evidence["sha256"] or read_json(report).get("passed") is not True:
            raise ValueError("Runtime validation report is missing, stale or unsuccessful")
    result["canonical_source"] = {"commit": catalog["source"]["commit"], "asset_version": catalog["source"]["asset_version"], "catalog_sha256": hashlib.sha256(encoded(catalog)).hexdigest()}
    result["counts"] = counts
    result["pending_ids"] = pending
    result["fully_complete"] = not result["unmapped_game_content"] and all(row["complete"] == row["canonical"] for row in counts.values())
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=CATALOG)
    parser.add_argument("--ledger", type=Path, default=LEDGER)
    parser.add_argument("--write", action="store_true", help="Rebuild derived counts and every pending canonical ID")
    parser.add_argument("--bootstrap", action="store_true", help="Regenerate initial claims; existing runtime verification will be discarded")
    parser.add_argument("--runtime-report", type=Path, help="Attach a successful report and mark current claimed game content runtime-verified")
    args = parser.parse_args()
    try:
        catalog = read_json(args.catalog)
        ledger = bootstrap(catalog) if args.bootstrap or not args.ledger.exists() else read_json(args.ledger)
        if args.runtime_report is not None:
            report = args.runtime_report.resolve()
            if not report.is_relative_to(ROOT) or read_json(report).get("passed") is not True:
                raise ValueError("Runtime report must be a successful workspace validation artifact")
            ledger["runtime_evidence"] = {"report": report.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(report.read_bytes()).hexdigest()}
            for entries in ledger["claims"].values():
                for entry in entries:
                    entry["runtime_verified"] = True
            for entry in ledger["unmapped_game_content"]:
                entry["runtime_verified"] = True
        result = audit(catalog, ledger)
        data = encoded(result)
        if args.write:
            args.ledger.parent.mkdir(parents=True, exist_ok=True)
            args.ledger.write_bytes(data)
        elif not args.ledger.exists() or args.ledger.read_bytes() != data:
            raise ValueError("Coverage ledger is stale; inspect claims, then rebuild with --write")
        print(json.dumps({"counts": result["counts"], "unmapped_game_maps": len(result["unmapped_game_content"]), "fully_complete": result["fully_complete"]}))
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"Coverage audit failed: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
