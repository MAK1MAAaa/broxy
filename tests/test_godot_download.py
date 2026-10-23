"""Verify release downloads against real local HTTP range responses and bad archives."""
from __future__ import annotations

import contextlib
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
from pathlib import Path
import re
import struct
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import godot_download as download


class DownloadTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.payload = bytes(range(256)) * 40
        self.requests = 0
        self.bad_range = False
        self.truncated = False
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, format: str, *args: object) -> None:
                pass

            def do_GET(self) -> None:
                owner.requests += 1
                match = re.fullmatch(r"bytes=(\d+)-(\d+)", self.headers.get("Range", ""))
                if match is None:
                    self.send_error(400)
                    return
                start, end = map(int, match.groups())
                body = owner.payload[start:end + 1]
                self.send_response(206)
                range_start = start + 1 if owner.bad_range else start
                self.send_header("Content-Range", f"bytes {range_start}-{end}/{len(owner.payload)}")
                self.end_headers()
                self.wfile.write(body[:-1] if owner.truncated else body)

            def do_HEAD(self) -> None:
                self.send_response(200)
                self.send_header("Content-Length", str(len(owner.payload)))
                self.end_headers()

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self.stop_server)
        self.asset = download.ReleaseAsset("test.zip", len(self.payload), hashlib.sha512(self.payload).hexdigest())
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(download, "ROOT", self.root))
        self.stack.enter_context(patch.object(download, "RELEASE_URL", f"http://127.0.0.1:{self.server.server_port}"))
        self.stack.enter_context(patch.object(download, "CHUNK_SIZE", 4096))
        self.stack.enter_context(patch.object(download.time, "sleep"))
        self.stack.enter_context(contextlib.redirect_stdout(io.StringIO()))

    def stop_server(self) -> None:
        self.server.shutdown()
        self.server.server_close()

    def test_download_and_verified_offline_cache(self) -> None:
        archive = download.fetch_archive(self.asset, workers=3)
        self.assertEqual(archive.read_bytes(), self.payload)
        self.assertEqual(self.requests, 3)
        self.assertEqual(download.fetch_archive(self.asset), archive)
        self.assertEqual(self.requests, 3)

    def test_corrupt_cached_part_is_replaced(self) -> None:
        archive = download.fetch_archive(self.asset)
        archive.unlink()
        part = next((archive.parent / "test.zip.parts").glob("*.part"))
        part.write_bytes(b"x" * part.stat().st_size)
        self.assertEqual(download.fetch_archive(self.asset).read_bytes(), self.payload)
        self.assertEqual(self.requests, 4)

    def test_wrong_http_range_is_rejected(self) -> None:
        self.bad_range = True
        with self.assertRaisesRegex(RuntimeError, "Content-Range"):
            download.fetch_archive(self.asset, workers=1)
        self.assertFalse((self.root / ".tools/downloads/test.zip").exists())

    def test_truncated_http_response_is_rejected(self) -> None:
        self.truncated = True
        with self.assertRaisesRegex(RuntimeError, "Truncated"):
            download.fetch_archive(self.asset, workers=1)

    def test_official_checksum_failure_discards_untrusted_cache(self) -> None:
        invalid = download.ReleaseAsset(self.asset.name, self.asset.size, "0" * 128)
        with self.assertRaisesRegex(RuntimeError, "Official SHA-512 mismatch"):
            download.fetch_archive(invalid)
        self.assertEqual(list((self.root / ".tools/downloads/test.zip.parts").glob("*.part")), [])
        self.assertFalse((self.root / ".tools/downloads/test.zip").exists())

    def test_zip_crc_failure_preserves_previous_output(self) -> None:
        archive_path = self.root / "corrupted.zip"
        with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_STORED) as archive:
            archive.writestr("template.exe", b"original payload")
        archive_path.write_bytes(archive_path.read_bytes().replace(b"original payload", b"modified payload"))
        output = self.root / "template.exe"
        output.write_bytes(b"previous verified output")
        with self.assertRaises(zipfile.BadZipFile):
            download.extract_member(archive_path, "template.exe", output)
        self.assertEqual(output.read_bytes(), b"previous verified output")
        self.assertFalse(output.with_suffix(".exe.extracting").exists())

    def test_windows_binary_architecture_validation(self) -> None:
        executable = self.root / "test.exe"
        binary = bytearray(72)
        binary[:2] = b"MZ"
        struct.pack_into("<I", binary, 60, 64)
        binary[64:70] = b"PE\0\0\x64\x86"
        executable.write_bytes(binary)
        download.validate_windows_x86_64(executable)
        binary[68:70] = b"\x4c\x01"
        executable.write_bytes(binary)
        with self.assertRaisesRegex(RuntimeError, "x86_64"):
            download.validate_windows_x86_64(executable)

    def test_unchanged_executable_does_not_require_replacement(self) -> None:
        archive_path = self.root / "editor.zip"
        with zipfile.ZipFile(archive_path, "w") as archive:
            archive.writestr("editor.exe", b"verified editor")
        output = self.root / "editor.exe"
        output.write_bytes(b"verified editor")
        with patch.object(Path, "replace", side_effect=PermissionError("running executable")):
            download.extract_member(archive_path, "editor.exe", output)
        self.assertEqual(output.read_bytes(), b"verified editor")


if __name__ == "__main__":
    unittest.main()
