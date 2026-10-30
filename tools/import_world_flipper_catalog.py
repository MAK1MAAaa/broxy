"""Rebuild a factual JP archive index from pinned, hash-checked original tables.

Raw dumps remain in .tools. This index records identities and references; it does
not claim that archived skills, equipment effects or map layouts are playable.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import urllib.request
from collections import defaultdict
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
LOCK_PATH = ROOT / "tools/world_flipper_catalog_sources.json"
OUTPUT_PATH = ROOT / "data/worldflipper/catalog.json"
CACHE_PATH = ROOT / ".tools/worldflipper/catalog/raw"
MAX_SOURCE_BYTES = 16 * 1024 * 1024
ELEMENTS = {"0": "fire", "1": "water", "2": "thunder", "3": "wind", "4": "light", "5": "dark"}

FIELD_MAPPING: dict[str, dict[str, Any]] = {
    "characters": {
        "shape": "original_id -> [one positional row]",
        "decoded": {"0": "dev_name", "2": "rarity", "3": "element_code", "4": "race_codes", "7": "gender_code", "8": "main_skill_id", "19..24": "ability_ids", "26": "stance_code"},
        "unknown_columns": "All other columns remain uninterpreted strings in raw_fields.",
    },
    "character_text": {
        "decoded": {"0": "name_jp", "3": "title_jp", "4": "skill_name_jp", "6": "skill_plus_name_jp"},
        "omitted": "Biography and skill-description prose are not copied into the normalized index.",
    },
    "equipment": {
        "shape": "original_id -> [one positional row]",
        "decoded": {"0": "dev_name", "1": "name_jp", "3": "fullsize_ref", "4": "thumbnail_ref", "6": "resource_ref", "11": "rarity"},
        "omitted_columns": [5, 7],
        "unknown_columns": "Resource references are not asserted to be PNG URLs or executable effects. Other non-prose columns stay raw.",
    },
    "skills": {
        "shape": "skill_group_id -> rank -> [one positional row]",
        "decoded": {"2": "icon_ref", "4": "gauge_column_4", "5": "gauge_column_5", "7": "action_ref"},
        "units": "Gauge values retain original game gauge units, not seconds, damage or cooldowns in this project.",
        "unknown_columns": "All 24 original strings remain in raw_fields. Other numeric strings have no invented semantic labels.",
        "action_lookup": "assets/{action_ref}.action.dsl.json in the pinned asset tree",
    },
    "switched_skills": {"shape": "skill_group_id -> rank -> positional rows", "decoded": {"0": "action_ref"}, "unknown_columns": "Remaining fields stay raw; switched actions are not assumed active for every owner."},
    "character_status": {"shape": "character_id -> level -> [[HP, ATK]]", "units": "Original base stats, not this game's balance."},
    "equipment_status": {"shape": "equipment_id -> upgrade_level -> [[HP, ATK]]", "units": "Original equipment stats, not this game's balance."},
    "fields": {"shape": "field_id -> [one positional row]", "decoded": {"0": "background_ref", "1": "foreground_ref", "2": "added_ref"}, "unknown_columns": "All ten resource slots stay in raw_fields; their presence is not evidence that image binaries are in this archive."},
    "layouts": {"shape": "layout_id -> [one positional row]", "decoded": {"0": "field_id", "1": "terrain_ref", "2": "dev_name"}},
    "floors": {"shape": "floor_group_id -> positional rows", "decoded": {}, "unknown_columns": "Challenge-floor rows retain three original fields without guessing their relationship to field_data."},
    "chapters": {"shape": "chapter_id -> [one positional row]", "decoded": {"0": "name_jp"}, "unknown_columns": "Other columns are retained resource references."},
}


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def load_lock(path: Path = LOCK_PATH) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def load_source(source: dict[str, Any], cache: Path, offline: bool) -> Any:
    filename = str(source["cache_filename"])
    if Path(filename).name != filename:
        raise ValueError("Unsafe cache filename")
    expected_bytes = int(source["bytes"])
    if not 0 < expected_bytes <= MAX_SOURCE_BYTES:
        raise ValueError("Invalid source size limit")
    path = cache / filename
    if path.exists():
        if path.stat().st_size != expected_bytes:
            raise ValueError(f"Source hash or size mismatch: {source['id']}")
        data = path.read_bytes()
    elif offline:
        raise FileNotFoundError(f"Offline source is missing: {path}")
    else:
        request = urllib.request.Request(str(source["url"]), headers={"User-Agent": "broxy-world-flipper-catalog/1"})
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read(expected_bytes + 1)
        if len(data) != expected_bytes or hashlib.sha256(data).hexdigest() != source["sha256"]:
            raise ValueError(f"Downloaded source hash mismatch: {source['id']}")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    if len(data) != source["bytes"] or hashlib.sha256(data).hexdigest() != source["sha256"]:
        raise ValueError(f"Source hash or size mismatch: {source['id']}")
    if source["format"] == "text":
        return data.decode("utf-8").strip()
    result = json.loads(data)
    records = len(result["tree"]) if source["id"] == "asset_tree" else len(result)
    if records != source["records"]:
        raise ValueError(f"Source record-count mismatch: {source['id']}")
    return result


def _one_row(rows: Any, size: int, context: str) -> list[str]:
    if not isinstance(rows, list) or len(rows) != 1 or not isinstance(rows[0], list) or len(rows[0]) != size or not all(isinstance(v, str) for v in rows[0]):
        raise ValueError(f"Unexpected original row shape: {context}")
    return rows[0]


def _stats(raw: dict[str, Any]) -> list[dict[str, int]]:
    result = []
    for level, rows in sorted(raw.items(), key=lambda pair: int(pair[0])):
        row = _one_row(rows, 2, "original stats")
        result.append({"level": int(level), "hp": int(row[0]), "atk": int(row[1])})
    return result


def _action_file(ref: str, tree: dict[str, dict[str, Any]]) -> dict[str, str]:
    path = f"assets/{ref}.action.dsl.json"
    entry = tree.get(path)
    if entry is None or entry["type"] != "blob":
        raise ValueError(f"Missing archived skill action: {path}")
    return {"path": path, "git_blob_sha1": entry["sha"]}


def normalize_catalog(tables: dict[str, Any], lock: dict[str, Any]) -> dict[str, Any]:
    if tables["version"] != lock["asset_version"] or tables["asset_tree"].get("truncated"):
        raise ValueError("Archive version mismatch or truncated asset tree")
    tree = {entry["path"]: entry for entry in tables["asset_tree"]["tree"]}
    characters = []
    owners: dict[str, list[str]] = defaultdict(list)
    for original_id, rows in sorted(tables["characters"].items(), key=lambda pair: int(pair[0])):
        row = _one_row(rows, 37, "character " + original_id)
        text = _one_row(tables["character_text"][original_id], 10, "character text " + original_id)
        if row[3] not in ELEMENTS:
            raise ValueError("Unknown original element code: " + row[3])
        owners[row[8]].append(original_id)
        characters.append({
            "id": original_id, "dev_name": row[0], "name_jp": text[0], "title_jp": text[3],
            "rarity": int(row[2]), "element": ELEMENTS[row[3]], "element_code": row[3],
            "main_skill_id": row[8], "skill_name_jp": text[4], "skill_plus_name_jp": text[6],
            "ability_ids": row[19:25], "base_stats": _stats(tables["character_status"][original_id]),
            "raw_fields": row,
        })
    equipment = []
    for original_id, rows in sorted(tables["equipment"].items(), key=lambda pair: int(pair[0])):
        row = _one_row(rows, 16, "equipment " + original_id)
        equipment.append({
            "id": original_id, "dev_name": row[0], "name_jp": row[1], "rarity": int(row[11]),
            "resource_ref": row[6], "fullsize_ref": row[3], "thumbnail_ref": row[4],
            "base_stats": _stats(tables["equipment_status"][original_id]),
            "raw_fields": {str(index): value for index, value in enumerate(row) if index not in [5, 7]},
        })
    skills = []
    for group, ranks in sorted(tables["skills"].items()):
        for rank, rows in sorted(ranks.items(), key=lambda pair: int(pair[0])):
            row = _one_row(rows, 24, "skill " + group)
            skills.append({
                "id": f"{group}:{rank}", "group_id": group, "rank": int(rank),
                "owner_character_ids": owners.get(group, []), "icon_ref": row[2], "action_ref": row[7],
                "action_file": _action_file(row[7], tree),
                "fact_parameters": {"gauge_column_4": int(row[4]), "gauge_column_5": int(row[5]), "unit": "original_skill_gauge"},
                "raw_fields": row,
            })
    switched = []
    for group, ranks in sorted(tables["switched_skills"].items()):
        for rank, rows in sorted(ranks.items(), key=lambda pair: int(pair[0])):
            for index, row in enumerate(rows):
                switched.append({"id": f"{group}:{rank}:{index}", "group_id": group, "rank": int(rank),
                                 "action_ref": row[0], "action_file": _action_file(row[0], tree), "raw_fields": row})
    fields = []
    for original_id, rows in sorted(tables["fields"].items()):
        row = _one_row(rows, 10, "field " + original_id)
        fields.append({"id": original_id, "background_ref": row[0], "foreground_ref": row[1], "added_ref": row[2], "raw_fields": row})
    layouts = []
    for original_id, rows in sorted(tables["layouts"].items()):
        row = _one_row(rows, 3, "layout " + original_id)
        layouts.append({"id": original_id, "field_id": row[0], "terrain_ref": row[1], "dev_name": row[2], "raw_fields": row})
    chapters = []
    for original_id, rows in sorted(tables["chapters"].items(), key=lambda pair: int(pair[0])):
        row = _one_row(rows, 11, "chapter " + original_id)
        chapters.append({"id": original_id, "name_jp": row[0], "raw_fields": row})
    result = {
        "schema_version": 1, "source": {key: lock[key] for key in ["repository", "commit", "commit_date", "region", "asset_version", "license_status"]},
        "scope": "Canonical factual archive, including independent seasonal/collaboration IDs. Catalog presence does not mean gameplay implementation.",
        "field_mapping": FIELD_MAPPING, "characters": characters, "equipment": equipment, "skills": skills,
        "switched_skills": switched, "maps": {"fields": fields, "layouts": layouts, "chapters": chapters,
            "floor_groups": [{"id": original_id, "raw_rows": rows} for original_id, rows in sorted(tables["floors"].items())]},
        "counts": {"characters": len(characters), "equipment": len(equipment), "skill_groups": len(tables["skills"]),
            "skills": len(skills), "switched_skill_groups": len(tables["switched_skills"]), "fields": len(fields),
            "layouts": len(layouts), "floor_groups": len(tables["floors"]), "chapters": len(chapters)},
    }
    validate_catalog(result, lock)
    return result


def validate_catalog(catalog: dict[str, Any], lock: dict[str, Any]) -> None:
    if catalog["source"]["commit"] != lock["commit"] or catalog["source"]["asset_version"] != lock["asset_version"]:
        raise ValueError("Normalized source identity mismatch")
    if catalog["counts"] != lock["expected_counts"]:
        raise ValueError("Canonical count mismatch")
    groups: dict[str, set[int]] = defaultdict(set)
    for skill in catalog["skills"]:
        groups[skill["group_id"]].add(skill["rank"])
        if not skill["action_ref"] or len(skill["action_file"]["git_blob_sha1"]) != 40 or len(skill["raw_fields"]) != 24:
            raise ValueError("Invalid skill action reference")
    for name in ["characters", "equipment", "skills"]:
        items = catalog[name]
        if len(items) != catalog["counts"][name] or len({item["id"] for item in items}) != len(items):
            raise ValueError("Duplicate or missing canonical " + name)
    if len(groups) != catalog["counts"]["skill_groups"]:
        raise ValueError("Canonical skill-group mismatch")
    for name in ["characters", "equipment"]:
        items = catalog[name]
        if len({item["dev_name"] for item in items}) != len(items) or any(not item["name_jp"] or item["rarity"] not in range(1, 6) for item in items):
            raise ValueError("Invalid identity or rarity: " + name)
    character_ids = {item["id"] for item in catalog["characters"]}
    for character in catalog["characters"]:
        if character["main_skill_id"] not in groups or character["element_code"] not in ELEMENTS:
            raise ValueError("Unresolved character skill or element")
    for skill in catalog["skills"]:
        if any(owner not in character_ids for owner in skill["owner_character_ids"]):
            raise ValueError("Unresolved skill owner")
    maps = catalog["maps"]
    for name in ["fields", "layouts", "floor_groups", "chapters"]:
        if len(maps[name]) != catalog["counts"][name] or len({item["id"] for item in maps[name]}) != len(maps[name]):
            raise ValueError("Duplicate or missing canonical map entries: " + name)
    fields = {item["id"] for item in maps["fields"]}
    if any(item["field_id"] not in fields for item in maps["layouts"]):
        raise ValueError("Unresolved map layout field")


def rebuild(lock: dict[str, Any], cache: Path, offline: bool) -> dict[str, Any]:
    return normalize_catalog({source["id"]: load_source(source, cache, offline) for source in lock["sources"]}, lock)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path, default=LOCK_PATH)
    parser.add_argument("--cache", type=Path, default=CACHE_PATH)
    parser.add_argument("--output", type=Path, default=OUTPUT_PATH)
    parser.add_argument("--offline", action="store_true", help="Require all hash-checked raw sources in the cache")
    parser.add_argument("--check", action="store_true", help="Compare the rebuilt bytes with the tracked output")
    args = parser.parse_args()
    try:
        lock = load_lock(args.sources)
        catalog = rebuild(lock, args.cache, args.offline)
        encoded = json_bytes(catalog)
        if args.check:
            if not args.output.exists() or args.output.read_bytes() != encoded:
                raise ValueError("Tracked catalog differs from the deterministic rebuild")
        else:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_bytes(encoded)
        print(json.dumps({"counts": catalog["counts"], "sha256": hashlib.sha256(encoded).hexdigest(), "checked": args.check}))
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"Catalog import failed: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
