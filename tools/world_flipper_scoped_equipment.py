"""Prepare exact original equipment icons with independent source and asset locks.

The 64px icon canvas preserves complete native sprites at exactly 2x nearest.
Missing original art is recorded explicitly; no core, cutout or placeholder is
substituted. Canonical equipment rules and gameplay coverage are separate.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import struct
import urllib.parse
import urllib.request
import zlib
from pathlib import Path
from typing import Any

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "tools/world_flipper_scoped_equipment.json"
CATALOG = ROOT / "data/worldflipper/catalog.json"
CACHE = ROOT / ".tools/wf-scoped-equipment/raw"
OUTPUT = ROOT / "assets/worldflipper/equipment"
PROFILE = {"canvas": [64, 64], "scale": 2, "filter": "nearest", "preserve_full_sprite_canvas": True}
IDENTITIES = {"bow_0006": ("3040006", "十字弓"), "sword_0005": ("5010005", "杜兰德尔"),
              "book_0002": ("3050002", "谎言之书"), "fist_0006": ("3070006", "半月拳刃"),
              "staff_0001": ("1060001", "老旧法杖")}
MAX_BYTES = 4 * 1024 * 1024


class AtlasReader:
    """Read only bounded, data-only AMF3 arrays/objects used by original atlases."""

    def __init__(self, raw: bytes):
        self.stream = io.BytesIO(raw)
        self.strings: list[str] = []
        self.objects: list[Any] = []
        self.traits: list[tuple[bool, list[str]]] = []

    def take(self, size: int) -> bytes:
        raw = self.stream.read(size)
        if len(raw) != size:
            raise ValueError("Truncated original atlas AMF3")
        return raw

    def u29(self) -> int:
        result = 0
        for index in range(4):
            byte = self.take(1)[0]
            if index == 3:
                return result << 8 | byte
            result = result << 7 | byte & 127
            if not byte & 128:
                return result
        raise ValueError("Invalid original atlas U29")

    @staticmethod
    def reference(pool: list[Any], index: int) -> Any:
        if not 0 <= index < len(pool):
            raise ValueError("Invalid original atlas AMF3 reference")
        return pool[index]

    def string(self) -> str:
        code = self.u29()
        if not code & 1:
            return self.reference(self.strings, code >> 1)
        size = code >> 1
        if size > MAX_BYTES:
            raise ValueError("Original atlas string exceeds the decode budget")
        value = self.take(size).decode("utf-8")
        if value:
            self.strings.append(value)
        return value

    def value(self, depth: int = 0) -> Any:
        if depth > 64:
            raise ValueError("Original atlas nesting exceeds the decode budget")
        marker = self.take(1)[0]
        if marker in (0, 1):
            return None
        if marker in (2, 3):
            return marker == 3
        if marker == 4:
            number = self.u29()
            return number - 0x20000000 if number & 0x10000000 else number
        if marker == 5:
            return struct.unpack(">d", self.take(8))[0]
        if marker == 6:
            return self.string()
        if marker not in (9, 10):
            raise ValueError("Original atlas AMF3 marker requires an explicit decoder")
        code = self.u29()
        if not code & 1:
            return self.reference(self.objects, code >> 1)
        if marker == 9:
            count = code >> 1
            if count > 100000 or self.string():
                raise ValueError("Original atlas requires a bounded non-associative array")
            values: list[Any] = []
            self.objects.append(values)
            values.extend(self.value(depth + 1) for _ in range(count))
            return values
        if not code & 2:
            dynamic, names = self.reference(self.traits, code >> 2)
        else:
            if code & 4 or self.string():
                raise ValueError("Typed/externalizable AMF3 is not an executable asset input")
            dynamic = bool(code & 8)
            names = [self.string() for _ in range(code >> 4)]
            self.traits.append((dynamic, names))
        record: dict[str, Any] = {}
        self.objects.append(record)
        for name in names:
            record[name] = self.value(depth + 1)
        if dynamic:
            for _ in range(100000):
                name = self.string()
                if not name:
                    break
                record[name] = self.value(depth + 1)
            else:
                raise ValueError("Original atlas object exceeds the field budget")
        return record


def inflate(raw: bytes, maximum: int) -> bytes:
    decoder = zlib.decompressobj(-15)
    try:
        result = decoder.decompress(raw, maximum + 1)
    except zlib.error as error:
        raise ValueError("Invalid raw DEFLATE original asset") from error
    if len(result) > maximum or decoder.unconsumed_tail or decoder.unused_data or not decoder.eof:
        raise ValueError("Raw DEFLATE asset exceeds its exact decode budget or has trailing bytes")
    return result


def atlas_frames(raw: bytes) -> list[dict[str, Any]]:
    inflated = inflate(raw, MAX_BYTES)
    reader = AtlasReader(inflated)
    result = reader.value()
    if reader.stream.tell() != len(inflated) or not isinstance(result, list) or not all(isinstance(row, dict) for row in result):
        raise ValueError("Original atlas did not decode completely into data-only frames")
    return result


def _validate_original_file(source: dict[str, Any]) -> None:
    if type(source["bytes"]) is not int or not 0 < source["bytes"] <= MAX_BYTES or not re.fullmatch(r"[a-zA-Z0-9_.-]+", source["filename"]) or not re.fullmatch(r"[0-9a-f]{64}", source["sha256"]):
        raise ValueError("Unsafe original icon cache filename/hash/byte budget")
    transport = source.get("transport")
    if transport is None:
        if not source["url"].startswith("https://worldflipper.wiki.gg/images/") or "Core" in source["url"] or "thumb/" in source["url"]:
            raise ValueError("Only original armament sprites may fill this standalone icon source")
        return
    if transport["kind"] != "archive_zip_range" or not source["url"].startswith("https://archive.org/download/gacha-archive/") or transport["whole_archive_checksum_verified"] is not False or transport["final_jp_byte_identity_verified"] is not False:
        raise ValueError("Archived icons must retain the unverified client/asset-version boundary")
    start, end = transport["range"]
    if any(type(value) is not int for value in (start, end)) or start < 0 or start != transport["zip_header_offset"] or not 0 < end - start + 1 <= MAX_BYTES or not re.fullmatch(r"[0-9a-f]{64}", transport["range_sha256"]):
        raise ValueError("Original archive request must use one bounded, locked byte range")
    if transport["zip_compression_method"] not in (0, 8) or not 0 < transport["zip_compressed_bytes"] <= MAX_BYTES or not re.fullmatch(r"[0-9a-f]{8}", transport["zip_crc32"]):
        raise ValueError("Original archive member requires a supported compression/CRC lock")


def archive_member(source: dict[str, Any], block: bytes) -> bytes:
    transport = source["transport"]
    start, end = transport["range"]
    if len(block) != end - start + 1 or sha256(block) != transport["range_sha256"] or len(block) < 30:
        raise ValueError("Original archive Range bytes changed")
    header = struct.unpack_from("<4s5H3I2H", block)
    name_length, extra_length = header[-2:]
    payload_start = 30 + name_length + extra_length
    stored_name = block[30:30 + name_length].decode("utf-8" if header[2] & 0x800 else "cp437")
    if header[0] != b"PK\x03\x04" or header[2] & 1 or header[3] != transport["zip_compression_method"] or stored_name != transport["zip_entry"] or payload_start + transport["zip_compressed_bytes"] > len(block):
        raise ValueError("Original archive local member header/name/compression changed")
    payload = block[payload_start:payload_start + transport["zip_compressed_bytes"]]
    raw = inflate(payload, source["bytes"]) if header[3] == 8 else payload
    if len(raw) != source["bytes"] or f"{zlib.crc32(raw) & 0xffffffff:08x}" != transport["zip_crc32"] or sha256(raw) != source["sha256"]:
        raise ValueError("Original archive member CRC32/SHA256/size changed")
    return raw


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")


def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def validate_registry(registry: dict[str, Any], catalog: dict[str, Any]) -> None:
    if registry["schema_version"] != 1 or registry["normalization"] != PROFILE or type(registry["normalization"]["scale"]) is not int or any(type(value) is not int for value in registry["normalization"]["canvas"]):
        raise ValueError("The exact 2x whole-sprite icon normalization profile changed")
    if registry["catalog_commit"] != catalog["source"]["commit"]:
        raise ValueError("Equipment icons require the fixed final JP canonical directory")
    sources = registry["sources"]
    if len(sources) != len(IDENTITIES) or {source["game_id"] for source in sources} != set(IDENTITIES):
        raise ValueError("Exactly five approved equipment identities are required")
    if len({source["id"] for source in sources}) != len(sources):
        raise ValueError("Duplicate original icon source identity")
    originals = {item["id"]: item for item in catalog["equipment"]}
    for source in sources:
        identifier, name = IDENTITIES[source["game_id"]]
        original = originals[identifier]
        if source["canonical_id"] != identifier or source["dev_name"] != original["dev_name"] or source["game_id"] != source["dev_name"] or source["image_resource_ref"] != original["resource_ref"]:
            raise ValueError("Icon identity differs from its exact canonical equipment/dev/resource")
        evidence = source["name_evidence"]
        name_url = "https://wiki.biligame.com/worldflipper/" + urllib.parse.quote(name)
        if source["display_name_zh"] != name or evidence["title"] != name or not str(evidence["wiki_revision"]).isdigit() or evidence["url"] != name_url or evidence["revision_url"] != name_url + "?oldid=" + evidence["wiki_revision"] or not re.fullmatch(r"[0-9a-f]{64}", evidence["raw_html_sha256"]):
            raise ValueError("Localized icon alias lacks its exact sourced original equipment page")
        if source["availability"] == "missing_original_weapon_sprite":
            if not source["missing_reason"]:
                raise ValueError("Missing art requires a concrete source gap")
            continue
        if source["availability"] != "verified_original":
            raise ValueError("Unsupported icon availability state")
        _validate_original_file(source)
        if source.get("source_kind", "standalone_sprite") not in ("standalone_sprite", "authored_atlas_frame"):
            raise ValueError("Original icon source requires an explicit standalone or authored-frame adapter")
        size = source["source_size"]
        if not isinstance(size, list) or len(size) != 2 or any(type(value) is not int or not 0 < value <= 22 for value in size):
            raise ValueError("Original standalone sprite exceeds the approved native size budget")
        if source["crop"] != [0, 0, *size] or any(type(value) is not int for value in source["crop"]):
            raise ValueError("A standalone icon must retain the complete original sprite canvas")
        if source.get("source_kind") == "authored_atlas_frame":
            _validate_original_file(source["atlas_source"])
            _validate_original_file(source["cache_metadata_source"])
            if source["cache_metadata_declared_version"] != "1.780.30" or source["source_object_final_jp_byte_identity_verified"] is not False:
                raise ValueError("Archive cache metadata is a version declaration, not a per-object final-JP version proof")
            frame = source["frame"]
            if frame["n"] != source["image_resource_ref"] or frame["n"].startswith("item/generated/") or [frame["fw"], frame["fh"]] != size or any(type(frame[key]) is not int for key in ("x", "y", "w", "h", "fx", "fy", "fw", "fh")):
                raise ValueError("The exact authored equipment atlas frame differs from its original identity/canvas")
            repair = source["signature_repair"]
            if repair["indices"] != [1, 2, 3] or repair["from"] != "706e67" or repair["to"] != "504e47":
                raise ValueError("Original PNG decoding permits only the fixed case-only signature repair")


def acquire(source: dict[str, Any], cache: Path, offline: bool) -> bytes:
    path = cache / source["filename"]
    expected: int = source["bytes"]
    if path.is_file():
        if path.stat().st_size != expected:
            raise ValueError("Original icon byte count differs from its source lock")
        raw = path.read_bytes()
    elif offline:
        raise FileNotFoundError("Missing original icon cache: " + str(path))
    else:
        transport = source.get("transport")
        headers = {"User-Agent": "Mozilla/5.0 (compatible; broxy-scoped-equipment/1)"}
        if transport:
            start, end = transport["range"]
            headers["Range"] = f"bytes={start}-{end}"
        request = urllib.request.Request(source["url"], headers=headers)
        with urllib.request.urlopen(request, timeout=30) as response:
            if transport:
                if response.status != 206 or response.headers.get("Content-Range") != f"bytes {start}-{end}/{transport['archive_bytes']}":
                    raise ValueError("Server did not honor the original bounded archive Range")
                raw = archive_member(source, response.read(end - start + 2))
            else:
                raw = response.read(expected + 1)
    if len(raw) != expected or sha256(raw) != source["sha256"]:
        raise ValueError("Original icon SHA256/bytes differ from the fixed source")
    if source.get("transport") and f"{zlib.crc32(raw) & 0xffffffff:08x}" != source["transport"]["zip_crc32"]:
        raise ValueError("Original cached archive member CRC32 changed")
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)
    return raw


def sprite_pixels(source: dict[str, Any], raw: bytes, atlas_raw: bytes | None = None) -> Image.Image:
    if len(raw) != source["bytes"] or sha256(raw) != source["sha256"]:
        raise ValueError("Original icon source bytes changed before normalization")
    framed = source.get("source_kind") == "authored_atlas_frame"
    if framed:
        if atlas_raw is None or len(atlas_raw) != source["atlas_source"]["bytes"] or sha256(atlas_raw) != source["atlas_source"]["sha256"]:
            raise ValueError("Original authored atlas source bytes changed")
        frames = atlas_frames(atlas_raw)
        matches = [frame for frame in frames if frame.get("n") == source["image_resource_ref"]]
        if len(frames) != source["atlas_frame_count"] or matches != [source["frame"]]:
            raise ValueError("Original authored atlas frame changed; no core or guessed crop is substituted")
        if raw[:8] != b"\x89png\r\n\x1a\n":
            raise ValueError("Original World Flipper lowercase PNG signature changed")
        raw = b"\x89PNG\r\n\x1a\n" + raw[8:]
        if sha256(raw) != source["signature_repaired_sha256"]:
            raise ValueError("Signature-only PNG decoding differs from the fixed original pixels")
    with Image.open(io.BytesIO(raw)) as original:
        expected_size = source["atlas_image_size"] if framed else source["source_size"]
        if original.format != "PNG" or original.mode != source["source_mode"] or list(original.size) != expected_size:
            raise ValueError("Original icon PNG mode/size changed")
        rgba = original.convert("RGBA")
    if framed:
        if sha256(rgba.tobytes()) != source["atlas_rgba_sha256"]:
            raise ValueError("Original atlas RGBA pixels changed")
        frame = source["frame"]
        x, y, width, height = (frame[key] for key in ("x", "y", "w", "h"))
        if x < 0 or y < 0 or width <= 0 or height <= 0 or x + width > rgba.width or y + height > rgba.height or frame["fx"] > 0 or frame["fy"] > 0 or -frame["fx"] + width > frame["fw"] or -frame["fy"] + height > frame["fh"]:
            raise ValueError("Original authored frame exceeds its exact atlas/full-canvas bounds")
        canvas = Image.new("RGBA", (frame["fw"], frame["fh"]))
        canvas.alpha_composite(rgba.crop((x, y, x + width, y + height)), (-frame["fx"], -frame["fy"]))
        rgba = canvas
    alpha = rgba.getchannel("A")
    if sha256(rgba.tobytes()) != source["source_rgba_sha256"] or set(alpha.tobytes()) != {0, 255} or list(alpha.getbbox() or ()) != source["alpha_bounds"]:
        raise ValueError("Original icon RGBA pixels/transparent alpha/bounds changed")
    return rgba


def normalize_sprite(source: dict[str, Any], raw: bytes, atlas_raw: bytes | None = None) -> tuple[Image.Image, tuple[int, int]]:
    rgba = sprite_pixels(source, raw, atlas_raw)
    scale = PROFILE["scale"]
    extent = (rgba.width * scale, rgba.height * scale)
    offset = ((64 - extent[0]) // 2, (64 - extent[1]) // 2)
    result = Image.new("RGBA", (64, 64))
    result.alpha_composite(rgba.resize(extent, Image.Resampling.NEAREST), offset)
    return result, offset


def produce(registry: dict[str, Any], catalog: dict[str, Any], cache: Path, offline: bool = True) -> tuple[dict[str, Any], dict[str, bytes]]:
    validate_registry(registry, catalog)
    for source in registry["sources"]:
        if source.get("source_kind") == "authored_atlas_frame" and source["availability"] == "verified_original":
            metadata = json.loads(acquire(source["cache_metadata_source"], cache, offline))
            if metadata.get("version") != source["cache_metadata_declared_version"]:
                raise ValueError("Original archive cache metadata version differs from its fixed declaration")
    prepared = [(source, *normalize_sprite(source, acquire(source, cache, offline), acquire(source["atlas_source"], cache, offline) if source.get("source_kind") == "authored_atlas_frame" else None))
                for source in registry["sources"] if source["availability"] == "verified_original"]
    images: dict[str, bytes] = {}
    assets: list[dict[str, Any]] = []
    for source, image, offset in prepared:
        filename = source["game_id"] + ".png"
        stream = io.BytesIO()
        image.save(stream, format="PNG", optimize=False)
        raw = stream.getvalue()
        images[filename] = raw
        asset = {"id": source["game_id"], "path": "assets/worldflipper/equipment/" + filename,
            "canonical_equipment_id": source["canonical_id"], "source_ids": [source["id"]], "display_name_zh": source["display_name_zh"],
            "size": [64, 64], "sha256": sha256(raw), "rgba_sha256": sha256(image.tobytes()),
            "source_crop": source["crop"], "source_size": source["source_size"], "source_scale": 2, "offset": list(offset),
            "alpha_bounds": list(image.getchannel("A").getbbox()), "filter": "nearest",
            "normalization": "2x nearest; complete original transparent sprite centered in 64px canvas; no cutout, recoloring, core substitution or added frame"}
        if source.get("source_kind") == "authored_atlas_frame":
            asset.update(source_kind="authored_atlas_frame", authored_frame=source["frame"],
                restoration_offset=[-source["frame"]["fx"], -source["frame"]["fy"]],
                source_asset_version=None, cache_metadata_declared_version=source["cache_metadata_declared_version"],
                source_object_final_jp_byte_identity_verified=False, final_jp_byte_identity_verified=False,
                normalization="Exact original equipment atlas frame; restore its authored fw/fh canvas at (-fx,-fy), then2x nearest centered in64px. Only PNG signature letter case is repaired; no core substitution or silhouette cutout.")
        assets.append(asset)
    manifest = {"schema_version": 1, "revision": "world-flipper-scoped-equipment-01", "source_registry": "tools/world_flipper_scoped_equipment.json",
        "source_registry_sha256": sha256(json_bytes(registry)), "catalog_commit": registry["catalog_commit"], "normalization": PROFILE,
        "scope": "Original equipment icon preparation only; rule decoding, runtime effects and coverage remain independent.",
        "license_status": registry["license_status"], "sources": registry["sources"], "assets": assets,
        "missing": [{"game_id": source["game_id"], "canonical_id": source["canonical_id"], "reason": source["missing_reason"]}
                    for source in registry["sources"] if source["availability"] != "verified_original"],
        "limitations": ["Localized names are sourced community-Wiki aliases, not an assertion that the complete final JP directory contains official Chinese text.",
            "Original sprites retain their true native sizes; small 18px images are not stretched to pretend they were22px.",
            "Same-archive production/info.json declares cache metadata version1.780.30. This is not proof of each object's individual version or equality with final JP1.780.40; the whole ZIP checksum is also unverified.",
            "Original art access is not an open asset license or a claim of gameplay implementation."]}
    return manifest, images


def build(output: Path, cache: Path, offline: bool = True, check: bool = False) -> dict[str, Any]:
    manifest, images = produce(read_json(REGISTRY), read_json(CATALOG), cache, offline)
    products = {**images, "manifest.json": json_bytes(manifest)}
    if check:
        if any(not (output / name).is_file() or (output / name).read_bytes() != raw for name, raw in products.items()):
            raise ValueError("Independent equipment outputs differ from the deterministic rebuild")
    else:
        output.mkdir(parents=True, exist_ok=True)
        for name, raw in products.items():
            (output / name).write_bytes(raw)
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=CACHE)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        manifest = build(args.output, args.cache, args.offline, args.check)
        print(json.dumps({"icons": len(manifest["assets"]), "missing": manifest["missing"], "checked": args.check}))
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"Original scoped equipment icon preparation failed: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
