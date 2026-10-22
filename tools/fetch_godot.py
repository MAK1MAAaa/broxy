#!/usr/bin/env python3
"""Fetch and verify the pinned official standard macOS editor into .tools/."""
import concurrent.futures
import hashlib
import pathlib
import re
import shutil
import subprocess
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
VERSION = "4.7.2-stable"
NAME = "Godot_v%s_macos.universal.zip" % VERSION
URL = "https://github.com/godotengine/godot/releases/download/%s/%s" % (VERSION, NAME)
SIZE = 170622178
PARTS = ROOT / ".tools" / "engine-parts"
PARTS.mkdir(parents=True, exist_ok=True)


def fetch(index):
    start = SIZE * index // 10
    end = SIZE * (index + 1) // 10 - 1
    destination = PARTS / ("%02d.part" % index)
    if destination.exists() and destination.stat().st_size == end - start + 1:
        return destination
    headers = PARTS / ("%02d.headers" % index)
    subprocess.run([
        "curl", "-L", "--fail", "--silent", "--show-error", "--retry", "3",
        "--connect-timeout", "20", "--range", "%d-%d" % (start, end),
        "-D", str(headers), URL + "?broxy_part=%d" % index, "-o", str(destination),
    ], check=True)
    ranges = re.findall(r"content-range:\s*bytes\s+(\d+)-(\d+)/(\d+)", headers.read_text(), re.I)
    if not ranges or tuple(map(int, ranges[-1])) != (start, end, SIZE):
        raise RuntimeError("Server returned an unexpected byte range for part %d" % index)
    if destination.stat().st_size != end - start + 1:
        raise RuntimeError("Truncated range %d" % index)
    print("Editor part %d/10 complete" % (index + 1), flush=True)
    return destination


def main():
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
        parts = list(pool.map(fetch, range(10)))
    archive = ROOT / ".tools" / "godot-verified.zip"
    with archive.open("wb") as output:
        for part in parts:
            with part.open("rb") as source:
                shutil.copyfileobj(source, output)
    sums_path = ROOT / ".tools" / "SHA512-SUMS.txt"
    if not sums_path.exists():
        subprocess.run(["curl", "-L", "--fail", "--silent", "--show-error", URL.rsplit("/", 1)[0] + "/SHA512-SUMS.txt", "-o", str(sums_path)], check=True)
    expected = next(line.split()[0] for line in sums_path.read_text().splitlines() if line.split()[-1] == NAME)
    actual = hashlib.sha512(archive.read_bytes()).hexdigest()
    if actual != expected:
        raise RuntimeError("Official SHA-512 checksum mismatch")
    target = ROOT / ".tools" / "godot"
    target.mkdir(exist_ok=True)
    subprocess.run(["ditto", "-x", "-k", str(archive), str(target)], check=True)
    print("Verified official editor: %s" % (target / "Godot.app"), flush=True)


if __name__ == "__main__":
    main()
