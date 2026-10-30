"""Verify and structurally index pinned World Flipper action DSL sources.

This is a research extractor, not an interpreter. Positional values and nested
callback scopes remain available even when the original engine semantics are
unknown. Raw archives and generated reports stay under .tools by default.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import time
import urllib.parse
import urllib.request
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path, PurePosixPath
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "tools/world_flipper_skill_action_sources.json"
DEFAULT_CATALOG = ROOT / "data/worldflipper/catalog.json"
DEFAULT_CACHE = ROOT / ".tools/wf-skill-research"
DEFAULT_INDEX = ROOT / "data/worldflipper/skill_actions.json"
MAX_ACTION_BYTES = 4 * 1024 * 1024
SHA1_PATTERN = re.compile(r"[0-9a-f]{40}\Z")


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def git_blob_sha1(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()


def action_url(repository: str, commit: str, path: str) -> str:
    if not SHA1_PATTERN.fullmatch(commit):
        raise ValueError("An immutable full commit SHA is required")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid GitHub repository")
    parts = PurePosixPath(path).parts
    if not parts or parts[0] != "assets" or ".." in parts or "\\" in path:
        raise ValueError("Invalid asset repository path")
    return f"https://raw.githubusercontent.com/{repository}/{commit}/{urllib.parse.quote(path, safe='/$')}"


def verified_action(data: bytes, source: dict[str, Any]) -> Any:
    if not 0 < len(data) <= MAX_ACTION_BYTES:
        raise ValueError(f"Invalid action source size: {source['path']}")
    expected = source["git_blob_sha1"]
    if not isinstance(expected, str) or not SHA1_PATTERN.fullmatch(expected):
        raise ValueError("Invalid expected Git blob SHA")
    if git_blob_sha1(data) != expected:
        raise ValueError(f"Git blob SHA mismatch: {source['path']}")
    if source.get("sha256") and hashlib.sha256(data).hexdigest() != source["sha256"]:
        raise ValueError(f"SHA256 mismatch: {source['path']}")
    if source.get("bytes") is not None and len(data) != source["bytes"]:
        raise ValueError(f"Byte count mismatch: {source['path']}")
    value = json.loads(data)
    if not isinstance(value, list) or len(value) < 12 or value[0] != "ActionDsl":
        raise ValueError(f"Not an ActionDsl document: {source['path']}")
    if not isinstance(value[11], list) or not value[11] or value[11][0] != "Block":
        raise ValueError(f"Unexpected ActionDsl root block: {source['path']}")
    return value


def cache_file(cache: Path, source: dict[str, Any]) -> Path:
    filename = source.get("cache_filename", f"raw/{source['git_blob_sha1']}.json")
    if not isinstance(filename, str) or "\\" in filename or Path(filename).is_absolute():
        raise ValueError("Unsafe cache filename")
    result = (cache / filename).resolve()
    if not result.is_relative_to(cache.resolve()):
        raise ValueError("Cache path escapes the research directory")
    return result


def load_action(source: dict[str, Any], manifest: dict[str, Any], cache: Path, offline: bool) -> tuple[Any, dict[str, Any]]:
    path = cache_file(cache, source)
    if path.exists():
        data = path.read_bytes()
        value = verified_action(data, source)
    elif offline:
        raise FileNotFoundError(f"Offline action source is missing: {path}")
    else:
        url = action_url(manifest["repository_full_name"], manifest["commit"], source["path"])
        for attempt in range(3):
            try:
                request = urllib.request.Request(url, headers={"User-Agent": "broxy-world-flipper-action-research/1"})
                with urllib.request.urlopen(request, timeout=30) as response:
                    data = response.read(MAX_ACTION_BYTES + 1)
                value = verified_action(data, source)
                break
            except (OSError, ValueError):
                if attempt == 2:
                    raise
                time.sleep(0.25 * (attempt + 1))
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    evidence = {**source, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), "verified_git_blob_sha1": git_blob_sha1(data)}
    return value, evidence


def pointer_value(document: Any, pointer: str) -> Any:
    current = document
    if not pointer:
        return current
    if not pointer.startswith("/"):
        raise ValueError("JSON pointer must be empty or absolute")
    for part in pointer[1:].split("/"):
        token = part.replace("~1", "/").replace("~0", "~")
        current = current[int(token)] if isinstance(current, list) else current[token]
    return current


def _reference(payload: list[Any], pointer: str, index: int) -> dict[str, Any] | None:
    if index >= len(payload):
        return None
    return {"pointer": f"{pointer}/{index}", "raw_value": payload[index]}


def _direct_instructions(block: Any, pointer: str) -> list[str]:
    if not isinstance(block, list) or len(block) != 2 or block[0] != "Block" or not isinstance(block[1], list):
        return []
    return [f"{pointer}/1/{index}/1" for index, value in enumerate(block[1]) if isinstance(value, list) and len(value) == 2 and value[0] in ("Command", "Event")]


def _project_instruction(payload: list[Any], pointer: str) -> dict[str, Any]:
    name = payload[0]
    indices: dict[str, int] = {}
    if name == "Wait":
        indices = {"delay_raw": 1, "selector_raw": 2}
    elif name == "CreateHitArea":
        indices = {"subject_raw": 2, "coordinate_tag_raw": 3, "offset_x_raw": 4, "offset_y_raw": 5, "rotation_raw": 6,
                   "shape": 9, "alignment_x_raw": 10, "alignment_y_raw": 11, "placement_tag_raw": 12,
                   "lifetime": 13, "hit_policy": 14, "parameter_15_raw": 15,
                   "parameter_19_raw": 19, "parameter_21_raw": 21, "target_register_raw": 22}
    elif name == "CreateNormalAttack":
        indices = {"target_raw": 1, "element_raw": 2, "condition_filter_raw": 4, "coefficient_range_raw": 6}
    elif name == "CreateCondition":
        indices = {"target_raw": 1, "condition_specs_raw": 2}
    elif name == "DeleteCondition":
        indices = {"target_raw": 1, "selector_raw": 2}
    elif name == "CreateRatioHeal":
        indices = {"target_raw": 1, "parameter_2_raw": 2, "ratio_range_raw": 3, "parameter_4_raw": 4, "parameter_5_raw": 5}
    elif name == "AddSkillPoint":
        indices = {"target_raw": 1, "amount_range_raw": 2}
    elif name == "CreateBombMultiball":
        indices = {"count_raw": 1, "resource_ref_raw": 2, "child_action_ref_raw": 6}
    projected = {key: reference for key, index in indices.items() if (reference := _reference(payload, pointer, index)) is not None}
    if name == "CreateHitArea":
        if len(payload) > 14 and isinstance(payload[14], list) and len(payload[14]) == 2:
            tag = payload[14][0]
            if tag in ("CalculatedUsingMaxNumOfHits", "SpecifyMinHitIntervalDirectly"):
                key = "max_hits_raw" if tag == "CalculatedUsingMaxNumOfHits" else "min_hit_interval_raw"
                projected[key] = {"pointer": f"{pointer}/14/1", "raw_value": payload[14][1]}
        projected["callback_blocks"] = [{"parameter_index": index, "pointer": f"{pointer}/{index}",
                                          "role": "hit_callback" if index == 23 else "parameter_20_block",
                                          "direct_instruction_pointers": _direct_instructions(payload[index], f"{pointer}/{index}")}
                                         for index in (20, 23) if index < len(payload) and isinstance(payload[index], list)
                                         and payload[index] and payload[index][0] == "Block"]
    return projected


def extract_action(document: Any) -> dict[str, Any]:
    """Preserve lexical scope and raw pointers; never invent timing or effects."""
    instructions: list[dict[str, Any]] = []
    dependencies: dict[str, list[str]] = {}

    def walk(value: Any, pointer: str, scopes: list[dict[str, Any]], waits: list[dict[str, Any]]) -> None:
        if isinstance(value, str):
            if value.startswith("battle/action/"):
                dependencies.setdefault(value, []).append(pointer)
            return
        if isinstance(value, dict):
            for key, child in value.items():
                escaped = str(key).replace("~", "~0").replace("/", "~1")
                walk(child, f"{pointer}/{escaped}", scopes, waits)
            return
        if not isinstance(value, list):
            return
        if len(value) == 2 and isinstance(value[0], str) and value[0] in ("Command", "Event"):
            payload = value[1]
            if not isinstance(payload, list) or not payload or not isinstance(payload[0], str):
                raise ValueError(f"Malformed instruction wrapper: {pointer}")
            command_pointer = f"{pointer}/1"
            name = payload[0]
            instructions.append({"name": name, "wrapper": value[0], "pointer": command_pointer,
                                 "scope": list(scopes), "wait_context": list(waits), "raw_payload": payload,
                                 "fields": _project_instruction(payload, command_pointer)})
            for index, child in enumerate(payload[1:], start=1):
                child_scopes, child_waits = scopes, waits
                if isinstance(child, list) and child and child[0] == "Block":
                    role = "hit_callback" if name == "CreateHitArea" and index == 23 else "nested_block"
                    child_scopes = [*scopes, {"owner": command_pointer, "instruction": name, "parameter_index": index, "role": role}]
                    if name == "Wait":
                        child_waits = [*waits, {"pointer": command_pointer, "delay_raw": payload[1] if len(payload) > 1 else None,
                                              "selector_raw": payload[2] if len(payload) > 2 else None}]
                walk(child, f"{command_pointer}/{index}", child_scopes, child_waits)
            return
        for index, child in enumerate(value):
            walk(child, f"{pointer}/{index}", scopes, waits)

    walk(document, "", [], [])
    counts = Counter(instruction["name"] for instruction in instructions)
    return {"root_tag": document[0], "root_header_raw": document[:11], "root_block_pointer": "/11",
            "instruction_counts": dict(sorted(counts.items())), "instructions": instructions,
            "action_dependencies": [{"action_ref": ref, "pointers": pointers} for ref, pointers in sorted(dependencies.items())]}


def catalog_sources(catalog: dict[str, Any], tree: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    """Deduplicate actual indexed paths, retaining every skill-rank reference."""
    sources: dict[str, dict[str, Any]] = {}
    for skill in catalog["skills"]:
        action = skill.get("action_file")
        if not action:
            raise ValueError(f"Catalog skill has no action file: {skill['id']}")
        path, sha = action["path"], action["git_blob_sha1"]
        if path in sources and sources[path]["git_blob_sha1"] != sha:
            raise ValueError(f"Conflicting action SHA: {path}")
        source = sources.setdefault(path, {"path": path, "git_blob_sha1": sha, "skill_ids": [], "kind": "catalog_action"})
        source["skill_ids"].append(skill["id"])
    if tree is not None:
        entries = {entry["path"]: entry["sha"] for entry in tree["tree"] if entry.get("type") == "blob"}
        for source in sources.values():
            if entries.get(source["path"]) != source["git_blob_sha1"]:
                raise ValueError(f"Action file disagrees with pinned tree: {source['path']}")
    return sorted(sources.values(), key=lambda item: item["path"])


def dependency_source(action_ref: str, tree: dict[str, Any]) -> dict[str, Any]:
    path = f"assets/{action_ref}.action.dsl.json"
    for entry in tree["tree"]:
        if entry["path"] == path and entry.get("type") == "blob":
            return {"path": path, "git_blob_sha1": entry["sha"], "kind": "child_action", "action_ref": action_ref}
    raise ValueError(f"Referenced action is absent from pinned tree: {action_ref}")


def research(sources: list[dict[str, Any]], manifest: dict[str, Any], cache: Path, offline: bool,
             workers: int, tree: dict[str, Any] | None = None) -> dict[str, Any]:
    remaining = sources
    completed: dict[str, dict[str, Any]] = {}
    failures: dict[str, str] = {}
    missing_dependencies: dict[str, str] = {}
    locked_sources = {source["path"]: source for source in manifest.get("sources", [])}
    while remaining:
        with ThreadPoolExecutor(max_workers=workers) as executor:
            futures = {executor.submit(load_action, source, manifest, cache, offline): source for source in remaining}
            for future in as_completed(futures):
                source = futures[future]
                try:
                    document, evidence = future.result()
                    extracted = extract_action(document)
                    completed[source["path"]] = {"source": evidence, **extracted}
                except (OSError, ValueError, KeyError, TypeError) as error:
                    failures[source["path"]] = f"{type(error).__name__}: {error}"
                if (len(completed) + len(failures)) % 50 == 0:
                    print(f"Verified {len(completed)} actions; failed {len(failures)}", flush=True)
        pending: dict[str, dict[str, Any]] = {}
        for record in completed.values():
            for dependency in record["action_dependencies"]:
                ref = dependency["action_ref"]
                path = f"assets/{ref}.action.dsl.json"
                if path in completed or path in failures:
                    continue
                if path in locked_sources:
                    pending[path] = locked_sources[path]
                    continue
                if tree is None:
                    missing_dependencies[ref] = "No pinned tree supplied for recursive lookup"
                    continue
                try:
                    pending[path] = dependency_source(ref, tree)
                except ValueError as error:
                    missing_dependencies[ref] = str(error)
        remaining = list(pending.values())
    counts: Counter[str] = Counter()
    for record in completed.values():
        counts.update(record["instruction_counts"])
    return {"schema_version": 1, "repository": manifest["repository_full_name"], "commit": manifest["commit"],
            "interpretation_status": "Structural research only; no claim that any extracted opcode is executable in this game.",
            "timing_policy": "Wait and lifetime values retain raw units; no original FPS or seconds conversion is asserted.",
            "scope_policy": "Wait contexts and callback blocks are lexical; nested delays are not flattened or summed.",
            "requested_root_files": len(sources), "verified_files": len(completed), "failure_count": len(failures),
            "instruction_counts": dict(sorted(counts.items())), "failures": failures,
            "unresolved_action_dependencies": missing_dependencies, "actions": [completed[path] for path in sorted(completed)]}


def compact_index(report: dict[str, Any], catalog: dict[str, Any], manifest: dict[str, Any]) -> dict[str, Any]:
    """Index factual operations and areas without copying the original AST."""
    if report["failure_count"] or report["unresolved_action_dependencies"]:
        raise ValueError("Cannot index an incomplete source extraction")
    locked_sources = {source["path"]: source for source in manifest["sources"]}
    records = {record["source"]["path"]: record for record in report["actions"]}
    roots = catalog_sources(catalog)
    missing = {source["path"] for source in roots} - records.keys()
    if missing:
        raise ValueError(f"Cannot index missing catalog roots: {sorted(missing)[:3]}")
    if catalog["source"]["commit"] != manifest["commit"] or report["commit"] != manifest["commit"]:
        raise ValueError("Catalog, report and source manifest commits differ")
    for path, record in records.items():
        if path not in locked_sources or record["source"]["git_blob_sha1"] != locked_sources[path]["git_blob_sha1"]:
            raise ValueError(f"Extraction source disagrees with source manifest: {path}")
        if record["source"]["sha256"] != locked_sources[path]["sha256"] or record["source"]["bytes"] != locked_sources[path]["bytes"]:
            raise ValueError(f"Extraction byte verification disagrees with source manifest: {path}")
    action_ref = lambda path: path.removeprefix("assets/").removesuffix(".action.dsl.json")
    path_for_ref = {action_ref(path): path for path in records}
    direct_dependencies = {path: sorted({dependency["action_ref"] for dependency in record["action_dependencies"]}) for path, record in records.items()}
    for refs in direct_dependencies.values():
        if any(ref not in path_for_ref for ref in refs):
            raise ValueError("An action dependency is absent from verified sources")

    def closure(path: str) -> list[str]:
        visited = {action_ref(path)}
        pending = list(direct_dependencies[path])
        result = set()
        while pending:
            ref = pending.pop()
            if ref in visited:
                continue
            visited.add(ref)
            result.add(ref)
            pending.extend(direct_dependencies[path_for_ref[ref]])
        return sorted(result)

    compact_actions = []
    shape_counts: Counter[str] = Counter()
    lifetime_counts: Counter[str] = Counter()
    hit_policy_counts: Counter[str] = Counter()
    condition_counts: Counter[str] = Counter()
    for path, record in sorted(records.items()):
        operations: dict[str, list[str]] = {}
        waits = []
        areas = []
        bomb_summons = []
        condition_types = set()
        for instruction in record["instructions"]:
            name, pointer, payload = instruction["name"], instruction["pointer"], instruction["raw_payload"]
            operations.setdefault(name, []).append(pointer)
            if name == "Wait":
                waits.append({"pointer": pointer, "delay_raw": payload[1] if len(payload) > 1 else None,
                              "selector_raw": payload[2] if len(payload) > 2 else None,
                              "enclosing_wait_pointers": [wait["pointer"] for wait in instruction["wait_context"]]})
            elif name == "CreateHitArea":
                if len(payload) != 27:
                    raise ValueError(f"Unrecognized hit-area shape at {path}#{pointer}")
                area = {"pointer": pointer, "scope": instruction["scope"],
                        "wait_pointers": [wait["pointer"] for wait in instruction["wait_context"]],
                        "subject_raw": payload[2], "coordinate_tag_raw": payload[3], "offset_raw": payload[4:7],
                        "flags_7_8_raw": payload[7:9], "shape_raw": payload[9], "lifetime_raw": payload[13],
                        "hit_policy_raw": payload[14], "parameter_15_raw": payload[15], "target_register_raw": payload[22],
                        "callback_blocks": [{"parameter_index": index, "pointer": f"{pointer}/{index}"} for index in (20, 23)
                                            if isinstance(payload[index], list) and payload[index] and payload[index][0] == "Block"]}
                areas.append(area)
                for counter, index in ((shape_counts, 9), (lifetime_counts, 13), (hit_policy_counts, 14)):
                    tagged = payload[index]
                    counter[tagged[0] if isinstance(tagged, list) and tagged and isinstance(tagged[0], str) else "<unrecognized>"] += 1
            elif name == "CreateCondition" and len(payload) > 2 and isinstance(payload[2], list):
                for condition in payload[2]:
                    if isinstance(condition, list) and condition and isinstance(condition[0], str):
                        condition_types.add(condition[0])
                        condition_counts[condition[0]] += 1
            elif name == "CreateBombMultiball":
                if len(payload) < 7:
                    raise ValueError(f"Unrecognized bomb summon at {path}#{pointer}")
                bomb_summons.append({"pointer": pointer, "scope": instruction["scope"],
                                     "wait_pointers": [wait["pointer"] for wait in instruction["wait_context"]],
                                     "count": {"pointer": f"{pointer}/1", "raw_value": payload[1]},
                                     "child_action_ref": {"pointer": f"{pointer}/6", "raw_value": payload[6]}})
        compact_action = {"action_ref": action_ref(path), "source_path": path,
                          "git_blob_sha1": record["source"]["git_blob_sha1"],
                          "operation_pointers": dict(sorted(operations.items())), "condition_types": sorted(condition_types),
                          "waits": waits, "hit_areas": areas, "child_actions": record["action_dependencies"]}
        if bomb_summons:
            compact_action["bomb_summons"] = bomb_summons
        compact_actions.append(compact_action)
    variants = []
    for skill in catalog["skills"]:
        path = skill["action_file"]["path"]
        dependencies = closure(path)
        opcodes = set(records[path]["instruction_counts"])
        for ref in dependencies:
            opcodes.update(records[path_for_ref[ref]]["instruction_counts"])
        variants.append({"skill_id": skill["id"], "owner_character_ids": skill["owner_character_ids"],
                         "root_action_ref": action_ref(path), "dependency_action_refs": dependencies,
                         "all_opcodes": sorted(opcodes)})
    return {"schema_version": 1, "source": {"repository": manifest["repository"], "commit": manifest["commit"],
            "region": manifest["region"], "asset_version": manifest["asset_version"],
            "manifest_path": "tools/world_flipper_skill_action_sources.json",
            "manifest_sha256": hashlib.sha256(json_bytes(manifest)).hexdigest()},
            "scope": "Factual structural index of catalog skill-rank actions and recursively referenced child actions; not runtime support.",
            "field_policy": manifest["field_policy"], "unresolved_semantics": manifest["unresolved_semantics"],
            "counts": {"skill_variants": len(variants), "unique_catalog_roots": len(roots), "verified_actions": len(records),
                       "child_only_actions": len(records) - len(roots), "opcode_types": len(report["instruction_counts"]),
                       "hit_areas": sum(shape_counts.values())},
            "inventory": {"instruction_counts": report["instruction_counts"], "hit_area_shapes": dict(sorted(shape_counts.items())),
                          "hit_area_lifetimes": dict(sorted(lifetime_counts.items())), "hit_policies": dict(sorted(hit_policy_counts.items())),
                          "condition_types": dict(sorted(condition_counts.items()))},
            "skills": variants, "actions": compact_actions}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--cache", type=Path, default=DEFAULT_CACHE)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--tree", type=Path, default=ROOT / ".tools/worldflipper/catalog/raw/asset_tree.json")
    parser.add_argument("--all", action="store_true", help="Use all indexed skill-rank action files, deduplicated by repository path")
    parser.add_argument("--offline", action="store_true", help="Verify local sources without any network access")
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--write-index", action="store_true", help="Rebuild the compact factual skill-action index; implies --all")
    parser.add_argument("--check", action="store_true", help="Compare a full rebuilt index byte-for-byte without changing it; implies --all")
    parser.add_argument("--index", type=Path, default=DEFAULT_INDEX)
    args = parser.parse_args()
    if not 1 <= args.workers <= 16:
        parser.error("--workers must be between 1 and 16")
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    tree = json.loads(args.tree.read_text(encoding="utf-8")) if args.tree.exists() else None
    if tree is not None:
        expected_tree = manifest.get("asset_tree_sha256")
        if not expected_tree or hashlib.sha256(args.tree.read_bytes()).hexdigest() != expected_tree:
            raise ValueError("Asset tree is not the locked pinned tree")
    all_actions = args.all or args.write_index or args.check
    if all_actions:
        catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
        if catalog["source"]["commit"] != manifest["commit"]:
            raise ValueError("Catalog and action manifest commits differ")
        sources = catalog_sources(catalog, tree)
        # Reuse the independently verified sample files rather than fetch duplicates.
        sample_by_path = {source["path"]: source for source in manifest["sources"]}
        for source in sources:
            if source["path"] not in sample_by_path or source["git_blob_sha1"] != sample_by_path[source["path"]]["git_blob_sha1"]:
                raise ValueError(f"Catalog action is absent from locked source manifest: {source['path']}")
        sources = [{**source, **sample_by_path.get(source["path"], {})} for source in sources]
    else:
        sample_paths = set(manifest["representative_source_paths"])
        sources = [source for source in manifest["sources"] if source["path"] in sample_paths]
    report = research(sources, manifest, args.cache, args.offline, args.workers, tree)
    output = args.output or args.cache / ("all-actions-structure.json" if all_actions else "sample-actions-structure.json")
    if not args.check:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(json_bytes(report))
    print(json.dumps({key: report[key] for key in ("requested_root_files", "verified_files", "failure_count", "unresolved_action_dependencies")}, ensure_ascii=False))
    if not args.check:
        print(f"Report: {output}")
    if report["failure_count"] or report["unresolved_action_dependencies"]:
        return 1
    if args.write_index or args.check:
        content = json_bytes(compact_index(report, catalog, manifest))
        if args.check:
            if not args.index.exists() or args.index.read_bytes() != content:
                print(f"Compact index differs: {args.index}")
                return 1
            print(f"Compact index matches: {args.index}")
        elif args.write_index:
            args.index.parent.mkdir(parents=True, exist_ok=True)
            args.index.write_bytes(content)
            print(f"Compact index written: {args.index} ({len(content)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
