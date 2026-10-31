"""Verify pinned JP upload-cache entries through bounded ZIP64 HTTP Ranges.

Original bytes and decoded research data stay in .tools. An indexed path is not
verified geometry, implemented gameplay, or proof of the final client version.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import io
import json
import math
from pathlib import Path, PurePosixPath
import re
import struct
import sys
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen
import zlib

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "tools/world_flipper_jp_archive_sources.json"
CACHE = ROOT / ".tools/wf-full-map-research/jp-archive"
SALT = "K6R9T9Hz22OpeIGEWB0ui6c6PYFQnJGy"
MAX_DIRECTORY = 40 * 1024 * 1024
MAX_SOURCE = 8 * 1024 * 1024
MAX_INFLATED = 32 * 1024 * 1024
MAX_BATCH = 64 * 1024 * 1024
HEADER_PADDING = 1024


def json_bytes(value: Any) -> bytes:
    output = bytearray()
    encoder = json.JSONEncoder(ensure_ascii=False, indent=2, allow_nan=False)
    for chunk in encoder.iterencode(value):
        encoded = chunk.encode("utf-8")
        if len(output) + len(encoded) + 1 > MAX_INFLATED:
            raise ValueError("Expanded source JSON exceeds byte limit")
        output.extend(encoded)
    output.extend(b"\n")
    return bytes(output)


def safe_path(value: Any) -> str:
    if not isinstance(value, str) or not value or "\\" in value or ":" in value or "\0" in value:
        raise ValueError("Invalid original ZIP/logical path")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or path.as_posix() != value.rstrip("/"):
        raise ValueError("Original path leaves its source root")
    return value


def salted_sha1(logical: str) -> str:
    return hashlib.sha1((safe_path(logical) + SALT).encode("utf-8")).hexdigest()


def inflate(data: bytes, maximum: int, wbits: int = -15) -> bytes:
    stream = zlib.decompressobj(wbits)
    value = stream.decompress(data, maximum + 1)
    if len(value) > maximum or stream.unconsumed_tail or not stream.eof or stream.unused_data:
        raise ValueError("Truncated, trailing or oversized compressed source")
    return value


def zip64_directory(tail: bytes, archive_size: int) -> dict[str, int]:
    offset = tail.rfind(b"PK\x05\x06")
    if offset < 20 or offset + 22 > len(tail):
        raise ValueError("Missing bounded ZIP64 end record")
    eocd = struct.unpack_from("<4s4H2LH", tail, offset)
    if offset + 22 + eocd[-1] != len(tail) or eocd[1:3] != (0, 0):
        raise ValueError("Unsupported trailing or multidisk ZIP")
    locator = struct.unpack_from("<4sLQL", tail, offset - 20)
    if locator[0] != b"PK\x06\x07" or locator[1] != 0 or locator[3] != 1:
        raise ValueError("Missing single-disk ZIP64 locator")
    position = locator[2] - (archive_size - len(tail))
    if position < 0 or position + 56 > offset - 20:
        raise ValueError("ZIP64 end record leaves the bounded tail")
    record = struct.unpack_from("<4sQ2H2L4Q", tail, position)
    if record[0] != b"PK\x06\x06" or record[1] < 44 or record[4:6] != (0, 0) or record[6] != record[7]:
        raise ValueError("Invalid ZIP64 directory identity")
    count, size, start = record[-3:]
    if not 0 < count <= 250000 or not 0 < size <= MAX_DIRECTORY or not 0 <= start < start + size <= locator[2]:
        raise ValueError("ZIP64 directory exceeds research bounds")
    return {"entries": count, "bytes": size, "offset": start}


def parse_directory(data: bytes, archive_size: int, count: int) -> dict[str, dict[str, Any]]:
    if not 0 < len(data) <= MAX_DIRECTORY or not 0 < count <= 250000:
        raise ValueError("Oversized ZIP directory")
    entries: dict[str, dict[str, Any]] = {}
    offset = 0
    while offset < len(data):
        if offset + 46 > len(data):
            raise ValueError("Truncated central-directory record")
        record = struct.unpack_from("<4s6H3I5H2I", data, offset)
        _, _, _, flags, method, _, _, crc, compressed, size, nlen, elen, clen, disk, _, external, local = record
        end = offset + 46 + nlen + elen + clen
        if record[0] != b"PK\x01\x02" or end > len(data) or disk != 0:
            raise ValueError("Invalid or multidisk central-directory record")
        name = safe_path(data[offset + 46:offset + 46 + nlen].decode("utf-8" if flags & 0x800 else "cp437"))
        extra = data[offset + 46 + nlen:offset + 46 + nlen + elen]
        cursor = 0
        while cursor < len(extra):
            if cursor + 4 > len(extra):
                raise ValueError("Truncated ZIP extra header")
            tag, length = struct.unpack_from("<HH", extra, cursor)
            value = extra[cursor + 4:cursor + 4 + length]
            if len(value) != length:
                raise ValueError("Truncated ZIP64 extra data")
            cursor += 4 + length
            if tag == 1:
                at = 0
                values = [size, compressed, local]
                for index, number in enumerate(values):
                    if number == 0xffffffff:
                        if at + 8 > len(value):
                            raise ValueError("Truncated extended ZIP64 entry value")
                        values[index] = struct.unpack_from("<Q", value, at)[0]
                        at += 8
                size, compressed, local = values
        if name in entries or max(size, compressed, local) >= archive_size or local + compressed > archive_size:
            raise ValueError("Duplicate or out-of-archive ZIP entry")
        entries[name] = {"name": name, "compressed_size": compressed, "size": size,
                         "crc32": f"{crc:08x}", "method": method, "flags": flags,
                         "header_offset": local, "external_attributes": external}
        offset = end
    if len(entries) != count:
        raise ValueError("ZIP entry count differs from its ZIP64 record")
    return entries


def read_range(url: str, start: int, length: int, archive_size: int) -> bytes:
    origin = urlparse(url)
    if origin.scheme != "https" or not (origin.hostname == "archive.org" or (origin.hostname or "").endswith(".archive.org")) or origin.username or origin.password:
        raise ValueError("Original archive must use its pinned public HTTPS provider")
    if not 0 <= start < archive_size or not 0 < length <= MAX_DIRECTORY or start + length > archive_size:
        raise ValueError("HTTP Range leaves the bounded original archive")
    last = start + length - 1
    request = Request(url, headers={"User-Agent": "BroxyAssetResearch", "Range": f"bytes={start}-{last}"})
    for attempt in range(3):
        try:
            with urlopen(request, timeout=45) as response:
                target = urlparse(response.url)
                if target.scheme != "https" or not (target.hostname == "archive.org" or (target.hostname or "").endswith(".archive.org")):
                    raise ValueError("Original archive redirected outside its HTTPS provider")
                if response.status != 206 or response.headers.get("Content-Range") != f"bytes {start}-{last}/{archive_size}":
                    raise ValueError("Server ignored or changed the exact original HTTP Range")
                data = response.read(length + 1)
            break
        except HTTPError as error:
            if error.code not in (429, 500, 502, 503, 504) or attempt == 2:
                raise
            time.sleep(attempt + 1)
        except (URLError, TimeoutError):
            if attempt == 2:
                raise
            time.sleep(attempt + 1)
    if len(data) != length:
        raise ValueError("Truncated or oversized original HTTP Range")
    return data


def extract_entry(block: bytes, entry: dict[str, Any]) -> bytes:
    if entry["flags"] & 1 or (entry.get("external_attributes", 0) >> 16) & 0xf000 == 0xa000 or entry["method"] not in (0, 8) or not 0 < entry["size"] <= MAX_SOURCE or not 0 < entry["compressed_size"] <= MAX_SOURCE:
        raise ValueError("Unsupported, encrypted or oversized asset entry")
    if len(block) < 30:
        raise ValueError("Missing local ZIP asset header")
    head = struct.unpack_from("<4s5H3I2H", block)
    if head[0] != b"PK\x03\x04" or head[2] != entry["flags"] or head[3] != entry["method"]:
        raise ValueError("Local ZIP header differs from pinned directory")
    if not entry["flags"] & 8 and (f"{head[6]:08x}" != entry["crc32"] or head[7] not in (entry["compressed_size"], 0xffffffff) or head[8] not in (entry["size"], 0xffffffff)):
        raise ValueError("Local ZIP size/CRC fields differ from pinned directory")
    nlen, elen = head[-2:]
    start = 30 + nlen + elen
    name = block[30:30 + nlen].decode("utf-8" if head[2] & 0x800 else "cp437")
    if safe_path(name) != entry["name"] or start > HEADER_PADDING or start + entry["compressed_size"] > len(block):
        raise ValueError("Local ZIP name or source payload leaves the bounded Range")
    payload = block[start:start + entry["compressed_size"]]
    data = inflate(payload, entry["size"]) if entry["method"] == 8 else payload
    if len(data) != entry["size"] or f"{zlib.crc32(data) & 0xffffffff:08x}" != entry["crc32"]:
        raise ValueError("Original asset ZIP size/CRC32 mismatch")
    return data


class AMF3:
    def __init__(self, data: bytes):
        if len(data) > MAX_INFLATED:
            raise ValueError("AMF3 input exceeds byte limit")
        self.stream = io.BytesIO(data)
        self.strings: list[str] = []
        self.objects: list[Any] = []
        self.traits: list[tuple[str, bool, list[str]]] = []
        self.nodes = 0

    def take(self, size: int) -> bytes:
        data = self.stream.read(size)
        if len(data) != size:
            raise ValueError("Truncated AMF3 input")
        return data

    def u29(self) -> int:
        value = 0
        for index in range(4):
            byte = self.take(1)[0]
            if index == 3:
                return (value << 8) | byte
            value = (value << 7) | (byte & 127)
            if not byte & 128:
                return value
        raise ValueError("Invalid AMF3 U29")

    @staticmethod
    def reference(values: list[Any], index: int) -> Any:
        if not 0 <= index < len(values):
            raise ValueError("AMF3 reference leaves its decoded table")
        return values[index]

    def string(self) -> str:
        code = self.u29()
        if not code & 1:
            return self.reference(self.strings, code >> 1)
        length = code >> 1
        if length > MAX_SOURCE:
            raise ValueError("Oversized AMF3 string")
        value = self.take(length).decode("utf-8")
        if value:
            self.strings.append(value)
        return value

    def value(self, depth: int = 0) -> Any:
        self.nodes += 1
        if depth > 64 or self.nodes > 250000:
            raise ValueError("AMF3 nesting/node limit exceeded")
        marker = self.take(1)[0]
        if marker in (0, 1): return None
        if marker == 2: return False
        if marker == 3: return True
        if marker == 4:
            value = self.u29()
            return value - 0x20000000 if value & 0x10000000 else value
        if marker == 5:
            value = struct.unpack(">d", self.take(8))[0]
            if not math.isfinite(value): raise ValueError("Nonfinite AMF3 number")
            return value
        if marker == 6: return self.string()
        if marker == 9:
            code = self.u29()
            if not code & 1: return self.reference(self.objects, code >> 1)
            count = code >> 1
            if count > 100000: raise ValueError("AMF3 array limit exceeded")
            value: list[Any] = []
            self.objects.append(value)
            if self.string(): raise ValueError("Associative AMF3 arrays require explicit preservation support")
            value.extend(self.value(depth + 1) for _ in range(count))
            return value
        if marker == 10:
            code = self.u29()
            if not code & 1: return self.reference(self.objects, code >> 1)
            if not code & 2:
                name, dynamic, names = self.reference(self.traits, code >> 2)
            else:
                if code & 4: raise ValueError("Externalizable AMF3 classes are not executable input")
                if code >> 4 > 10000: raise ValueError("AMF3 trait limit exceeded")
                name = self.string()
                dynamic = bool(code & 8)
                names = [self.string() for _ in range(code >> 4)]
                if len(set(names)) != len(names):
                    raise ValueError("Duplicate AMF3 sealed object property")
                self.traits.append((name, dynamic, names))
            if name: raise ValueError("Typed AMF3 class requires explicit preservation support: " + name)
            result: dict[str, Any] = {}
            self.objects.append(result)
            for key in names: result[key] = self.value(depth + 1)
            if dynamic:
                while True:
                    key = self.string()
                    if not key: break
                    if key in result: raise ValueError("Duplicate AMF3 object property")
                    result[key] = self.value(depth + 1)
            return result
        raise ValueError(f"Unsupported original AMF3 marker: {marker}")


def decode_amf3(data: bytes) -> tuple[Any, dict[str, Any]]:
    raw = inflate(data, MAX_INFLATED)
    reader = AMF3(raw)
    value = reader.value()
    if reader.stream.tell() != len(raw):
        raise ValueError("Trailing bytes after original AMF3 document")
    encoded = json_bytes(value)
    return value, {"encoding": "AMF3", "compression": "raw DEFLATE", "fully_consumed": True,
                   "inflated_bytes": len(raw), "inflated_sha256": hashlib.sha256(raw).hexdigest(),
                   "decoded_json_sha256": hashlib.sha256(encoded).hexdigest()}


def validate_registry(registry: dict[str, Any], catalog: dict[str, Any]) -> None:
    archive = registry["archive"]
    if archive["url"] != "https://archive.org/download/gacha-archive/Online/World%20Flipper/air.jp.co.cygames.worldflipper-1.780.0.1780000.zip" or archive["bytes"] != 6861267373 or archive["whole_archive_checksum_verified"] or archive["asset_version"] != "1.780.30":
        raise ValueError("JP archive identity, verified cache version or full-download scope changed")
    if archive["range_url"] != "https://dn721903.ca.archive.org/0/items/gacha-archive/Online/World%20Flipper/air.jp.co.cygames.worldflipper-1.780.0.1780000.zip":
        raise ValueError("Pinned original archive Range endpoint changed")
    metadata = registry["cache_metadata"]
    if metadata["value"]["version"] != archive["asset_version"] or metadata["raw_sha256"] != "96991a8f2ff0531b0b8b50fd564c0245721493c85cb2cf3605e6a5830a1861fb" or not metadata["zip_entry"]["name"].endswith("/asset_download/production/info.json"):
        raise ValueError("Asset cache version is not bound to its measured original metadata")
    if registry["comparison_catalog"]["commit"] != catalog["source"]["commit"] or registry["runtime_ready"] or registry["final_jp_byte_identity_verified"]:
        raise ValueError("Research cache cannot claim runtime or final-client identity")
    refs: dict[str, list[str]] = {}
    for layout in catalog["maps"]["layouts"]:
        refs.setdefault(layout["terrain_ref"], []).append(layout["id"])
    seen: set[str] = set()
    terrains: set[str] = set()
    for source in registry["sources"]:
        logical = safe_path(source["logical_path"])
        if logical in seen or source["salted_sha1"] != salted_sha1(logical):
            raise ValueError("Duplicate or mismatched salted original identity")
        seen.add(logical)
        entry = source["zip_entry"]
        suffix = "/" + source["salted_sha1"][:2] + "/" + source["salted_sha1"][2:]
        if not safe_path(entry["name"]).endswith(suffix) or entry["flags"] & 1 or entry["method"] not in (0, 8):
            raise ValueError("Original logical asset is not bound to its exact unencrypted ZIP entry")
        if not 0 < entry["size"] <= MAX_SOURCE or not 0 < entry["compressed_size"] <= MAX_SOURCE or not 0 <= entry["header_offset"] < archive["bytes"] - entry["compressed_size"]:
            raise ValueError("Source sizes/offsets exceed the bounded archive")
        if source.get("raw_sha256") is not None and re.fullmatch("[0-9a-f]{64}", source["raw_sha256"]) is None:
            raise ValueError("Invalid verified original-byte digest")
        if source["kind"] == "terrain":
            ref = logical.removesuffix(".amf3.deflate")
            if not logical.endswith(".amf3.deflate") or ref not in refs or source["canonical_layout_ids"] != sorted(refs[ref]):
                raise ValueError("Terrain has no exact final-catalog layout-reference binding")
            terrains.add(ref)
        if "canonical_field_ids" in source:
            suffix = {"png": ".png", "atlas": ".atlas.amf3.deflate", "parts": ".parts.amf3.deflate", "timeline": ".timeline.amf3.deflate"}.get(source["kind"])
            if suffix is None or not logical.endswith(suffix):
                raise ValueError("Field asset needs its exact original format suffix")
            ref = logical.removesuffix(suffix)
            owners = sorted(field["id"] for field in catalog["maps"]["fields"] if field["background_ref"] == ref)
            if not owners or source["canonical_field_ids"] != owners:
                raise ValueError("Field asset is not bound to its exact canonical background reference")
    if terrains != set(refs):
        raise ValueError("The full1230 exact terrain-reference index is required")
    sources = [source for source in registry["sources"] if source["kind"] == "terrain"]
    expected = {"canonical_layout_references": sum(len(ids) for ids in refs.values()),
                "unique_terrain_refs_indexed": len(refs),
                "terrain_zip_compressed_bytes": sum(source["zip_entry"]["compressed_size"] for source in sources),
                "terrain_raw_bytes": sum(source["zip_entry"]["size"] for source in sources),
                "estimated_terrain_range_bytes": sum(source["zip_entry"]["compressed_size"] + HEADER_PADDING for source in sources),
                "verified_terrain_raw_files": sum(source.get("raw_sha256") is not None for source in sources)}
    if registry["availability"] != expected:
        raise ValueError("Source availability totals differ from their exact indexed/verified evidence")


def checked_index(registry: dict[str, Any], cache: Path, offline: bool) -> dict[str, dict[str, Any]]:
    record = registry["central_directory"]
    path = cache / "zip-central-directory.bin"
    data = path.read_bytes() if path.is_file() else None
    if data is None:
        if offline: raise FileNotFoundError("Missing ignored ZIP64 central-directory cache")
        data = read_range(registry["archive"]["range_url"], record["offset"], record["bytes"], registry["archive"]["bytes"])
    if len(data) != record["bytes"] or hashlib.sha256(data).hexdigest() != record["sha256"]:
        raise ValueError("Original ZIP64 directory changed from its verified bytes")
    entries = parse_directory(data, registry["archive"]["bytes"], record["entries"])
    for source in registry["sources"]:
        if entries.get(source["zip_entry"]["name"]) != source["zip_entry"]:
            raise ValueError("Pinned asset entry differs from the verified ZIP64 directory")
    metadata = registry["cache_metadata"]["zip_entry"]
    if entries.get(metadata["name"]) != metadata:
        raise ValueError("Pinned cache metadata differs from the verified ZIP64 directory")
    if not path.is_file():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    return entries


def checked_cache_metadata(registry: dict[str, Any], cache: Path, offline: bool) -> dict[str, Any]:
    source = registry["cache_metadata"]
    entry = source["zip_entry"]
    path = cache / "asset-cache-info.raw.json"
    if path.is_file():
        if path.stat().st_size != entry["size"]:
            raise ValueError("Cached asset-version metadata size changed")
        raw = path.read_bytes()
    else:
        if offline:
            raise FileNotFoundError("Missing ignored original asset-cache version metadata")
        block = read_range(registry["archive"]["range_url"], entry["header_offset"], entry["compressed_size"] + HEADER_PADDING, registry["archive"]["bytes"])
        raw = extract_entry(block, entry)
    if len(raw) != entry["size"] or f"{zlib.crc32(raw) & 0xffffffff:08x}" != entry["crc32"] or hashlib.sha256(raw).hexdigest() != source["raw_sha256"]:
        raise ValueError("Original asset-cache metadata CRC32/SHA256 changed")
    value = json.loads(raw)
    if value != source["value"] or value["version"] != registry["archive"]["asset_version"]:
        raise ValueError("Original asset-cache version does not match its registry")
    if not path.is_file():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)
    return value


def checked_source(source: dict[str, Any], registry: dict[str, Any], cache: Path, offline: bool) -> dict[str, Any]:
    entry = source["zip_entry"]
    digest = salted_sha1(source["logical_path"])
    path = cache / "raw" / digest
    if path.is_file():
        if path.stat().st_size != entry["size"]:
            raise ValueError("Cached original asset size differs from pinned directory")
        data = path.read_bytes()
        range_info: dict[str, Any] = {"downloaded": False}
        evidence = cache / "verified-entry" / (digest + ".json")
        if evidence.is_file():
            previous = json.loads(evidence.read_text(encoding="utf-8"))
            if previous.get("logical_path") == source["logical_path"] and previous.get("zip_entry") == entry and previous.get("raw_sha256") == hashlib.sha256(data).hexdigest():
                original_range = previous["range"]
                if original_range.get("downloaded"):
                    range_info["previously_downloaded_range"] = original_range
                elif "previously_downloaded_range" in original_range:
                    range_info["previously_downloaded_range"] = original_range["previously_downloaded_range"]
    else:
        if offline: raise FileNotFoundError("Missing ignored source cache: " + source["logical_path"])
        length = min(entry["compressed_size"] + HEADER_PADDING, registry["archive"]["bytes"] - entry["header_offset"])
        block = read_range(registry["archive"]["range_url"], entry["header_offset"], length, registry["archive"]["bytes"])
        data = extract_entry(block, entry)
        range_info = {"downloaded": True, "start": entry["header_offset"], "bytes": length,
                      "sha256": hashlib.sha256(block).hexdigest()}
    sha = hashlib.sha256(data).hexdigest()
    if len(data) != entry["size"] or f"{zlib.crc32(data) & 0xffffffff:08x}" != entry["crc32"] or (source.get("raw_sha256") is not None and sha != source["raw_sha256"]):
        raise ValueError("Cached original asset size/CRC32/SHA256 changed")
    if not path.is_file():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    result = {"logical_path": source["logical_path"], "kind": source["kind"], "canonical_layout_ids": source.get("canonical_layout_ids", []),
              "canonical_field_ids": source.get("canonical_field_ids", []),
              "raw_sha256": sha, "raw_bytes": len(data), "zip_entry": entry, "range": range_info,
              "archive_url": registry["archive"]["url"], "range_url": registry["archive"]["range_url"],
              "central_directory_sha256": registry["central_directory"]["sha256"],
              "runtime_ready": False, "final_jp_byte_identity_verified": False}
    if source["logical_path"].endswith(".amf3.deflate"):
        try:
            value, decoded = decode_amf3(data)
            output = cache / "decoded" / (digest + ".json")
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(json_bytes(value))
            result["decode"] = decoded
        except ValueError as error:
            result["decode_error"] = str(error)
    evidence = cache / "verified-entry" / (digest + ".json")
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_bytes(json_bytes(result))
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download", action="store_true", help="Fetch missing exact entry Ranges; default is offline")
    parser.add_argument("--cache", type=Path, default=CACHE)
    parser.add_argument("--kind", choices=("all", "terrain", "png", "atlas", "parts", "timeline", "orderedmap"), default="terrain")
    parser.add_argument("--limit", type=int)
    parser.add_argument("--workers", type=int, default=3)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not 1 <= args.workers <= 4 or (args.limit is not None and args.limit < 1):
        parser.error("Use1..4 workers and a positive optional limit")
    if not args.cache.resolve().is_relative_to((ROOT / ".tools").resolve()):
        parser.error("Original archive data must remain inside the ignored .tools cache")
    output = args.output or args.cache / "verified-assets.json"
    if not output.resolve().is_relative_to(args.cache.resolve()):
        parser.error("Research output must remain inside the selected ignored cache")
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    catalog = json.loads((ROOT / "data/worldflipper/catalog.json").read_text(encoding="utf-8"))
    validate_registry(registry, catalog)
    checked_index(registry, args.cache, not args.download)
    checked_cache_metadata(registry, args.cache, not args.download)
    sources = [source for source in registry["sources"] if args.kind == "all" or source["kind"] == args.kind]
    if args.limit is not None: sources = sources[:args.limit]
    estimate = sum(source["zip_entry"]["compressed_size"] + HEADER_PADDING for source in sources)
    if estimate > MAX_BATCH: parser.error("Batch exceeds the64MiB bounded research budget")
    print(json.dumps({"selected_entries": len(sources), "estimated_range_bytes": estimate, "offline": not args.download}), flush=True)
    successful: dict[int, dict[str, Any]] = {}
    failures: list[dict[str, str]] = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        pending = {pool.submit(checked_source, source, registry, args.cache, not args.download): index for index, source in enumerate(sources)}
        for completed, future in enumerate(as_completed(pending), 1):
            index = pending[future]
            try:
                successful[index] = future.result()
            except (OSError, ValueError) as error:
                failures.append({"logical_path": sources[index]["logical_path"], "error": type(error).__name__ + ": " + str(error)})
            if completed % 100 == 0:
                print(json.dumps({"completed": completed, "verified": len(successful), "failed": len(failures)}), flush=True)
    files = [successful[index] for index in sorted(successful)]
    failures.sort(key=lambda value: value["logical_path"])
    report = {"scope": registry["scope"], "archive": registry["archive"], "central_directory": registry["central_directory"], "cache_metadata": registry["cache_metadata"],
              "verified_entries": len(files), "verified_raw_bytes": sum(file["raw_bytes"] for file in files),
              "decoded_entries": sum("decode" in file for file in files), "runtime_ready": False,
              "final_jp_byte_identity_verified": False, "failures": failures, "files": files}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(json_bytes(report))
    print(json.dumps({key: value for key, value in report.items() if key != "files"}))
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
