#!/usr/bin/env python3
"""Download pinned official Godot archives using resumable checked HTTP ranges."""
from __future__ import annotations

import hashlib
import json
import re
import shutil
import struct
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = "4.7.2-stable"
RELEASE_URL = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}"
CHECKSUM_URL = f"{RELEASE_URL}/SHA512-SUMS.txt"
CHUNK_SIZE = 16 * 1024 * 1024


@dataclass(frozen=True)
class ReleaseAsset:
    name: str
    size: int
    sha512: str

    @property
    def url(self) -> str:
        return f"{RELEASE_URL}/{self.name}"


# SHA-512 values from the official release's SHA512-SUMS.txt, pinned with the version.
WINDOWS_EDITOR = ReleaseAsset(
    f"Godot_v{VERSION}_win64.exe.zip", 86_013_866,
    "83decd58fdf67b9d657958a1ae6bf1929c20785315a81effe245874cdc57acb709"
    "bf868e00778a96984338c1b29dafdb453c6847747694621c6ecf5da2259993",
)
MACOS_EDITOR = ReleaseAsset(
    f"Godot_v{VERSION}_macos.universal.zip", 170_622_178,
    "38aa16e5bba2083941fc5b3e54be0089bd4cc35e32415f5b9fd9a8a6a7b9818255"
    "d44532ea8ef94b5aef56c4b407c2d634fa4f657e4ebe681ebbf59b7bac69ca",
)
EXPORT_TEMPLATES = ReleaseAsset(
    f"Godot_v{VERSION}_export_templates.tpz", 1_281_349_702,
    "ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f"
    "40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079",
)


def sha512_file(path: Path) -> str:
    digest = hashlib.sha512()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_archive(path: Path, asset: ReleaseAsset) -> bool:
    return path.is_file() and path.stat().st_size == asset.size and sha512_file(path) == asset.sha512


def _resolve_download_url(asset: ReleaseAsset) -> str:
    request = urllib.request.Request(asset.url, method="HEAD", headers={"User-Agent": "broxy-godot-fetch/1"})
    with urllib.request.urlopen(request, timeout=90) as response:
        return response.url


def _fetch_part(asset: ReleaseAsset, download_url: str, start: int, end: int, cache: Path) -> Path:
    destination = cache / f"{start}-{end}.part"
    checksum = destination.with_suffix(".sha512")
    expected = end - start + 1
    if destination.is_file() and destination.stat().st_size == expected and checksum.is_file():
        if sha512_file(destination) == checksum.read_text(encoding="ascii").strip():
            return destination
    temporary = destination.with_suffix(".download")
    for attempt in range(3):
        separator = "&" if urllib.parse.urlsplit(download_url).query else "?"
        request = urllib.request.Request(
            f"{download_url}{separator}broxy_range={start}-{end}&attempt={attempt}",
            headers={"Range": f"bytes={start}-{end}", "User-Agent": "broxy-godot-fetch/1"},
        )
        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                content_range = re.fullmatch(r"bytes (\d+)-(\d+)/(\d+)", response.headers.get("Content-Range", ""))
                if response.status != 206 or content_range is None:
                    raise RuntimeError("Server did not honor the requested HTTP byte range")
                if tuple(map(int, content_range.groups())) != (start, end, asset.size):
                    raise RuntimeError("Server returned an unexpected HTTP Content-Range")
                size = 0
                with temporary.open("wb") as target:
                    while chunk := response.read(1024 * 1024):
                        size += len(chunk)
                        if size > expected:
                            raise RuntimeError("HTTP range response exceeds the requested size")
                        target.write(chunk)
                if size != expected:
                    raise RuntimeError("Truncated HTTP range response")
            temporary.replace(destination)
            checksum.write_text(sha512_file(destination) + "\n", encoding="ascii")
            return destination
        except (OSError, urllib.error.URLError, RuntimeError) as error:
            if attempt == 2:
                raise RuntimeError(f"Failed downloading {asset.name} bytes {start}-{end}: {error}") from error
            time.sleep(attempt + 1)
    raise AssertionError("Unreachable")


def fetch_archive(asset: ReleaseAsset, workers: int = 8) -> Path:
    if workers < 1:
        raise ValueError("workers must be positive")
    downloads = ROOT / ".tools" / "downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    archive = downloads / asset.name
    if verify_archive(archive, asset):
        print(f"Verified cached official archive: {archive}", flush=True)
        return archive
    cache = downloads / f"{asset.name}.parts"
    cache.mkdir(exist_ok=True)
    # Resolve the signed release-assets URL once, avoiding GitHub's redirect rate limit.
    download_url = _resolve_download_url(asset)
    ranges = [(start, min(start + CHUNK_SIZE, asset.size) - 1) for start in range(0, asset.size, CHUNK_SIZE)]
    chunks: dict[int, Path] = {}
    with ThreadPoolExecutor(max_workers=workers) as pool:
        pending = {pool.submit(_fetch_part, asset, download_url, start, end, cache): start for start, end in ranges}
        for future in as_completed(pending):
            chunks[pending[future]] = future.result()
            print(f"{asset.name}: {len(chunks)}/{len(ranges)} parts ready", flush=True)
    temporary = archive.with_suffix(archive.suffix + ".download")
    with temporary.open("wb") as target:
        for start in sorted(chunks):
            with chunks[start].open("rb") as source:
                shutil.copyfileobj(source, target)
    if not verify_archive(temporary, asset):
        # Discard only these generated cached ranges so a retry cannot reuse bad data.
        for part in chunks.values():
            part.unlink(missing_ok=True)
            part.with_suffix(".sha512").unlink(missing_ok=True)
        temporary.unlink(missing_ok=True)
        raise RuntimeError(f"Official SHA-512 mismatch for {asset.name}; cached parts discarded")
    temporary.replace(archive)
    metadata = {"version": VERSION, "source": asset.url, "checksum_source": CHECKSUM_URL,
                "size": asset.size, "sha512": asset.sha512,
                "validation": ["HTTP Content-Range and length", "complete archive official SHA-512"]}
    archive.with_suffix(archive.suffix + ".source.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(f"Official SHA-512 passed: {archive}", flush=True)
    return archive


def extract_member(archive_path: Path, member: str, output: Path) -> None:
    """Write a single named ZIP member with CRC verification and an atomic replace."""
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".extracting")
    try:
        with zipfile.ZipFile(archive_path) as archive:
            with archive.open(member) as source, temporary.open("wb") as target:
                shutil.copyfileobj(source, target)
        if output.is_file() and output.stat().st_size == temporary.stat().st_size:
            if sha512_file(output) == sha512_file(temporary):
                # Windows locks running executables; identical verified outputs need no replacement.
                return
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)


def validate_windows_x86_64(path: Path) -> None:
    with path.open("rb") as source:
        header = source.read(64)
        if len(header) < 64 or header[:2] != b"MZ":
            raise RuntimeError(f"Missing DOS executable header: {path}")
        source.seek(struct.unpack_from("<I", header, 60)[0])
        if source.read(6) != b"PE\0\0\x64\x86":
            raise RuntimeError(f"Expected a Windows x86_64 PE executable: {path}")
