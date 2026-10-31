"""Benchmark provenance must be stable across checkout line endings and detect stale sources."""

from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("dash_benchmark_manifest", ROOT / "tools/build_dash_benchmark_manifest.py")
assert SPEC and SPEC.loader
TOOL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TOOL)


class DashBenchmarkManifestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for directory in (*TOOL.CODE_ROOTS, "assets"):
            (self.root / directory).mkdir()
        for relative in TOOL.FIXED_FILES:
            self.put(relative, b"original source\n")
        self.put("scripts/player.gd", "extends Node\n# 中文\n".encode())
        self.put("data/content.json", b'{"original": true}\n')
        self.put("scenes/main.tscn", b'[gd_scene format=3]\n')
        self.put("shaders/effect.gdshader", b'shader_type canvas_item;\n')
        self.put("assets/icon.svg", b'<svg/>\n')
        self.put("assets/icon.png", b"binary\r\n\x00\xff")

    def put(self, relative: str, data: bytes) -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def test_deterministic_bytes_and_sorted_composition(self) -> None:
        first = TOOL.build(self.root)
        self.assertEqual(TOOL.render(first), TOOL.render(TOOL.build(self.root)))
        self.assertEqual(first["schema_version"], 1)
        self.assertEqual(first["algorithm"], "sha256-utf8-lf-text-and-raw-binary")
        combined = "\n".join(path + ":" + digest for path, digest in sorted(first["files"].items()))
        self.assertEqual(first["source_hash"], hashlib.sha256(combined.encode()).hexdigest())
        self.assertNotIn(b"\r\n", TOOL.render(first))
        TOOL.write(self.root)
        self.assertIsNone(TOOL.check(self.root))

    def test_text_line_endings_have_the_same_fingerprint_without_rewriting_inputs(self) -> None:
        before = TOOL.build(self.root)
        for relative in TOOL.source_paths(self.root):
            path = self.root / relative
            if path.suffix in TOOL.TEXT_SUFFIXES:
                path.write_bytes(path.read_bytes().replace(b"\n", b"\r\n"))
        self.assertEqual(before, TOOL.build(self.root))
        self.assertIn(b"\r\n", (self.root / "scripts/player.gd").read_bytes())
        self.put("scripts/player.gd", (self.root / "scripts/player.gd").read_bytes().replace(b"\r\n", b"\r"))
        self.assertEqual(before, TOOL.build(self.root))

    def test_binary_bytes_are_not_line_normalized(self) -> None:
        before = TOOL.build(self.root)
        self.put("assets/icon.png", b"binary\n\x00\xff")
        after = TOOL.build(self.root)
        self.assertNotEqual(before["source_hash"], after["source_hash"])
        self.assertEqual(after["files"]["res://assets/icon.png"], hashlib.sha256(b"binary\n\x00\xff").hexdigest())

    def test_all_required_asset_and_code_suffixes_are_included_only_in_their_roots(self) -> None:
        for suffix in TOOL.ASSET_SUFFIXES:
            self.put("assets/fixture" + suffix, b"fixture")
        for suffix in TOOL.CODE_SUFFIXES:
            for directory in TOOL.CODE_ROOTS:
                self.put(directory + "/fixture" + suffix, b"fixture")
        for relative in ("assets/no.txt", "assets/icon.png.import", "scripts/no.py", "reports/no.json", "tests/no.gd", "assets/.godot/hidden.png", "assets/.import/hidden.png", "assets/.cache/hidden.json"):
            self.put(relative, b"must be excluded")
        files = TOOL.build(self.root)["files"]
        for suffix in TOOL.ASSET_SUFFIXES:
            self.assertIn("res://assets/fixture" + suffix, files)
        for suffix in TOOL.CODE_SUFFIXES:
            for directory in TOOL.CODE_ROOTS:
                self.assertIn("res://" + directory + "/fixture" + suffix, files)
        self.assertFalse(any("hidden" in path or "no." in path or path.endswith(".import") for path in files))

    def test_manifest_and_ledger_are_excluded_from_the_fingerprint(self) -> None:
        before = TOOL.build(self.root)
        self.put(TOOL.OUTPUT, b"changed generated manifest")
        self.put("data/worldflipper/implementation.json", b"changed ledger")
        after = TOOL.build(self.root)
        self.assertEqual(before, after)
        self.assertNotIn("res://" + TOOL.OUTPUT, after["files"])
        self.assertNotIn("res://data/worldflipper/implementation.json", after["files"])

    def test_modified_added_and_removed_sources_are_rejected_by_check(self) -> None:
        for action in ("modify", "add", "remove"):
            with self.subTest(action=action):
                original = (self.root / "scripts/player.gd").read_bytes()
                TOOL.write(self.root)
                if action == "modify":
                    self.put("scripts/player.gd", b"changed content\n")
                elif action == "add":
                    self.put("scripts/new.gd", b"new source\n")
                else:
                    (self.root / "scripts/player.gd").unlink()
                with self.assertRaises(ValueError):
                    TOOL.check(self.root)
                self.put("scripts/player.gd", original)
                (self.root / "scripts/new.gd").unlink(missing_ok=True)

    def test_manifest_tampering_and_crlf_output_are_rejected(self) -> None:
        path = TOOL.write(self.root)
        original = path.read_bytes()
        value = json.loads(original)
        value["files"]["res://scripts/player.gd"] = "0" * 64
        path.write_bytes(TOOL.render(value))
        with self.assertRaises(ValueError):
            TOOL.check(self.root)
        path.write_bytes(original.replace(b"\n", b"\r\n"))
        with self.assertRaises(ValueError):
            TOOL.check(self.root)

    def test_missing_required_or_invalid_utf8_source_does_not_replace_existing_manifest(self) -> None:
        path = TOOL.write(self.root)
        original = path.read_bytes()
        self.put("scripts/player.gd", b"\xffinvalid UTF8")
        with self.assertRaises(ValueError):
            TOOL.write(self.root)
        self.assertEqual(path.read_bytes(), original)
        self.put("scripts/player.gd", b"valid\n")
        (self.root / "tools/audio_skills.py").unlink()
        with self.assertRaises(ValueError):
            TOOL.write(self.root)
        self.assertEqual(path.read_bytes(), original)

    def test_unsafe_resource_paths_are_rejected(self) -> None:
        for path in ("", ".", "../private.gd", "/private.gd", "scripts/../private.gd", "scripts\\private.gd", "res://private.gd", "scripts//private.gd", "scripts/line\nbreak.gd", "scripts/line\rbreak.gd"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                TOOL._relative_uri(path)

    def test_check_cli_is_read_only_and_returns_failure_for_stale_sources(self) -> None:
        path = TOOL.write(self.root)
        original = path.read_bytes()
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(TOOL.main(["--root", str(self.root), "--check"]), 0)
            self.put("data/content.json", b'{"changed": true}\n')
            self.assertEqual(TOOL.main(["--root", str(self.root), "--check"]), 1)
        self.assertEqual(path.read_bytes(), original)


class CurrentDashBenchmarkManifestTests(unittest.TestCase):
    def test_current_tree_check_and_determinism(self) -> None:
        if not (ROOT / TOOL.OUTPUT).is_file():
            self.skipTest("Generate the real manifest only after the shared benchmark sources are frozen")
        first = TOOL.build(ROOT)
        self.assertEqual(TOOL.render(first), TOOL.render(TOOL.build(ROOT)))
        TOOL.check(ROOT)


if __name__ == "__main__":
    unittest.main()
