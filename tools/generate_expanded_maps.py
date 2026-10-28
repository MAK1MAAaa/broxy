#!/usr/bin/env python3
"""Author continuous pixel arenas in world coordinates without resizing legacy art."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import random
from typing import Any
from xml.etree import ElementTree

from starfall_environment import BUSH, CRYSTAL, PALETTES, Palette

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "assets/starfall/maps/expanded"
ARENA = (-1082, -535, 3444, 1800)
ORIGIN = (-1146, -679)
SIZE = (3780, 2104)
PIXEL = 4
ART_MARGINS = (64, 144, 272, 160)
WALKABLE = (ART_MARGINS[0], ART_MARGINS[1], SIZE[0] - ART_MARGINS[2], SIZE[1] - ART_MARGINS[3])
IDS = ("reliquary", "mire", "glacier", "ashland")


class Canvas:
    def __init__(self) -> None:
        self.parts: list[str] = []

    def rect(self, x: int, y: int, width: int, height: int, color: str) -> None:
        if width <= 0 or height <= 0:
            return
        if min(x, y) < 0 or x + width > SIZE[0] or y + height > SIZE[1]:
            raise ValueError(f"Pixel mark leaves expanded canvas: {(x, y, width, height)}")
        if any(value % PIXEL for value in (x, y, width, height)):
            raise ValueError(f"Pixel mark leaves the four-pixel grid: {(x, y, width, height)}")
        self.parts.append(f'<rect x="{x}" y="{y}" width="{width}" height="{height}" fill="{color}"/>')

    def cluster(self, x: int, y: int, rows: tuple[str, ...], colors: dict[str, str], kind: str) -> None:
        width, height = max(map(len, rows)) * PIXEL, len(rows) * PIXEL
        walkable = WALKABLE
        if x < walkable[2] and x + width > walkable[0] and y < walkable[3] and y + height > walkable[1]:
            raise ValueError(f"Upright ornament enters the walkable arena: {kind}")
        self.parts.append(f'<g data-role="rim-decoration" data-kind="{kind}" data-bounds="{x},{y},{width},{height}">')
        for row_index, row in enumerate(rows):
            start = 0
            while start < len(row):
                symbol = row[start]
                end = start + 1
                while end < len(row) and row[end] == symbol:
                    end += 1
                if symbol in colors:
                    self.rect(x + start * PIXEL, y + row_index * PIXEL, (end - start) * PIXEL, PIXEL, colors[symbol])
                start = end
        self.parts.append("</g>")

    def encode(self) -> bytes:
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE[0]}" height="{SIZE[1]}" '
                f'viewBox="0 0 {SIZE[0]} {SIZE[1]}" shape-rendering="crispEdges">\n'
                + "\n".join(self.parts) + "\n</svg>\n").encode("utf-8")


def _snap(value: float) -> int:
    return int(value // PIXEL) * PIXEL


def _floor(canvas: Canvas, palette: Palette, rng: random.Random) -> None:
    left, top, right, bottom = WALKABLE
    base, tile, alternate, seam, light = palette.floor
    canvas.rect(0, 0, *SIZE, palette.backdrop)
    canvas.rect(left, top, right - left, bottom - top, base)
    center_x, center_y = (left + right) // 2, (top + bottom) // 2
    for row, y in enumerate(range(top, bottom, 40)):
        for x in range(left - (40 if row % 2 else 0), right, 80):
            start, end = max(left, x), min(right, x + 76)
            height = min(36, bottom - y)
            if end <= start:
                continue
            crossing = abs((start + end) * 0.5 - center_x) < 92 or abs(y + 18 - center_y) < 84
            color = tile if crossing or rng.randrange(3) else alternate
            canvas.rect(start, y, end - start, height, color)
            if end - start >= 28 and rng.randrange(4) == 0:
                canvas.rect(start + 8, y, 20, 4, light)
            if height >= 28 and rng.randrange(5) == 0:
                canvas.rect(end - 8, y + 24, 4, 4, seam)
    for _ in range(820):
        x, y = rng.randrange(left // 4 + 2, right // 4 - 6) * 4, rng.randrange(top // 4 + 2, bottom // 4 - 3) * 4
        color = rng.choice((base, alternate, seam))
        canvas.rect(x, y, rng.choice((4, 8, 12)), 4, color)
        if rng.randrange(4) == 0:
            canvas.rect(x + 4, y - 4, 4, 4, color)
    for _ in range(110):
        x, y = rng.randrange(left // 4 + 4, right // 4 - 8) * 4, rng.randrange(top // 4 + 4, bottom // 4 - 5) * 4
        canvas.rect(x, y, 16, 4, seam)
        canvas.rect(x + 16, y - 4, 4, 4, seam)


def _floor_inlay(canvas: Canvas, palette: Palette, world: tuple[int, int], direction: str, kind: str) -> None:
    cx, cy = _snap(world[0] - ORIGIN[0]), _snap(world[1] - ORIGIN[1])
    quiet, light, middle = palette.floor[0], palette.floor[4], palette.floor[2]
    canvas.parts.append(f'<g data-role="floor-inlay" data-direction="{direction}" data-world-center="{world[0]},{world[1]}">')
    for dx, dy, width, height in ((-64, -48, 128, 8), (-64, 40, 128, 8), (-72, -40, 8, 80), (64, -40, 8, 80)):
        canvas.rect(cx + dx, cy + dy, width, height, quiet)
    for dx, dy, width, height in ((-40, -24, 80, 48), (-24, -40, 48, 80)):
        canvas.rect(cx + dx, cy + dy, width, height, middle)
    if kind == "glacier":
        marks = ((-4, -32, 8, 64), (-32, -4, 64, 8), (-24, -24, 8, 8), (16, 16, 8, 8), (-24, 16, 8, 8), (16, -24, 8, 8))
    elif kind == "ashland":
        marks = ((-32, -16, 24, 4), (-8, -12, 16, 4), (8, -8, 24, 4), (-32, 4, 24, 4), (-8, 8, 16, 4), (8, 12, 24, 4))
    elif kind == "mire":
        marks = ((-4, -28, 8, 56), (-28, -12, 24, 8), (4, 4, 24, 8), (-20, -20, 16, 8), (4, 12, 16, 8))
    else:
        marks = ((-4, -32, 8, 64), (-32, -4, 64, 8), (-12, -12, 24, 24))
    for dx, dy, width, height in marks:
        canvas.rect(cx + dx, cy + dy, width, height, light)
    canvas.rect(cx - 4, cy - 4, 8, 8, quiet)
    canvas.parts.append("</g>")


def _terrain(canvas: Canvas, palette: Palette, definition: dict[str, Any], rng: random.Random) -> None:
    fill, edge, detail = palette.terrain
    for index, zone in enumerate(definition["zones"]):
        world_x, world_y = zone["center"]
        rx, ry = zone["radius"]
        cx, cy = world_x - ORIGIN[0], world_y - ORIGIN[1]
        left, top, right, bottom = WALKABLE
        if not (left <= cx - rx < cx + rx <= right and top <= cy - ry < cy + ry <= bottom):
            raise ValueError(f"Terrain leaves the expanded walkable arena: {definition['id']} #{index}")
        canvas.parts.append(f'<ellipse data-role="slow-terrain" data-index="{index}" '
                            f'cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{fill}" stroke="{edge}" stroke-width="2"/>')
        for _ in range(90):
            x, y = _snap(rng.uniform(cx - rx + 12, cx + rx - 20)), _snap(rng.uniform(cy - ry + 8, cy + ry - 12))
            width = rng.choice((8, 12, 16))
            corners = ((px, py) for px in (x, x + width + 4) for py in (y - 4, y + 8))
            if not all(((px - cx) / max(1, rx - 4)) ** 2 + ((py - cy) / max(1, ry - 4)) ** 2 < 1 for px, py in corners):
                continue
            canvas.rect(x, y, width, 4, detail if rng.randrange(3) else fill)
            if definition["id"] == "glacier":
                canvas.rect(x + width, y + 4, 4, 4, detail)


def _rim(canvas: Canvas, palette: Palette, kind: str) -> None:
    left, top, right, bottom = WALKABLE
    dark, middle, light = palette.rim
    canvas.rect(left - 12, top - 12, right - left + 24, 12, dark)
    canvas.rect(left - 12, bottom, right - left + 24, 12, dark)
    canvas.rect(left - 12, top, 12, bottom - top, dark)
    canvas.rect(right, top, 12, bottom - top, dark)
    canvas.rect(left - 4, top - 4, right - left + 8, 4, light)
    canvas.rect(left - 4, bottom, right - left + 8, 4, light)
    canvas.rect(left - 4, top, 4, bottom - top, middle)
    canvas.rect(right, top, 4, bottom - top, light)
    for x in range(left + 12, right - 12, 48):
        canvas.rect(x, top - 12, 4, 8, middle)
        canvas.rect(x + 8, bottom + 4, 4, 8, middle)
    for y in range(top + 12, bottom - 12, 44):
        canvas.rect(left - 12, y, 8, 4, middle)
        canvas.rect(right + 4, y + 8, 8, 4, middle)
    foliage = dict(zip(("d", "l", "h"), palette.foliage))
    crystal = {**foliage, "u": palette.accent}
    rows, colors, ornament = (CRYSTAL, crystal, "ice-cluster") if kind == "glacier" else (BUSH, foliage, "courtyard-canopy")
    if rows is CRYSTAL:
        # The sixteen-row crystal remains entirely outside the legal play area.
        rows = rows[:12]
    ornament_width, ornament_height = max(map(len, rows)) * 4, len(rows) * 4
    for x in range(128, right - 64, 240):
        canvas.cluster(x, 8, rows, colors, ornament)
        canvas.cluster(x, top - ornament_height - 16, rows, colors, ornament)
        canvas.cluster(x, bottom + 16, rows, colors, ornament)
        canvas.cluster(x, SIZE[1] - ornament_height - 8, rows, colors, ornament)
    for y in range(top + 64, bottom - 64, 200):
        canvas.cluster(0, y, rows, colors, ornament)
        canvas.cluster(right + 16, y, rows, colors, ornament)
        canvas.cluster(SIZE[0] - ornament_width - 8, y, rows, colors, ornament)
    center_x, center_y = (left + right) // 2, (top + bottom) // 2
    for cx, cy, horizontal, direction in ((center_x, top - 32, True, "north"),
                                          (center_x, bottom + 32, True, "south"),
                                          (left - 32, center_y, False, "west"),
                                          (right + 32, center_y, False, "east")):
        cx, cy = _snap(cx), _snap(cy)
        canvas.parts.append(f'<g data-role="rim-landmark" data-direction="{direction}">')
        for shift in (-48, 32):
            x, y = (cx + shift, cy - 20) if horizontal else (cx - 20, cy + shift)
            canvas.rect(x, y, 32, 40, dark)
            canvas.rect(x + 4, y + 4, 24, 28, middle)
            canvas.rect(x + 8, y + 4, 16, 4, light)
            canvas.rect(x + 12, y + 12, 8, 8, palette.accent)
        canvas.parts.append("</g>")


def build_maps() -> list[tuple[str, bytes]]:
    definitions: list[dict[str, Any]] = json.loads((ROOT / "data/arenas.json").read_text(encoding="utf-8"))
    if tuple(definition["id"] for definition in definitions) != IDS:
        raise ValueError("Expanded maps require the four existing arena identities in catalog order")
    result: list[tuple[str, bytes]] = []
    for index, definition in enumerate(definitions):
        kind = str(definition["id"])
        palette = PALETTES[kind]
        rng = random.Random(0xE8A2D411 + index * 719)
        canvas = Canvas()
        _floor(canvas, palette, rng)
        for world, direction in (((-260, 365), "west"), ((1540, 365), "east"), ((640, -195), "north"), ((640, 925), "south")):
            _floor_inlay(canvas, palette, world, direction, kind)
        _terrain(canvas, palette, definition, rng)
        _rim(canvas, palette, kind)
        content = canvas.encode()
        ElementTree.fromstring(content)
        result.append((kind, content))
    return result


def main() -> None:
    DESTINATION.mkdir(parents=True, exist_ok=True)
    entries: list[dict[str, Any]] = []
    for kind, content in build_maps():
        path = DESTINATION / f"{kind}.svg"
        path.write_bytes(content)
        entries.append({"id": kind, "path": path.relative_to(ROOT).as_posix(), "size": list(SIZE),
                        "world_origin": list(ORIGIN), "walkable_bounds": list(ARENA),
                        "art_margins": list(ART_MARGINS), "pixel_grid": PIXEL,
                        "pivot": [0.0, 0.0], "source": "tools/generate_expanded_maps.py",
                        "palette_source": "tools/starfall_environment.py", "terrain_source": "data/arenas.json",
                        "license": "CC0-1.0", "sha256": hashlib.sha256(content).hexdigest()})
    manifest = {"schema_version": 1, "art_revision": "expanded-arena-01", "purpose": "Continuous world-scale maps for the existing game",
                "legacy_assets_preserved": True, "filter": "nearest", "assets": entries}
    (DESTINATION / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"Generated {len(entries)} continuous pixel maps at {SIZE[0]}x{SIZE[1]}; world origin={ORIGIN}; legacy maps untouched")


if __name__ == "__main__":
    main()
