#!/usr/bin/env python3
"""Extract only the macOS member from Godot's official remote template ZIP.

Uses checked HTTP ranges, eight parallel workers, ZIP metadata, and CRC checks.
Only Python's standard library and curl are required. No user Library is modified.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
import re
import struct
import subprocess
import time
from pathlib import Path
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
SOURCE = "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
SIZE = 1_281_349_702


class RemoteZip:
    def __init__(self, url: str, total: int, cache: Path) -> None:
        self.url = url
        self.total = total
        self.cache = cache
        self.cache.mkdir(parents=True, exist_ok=True)
        result = subprocess.run(["curl", "--head", "--fail", "--silent", "--show-error", "--max-time", "45", url], capture_output=True, check=True)
        locations = re.findall(r"(?im)^location:\s*(\S+)", result.stdout.decode())
        self.download_url = locations[-1].strip() if locations else url

    def read(self, start: int, end: int) -> bytes:
        if not 0 <= start <= end < self.total:
            raise ValueError(f"Invalid ZIP range {start}-{end}/{self.total}")
        data = self.cache / f"{start}-{end}.bin"
        headers = self.cache / f"{start}-{end}.headers"
        expected = end - start + 1
        pattern = re.compile(r"(?im)^content-range:\s*bytes\s+(\d+)-(\d+)/(\d+)\s*$")
        def valid() -> bool:
            if not data.exists() or not headers.exists() or data.stat().st_size != expected:
                return False
            matches = pattern.findall(headers.read_text())
            return bool(matches) and tuple(map(int, matches[-1])) == (start, end, self.total)
        if valid():
            return data.read_bytes()
        for attempt in range(3):
            separator = "&" if "?" in self.download_url else "?"
            # Unique per range avoids CDN caches serving a previous byte interval.
            url = f"{self.download_url}{separator}broxy_range={start}-{end}&attempt={attempt}"
            result = subprocess.run(["curl", "--location", "--fail", "--silent", "--show-error", "--connect-timeout", "20", "--max-time", "240", "--retry", "2", "--range", f"{start}-{end}", "--dump-header", str(headers), "--output", str(data), url], capture_output=True)
            if result.returncode == 0 and valid():
                return data.read_bytes()
            if attempt == 2:
                raise RuntimeError(f"Range {start}-{end} failed integrity/HTTP validation (curl {result.returncode}): {result.stderr.decode().strip()}")
            time.sleep(1)
        raise AssertionError("Unreachable")


def locate_member(remote: RemoteZip) -> dict:
    start = max(0, remote.total - 65_557)
    tail = remote.read(start, remote.total - 1)
    eocd = tail.rfind(b"PK\x05\x06")
    if eocd < 0:
        raise RuntimeError("ZIP end-of-central-directory not found")
    fields = struct.unpack_from("<4s4H2IH", tail, eocd)
    _, disk, cd_disk, disk_entries, entries, cd_size, cd_offset, comment_len = fields
    if disk or cd_disk or disk_entries != entries:
        raise RuntimeError("Multi-disk ZIP archives are unsupported")
    if cd_offset == 0xFFFFFFFF or cd_size == 0xFFFFFFFF:
        raise RuntimeError("This utility expects non-ZIP64 official templates")
    if eocd + 22 + comment_len != len(tail):
        raise RuntimeError("Invalid end-of-central-directory length")
    directory = remote.read(cd_offset, cd_offset + cd_size - 1)
    offset = 0
    for _ in range(entries):
        fields = struct.unpack_from("<4s6H3I5H2I", directory, offset)
        if fields[0] != b"PK\x01\x02":
            raise RuntimeError("Invalid central directory header")
        flags, compression = fields[3], fields[4]
        crc, compressed_size, uncompressed_size = fields[7:10]
        filename_len, extra_len, comment_len = fields[10:13]
        local_offset = fields[16]
        filename = directory[offset + 46:offset + 46 + filename_len].decode("utf-8" if flags & 0x800 else "cp437")
        if filename in {"macos.zip", "templates/macos.zip"}:
            if flags & 1:
                raise RuntimeError("Encrypted members are unsupported")
            return {"filename": filename, "compression": compression, "crc32": crc, "compressed_size": compressed_size, "uncompressed_size": uncompressed_size, "local_offset": local_offset}
        offset += 46 + filename_len + extra_len + comment_len
    raise RuntimeError("macos.zip is absent from the official template archive")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default=SOURCE)
    parser.add_argument("--size", type=int, default=SIZE)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--output", type=Path, default=ROOT / ".tools" / "macos.zip")
    args = parser.parse_args()
    if args.workers < 1:
        parser.error("--workers must be positive")
    remote = RemoteZip(args.url, args.size, ROOT / ".tools" / "template-ranges")
    member = locate_member(remote)
    print(f"Located {member['filename']}: {member['compressed_size'] / 1024**2:.1f} MiB compressed; {member['uncompressed_size'] / 1024**2:.1f} MiB output", flush=True)
    header = remote.read(member["local_offset"], member["local_offset"] + 29)
    fields = struct.unpack("<4s5H3I2H", header)
    if fields[0] != b"PK\x03\x04" or fields[3] != member["compression"]:
        raise RuntimeError("Local ZIP header does not match central directory")
    offset = member["local_offset"] + 30 + fields[9] + fields[10]
    total = member["compressed_size"]
    chunk_size = (total + args.workers - 1) // args.workers
    chunks: dict[int, bytes] = {}
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        pending = {pool.submit(remote.read, offset + i, offset + min(i + chunk_size, total) - 1): i for i in range(0, total, chunk_size)}
        for future in as_completed(pending):
            index = pending[future]
            chunks[index] = future.result()
            print(f"Downloaded part {len(chunks)}/{len(pending)} ({sum(map(len, chunks.values())) / 1024**2:.1f} MiB)", flush=True)
    compressed = b"".join(chunks[key] for key in sorted(chunks))
    if member["compression"] == 0:
        payload = compressed
    elif member["compression"] == 8:
        payload = zlib.decompress(compressed, -15)
    else:
        raise RuntimeError(f"Unsupported ZIP method: {member['compression']}")
    if len(payload) != member["uncompressed_size"] or zlib.crc32(payload) & 0xFFFFFFFF != member["crc32"]:
        raise RuntimeError("Extracted member size or CRC32 mismatch")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temp = args.output.with_suffix(".zip.part")
    temp.write_bytes(payload)
    with zipfile.ZipFile(temp) as archive:
        bad = archive.testzip()
        if bad:
            raise RuntimeError(f"Inner macos.zip CRC error in {bad}")
        members = archive.namelist()
        if not any("Contents/MacOS/" in name and not name.endswith("/") for name in members):
            raise RuntimeError("macos.zip lacks the expected Godot app executable")
    temp.replace(args.output)
    metadata = {"source": args.url, "archive_total_bytes": args.size, **member, "output": str(args.output.relative_to(ROOT)) if args.output.is_relative_to(ROOT) else str(args.output), "sha512": hashlib.sha512(payload).hexdigest(), "validation": ["checked HTTP Content-Range for every part", "outer ZIP member CRC32", "inner ZIP testzip"]}
    args.output.with_suffix(".source.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Verified {args.output} ({len(payload) / 1024**2:.1f} MiB); CRC32 and every inner ZIP member passed", flush=True)


if __name__ == "__main__":
    main()
