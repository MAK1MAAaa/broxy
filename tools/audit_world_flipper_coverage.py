"""Audit actual game mappings against every canonical JP archive identity.

The ledger separates archived, partially adapted and verified playable content.
Its pending ID arrays are derived from the complete catalog, not hand-counted.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
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
    "clarisse": ["原作驱散尚未实现", "背包pulse仍为本作击退技能，尚未与原作炼金爆发对齐", "角色原作能力与技能等级成长尚未完整移植"],
    "celtie": ["原作连击以当前球化连击代理", "背包arc_slash仍为此前改编，尚未与原作双向剑斩完全对齐", "角色原作能力与技能等级成长尚未完整移植"],
    "hanabi": ["原作协力球简化为限时炸弹，不参加常规弹板反射", "背包starfall仍为此前落星改编", "角色原作能力与技能等级成长尚未完整移植"],
}


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
                  "notes": string_property(path, "adaptation_notes")}
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
    return {"schema_version": 1, "scope": "Japanese final archive coverage; catalogued identities are not implemented gameplay. Runtime verification is recorded separately from adaptation status.",
            "claims": claims, "unmapped_game_content": unmapped, "runtime_evidence": None}


def audit(catalog: dict[str, Any], ledger: dict[str, Any], root: Path = ROOT) -> dict[str, Any]:
    original = canonical_sets(catalog)
    result = copy.deepcopy(ledger)
    if set(result["claims"]) != set(CATEGORIES):
        raise ValueError("Coverage categories must include every canonical target")
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
            elif category in ["layouts", "chapters"]:
                raise ValueError("Original layouts and chapters have no implemented game-resource validator yet; keep their identities pending")
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
