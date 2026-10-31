"""Build deterministic benchmark provenance without engine or network access."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import tempfile
from typing import Sequence, TypedDict

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = "assets/diagnostics/dash_benchmark_sources.json"
ALGORITHM = "sha256-utf8-lf-text-and-raw-binary"
FIXED_FILES = (
    "project.godot", "export_presets.cfg", "tools/benchmark_dash.gd",
    "tools/build_dash_benchmark_manifest.py", "tools/audio_skills.py", "tools/generate_assets.py",
)
CODE_ROOTS = ("scripts", "data", "scenes", "shaders")
CODE_SUFFIXES = frozenset({".gd", ".tscn", ".tres", ".json", ".gdshader"})
ASSET_SUFFIXES = frozenset({".png", ".svg", ".json", ".wav", ".ogg", ".ttf", ".otf", ".gif"})
TEXT_SUFFIXES = frozenset({".gd", ".json", ".tres", ".godot", ".py", ".sh", ".ps1", ".gdshader", ".tscn", ".svg", ".cfg"})
EXCLUDED = frozenset({OUTPUT, "data/worldflipper/implementation.json"})
CACHE_DIRECTORIES = frozenset({".godot", ".import", ".cache", ".tools", ".git", "__pycache__", "node_modules"})
SHA256 = re.compile(r"[0-9a-f]{64}")


class Manifest(TypedDict):
    schema_version: int
    algorithm: str
    files: dict[str, str]
    source_hash: str


def _relative_uri(relative: str) -> str:
    if not relative or any(character in relative for character in ("\\", ":", "\x00", "\r", "\n")):
        raise ValueError("Unsafe resource path: " + relative)
    path = PurePosixPath(relative)
    if not path.parts or path.is_absolute() or path.as_posix() != relative or any(part in ("", ".", "..") for part in path.parts):
        raise ValueError("Unsafe resource path: " + relative)
    return "res://" + relative


def _file(root: Path, relative: str) -> Path:
    _relative_uri(relative)
    path = root / relative
    if not path.is_file() or path.is_symlink():
        raise ValueError("Missing or linked benchmark input: " + relative)
    if not path.resolve(strict=True).is_relative_to(root):
        raise ValueError("Benchmark input escapes its root: " + relative)
    return path


def _walk(root: Path, directory: str, suffixes: frozenset[str]) -> set[str]:
    base = root / directory
    if not base.is_dir() or base.is_symlink() or not base.resolve(strict=True).is_relative_to(root):
        raise ValueError("Missing or linked source directory: " + directory)
    result: set[str] = set()
    for parent, directories, filenames in os.walk(base, followlinks=False):
        directories[:] = sorted(name for name in directories if name.casefold() not in CACHE_DIRECTORIES)
        for name in directories:
            if (Path(parent) / name).is_symlink():
                raise ValueError("Linked benchmark source directory: " + str(Path(parent) / name))
        for name in filenames:
            path = Path(parent) / name
            if path.suffix.casefold() in suffixes:
                relative = path.relative_to(root).as_posix()
                if relative.casefold() not in EXCLUDED:
                    _file(root, relative)
                    result.add(relative)
    return result


def source_paths(root: Path) -> tuple[str, ...]:
    root = root.resolve(strict=True)
    if not root.is_dir():
        raise ValueError("Benchmark root must be a directory")
    paths = set(FIXED_FILES)
    for directory in CODE_ROOTS:
        paths.update(_walk(root, directory, CODE_SUFFIXES))
    paths.update(_walk(root, "assets", ASSET_SUFFIXES))
    paths.difference_update(EXCLUDED)
    if len({path.casefold() for path in paths}) != len(paths):
        raise ValueError("Case-colliding benchmark resource paths")
    for path in paths:
        _file(root, path)
    return tuple(sorted(paths))


def content_bytes(path: Path) -> bytes:
    data = path.read_bytes()
    if path.suffix.casefold() in TEXT_SUFFIXES:
        try:
            return data.decode("utf-8").replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
        except UnicodeDecodeError as error:
            raise ValueError("Benchmark text is not UTF-8: " + str(path)) from error
    return data


def build(root: Path = ROOT) -> Manifest:
    """Return current source fingerprints; never write or normalize source files."""
    root = Path(root).resolve(strict=True)
    paths = source_paths(root)
    files = {_relative_uri(relative): hashlib.sha256(content_bytes(_file(root, relative))).hexdigest() for relative in paths}
    if paths != source_paths(root):
        raise ValueError("Benchmark input set changed while hashing")
    if not files or not all(SHA256.fullmatch(digest) for digest in files.values()):
        raise ValueError("Every benchmark resource needs a nonempty SHA256")
    combined = "\n".join(path + ":" + files[path] for path in sorted(files))
    return {"schema_version": 1, "algorithm": ALGORITHM, "files": files,
            "source_hash": hashlib.sha256(combined.encode("utf-8")).hexdigest()}


def render(value: Manifest) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def write(root: Path = ROOT) -> Path:
    """Validate all inputs before atomically replacing an existing manifest."""
    root = Path(root).resolve(strict=True)
    data = render(build(root))
    destination = root / OUTPUT
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink() or not destination.parent.resolve(strict=True).is_relative_to(root):
        raise ValueError("Benchmark manifest destination escapes its root")
    temporary: str | None = None
    try:
        with tempfile.NamedTemporaryFile(prefix=".dash-sources-", suffix=".tmp", dir=destination.parent, delete=False) as stream:
            temporary = stream.name
            stream.write(data)
        os.replace(temporary, destination)
        temporary = None
    finally:
        if temporary is not None:
            Path(temporary).unlink(missing_ok=True)
    return destination


def check(root: Path = ROOT) -> None:
    root = Path(root).resolve(strict=True)
    expected = render(build(root))
    destination = _file(root, OUTPUT)
    if destination.read_bytes() != expected:
        raise ValueError("Benchmark source manifest is stale or modified; rebuild before exporting")


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Require exact current manifest bytes without writing")
    parser.add_argument("--root", type=Path, default=ROOT, help="Project root; defaults to this tool's repository")
    args = parser.parse_args(argv)
    try:
        if args.check:
            check(args.root)
            print("Dash benchmark source manifest matches current canonical inputs")
        else:
            path = write(args.root)
            print("Wrote " + str(path))
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
