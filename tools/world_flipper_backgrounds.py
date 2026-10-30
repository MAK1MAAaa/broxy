"""Fetch/check a pinned historical background mirror without claiming JP geometry.

PNG bytes stay in the ignored cache. The mirror is from June 2022; matching final
JP field paths neither verifies final-client byte identity nor supplies terrain.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
from typing import Any
from urllib.parse import quote
from urllib.request import Request, urlopen

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "tools/world_flipper_background_sources.json"
CACHE = ROOT / ".tools/wf-full-map-research/backgrounds"
MAX_FILE_BYTES = 4 * 1024 * 1024
MAX_IMAGE_PIXELS = 16 * 1024 * 1024
COMMIT = "6bf81da717f2ac073e630fd17aa819d1cdb0d815"
REPOSITORY = "televenus/World-Flipper-Assets"


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def safe_source_path(value: Any) -> str:
    if not isinstance(value, str) or "\\" in value or ":" in value:
        raise ValueError("Invalid background source path")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or path.as_posix() != value or not value.startswith("battle/field/") or not value.endswith(".png"):
        raise ValueError("Background source path leaves the pinned field tree")
    return value


def source_url(source: dict[str, Any]) -> str:
    return f"https://raw.githubusercontent.com/{REPOSITORY}/{COMMIT}/" + quote(safe_source_path(source["path"]), safe="/._-")


def png_info(data: bytes) -> dict[str, Any]:
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("Background bytes are not a PNG")
    with Image.open(io.BytesIO(data)) as image:
        width, height = image.size
        if image.format != "PNG" or min(width, height) < 1 or width * height > MAX_IMAGE_PIXELS:
            raise ValueError("Invalid or oversized background PNG canvas")
        result = {"source_size": [width, height], "mode": image.mode}
        image.verify()
    # verify() checks the container/CRC; load() also validates pixel decoding.
    with Image.open(io.BytesIO(data)) as image:
        image.load()
    return result


def validate_png(data: bytes, source: dict[str, Any]) -> dict[str, Any]:
    expected_size = source["bytes"]
    if type(expected_size) is not int or not 0 < expected_size <= MAX_FILE_BYTES or len(data) != expected_size:
        raise ValueError(f"Background byte size changed: {source['id']}")
    digest = hashlib.sha256(data).hexdigest()
    blob = hashlib.sha1(f"blob {len(data)}\0".encode("ascii") + data).hexdigest()
    if digest != source["sha256"] or blob != source["git_blob_sha1"]:
        raise ValueError(f"Background source hash changed: {source['id']}")
    info = png_info(data)
    if info["source_size"] != source["source_size"] or info["mode"] != source["mode"]:
        raise ValueError(f"Background PNG metadata changed: {source['id']}")
    return {"id": source["id"], "path": source["path"], "bytes": len(data),
            "sha256": digest, "git_blob_sha1": blob, **info}


def validate_registry(registry: dict[str, Any], catalog: dict[str, Any]) -> None:
    if registry.get("schema_version") != 1 or registry["mirror"]["repository"] != REPOSITORY or registry["mirror"]["commit"] != COMMIT:
        raise ValueError("Unexpected background mirror identity")
    archive = catalog["source"]
    if registry["comparison_catalog"]["commit"] != archive["commit"] or registry["comparison_catalog"]["asset_version"] != archive["asset_version"]:
        raise ValueError("Background mapping targets a different canonical catalog")
    fields = {field["id"]: field for field in catalog["maps"]["fields"]}
    ids, paths, matched = set(), set(), set()
    for source in registry["sources"]:
        source_id, path = source["id"], safe_source_path(source["path"])
        if not isinstance(source_id, str) or not source_id or source_id in ids or path in paths:
            raise ValueError("Duplicate/invalid background identity")
        ids.add(source_id)
        paths.add(path)
        for key, length in (("sha256", 64), ("git_blob_sha1", 40)):
            if not isinstance(source[key], str) or re.fullmatch(rf"[0-9a-f]{{{length}}}", source[key]) is None:
                raise ValueError("Invalid pinned background digest")
        if type(source["bytes"]) is not int or not 0 < source["bytes"] <= MAX_FILE_BYTES:
            raise ValueError("Invalid pinned background byte size")
        canvas = source["source_size"]
        if not isinstance(canvas, list) or len(canvas) != 2 or any(type(value) is not int or value < 1 for value in canvas) or canvas[0] * canvas[1] > MAX_IMAGE_PIXELS:
            raise ValueError("Invalid pinned background canvas")
        if not source["fields"]:
            raise ValueError("Background without a canonical field binding")
        for field_id in source["fields"]:
            if field_id in matched or field_id not in fields or fields[field_id]["background_ref"] + ".png" != path:
                raise ValueError("Ambiguous or inexact canonical field/background binding")
            matched.add(field_id)
    missing = set()
    for row in registry["missing_fields"]:
        field_id = row["id"]
        if field_id in missing or field_id in matched or field_id not in fields or row["background_ref"] != fields[field_id]["background_ref"]:
            raise ValueError("Invalid missing-field evidence")
        missing.add(field_id)
    coverage = registry["coverage"]
    if matched | missing != set(fields) or (coverage["canonical_fields"], coverage["matched_field_refs"], coverage["missing_field_refs"], coverage["unique_background_pngs"]) != (len(fields), len(matched), len(missing), len(paths)):
        raise ValueError("Background coverage does not reconcile with the full canonical catalog")
    if coverage["final_jp_byte_identity_verified"] or coverage["terrain_files_acquired"] != 0 or registry["runtime_ready"]:
        raise ValueError("A historical PNG mirror cannot claim final-byte, terrain, or playable coverage")


def checked_source(source: dict[str, Any], cache: Path, offline: bool = True) -> dict[str, Any]:
    relative = safe_source_path(source["path"])
    destination = cache.joinpath(*PurePosixPath(relative).parts)
    if destination.is_file():
        data = destination.read_bytes()
    else:
        if offline:
            raise FileNotFoundError(f"Missing pinned background: {destination}")
        size = source["bytes"]
        if type(size) is not int or not 0 < size <= MAX_FILE_BYTES:
            raise ValueError("Invalid background download size")
        request = Request(source_url(source), headers={"User-Agent": "BroxyAssetResearch"})
        with urlopen(request, timeout=45) as response:
            data = response.read(size + 1)
    verified = validate_png(data, source)
    if not destination.is_file():
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    return verified


def verify_all(registry: dict[str, Any], catalog: dict[str, Any], cache: Path, offline: bool = True, workers: int = 4) -> dict[str, Any]:
    validate_registry(registry, catalog)
    if type(workers) is not int or not 1 <= workers <= 16:
        raise ValueError("Background worker count must be between 1 and 16")
    with ThreadPoolExecutor(max_workers=workers) as pool:
        # map preserves registry order, making the offline report deterministic.
        files = list(pool.map(lambda source: checked_source(source, cache, offline), registry["sources"]))
    return {"schema_version": 1, "mirror": registry["mirror"], "coverage": registry["coverage"],
            "verified_background_pngs": len(files), "verified_bytes": sum(source["bytes"] for source in files),
            "runtime_ready": False, "files": files}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--download", action="store_true", help="Fetch missing pinned PNGs; existing files still require exact hashes")
    modes.add_argument("--offline", action="store_true", help="Verify the existing ignored cache (default)")
    parser.add_argument("--cache", type=Path, default=CACHE)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = verify_all(read_json(REGISTRY), read_json(ROOT / "data/worldflipper/catalog.json"), args.cache, not args.download, args.workers)
    report = args.report or args.cache / "verification.json"
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({key: value for key, value in result.items() if key != "files"}, sort_keys=True))


if __name__ == "__main__":
    main()
