"""Pinned historical background checks, without network or optional raw caches."""

from __future__ import annotations

from copy import deepcopy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def module():
    spec = importlib.util.spec_from_file_location("wf_background_import", ROOT / "tools/world_flipper_backgrounds.py")
    assert spec and spec.loader
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def png_fixture() -> tuple[bytes, dict]:
    buffer = io.BytesIO()
    Image.new("RGBA", (3, 7), (40, 80, 120, 255)).save(buffer, format="PNG")
    data = buffer.getvalue()
    return data, {"id": "fixture", "path": "battle/field/fixture/background/background.png",
                  "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                  "git_blob_sha1": hashlib.sha1(f"blob {len(data)}\0".encode("ascii") + data).hexdigest(),
                  "source_size": [3, 7], "mode": "RGBA", "fields": ["fixture"]}


class BackgroundMirror(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.tool = module()
        cls.registry = json.loads((ROOT / "tools/world_flipper_background_sources.json").read_text(encoding="utf-8"))
        cls.catalog = json.loads((ROOT / "data/worldflipper/catalog.json").read_text(encoding="utf-8"))

    def test_registry_covers_exact_paths_without_confusing_aliases_with_maps(self) -> None:
        self.tool.validate_registry(self.registry, self.catalog)
        coverage = self.registry["coverage"]
        self.assertEqual((coverage["canonical_fields"], coverage["matched_field_refs"], coverage["missing_field_refs"], coverage["unique_background_pngs"]), (247, 198, 49, 132))
        sources = self.registry["sources"]
        fields = {value for source in sources for value in source["fields"]}
        self.assertEqual(len(sources), 132)
        self.assertEqual(len({source["path"] for source in sources}), 132)
        self.assertEqual(len(fields), 198)
        self.assertTrue(any(len(source["fields"]) > 1 for source in sources))
        missing = {row["id"] for row in self.registry["missing_fields"]}
        self.assertFalse(fields & missing)
        self.assertEqual(fields | missing, {row["id"] for row in self.catalog["maps"]["fields"]})
        self.assertEqual(sum(source["bytes"] for source in sources), 10008106)

    def test_mirror_provenance_does_not_claim_final_jp_geometry_or_runtime(self) -> None:
        self.assertEqual(self.registry["mirror"]["commit"], "6bf81da717f2ac073e630fd17aa819d1cdb0d815")
        self.assertEqual(self.registry["mirror"]["commit_date"], "2022-06-03T02:27:43Z")
        self.assertIsNone(self.registry["mirror"]["asset_version"])
        self.assertEqual(self.registry["comparison_catalog"]["asset_version"], "1.780.40")
        self.assertFalse(self.registry["coverage"]["final_jp_byte_identity_verified"])
        self.assertEqual(self.registry["coverage"]["terrain_files_acquired"], 0)
        self.assertFalse(self.registry["runtime_ready"])
        self.assertIn("no battle/terrain", " ".join(self.registry["limitations"]))
        self.assertIn("raw background atlases", " ".join(self.registry["limitations"]))
        self.assertTrue(all(self.tool.source_url(source).startswith("https://raw.githubusercontent.com/televenus/World-Flipper-Assets/6bf81da717f2ac073e630fd17aa819d1cdb0d815/battle/field/") for source in self.registry["sources"]))

    def test_ambiguous_bindings_and_overclaims_are_rejected(self) -> None:
        invalid = []
        value = deepcopy(self.registry); value["sources"].append(deepcopy(value["sources"][0])); invalid.append(value)
        value = deepcopy(self.registry); value["sources"][1]["fields"].append(value["sources"][0]["fields"][0]); invalid.append(value)
        value = deepcopy(self.registry); value["sources"][0]["path"] = "battle/field/wrong/background.png"; invalid.append(value)
        value = deepcopy(self.registry); value["missing_fields"][0]["background_ref"] = "wrong"; invalid.append(value)
        value = deepcopy(self.registry); value["coverage"]["final_jp_byte_identity_verified"] = True; invalid.append(value)
        value = deepcopy(self.registry); value["coverage"]["terrain_files_acquired"] = 132; invalid.append(value)
        value = deepcopy(self.registry); value["runtime_ready"] = True; invalid.append(value)
        value = deepcopy(self.registry); value["mirror"]["commit"] = "main"; invalid.append(value)
        for value in invalid:
            with self.subTest(change=value["scope"]), self.assertRaises(ValueError):
                self.tool.validate_registry(value, self.catalog)

    def test_exact_bytes_validate_git_blob_png_crc_pixels_size_and_mode(self) -> None:
        data, source = png_fixture()
        record = self.tool.validate_png(data, source)
        self.assertEqual(record["source_size"], [3, 7])
        self.assertEqual(record["sha256"], source["sha256"])
        self.assertEqual(record["git_blob_sha1"], source["git_blob_sha1"])
        self.assertEqual(record["mode"], "RGBA")
        for key, changed in (("sha256", "0" * 64), ("git_blob_sha1", "0" * 40), ("bytes", len(data) + 1), ("source_size", [7, 3]), ("mode", "RGB")):
            value = deepcopy(source); value[key] = changed
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.tool.validate_png(data, value)
        html = b"<html>not an image</html>"
        value = {**source, "bytes": len(html), "sha256": hashlib.sha256(html).hexdigest(),
                 "git_blob_sha1": hashlib.sha1(f"blob {len(html)}\0".encode("ascii") + html).hexdigest()}
        with self.assertRaises(ValueError):
            self.tool.validate_png(html, value)

    def test_cache_is_offline_and_cannot_escape_its_source_root(self) -> None:
        data, source = png_fixture()
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            with self.assertRaises(FileNotFoundError):
                self.tool.checked_source(source, cache, True)
            path = cache / source["path"]
            path.parent.mkdir(parents=True)
            path.write_bytes(data)
            self.assertEqual(self.tool.checked_source(source, cache, True)["sha256"], source["sha256"])
            path.write_bytes(data[:-1])
            with self.assertRaises(ValueError):
                self.tool.checked_source(source, cache, True)
            for value in ("../outside.png", "/battle/field/a.png", "battle/field/../../outside.png", "battle\\field\\a.png", "C:/battle/field/a.png", "battle/field/a/./b.png", "battle/field/a.png?query"):
                with self.subTest(path=value), self.assertRaises(ValueError):
                    self.tool.safe_source_path(value)

    def test_committed_pipeline_and_registry_are_lf_and_do_not_ship_raw_pngs(self) -> None:
        for relative in ("tools/world_flipper_backgrounds.py", "tools/world_flipper_background_sources.json", "tests/test_world_flipper_backgrounds.py"):
            value = (ROOT / relative).read_bytes()
            self.assertNotIn(b"\r", value)
            self.assertTrue(value.endswith(b"\n"))
        for source in self.registry["sources"]:
            self.assertFalse((ROOT / source["path"]).exists(), "The historical raw mirror must stay under the ignored cache")


if __name__ == "__main__":
    unittest.main()
