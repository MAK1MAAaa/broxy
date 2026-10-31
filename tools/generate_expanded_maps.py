#!/usr/bin/env python3
"""Author continuous pixel arenas in world coordinates without resizing legacy art."""
from __future__ import annotations

import hashlib
import json
import math
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
MATERIALS = {"reliquary": "worn-limestone", "mire": "mossy-wet-stone", "glacier": "frosted-slate", "ashland": "weathered-basalt"}

PILLAR = (
    "  dddddddddd  ", " dlllllllllld ", "ddhhhhhhhhhhdd", " dlllllllllld ",
    "  dllhhhh l d ", "  dlllhhllld  ", "  dlllhhllld  ", "  dlllhhllld  ",
    "  dlllhhllld  ", "  dlllhhllld  ", "  dlllhhllld  ", "  dlllhhllld  ",
    "  dlllhhllld  ", " dlllllllllld ", "ddhhhhhhhhhhdd", " dddddddddddd ")
BASALT = (
    "     ddddd    ", "   ddllllld   ", "  dllhhhhlld  ", " ddllhhhhhld  ",
    "dlllhhhlll l d", "dlllhhlllllld ", "dlllhhlllllld ", "dll lllllllld ",
    "dll lllllllld ", " dll lllllld  ", "  dll lllld   ", "   ddddddd    ")


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


def _mix(first: str, second: str, amount: float) -> str:
    a = tuple(int(first[index:index + 2], 16) for index in (1, 3, 5))
    b = tuple(int(second[index:index + 2], 16) for index in (1, 3, 5))
    return "#" + "".join(f"{round(x + (y - x) * amount):02x}" for x, y in zip(a, b))


def _floor(canvas: Canvas, palette: Palette, rng: random.Random, kind: str) -> None:
    left, top, right, bottom = WALKABLE
    base, tile, alternate, seam, light = palette.floor
    canvas.rect(0, 0, *SIZE, palette.backdrop)
    canvas.rect(left, top, right - left, bottom - top, _mix(base, seam, 0.35))
    center_x, center_y = (left + right) // 2, (top + bottom) // 2
    canvas.parts.append(f'<g data-role="floor-material" data-material="{MATERIALS[kind]}" data-flat="true">')
    row, y = 0, top
    while y < bottom:
        row_height = min((48, 64, 56, 48)[row % 4], bottom - y)
        x = left - (48 if row % 2 else 0)
        while x < right:
            width = rng.choice((96, 112, 144, 160))
            start, end = max(left, x), min(right, x + width - 4)
            height = row_height - 4
            if end > start and height > 0:
                crossing = abs((start + end) * 0.5 - center_x) < 104 or abs(y + height * 0.5 - center_y) < 84
                color = _mix(tile if crossing else rng.choice((tile, alternate, base)), base, 0.28)
                canvas.rect(start, y, end - start, height, color)
                if end - start > 40 and rng.randrange(3) == 0:
                    canvas.rect(start + 8, y, min(32, end - start - 16), 4, _mix(light, color, 0.58))
                if end - start > 32 and height >= 32 and rng.randrange(4) == 0:
                    canvas.rect(end - 20, y + height - 4, 12, 4, _mix(seam, color, 0.35))
                    canvas.rect(end - 8, y + height - 8, 4, 4, _mix(seam, color, 0.35))
            x += width
        y += row_height
        row += 1
    for _ in range(650):
        x, y = rng.randrange(left // 4 + 2, right // 4 - 6) * 4, rng.randrange(top // 4 + 2, bottom // 4 - 3) * 4
        color = _mix(rng.choice((base, alternate, seam)), tile, 0.40)
        canvas.rect(x, y, rng.choice((4, 8, 12)), 4, color)
        if rng.randrange(4) == 0:
            canvas.rect(x + 4, y - 4, 4, 4, color)
    for _ in range(105):
        x, y = rng.randrange(left // 4 + 4, right // 4 - 8) * 4, rng.randrange(top // 4 + 4, bottom // 4 - 5) * 4
        quiet = _mix(seam, base, 0.45)
        if kind == "mire":
            quiet = _mix(base, palette.foliage[1], 0.24)
            canvas.rect(x, y, 20, 4, quiet)
            canvas.rect(x + 4, y - 4, 12, 4, quiet)
            canvas.rect(x + 12, y + 4, 12, 4, _mix(quiet, light, 0.18))
        elif kind == "glacier":
            canvas.rect(x, y, 20, 4, _mix(base, light, 0.50))
            canvas.rect(x + 20, y + 4, 12, 4, _mix(base, light, 0.50))
            canvas.rect(x + 8, y - 4, 4, 4, _mix(base, seam, 0.55))
        elif kind == "ashland":
            canvas.rect(x, y, 16, 4, quiet)
            canvas.rect(x + 12, y - 4, 12, 4, quiet)
            canvas.rect(x + 24, y - 8, 8, 4, quiet)
            canvas.rect(x + 16, y + 4, 8, 4, _mix(base, light, 0.35))
        else:
            canvas.rect(x, y, 20, 4, quiet)
            canvas.rect(x + 20, y - 4, 4, 4, quiet)
            canvas.rect(x + 4, y + 4, 8, 4, _mix(light, base, 0.65))
    canvas.parts.append("</g>")


def _floor_inlay(canvas: Canvas, palette: Palette, world: tuple[int, int], direction: str, kind: str) -> None:
    cx, cy = _snap(world[0] - ORIGIN[0]), _snap(world[1] - ORIGIN[1])
    quiet = _mix(palette.floor[3], palette.floor[0], 0.48)
    light = _mix(palette.floor[4], palette.accent, 0.16)
    middle = _mix(palette.floor[0], palette.floor[2], 0.50)
    canvas.parts.append(f'<g data-role="floor-inlay" data-direction="{direction}" data-world-center="{world[0]},{world[1]}" data-flat="true" data-material="{MATERIALS[kind]}">')
    for dx, dy, width, height in ((-80, -72, 160, 4), (-80, 68, 160, 4), (-100, -52, 4, 104), (96, -52, 4, 104),
                                  (-96, -68, 16, 4), (80, -68, 16, 4), (-96, 64, 16, 4), (80, 64, 16, 4)):
        canvas.rect(cx + dx, cy + dy, width, height, quiet)
    for dx, dy, width, height in ((-68, -60, 136, 120), (-88, -40, 176, 80)):
        canvas.rect(cx + dx, cy + dy, width, height, middle)
    for offset in range(-48, 49, 24):
        canvas.rect(cx + offset, cy - 64, 12, 4, light)
        canvas.rect(cx + offset, cy + 60, 12, 4, quiet)
    for offset in (-84, 76):
        for dy in (-32, 24):
            canvas.rect(cx + offset, cy + dy, 8, 8, light)
    dim = _mix(quiet, middle, 0.5)
    if kind == "glacier":
        marks = ((-4, -44, 8, 88), (-48, -4, 96, 8), (-36, -28, 8, 8), (28, 20, 8, 8), (-36, 20, 8, 8), (28, -28, 8, 8),
                 (-16, -36, 12, 4), (4, -36, 12, 4), (-16, 32, 12, 4), (4, 32, 12, 4))
        for step in range(4):
            for sign in (-1, 1):
                canvas.rect(cx + sign * (12 + step * 8) - 4, cy - 12 - step * 8, 8, 8, light)
                canvas.rect(cx + sign * (12 + step * 8) - 4, cy + 4 + step * 8, 8, 8, light)
    elif kind == "ashland":
        marks = ((-4, -36, 8, 72), (-48, -4, 96, 8))
        for row in range(4):
            for column in range(6):
                x, y = cx - 48 + column * 16, cy - 32 + row * 16
                canvas.rect(x, y, 12, 12, quiet if (row + column) % 2 else dim)
                if (row + column) % 3 == 0:
                    canvas.rect(x, y, 8, 4, light)
    elif kind == "mire":
        marks = ((-4, -40, 8, 80), (-40, -20, 32, 8), (8, 12, 32, 8), (-32, -28, 24, 8), (8, 20, 24, 8),
                 (-24, 8, 16, 8), (8, -16, 16, 8))
        for sign in (-1, 1):
            for step in range(3):
                canvas.rect(cx + sign * (44 + step * 8) - 4, cy - 24 + step * 16, 8, 12, _mix(light, palette.terrain[0], 0.35))
    else:
        marks = ((-4, -44, 8, 88), (-48, -4, 96, 8), (-16, -16, 32, 32))
        for step in range(5):
            for sign in (-1, 1):
                canvas.rect(cx - 40 + step * 8, cy + sign * (40 - step * 8) - 4, 8, 8, light)
                canvas.rect(cx + step * 8, cy + sign * step * 8 - 4, 8, 8, light)
    for dx, dy, width, height in marks:
        canvas.rect(cx + dx, cy + dy, width, height, light)
    canvas.rect(cx - 8, cy - 8, 16, 16, quiet)
    canvas.rect(cx - 4, cy - 4, 8, 8, middle)
    canvas.parts.append("</g>")


def _terrain_mark(canvas: Canvas, center: tuple[float, float], radius: tuple[float, float],
                  x: int, y: int, width: int, height: int, color: str) -> bool:
    cx, cy = center
    rx, ry = radius
    corners = ((px, py) for px in (x, x + width) for py in (y, y + height))
    if not all(((px - cx) / max(1.0, rx - 4)) ** 2 + ((py - cy) / max(1.0, ry - 4)) ** 2 < 1.0 for px, py in corners):
        return False
    canvas.rect(x, y, width, height, color)
    return True


def _terrain(canvas: Canvas, palette: Palette, definition: dict[str, Any], rng: random.Random) -> None:
    fill, edge, detail = palette.terrain
    kind = str(definition["id"])
    for index, zone in enumerate(definition["zones"]):
        world_x, world_y = zone["center"]
        rx, ry = zone["radius"]
        cx, cy = world_x - ORIGIN[0], world_y - ORIGIN[1]
        left, top, right, bottom = WALKABLE
        if not (left <= cx - rx < cx + rx <= right and top <= cy - ry < cy + ry <= bottom):
            raise ValueError(f"Terrain leaves the expanded walkable arena: {definition['id']} #{index}")
        canvas.parts.append(f'<g data-role="terrain-material" data-material="{MATERIALS[kind]}" data-flat="true">')
        canvas.parts.append(f'<ellipse data-role="slow-terrain" data-index="{index}" '
                            f'cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{fill}" stroke="{edge}" stroke-width="2"/>')
        for y in range(_snap(cy - ry + 8), _snap(cy + ry - 8), 12):
            extent = rx * math.sqrt(max(0.0, 1.0 - ((y - cy) / ry) ** 2))
            for x in (_snap(cx - extent + 12), _snap(cx + extent - 20)):
                _terrain_mark(canvas, (cx, cy), (rx, ry), x, y, 8, 8, _mix(fill, edge, 0.25))
        for _ in range(48):
            x, y = _snap(rng.uniform(cx - rx + 12, cx + rx - 20)), _snap(rng.uniform(cy - ry + 8, cy + ry - 12))
            width = rng.choice((8, 12, 16))
            if not _terrain_mark(canvas, (cx, cy), (rx, ry), x, y, width, 4, _mix(detail, fill, 0.45)):
                continue
            if kind == "mire" and rng.randrange(3) == 0:
                _terrain_mark(canvas, (cx, cy), (rx, ry), x + 4, y - 4, 8, 4, _mix(fill, palette.foliage[1], 0.30))
                _terrain_mark(canvas, (cx, cy), (rx, ry), x + 4, y + 4, 12, 4, _mix(fill, palette.foliage[1], 0.22))
            elif kind == "glacier":
                direction = rng.choice((-1, 1))
                for step in range(rng.randrange(3, 7)):
                    _terrain_mark(canvas, (cx, cy), (rx, ry), x + step * 8, y + direction * step * 4, 12, 4, _mix(detail, fill, 0.33))
                    if step == 2:
                        _terrain_mark(canvas, (cx, cy), (rx, ry), x + 16, y + direction * 8 - direction * 4, 4, 8, _mix(edge, fill, 0.70))
            elif kind == "ashland":
                _terrain_mark(canvas, (cx, cy), (rx, ry), x + 4, y - 4, 8, 4, _mix(edge, fill, 0.62))
                _terrain_mark(canvas, (cx, cy), (rx, ry), x + 4, y + 4, 12, 4, _mix(detail, fill, 0.72))
        if kind == "mire":
            for _ in range(10):
                x, y = _snap(rng.uniform(cx - rx * 0.75, cx + rx * 0.75)), _snap(rng.uniform(cy - ry * 0.65, cy + ry * 0.65))
                _terrain_mark(canvas, (cx, cy), (rx, ry), x, y, 28, 4, _mix(detail, fill, 0.32))
                _terrain_mark(canvas, (cx, cy), (rx, ry), x + 8, y + 8, 16, 4, _mix(detail, fill, 0.65))
        canvas.parts.append("</g>")


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
    if kind == "reliquary":
        rows, colors, ornament = PILLAR, dict(zip(("d", "l", "h"), palette.rim)), "carved-courtyard-pillar"
    elif kind == "glacier":
        rows, colors, ornament = CRYSTAL, {**foliage, "u": palette.accent}, "frost-crystal"
    elif kind == "ashland":
        rows, colors, ornament = BASALT, foliage, "layered-basalt-outcrop"
    else:
        rows, colors, ornament = BUSH, foliage, "moss-canopy"
    ornament_width, ornament_height = max(map(len, rows)) * 4, len(rows) * 4
    for x in range(128, right - 64, 240):
        canvas.cluster(x, 8, rows, colors, ornament)
        canvas.cluster(x, top - ornament_height - 8, rows, colors, ornament)
        canvas.cluster(x, bottom + 16, rows, colors, ornament)
        canvas.cluster(x, SIZE[1] - ornament_height - 8, rows, colors, ornament)
    for y in range(top + 64, bottom - 64, 200):
        canvas.cluster(0, y, rows, colors, ornament)
        canvas.cluster(right + 16, y, rows, colors, ornament)
        canvas.cluster(SIZE[0] - ornament_width - 8, y, rows, colors, ornament)
    center_x, center_y = (left + right) // 2, (top + bottom) // 2
    for cx, cy, horizontal, direction in ((center_x, top - 40, True, "north"),
                                          (center_x, bottom + 40, True, "south"),
                                          (left - 32, center_y, False, "west"),
                                          (right + 32, center_y, False, "east")):
        cx, cy = _snap(cx), _snap(cy)
        canvas.parts.append(f'<g data-role="rim-landmark" data-direction="{direction}" data-kind="{kind}-wardstones">')
        for shift in (-52, 52):
            x, y = (cx + shift, cy) if horizontal else (cx, cy + shift)
            _wardstone(canvas, palette, kind, x, y)
        canvas.parts.append("</g>")


def _wardstone(canvas: Canvas, palette: Palette, kind: str, cx: int, cy: int) -> None:
    dark, middle, light = palette.rim
    canvas.rect(cx - 20, cy + 24, 40, 8, dark)
    canvas.rect(cx - 16, cy - 32, 32, 56, dark)
    canvas.rect(cx - 12, cy - 28, 24, 48, middle)
    canvas.rect(cx - 12, cy - 28, 4, 44, light)
    canvas.rect(cx - 20, cy - 36, 40, 8, middle)
    canvas.rect(cx - 16, cy - 40, 32, 4, light)
    if kind == "reliquary":
        canvas.rect(cx - 8, cy - 12, 16, 20, dark)
        canvas.rect(cx - 4, cy - 16, 8, 28, palette.accent)
        canvas.rect(cx - 12, cy - 4, 24, 4, palette.accent)
    elif kind == "mire":
        canvas.rect(cx - 8, cy - 16, 16, 28, palette.foliage[0])
        canvas.rect(cx - 4, cy - 12, 8, 20, palette.foliage[2])
        canvas.rect(cx - 12, cy - 4, 8, 8, palette.foliage[1])
        canvas.rect(cx + 4, cy + 4, 8, 8, palette.foliage[1])
    elif kind == "glacier":
        canvas.rect(cx - 8, cy - 20, 16, 32, palette.foliage[0])
        canvas.rect(cx - 4, cy - 24, 8, 36, palette.foliage[2])
        canvas.rect(cx - 8, cy - 8, 16, 8, palette.accent)
    else:
        canvas.rect(cx - 8, cy - 20, 16, 8, dark)
        canvas.rect(cx - 4, cy - 12, 12, 8, dark)
        canvas.rect(cx - 8, cy - 4, 12, 8, dark)
        canvas.rect(cx - 4, cy + 4, 12, 8, _mix(palette.accent, middle, 0.45))


def build_maps() -> list[tuple[str, bytes]]:
    definitions: list[dict[str, Any]] = json.loads((ROOT / "data/arenas.json").read_text(encoding="utf-8"))
    # This generator preserves the archived four-map Starfall family.
    # Original-game additions use world_flipper_maps.py instead.
    definitions = [definition for definition in definitions if definition["id"] in IDS]
    if tuple(definition["id"] for definition in definitions) != IDS:
        raise ValueError("Expanded maps require the four existing arena identities in catalog order")
    result: list[tuple[str, bytes]] = []
    for index, definition in enumerate(definitions):
        kind = str(definition["id"])
        palette = PALETTES[kind]
        rng = random.Random(0xE8A2D411 + index * 719)
        canvas = Canvas()
        _floor(canvas, palette, rng, kind)
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
                        "art_margins": list(ART_MARGINS), "pixel_grid": PIXEL, "material": MATERIALS[kind],
                        "pivot": [0.0, 0.0], "source": "tools/generate_expanded_maps.py",
                        "palette_source": "tools/starfall_environment.py", "terrain_source": "data/arenas.json",
                        "license": "CC0-1.0", "sha256": hashlib.sha256(content).hexdigest()})
    manifest = {"schema_version": 1, "art_revision": "expanded-arena-02", "purpose": "Continuous world-scale maps with biome materials and carved landmarks",
                "legacy_assets_preserved": True, "filter": "nearest", "assets": entries}
    (DESTINATION / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"Generated {len(entries)} continuous pixel maps at {SIZE[0]}x{SIZE[1]}; world origin={ORIGIN}; legacy maps untouched")


if __name__ == "__main__":
    main()
