"""Cache only original, exact-identity GIF poses from a pinned character mirror.

The registry includes every JP character, even when this older mirror has no
matching files. Missing art is never replaced by another pose or a placeholder.
Foot measurements describe the lowest opaque row, not an anatomical anchor.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import copy
import hashlib
import json
import re
import urllib.request
from pathlib import Path
from typing import Any

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "tools/world_flipper_character_animation_sources.json"
CACHE = ROOT / ".tools/wf-character-assets/raw"
REPORT = ROOT / ".tools/wf-character-assets/animation-qa-raw.json"
MAX_FILE_BYTES = 64 * 1024
MAX_TOTAL_BYTES = 8 * 1024 * 1024
MIRROR_COMMIT = "24935f8731f134cb9ec6da9c126ca38ae8c8ae1f"
POSES = frozenset({"neutral", "walk_front", "walk_back"})
SAMPLE_IDS = frozenset({"111004", "141021", "111015", "121027", "121021", "151011", "512001"})


def git_blob_sha1(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()


def validate_registry(registry: dict[str, Any], canonical: dict[str, Any]) -> None:
    if registry["mirror_commit"] != MIRROR_COMMIT:
        raise ValueError("The original animation mirror must remain pinned")
    original = {item["id"]: item for item in canonical["characters"]}
    characters = registry["characters"]
    if len(characters) != len(original) or len({item["id"] for item in characters}) != len(characters):
        raise ValueError("The animation registry must account for every unique canonical character")
    sources = registry["sources"]
    if len(sources) > 505 * 3 or sum(source["expected_bytes"] for source in sources) > MAX_TOTAL_BYTES:
        raise ValueError("The pinned source family exceeds its controlled byte/count budget")
    by_id = {source["id"]: source for source in sources}
    if len(by_id) != len(sources):
        raise ValueError("Duplicate original animation source identity")
    used: set[str] = set()
    missing: set[str] = set()
    for character in characters:
        identifier = character["id"]
        entry = original.get(identifier)
        if entry is None or character["dev_name"] != entry["dev_name"] or character["rarity"] != entry["rarity"]:
            raise ValueError("Character animation identity differs from the final JP catalogue")
        family = character["source_ids"]
        if set(family) | set(character["missing_poses"]) != POSES or set(family) & set(character["missing_poses"]):
            raise ValueError("A character pose is omitted, duplicated or replaced")
        if character["missing_poses"]:
            missing.add(identifier)
        for pose, source_id in family.items():
            source = by_id[source_id]
            filename = f"{identifier}-{pose}.gif"
            path = f"assets/rarity{entry['rarity']}/{entry['dev_name']}/{pose}.gif"
            url = f"https://raw.githubusercontent.com/vivaldi6352/vivaldi6352.github.io/{MIRROR_COMMIT}/{path}"
            if source_id != f"character_{identifier}_{pose}" or source["canonical_character_id"] != identifier or source["pose"] != pose:
                raise ValueError("An original animation was assigned to another character or pose")
            if source["filename"] != filename or source["repository_path"] != path or source["url"] != url:
                raise ValueError("An original GIF path differs from the exact pinned character pose")
            if source["dev_name"] != entry["dev_name"] or source["rarity"] != entry["rarity"] or not re.fullmatch(r"[0-9a-f]{40}", source["git_blob_sha1"]):
                raise ValueError("Invalid original GIF identity or pinned Git blob")
            if not 0 < source["expected_bytes"] <= MAX_FILE_BYTES:
                raise ValueError("An original GIF exceeds its per-file byte budget")
            used.add(source_id)
    if used != set(by_id) or missing != {item["canonical_character_id"] for item in registry["missing"]}:
        raise ValueError("Unlinked animation sources or an incomplete missing-character ledger")


def inspect_gif(path: Path) -> dict[str, Any]:
    frames = []
    with Image.open(path) as image:
        if image.format != "GIF" or not 0 < image.n_frames <= 128 or max(image.size) > 256:
            raise ValueError("Unexpected original character GIF format, canvas or frame limit")
        size = list(image.size)
        for index in range(image.n_frames):
            image.seek(index)
            rgba = image.convert("RGBA")
            alpha = rgba.getchannel("A")
            bounds = alpha.getbbox()
            if bounds is None or alpha.getextrema() != (0, 255):
                raise ValueError("A character pose frame lacks genuine transparent alpha")
            bottom = bounds[3] - 1
            visible_x = [x for x in range(image.width) if alpha.getpixel((x, bottom)) > 0]
            frames.append({"duration_ms": int(image.info.get("duration", 0)), "alpha_bounds": list(bounds),
                "opaque_bottom_span": [min(visible_x), bottom, max(visible_x) + 1, bottom + 1],
                "rgba_sha256": hashlib.sha256(rgba.tobytes()).hexdigest()})
    unique = len({frame["rgba_sha256"] for frame in frames})
    return {"source_size": size, "frame_count": len(frames), "durations_ms": [frame["duration_ms"] for frame in frames],
            "unique_rgba_frames": unique, "genuine_transparency": True,
            "motion": "animated_distinct" if unique > 1 else "original_static",
            "foot_measurement": "lowest opaque row span, not an anatomical foot anchor", "frames": frames}


def fetch_one(source: dict[str, Any], cache: Path, offline: bool) -> dict[str, Any]:
    result = copy.deepcopy(source)
    filename = str(source["filename"])
    expected = int(source["expected_bytes"])
    if Path(filename).name != filename or not filename.endswith(".gif") or not 0 < expected <= MAX_FILE_BYTES:
        raise ValueError("Invalid original GIF cache filename or byte budget")
    path = cache / filename
    try:
        if path.is_file():
            if path.stat().st_size != expected:
                raise ValueError("Cached original GIF byte size changed")
            raw = path.read_bytes()
        elif offline:
            raise FileNotFoundError("Missing cached original GIF")
        else:
            request = urllib.request.Request(source["url"], headers={"User-Agent": "broxy-character-animation-archival/1"})
            with urllib.request.urlopen(request, timeout=30) as response:
                raw = response.read(expected + 1)
        if len(raw) != expected or git_blob_sha1(raw) != source["git_blob_sha1"]:
            raise ValueError("Original GIF differs from its pinned Git blob")
        digest = hashlib.sha256(raw).hexdigest()
        if source.get("sha256") and digest != source["sha256"]:
            raise ValueError("Original GIF differs from its previously verified SHA-256")
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
        result.update(inspect_gif(path))
        result.update(availability="verified_original", sha256=digest, bytes=len(raw))
        result.pop("failure", None)
    except (OSError, ValueError) as error:
        result.update(availability="unavailable_or_invalid", failure=str(error))
    return result


def summarize(registry: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(registry)
    by_id = {source["id"]: source for source in result["sources"]}
    complete = 0
    animated = 0
    duplicate_walks = []
    for character in result["characters"]:
        family = {pose: by_id[identifier] for pose, identifier in character["source_ids"].items()}
        verified = len(family) == 3 and all(source["availability"] == "verified_original" for source in family.values())
        character["three_pose_sources_verified"] = verified
        usable_walk = False
        if verified:
            complete += 1
            neutral_frames = {frame["rgba_sha256"] for frame in family["neutral"]["frames"]}
            for pose in ["walk_front", "walk_back"]:
                source = family[pose]
                source["identical_to_neutral_bytes"] = source["sha256"] == family["neutral"]["sha256"]
                source["only_neutral_rgba_frames"] = all(frame["rgba_sha256"] in neutral_frames for frame in source["frames"])
                if source["identical_to_neutral_bytes"] or source["only_neutral_rgba_frames"]:
                    duplicate_walks.append(source["id"])
            usable_walk = all(family[pose]["motion"] == "animated_distinct" and not family[pose]["only_neutral_rgba_frames"] for pose in ["walk_front", "walk_back"])
            animated += int(usable_walk)
        character["distinct_walking_animation_verified"] = usable_walk
    sources = result["sources"]
    result["summary"] = {"canonical_characters": len(result["characters"]), "indexed_three_pose_characters": sum(not item["missing_poses"] for item in result["characters"]),
        "indexed_sources": len(sources), "indexed_bytes": sum(source["expected_bytes"] for source in sources),
        "verified_original_sources": sum(source["availability"] == "verified_original" for source in sources),
        "verified_three_pose_characters": complete, "distinct_walking_characters": animated,
        "missing_characters": len(result["missing"]), "failed_indexed_sources": sum(source["availability"] == "unavailable_or_invalid" for source in sources),
        "walk_sources_repeating_only_neutral": duplicate_walks, "full_jp_animation_set_available": complete == len(result["characters"])}
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", type=Path, default=REGISTRY)
    parser.add_argument("--cache", type=Path, default=CACHE)
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--check", action="store_true", help="Verify original GIFs and exact LF registry bytes without writing a registry or report")
    parser.add_argument("--sample", action="store_true", help="Check seasonal, collaboration and low-rarity samples before a full download")
    parser.add_argument("--character", action="append", default=[], help="Original numeric ID or exact original dev_name")
    parser.add_argument("--workers", type=int, default=4, choices=range(1, 9))
    parser.add_argument("--write-registry", action="store_true", help="Save verified hashes, real frames, duration and missing identities")
    args = parser.parse_args()
    if args.check and args.write_registry:
        parser.error("--check cannot be combined with --write-registry")
    registry = json.loads(args.registry.read_text(encoding="utf-8"))
    canonical = json.loads((ROOT / "data/worldflipper/catalog.json").read_text(encoding="utf-8"))
    try:
        validate_registry(registry, canonical)
    except (KeyError, TypeError, ValueError) as error:
        parser.exit(1, f"Invalid pinned animation registry: {error}\n")
    sources = registry["sources"]
    selected_ids = SAMPLE_IDS if args.sample else set(args.character)
    known_ids = {character["id"] for character in registry["characters"]} | {character["dev_name"] for character in registry["characters"]}
    if selected_ids - known_ids:
        parser.exit(1, "Unknown canonical character selector: " + ", ".join(sorted(selected_ids - known_ids)) + "\n")
    selected = [source for source in sources if not selected_ids or source["canonical_character_id"] in selected_ids or source["dev_name"] in selected_ids]
    if selected_ids and not selected:
        parser.exit(1, "The selected canonical characters have no original poses in this pinned mirror\n")
    replacements = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = {executor.submit(fetch_one, source, args.cache, args.offline): source for source in selected}
        for index, future in enumerate(concurrent.futures.as_completed(futures), 1):
            source = future.result()
            replacements[source["id"]] = source
            if index % 100 == 0:
                print(json.dumps({"verified_or_checked": index, "selected": len(selected)}), flush=True)
    registry["sources"] = [replacements.get(source["id"], source) for source in sources]
    result = summarize(registry)
    encoded = (json.dumps(result, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if args.check:
        if args.registry.read_bytes() != encoded:
            parser.exit(1, "The original GIF registry differs from its deterministic LF rebuild\n")
    elif args.write_registry:
        args.registry.write_bytes(encoded)
    if not args.check:
        REPORT.parent.mkdir(parents=True, exist_ok=True)
        REPORT.write_bytes(encoded)
    print(json.dumps(result["summary"]), flush=True)
    return 1 if any(source["availability"] != "verified_original" for source in replacements.values()) else 0


if __name__ == "__main__":
    raise SystemExit(main())
