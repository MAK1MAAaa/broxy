"""Offline ZIP64/CRC/AMF3 boundaries and exact canonical source bindings."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest import mock
from urllib.error import HTTPError
import zlib

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("wf_jp_archive", ROOT / "tools/world_flipper_jp_archive.py")
assert SPEC and SPEC.loader
TOOL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TOOL)


def compressed(data: bytes) -> bytes:
    compressor = zlib.compressobj(wbits=-15)
    return compressor.compress(data) + compressor.flush()


def u29(value: int) -> bytes:
    if value < 128: return bytes([value])
    if value < 16384: return bytes([(value >> 7) | 128, value & 127])
    if value < 2097152: return bytes([(value >> 14) | 128, ((value >> 7) & 127) | 128, value & 127])
    return bytes([((value >> 22) & 127) | 128, ((value >> 15) & 127) | 128, ((value >> 8) & 127) | 128, value & 255])


def amf_string(value: str) -> bytes:
    data = value.encode("utf-8")
    return u29(len(data) * 2 + 1) + data


def amf(value) -> bytes:
    if value is None: return b"\x01"
    if value is False: return b"\x02"
    if value is True: return b"\x03"
    if isinstance(value, int): return b"\x04" + u29(value & 0x1fffffff)
    if isinstance(value, float): return b"\x05" + struct.pack(">d", value)
    if isinstance(value, str): return b"\x06" + amf_string(value)
    if isinstance(value, list): return b"\x09" + u29(len(value) * 2 + 1) + b"\x01" + b"".join(amf(item) for item in value)
    return b"\x0a\x0b\x01" + b"".join(amf_string(key) + amf(item) for key, item in value.items()) + b"\x01"


def entry_fixture(method: int = 8) -> tuple[bytes, dict]:
    name = "data/production/upload/ab/" + "1" * 38
    data = b"actual original bytes" * 5
    payload = compressed(data) if method == 8 else data
    crc = zlib.crc32(data) & 0xffffffff
    encoded_name = name.encode("utf-8")
    head = struct.pack("<4s5H3I2H", b"PK\x03\x04", 20, 0, method, 0, 0, crc, len(payload), len(data), len(encoded_name), 0)
    entry = {"name": name, "size": len(data), "compressed_size": len(payload), "method": method, "flags": 0,
             "crc32": f"{crc:08x}", "header_offset": 15, "external_attributes": 0}
    return head + encoded_name + payload, entry


class OriginalJPArchive(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.registry = json.loads(TOOL.REGISTRY.read_text(encoding="utf-8"))
        cls.catalog = json.loads((ROOT / "data/worldflipper/catalog.json").read_text(encoding="utf-8"))

    def test_full_terrain_index_binds_refs_not_backgrounds_or_playability(self) -> None:
        TOOL.validate_registry(self.registry, self.catalog)
        sources = [row for row in self.registry["sources"] if row["kind"] == "terrain"]
        self.assertEqual(len(sources), 1230)
        self.assertEqual(sum(len(row["canonical_layout_ids"]) for row in sources), 1422)
        self.assertEqual(sum(row["zip_entry"]["compressed_size"] for row in sources), 1731439)
        self.assertEqual(sum(row["zip_entry"]["size"] for row in sources), 1731439)
        self.assertTrue(all(row["raw_sha256"] for row in sources))
        self.assertEqual(self.registry["availability"]["verified_terrain_raw_files"], 1230)
        self.assertEqual(self.registry["central_directory"]["sha256"], "3e7b2893cd09a3d200b597eeedd1bf6f1f3542cd0e031fdb1d9e4d77b64d4e62")
        self.assertEqual(self.registry["central_directory"]["entries"], 136289)
        self.assertFalse(self.registry["archive"]["whole_archive_checksum_verified"])
        self.assertEqual(self.registry["archive"]["asset_version"], "1.780.30")
        self.assertEqual(self.registry["cache_metadata"]["value"]["version"], "1.780.30")
        self.assertFalse(self.registry["runtime_ready"])
        self.assertFalse(self.registry["final_jp_byte_identity_verified"])

    def test_inexact_salted_paths_duplicates_false_versions_and_claims_fail(self) -> None:
        for change in [lambda v: v["sources"][0].update(salted_sha1="0" * 40),
                       lambda v: v["sources"][0].update(canonical_layout_ids=["main_1_1_2"]),
                       lambda v: v["sources"][0].update(logical_path="../outside"),
                       lambda v: next(row for row in v["sources"] if "canonical_field_ids" in row).update(canonical_field_ids=["wrong_field"]),
                       lambda v: v["sources"].append(copy.deepcopy(v["sources"][0])),
                       lambda v: v["sources"].pop(0),
                       lambda v: v["archive"].update(asset_version="1.780.40"),
                       lambda v: v["archive"].update(range_url="https://other.example/archive.zip"),
                       lambda v: v["archive"].update(whole_archive_checksum_verified=True),
                       lambda v: v["availability"].update(verified_terrain_raw_files=999999),
                       lambda v: v.update(runtime_ready=True),
                       lambda v: v.update(final_jp_byte_identity_verified=True)]:
            value = copy.deepcopy(self.registry)
            change(value)
            with self.assertRaises(ValueError): TOOL.validate_registry(value, self.catalog)

    def test_paths_cannot_escape_or_rename_the_original_source(self) -> None:
        for value in ["../a", "/root/a", "data/../a", "data/./a", "data\\a", "C:/a", "data//a", "data/\0a"]:
            with self.subTest(path=value), self.assertRaises(ValueError): TOOL.safe_path(value)
        self.assertEqual(TOOL.safe_path("data/Local Store/upload/ab/file"), "data/Local Store/upload/ab/file")

    def test_http_range_is_exact_bounded_and_transient_retry_is_limited(self) -> None:
        url = self.registry["archive"]["range_url"]
        def response(content_range="bytes 4-6/12", status=206):
            result = io.BytesIO(b"abc")
            result.url, result.status, result.headers = url, status, {"Content-Range": content_range}
            return result
        transient = HTTPError(url, 503, "transient", {}, None)
        with mock.patch.object(TOOL, "urlopen", side_effect=[transient, response()]) as request, mock.patch.object(TOOL.time, "sleep") as sleep:
            self.assertEqual(TOOL.read_range(url, 4, 3, 12), b"abc")
            self.assertEqual(request.call_count, 2)
            sleep.assert_called_once_with(1)
        with mock.patch.object(TOOL, "urlopen", side_effect=transient) as request, mock.patch.object(TOOL.time, "sleep"):
            with self.assertRaises(HTTPError): TOOL.read_range(url, 4, 3, 12)
            self.assertEqual(request.call_count, 3)
        for content_range, status in [("bytes 5-7/12", 206), ("bytes 4-6/99", 206), ("bytes 4-6/12", 200)]:
            with mock.patch.object(TOOL, "urlopen", return_value=response(content_range, status)) as request:
                with self.assertRaises(ValueError): TOOL.read_range(url, 4, 3, 12)
                self.assertEqual(request.call_count, 1)
        with mock.patch.object(TOOL, "urlopen") as request:
            for target, start, length in [("https://archive.org.evil.example/a", 0, 1), (url, -1, 2), (url, 11, 2), (url, 0, TOOL.MAX_DIRECTORY + 1)]:
                with self.assertRaises(ValueError): TOOL.read_range(target, start, length, 12)
            request.assert_not_called()

    def test_zip64_footer_preserves_large_offsets_and_rejects_multidisk(self) -> None:
        archive_size = 6000000000
        directory_offset, directory_size, count = 5900000000, 1000, 70000
        zip64_offset = archive_size - 98
        footer = struct.pack("<4sQ2H2L4Q", b"PK\x06\x06", 44, 45, 45, 0, 0, count, count, directory_size, directory_offset)
        footer += struct.pack("<4sLQL", b"PK\x06\x07", 0, zip64_offset, 1)
        footer += struct.pack("<4s4H2LH", b"PK\x05\x06", 0, 0, 65535, 65535, directory_size, 0xffffffff, 0)
        self.assertEqual(TOOL.zip64_directory(footer, archive_size), {"entries": count, "bytes": directory_size, "offset": directory_offset})
        with self.assertRaises(ValueError): TOOL.zip64_directory(footer[:-1], archive_size)
        value = bytearray(footer); struct.pack_into("<L", value, 56 + 4, 1)
        with self.assertRaises(ValueError): TOOL.zip64_directory(bytes(value), archive_size)

    def test_extended_zip64_entries_and_duplicate_or_unsafe_names(self) -> None:
        def record(name: str) -> bytes:
            text = name.encode()
            extra = struct.pack("<HHQQQ", 1, 24, 3, 3, 5000000000)
            return struct.pack("<4s6H3I5H2I", b"PK\x01\x02", 45, 45, 0, 0, 0, 0, 123, 0xffffffff, 0xffffffff,
                               len(text), len(extra), 0, 0, 0, 0, 0xffffffff) + text + extra
        data = record("data/upload/ab/original")
        parsed = TOOL.parse_directory(data, 6000000000, 1)["data/upload/ab/original"]
        self.assertEqual((parsed["size"], parsed["compressed_size"], parsed["header_offset"]), (3, 3, 5000000000))
        for changed, count in [(data + data, 2), (data[:-1], 1), (record("../outside"), 1)]:
            with self.assertRaises(ValueError): TOOL.parse_directory(changed, 6000000000, count)

    def test_local_payload_checks_real_header_name_size_crc_and_compression(self) -> None:
        for method in (0, 8):
            block, entry = entry_fixture(method)
            self.assertEqual(TOOL.extract_entry(block, entry), b"actual original bytes" * 5)
            for change in [{"name": "wrong"}, {"size": 1}, {"crc32": "00000000"}, {"flags": 1}, {"external_attributes": 0xa000 << 16}]:
                with self.subTest(change=change), self.assertRaises(ValueError): TOOL.extract_entry(block, {**entry, **change})
            with self.assertRaises(ValueError): TOOL.extract_entry(block[:-1], entry)

    def test_offline_cache_rejects_changed_bytes_and_never_uses_network(self) -> None:
        source = copy.deepcopy(self.registry["sources"][0])
        data = b"source fixture"
        source["zip_entry"].update(size=len(data), crc32=f"{zlib.crc32(data) & 0xffffffff:08x}")
        source["raw_sha256"] = hashlib.sha256(data).hexdigest()
        source["logical_path"] = "fixture/data.bin"
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(TOOL, "read_range", side_effect=AssertionError("network")):
            cache = Path(directory)
            with self.assertRaises(FileNotFoundError): TOOL.checked_source(source, self.registry, cache, True)
            path = cache / "raw" / TOOL.salted_sha1(source["logical_path"])
            path.parent.mkdir(); path.write_bytes(data)
            self.assertEqual(TOOL.checked_source(source, self.registry, cache, True)["raw_sha256"], source["raw_sha256"])
            path.write_bytes(b"different data")
            with self.assertRaises(ValueError): TOOL.checked_source(source, self.registry, cache, True)

    def test_actual_range_evidence_survives_offline_reruns_without_refetch(self) -> None:
        block, entry = entry_fixture()
        source = {"logical_path": "fixture/actual.bin", "kind": "png", "zip_entry": entry}
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(TOOL, "read_range", return_value=block) as request:
            cache = Path(directory)
            original = TOOL.checked_source(source, self.registry, cache, False)
            self.assertTrue(original["range"]["downloaded"])
            self.assertEqual(original["range"]["sha256"], hashlib.sha256(block).hexdigest())
            self.assertEqual(original["central_directory_sha256"], self.registry["central_directory"]["sha256"])
            for _ in range(2):
                offline = TOOL.checked_source(source, self.registry, cache, True)
                self.assertFalse(offline["range"]["downloaded"])
                self.assertEqual(offline["range"]["previously_downloaded_range"], original["range"])
            request.assert_called_once()

    def test_original_cache_version_metadata_is_byte_verified_not_package_inferred(self) -> None:
        raw = json.dumps(self.registry["cache_metadata"]["value"], separators=(",", ":")).encode("utf-8")
        self.assertEqual(hashlib.sha256(raw).hexdigest(), self.registry["cache_metadata"]["raw_sha256"])
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(TOOL, "read_range", side_effect=AssertionError("network")):
            cache = Path(directory)
            with self.assertRaises(FileNotFoundError): TOOL.checked_cache_metadata(self.registry, cache, True)
            (cache / "asset-cache-info.raw.json").write_bytes(raw)
            self.assertEqual(TOOL.checked_cache_metadata(self.registry, cache, True)["version"], "1.780.30")
            (cache / "asset-cache-info.raw.json").write_bytes(raw.replace(b"1.780.30", b"1.780.40"))
            with self.assertRaises(ValueError): TOOL.checked_cache_metadata(self.registry, cache, True)

    def test_amf3_preserves_layers_numbers_arrays_and_reference_tables(self) -> None:
        original = {"layers": [{"name": "0", "objects": [{"type": "WALL", "x": -3.5, "id": 7}]}], "enabled": True, "empty": None}
        value, evidence = TOOL.decode_amf3(compressed(amf(original)))
        self.assertEqual(value, original)
        self.assertTrue(evidence["fully_consumed"])
        self.assertEqual(evidence["inflated_sha256"], hashlib.sha256(amf(original)).hexdigest())
        string_refs = b"\x09\x05\x01\x06\x03a\x06\x00"
        self.assertEqual(TOOL.decode_amf3(compressed(string_refs))[0], ["a", "a"])
        object_refs = b"\x09\x05\x01\x0a\x0b\x01\x01\x0a\x02"
        self.assertEqual(TOOL.decode_amf3(compressed(object_refs))[0], [{}, {}])
        self.assertEqual(TOOL.decode_amf3(compressed(b"\x04\xff\xff\xff\xff"))[0], -1)

    def test_amf3_rejects_unsupported_nonfinite_trailing_truncated_and_bomb_data(self) -> None:
        for raw in [b"\x0a\x07", b"\x06\x00", b"\x05" + struct.pack(">d", float("nan")), b"\x01\x01", b"\x09\x03\x01", b"\x0c", b"\x0a\x23\x01\x03a\x00\x01\x01"]:
            with self.subTest(raw=raw), self.assertRaises(ValueError): TOOL.decode_amf3(compressed(raw))
        with self.assertRaises(ValueError): TOOL.inflate(compressed(b"a" * 4096), 32)
        with self.assertRaises(ValueError): TOOL.inflate(compressed(b"a") + b"trailing", 32)
        amplification = b"\x09" + u29(201) + b"\x01\x06" + amf_string("a" * 32) + b"\x06\x00" * 99
        with mock.patch.object(TOOL, "MAX_INFLATED", 1024):
            with self.assertRaises(ValueError): TOOL.decode_amf3(compressed(amplification))

    def test_optional_actual_directory_and_five_original_samples_verify_offline(self) -> None:
        if not (TOOL.CACHE / "zip-central-directory.bin").is_file():
            self.skipTest("Ignored original ZIP64 directory cache is unavailable")
        TOOL.checked_index(self.registry, TOOL.CACHE, True)
        targets = {"main_1_1_2", "main_2_9_5", "main_3_6_2", "main_4_1_2", "main_6_6_2"}
        for source in self.registry["sources"]:
            if targets.intersection(source["canonical_layout_ids"]):
                if not (TOOL.CACHE / "raw" / source["salted_sha1"]).is_file():
                    self.skipTest("Ignored representative terrain cache is unavailable")
                result = TOOL.checked_source(source, self.registry, TOOL.CACHE, True)
                self.assertIn("decode", result)
                self.assertNotIn("decode_error", result)

    def test_optional_complete_terrain_cache_checks_all_pinned_bytes_and_decodes(self) -> None:
        sources = [row for row in self.registry["sources"] if row["kind"] == "terrain"]
        if not all((TOOL.CACHE / "raw" / row["salted_sha1"]).is_file() for row in sources):
            self.skipTest("Ignored complete original terrain cache is unavailable")
        for source in sources:
            with self.subTest(terrain=source["logical_path"]):
                result = TOOL.checked_source(source, self.registry, TOOL.CACHE, True)
                self.assertEqual(result["raw_sha256"], source["raw_sha256"])
                self.assertTrue(result["decode"]["fully_consumed"])

    def test_committed_research_texts_are_lf_and_no_runtime_claim_is_added(self) -> None:
        for relative in ["tools/world_flipper_jp_archive.py", "tools/world_flipper_jp_archive_sources.json", "tests/test_world_flipper_jp_archive.py"]:
            data = (ROOT / relative).read_bytes()
            self.assertNotIn(b"\r", data)
            self.assertTrue(data.endswith(b"\n"))
        self.assertIn("Existing94 runtime PNGs", " ".join(self.registry["limitations"]))


if __name__ == "__main__":
    unittest.main()
