"""Independent original equipment icons never replace unknown art with a core."""

from __future__ import annotations

import copy
import importlib.util
import io
import hashlib
import struct
import tempfile
import unittest
import zlib
from pathlib import Path
from unittest import mock

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("scoped_equipment", ROOT / "tools/world_flipper_scoped_equipment.py")
assert SPEC and SPEC.loader
ART = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ART)


class ScopedEquipmentArtTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.registry = ART.read_json(ART.REGISTRY)
        cls.catalog = ART.read_json(ART.CATALOG)
        cls.manifest = ART.read_json(ART.OUTPUT / "manifest.json")

    def require_raw_cache(self) -> None:
        files = [source for source in self.registry["sources"] if source["availability"] == "verified_original"]
        files += [source["atlas_source"] for source in files if source.get("source_kind") == "authored_atlas_frame"]
        files += [source["cache_metadata_source"] for source in self.registry["sources"] if source.get("source_kind") == "authored_atlas_frame"]
        if any(not (ART.CACHE / source["filename"]).is_file() for source in files):
            self.skipTest("Original icon sources are local-only; acquire with the icon tool before offline normalization")

    def test_five_canonical_aliases_keep_exact_chinese_source_pages(self) -> None:
        ART.validate_registry(self.registry, self.catalog)
        self.assertEqual(len(self.registry["sources"]), 5)
        self.assertEqual(self.registry["catalog_commit"], "1d45b529ef078ba9b1f876d4588debd0c8a9a214")
        for source in self.registry["sources"]:
            identifier, name = ART.IDENTITIES[source["game_id"]]
            self.assertEqual(source["canonical_id"], identifier)
            self.assertEqual(source["display_name_zh"], name)
            self.assertEqual(source["name_evidence"]["title"], name)
            self.assertTrue(source["name_evidence"]["wiki_revision"].isdigit())
            self.assertEqual(len(source["original_ability_row_sha256"]), 1 if source["game_id"] == "staff_0001" else 2)
        self.assertIn("not an assertion", self.manifest["limitations"][0])

    def test_missing_art_is_explicit_and_never_a_placeholder_or_ability_core(self) -> None:
        verified = {source["game_id"] for source in self.registry["sources"] if source["availability"] == "verified_original"}
        missing = {source["game_id"] for source in self.registry["sources"] if source["availability"] != "verified_original"}
        self.assertEqual({asset["id"] for asset in self.manifest["assets"]}, verified)
        self.assertEqual({item["game_id"] for item in self.manifest["missing"]}, missing)
        self.assertEqual(len(verified) + len(missing), 5)
        self.assertEqual(verified, set(ART.IDENTITIES))
        for item in self.manifest["missing"]:
            self.assertTrue(item["reason"])
            self.assertFalse((ART.OUTPUT / (item["game_id"] + ".png")).exists())

    def test_committed_icons_have_binary_alpha_and_fixed_full_canvas_nearest_geometry(self) -> None:
        self.assertEqual(self.manifest["source_registry_sha256"], ART.sha256(ART.json_bytes(self.registry)))
        self.assertEqual((ART.OUTPUT / "manifest.json").read_bytes(), ART.json_bytes(self.manifest))
        sources = {source["id"]: source for source in self.registry["sources"]}
        for asset in self.manifest["assets"]:
            path = ROOT / asset["path"]
            self.assertEqual(ART.sha256(path.read_bytes()), asset["sha256"])
            source = sources[asset["source_ids"][0]]
            self.assertEqual(asset["canonical_equipment_id"], source["canonical_id"])
            self.assertEqual(asset["source_crop"], [0, 0, *source["source_size"]])
            self.assertEqual(asset["source_scale"], 2)
            width, height = source["source_size"]
            self.assertEqual(asset["offset"], [(64 - width * 2) // 2, (64 - height * 2) // 2])
            with Image.open(path) as image:
                self.assertEqual((image.mode, image.size), ("RGBA", (64, 64)))
                self.assertEqual(set(image.getchannel("A").tobytes()), {0, 255})
                self.assertEqual(ART.sha256(image.tobytes()), asset["rgba_sha256"])
                self.assertEqual(list(image.getchannel("A").getbbox()), asset["alpha_bounds"])

    def test_original_source_pixels_form_exact_integer_blocks_without_cutout(self) -> None:
        self.require_raw_cache()
        for source in self.registry["sources"]:
            if source["availability"] != "verified_original":
                continue
            raw = (ART.CACHE / source["filename"]).read_bytes()
            framed = source.get("source_kind") == "authored_atlas_frame"
            atlas_raw = (ART.CACHE / source["atlas_source"]["filename"]).read_bytes() if framed else None
            image, offset = ART.normalize_sprite(source, raw, atlas_raw)
            decoded = b"\x89PNG\r\n\x1a\n" + raw[8:] if framed else raw
            with Image.open(io.BytesIO(decoded)) as original:
                rgba = original.convert("RGBA")
                for y in range(source["source_size"][1]):
                    for x in range(source["source_size"][0]):
                        if framed:
                            frame = source["frame"]
                            sx, sy = x + frame["fx"], y + frame["fy"]
                            pixel = rgba.getpixel((frame["x"] + sx, frame["y"] + sy)) if 0 <= sx < frame["w"] and 0 <= sy < frame["h"] else (0, 0, 0, 0)
                        else:
                            pixel = rgba.getpixel((x, y))
                        expected = pixel if pixel[3] else (0, 0, 0, 0)
                        for dy in range(2):
                            for dx in range(2):
                                self.assertEqual(image.getpixel((offset[0] + x * 2 + dx, offset[1] + y * 2 + dy)), expected)

    def test_offline_rebuild_is_byte_identical_and_check_does_not_write(self) -> None:
        self.require_raw_cache()
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(ART.urllib.request, "urlopen") as network:
            output = Path(directory)
            rebuilt = ART.build(output, ART.CACHE, offline=True)
            self.assertEqual(ART.json_bytes(rebuilt), (ART.OUTPUT / "manifest.json").read_bytes())
            for asset in rebuilt["assets"]:
                self.assertEqual((output / Path(asset["path"]).name).read_bytes(), (ROOT / asset["path"]).read_bytes())
            with mock.patch.object(Path, "write_bytes") as writes:
                ART.build(output, ART.CACHE, offline=True, check=True)
                writes.assert_not_called()
            network.assert_not_called()

    def test_tampered_identity_crop_name_scale_and_core_url_are_rejected(self) -> None:
        for mutate in [lambda r: r["sources"][0].update(canonical_id="5010005"),
                       lambda r: r["sources"][0].update(dev_name="other"),
                       lambda r: r["sources"][0].update(display_name_zh="unverified translation"),
                       lambda r: r["sources"][0]["name_evidence"].update(revision_url="https://example.com"),
                       lambda r: r["sources"][0].update(filename="../escape.png"),
                       lambda r: r["sources"][0].update(crop=[1, 0, 18, 18]),
                       lambda r: r["sources"][0].update(url="https://worldflipper.wiki.gg/images/Some_Core.png"),
                       lambda r: r["normalization"].update(scale=2.0),
                       lambda r: r["normalization"].update(canvas=[64.0, 64]),
                       lambda r: r["sources"].append(copy.deepcopy(r["sources"][0]))]:
            registry = copy.deepcopy(self.registry)
            mutate(registry)
            with self.assertRaises(ValueError):
                ART.validate_registry(registry, self.catalog)

    def test_source_and_output_tampering_fail_without_overwriting_assets(self) -> None:
        self.require_raw_cache()
        source = next(source for source in self.registry["sources"] if source["availability"] == "verified_original")
        raw = (ART.CACHE / source["filename"]).read_bytes()
        with self.assertRaisesRegex(ValueError, "source bytes"):
            ART.normalize_sprite(source, raw[:-1] + bytes([raw[-1] ^ 1]))
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            ART.build(output, ART.CACHE, offline=True)
            (output / (source["game_id"] + ".png")).write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "deterministic rebuild"):
                ART.build(output, ART.CACHE, offline=True, check=True)

    def test_previous_ninety_four_pngs_keep_their_original_three_manifests(self) -> None:
        count = 0
        for name in ("manifest.json", "stages/manifest.json", "roster/manifest.json"):
            manifest = ART.read_json(ROOT / "assets/worldflipper" / name)
            for record in manifest["assets"]:
                count += 1
                self.assertNotIn("/equipment/", record["path"])
                self.assertEqual(ART.sha256((ROOT / record["path"]).read_bytes()), record["sha256"])
        self.assertEqual(count, 94)

    def test_original_atlas_uses_exact_weapon_frame_and_retains_unverified_version_boundary(self) -> None:
        source = next(source for source in self.registry["sources"] if source["game_id"] == "fist_0006")
        self.assertEqual(source["source_kind"], "authored_atlas_frame")
        self.assertEqual(source["cache_metadata_declared_version"], "1.780.30")
        self.assertFalse(source["source_object_final_jp_byte_identity_verified"])
        self.assertEqual(source["frame"], {"n": "item/equipment/general/fist_0006", "w": 18, "h": 18, "x": 1260, "y": 310, "fx": -1, "fy": -1, "fw": 20, "fh": 20})
        for original in (source, source["atlas_source"]):
            self.assertFalse(original["transport"]["final_jp_byte_identity_verified"])
            self.assertFalse(original["transport"]["whole_archive_checksum_verified"])
            self.assertIsNone(original["transport"]["source_asset_version"])
            self.assertEqual(original["transport"]["range"][0], original["transport"]["zip_header_offset"])
        self.require_raw_cache()
        metadata = ART.read_json(ART.CACHE / source["cache_metadata_source"]["filename"])
        self.assertEqual(metadata["version"], source["cache_metadata_declared_version"])
        self.assertEqual(source["cache_metadata_source"]["sha256"], "96991a8f2ff0531b0b8b50fd564c0245721493c85cb2cf3605e6a5830a1861fb")
        atlas = (ART.CACHE / source["atlas_source"]["filename"]).read_bytes()
        frames = ART.atlas_frames(atlas)
        self.assertEqual(len(frames), 1382)
        weapon = next(frame for frame in frames if frame["n"] == source["image_resource_ref"])
        core = next(frame for frame in frames if frame["n"] == "item/generated/ability_soul/general/fist_0006")
        self.assertNotEqual((weapon["x"], weapon["y"]), (core["x"], core["y"]))
        raw = (ART.CACHE / source["filename"]).read_bytes()
        for change in (lambda s: s["frame"].update(x=1261),
                       lambda s: s["frame"].update(n=core["n"]),
                       lambda s: s.update(source_rgba_sha256="0" * 64),
                       lambda s: s.update(atlas_rgba_sha256="0" * 64)):
            changed = copy.deepcopy(source)
            change(changed)
            with self.assertRaises(ValueError):
                ART.normalize_sprite(changed, raw, atlas)
        with self.assertRaises(ValueError):
            ART.normalize_sprite(source, raw, atlas[:-1] + bytes([atlas[-1] ^ 1]))

    def test_absent_original_art_is_explicit_in_memory_without_any_substitute(self) -> None:
        self.require_raw_cache()
        registry = copy.deepcopy(self.registry)
        fist = next(source for source in registry["sources"] if source["game_id"] == "fist_0006")
        fist.update(availability="missing_original_weapon_sprite", missing_reason="Original frame unavailable in this fixture")
        manifest, images = ART.produce(registry, self.catalog, ART.CACHE, offline=True)
        self.assertEqual(len(images), 4)
        self.assertNotIn("fist_0006.png", images)
        self.assertEqual([entry["game_id"] for entry in manifest["missing"]], ["fist_0006"])

    def test_bounded_zip_range_checks_member_header_crc_and_honored_http_range(self) -> None:
        payload = b"exact original archived bytes"
        compressor = zlib.compressobj(wbits=-15)
        compressed = compressor.compress(payload) + compressor.flush()
        filename = b"upload/aa/original"
        crc = zlib.crc32(payload) & 0xffffffff
        header = struct.pack("<4s5H3I2H", b"PK\x03\x04", 20, 0, 8, 0, 0, crc, len(compressed), len(payload), len(filename), 0)
        block = header + filename + compressed
        source = {"filename": "fixture.raw", "url": "https://archive.org/download/gacha-archive/fixture.zip", "bytes": len(payload),
            "sha256": hashlib.sha256(payload).hexdigest(), "transport": {"kind": "archive_zip_range", "range": [100, 99 + len(block)],
            "range_sha256": hashlib.sha256(block).hexdigest(), "zip_entry": filename.decode(), "zip_compression_method": 8,
            "zip_compressed_bytes": len(compressed), "zip_crc32": f"{crc:08x}", "archive_bytes": 1000}}
        self.assertEqual(ART.archive_member(source, block), payload)
        for field, value in [("zip_crc32", "00000000"), ("zip_entry", "upload/core"), ("zip_compression_method", 0)]:
            changed = copy.deepcopy(source)
            changed["transport"][field] = value
            with self.assertRaises(ValueError):
                ART.archive_member(changed, block)
        with self.assertRaises(ValueError):
            ART.archive_member(source, block[:-1])
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            response = mock.MagicMock()
            response.__enter__.return_value = response
            response.status = 200
            with mock.patch.object(ART.urllib.request, "urlopen", return_value=response):
                with self.assertRaisesRegex(ValueError, "honor"):
                    ART.acquire(source, cache, offline=False)
                response.read.assert_not_called()
                self.assertFalse((cache / source["filename"]).exists())
                response.status = 206
                response.headers = {"Content-Range": f"bytes 100-{99 + len(block)}/1000"}
                response.read.return_value = block
                self.assertEqual(ART.acquire(source, cache, offline=False), payload)
                response.read.assert_called_once_with(len(block) + 1)

    def test_amf_decoder_rejects_truncated_unsupported_and_oversized_payloads(self) -> None:
        def compressed(raw: bytes) -> bytes:
            compressor = zlib.compressobj(wbits=-15)
            return compressor.compress(raw) + compressor.flush()
        for raw in (b"", b"\xff", b"\x09", b"\x09\x00", b"\x09\x03\x01"):
            with self.assertRaises(ValueError):
                ART.atlas_frames(compressed(raw))
        with self.assertRaises(ValueError):
            ART.inflate(compressed(b"larger than budget"), 4)


if __name__ == "__main__":
    unittest.main()
