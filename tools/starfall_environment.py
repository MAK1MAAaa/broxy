#!/usr/bin/env python3
"""Pixel artwork for the four existing occult arenas on a four-pixel grid.

Only the authored movement ellipses use smooth geometry. All other marks are
integer pixel clusters. Upright rim ornaments carry bounds checked against the
unchanged combat rectangle; floor texture never implies a new solid obstacle.
"""
from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import random
from typing import Callable


SaveSVG = Callable[[str, int, int, str, str], None]
ROOT = Path(__file__).resolve().parents[1]
PIXEL = 4
ARENA = (66, 140, 1214, 590)


@dataclass(frozen=True)
class Palette:
    backdrop: str
    rim: tuple[str, str, str]
    floor: tuple[str, str, str, str, str]
    foliage: tuple[str, str, str]
    terrain: tuple[str, str, str]
    accent: str
    banner: str
    wood: str = "#7d7861"


PALETTES: dict[str, Palette] = {
    "reliquary": Palette(
        "#7d9b90", ("#506f70", "#78978a", "#c5d8b5"),
        ("#afc3a8", "#b7cbb0", "#b1c6ab", "#a9bea2", "#c1d0b5"),
        ("#4f7e74", "#6a9d80", "#9abd88"),
        ("#9db99b", "#78987e", "#bbcfad"), "#f0d394", "#679eac"),
    "mire": Palette(
        "#668c80", ("#426d68", "#739888", "#b8d2ab"),
        ("#9dbb9f", "#a8c3a6", "#a2bfa2", "#95b397", "#b4ccad"),
        ("#3f7965", "#55947a", "#8cba85"),
        ("#70aaa1", "#507f7b", "#9bc5ad"), "#eee0a1", "#91bfa1"),
    "glacier": Palette(
        "#719da9", ("#547d92", "#87adba", "#d8e7dc"),
        ("#b8d0d0", "#c2d9d5", "#bcd4d2", "#adc7c9", "#d0e1db"),
        ("#547f96", "#8bbac6", "#c8e6e5"),
        ("#a0beca", "#7a9da9", "#cae1df"), "#f1dfa4", "#839fbb"),
    "ashland": Palette(
        "#9b806e", ("#6c6868", "#9c8a7b", "#d8c7a7"),
        ("#bda994", "#c6b29a", "#c1ad97", "#b4a08b", "#cebea6"),
        ("#646b70", "#868b88", "#b9b8a0"),
        ("#ad9d8a", "#8d8c7d", "#c7b59b"), "#efce8e", "#91aaa1"),
}


class Canvas:
    def __init__(self) -> None:
        self.parts: list[str] = []

    def rect(self, x: int, y: int, width: int, height: int, color: str) -> None:
        if width <= 0 or height <= 0:
            return
        self.parts.append(
            f'<rect x="{x * PIXEL}" y="{y * PIXEL}" '
            f'width="{width * PIXEL}" height="{height * PIXEL}" fill="{color}"/>')

    def sprite(self, x: int, y: int, rows: tuple[str, ...],
               colors: dict[str, str], name: str) -> None:
        width, height = max(map(len, rows)), len(rows)
        left, top, right, bottom = x * PIXEL, y * PIXEL, (x + width) * PIXEL, (y + height) * PIXEL
        if left < ARENA[2] and right > ARENA[0] and top < ARENA[3] and bottom > ARENA[1]:
            raise ValueError(f"Upright ornament enters the arena: {name}")
        if left < 0 or top < 0 or right > 1280 or bottom > 720:
            raise ValueError(f"Upright ornament leaves the canvas: {name}")
        self.parts.append(
            f'<g data-role="rim-decoration" data-kind="{name}" '
            f'data-bounds="{left},{top},{right - left},{bottom - top}">')
        for row_index, row in enumerate(rows):
            run_start = 0
            while run_start < len(row):
                symbol = row[run_start]
                run_end = run_start + 1
                while run_end < len(row) and row[run_end] == symbol:
                    run_end += 1
                if symbol in colors:
                    self.rect(x + run_start, y + row_index, run_end - run_start, 1, colors[symbol])
                run_start = run_end
        self.parts.append("</g>")

    def star(self, x: int, y: int, color: str, core: str | None = None) -> None:
        self.rect(x, y - 2, 1, 5, color)
        self.rect(x - 2, y, 5, 1, color)
        self.rect(x - 1, y - 1, 3, 3, color)
        if core is not None:
            self.rect(x, y, 1, 1, core)

    def body(self) -> str:
        return "\n".join(self.parts)


BUSH = (
    ".....ddddd.....", "...ddllllldd...", "..dllhhlhllld..",
    ".dllhhhlhhhlld.", "dllhhhllhlllldd", "dllhlllllllhhld",
    "ddllllhlllhhlld", ".ddlllhllllldd.", "...dddddddddd..",
)
FERN = (
    ".....h......", "..h..hh..h..", "..hhlhh.hh..", ".hhhlhhlhh..",
    "..lllhhhhhl.", "h..llhhllllh", "hhl.llhlll..", ".hhlllhhll..",
    "..llllhll...", "...lllll....", "....ddd.....", "....ddd.....",
)
TREE = (
    "......ddd......", "....ddllldd....", "...dllhhllld...",
    "..dllhhhlllhd..", ".dllhhhlhhhhld.", ".dllhhhlhhhhlld",
    "dllhhlhhhhlllld", "dllhllhhlllllld", "dlhhllhllllhlld",
    "dllhlllllhhhldd", "ddlllllllhhlld.", ".ddlllhlhlllhd.",
    "..ddllhllllld..", "...ddllllldd...", ".....ddldd.....",
    "......www......", "......wlw......", "......wlw......",
    "......wlw......", ".....wwlww.....", "....wwllwww....",
    "...ddddddddd...", "..ddllldllldd..",
)
PILLAR = (
    "..hhhhhhh..", ".hlllllllh.", "dhhhhhhhhhd", "ddllllllldd",
    ".dllllllld.", ".dlhhhhhld.", ".dlhhlllhd.", ".dlhhl.lhd.",
    ".dlhhl.lhd.", ".dlhhl.lhd.", ".dlhhl.lhd.", ".dlhhlllhd.",
    ".dlhhhhhld.", ".dllllllld.", "ddhhhhhhhdd", "ddllllllldd",
    "ddddddddddd",
)
CRYSTAL = (
    ".....h......", "....hh......", "....hlh.....", "...hhllh....",
    "...hhlld....", "..hhhllld...", "..hhhllld...", "..hhlllld...",
    "..hhlllld.h.", "..hllllldhh.", ".hhllluldhld", ".hlllluldhld",
    ".dlllluldlld", "..dlllulldd.", "...ddddddd..", "..ddddddddd.",
)
BASALT = (
    "...hhhh....", "..hlllld...", ".hhllllld..", ".hllullld..",
    ".hllullld..", ".hllullld..", ".hllullld..", ".hlllllld..",
    ".hlllllld..", ".hlllllld..", "dhlllllldd.", "dllllllllld",
    "dllllllllld", "ddddddddddd",
)
FLAG = (
    "d.hhhhhhhh", "dhllllllll", "dhllllhhll", "dhlllhhhhl", "dhllllhhll",
    "dhllllllll", "dhllllllll", "dhllllll..", "d.hhhh....", "d.........",
    "d.........", "d.........", "d.........", "d.........", "dd........",
)


def _floor(canvas: Canvas, palette: Palette, rng: random.Random, id: str) -> None:
    base, tile, tile_alt, seam, light = palette.floor
    canvas.rect(0, 0, 320, 180, palette.backdrop)
    canvas.rect(16, 34, 288, 115, base)
    for row, y in enumerate(range(36, 148, 10)):
        offset = 8 if row % 2 else 0
        for x in range(16 - offset, 304, 20):
            start, end = max(17, x), min(303, x + 19)
            if end <= start:
                continue
            color = tile if rng.randrange(3) else tile_alt
            canvas.rect(start, y, end - start, min(9, 148 - y), color)
            if rng.randrange(3) == 0 and end - start > 6:
                canvas.rect(start + 2, y, min(6, end - start - 2), 1, light)
            if rng.randrange(4) == 0:
                canvas.rect(end - 2, y + 7, 1, 1, seam)
    for _ in range(170):
        x, y = rng.randrange(19, 300), rng.randrange(38, 145)
        color = rng.choice((base, tile_alt, seam))
        canvas.rect(x, y, rng.choice((1, 2, 3)), 1, color)
        if rng.randrange(4) == 0:
            canvas.rect(x + 1, y - 1, 1, 1, color)
    for _ in range(42):
        x, y = rng.randrange(20, 299), rng.randrange(39, 144)
        color = light if id == "glacier" else seam
        canvas.rect(x, y, 2, 1, color)
        canvas.rect(x + 2, y - 1, 1, 1, color)
    for _ in range(25):
        x, y = rng.randrange(20, 285), rng.randrange(40, 138)
        color = base if id in ("reliquary", "glacier") else seam
        canvas.rect(x + 3, y, 9, 1, color)
        canvas.rect(x, y + 1, 15, 2, color)
        canvas.rect(x + 2, y + 3, 10, 1, color)
        canvas.rect(x + 5, y + 4, 4, 1, color)
    _compass(canvas, palette)


def _compass(canvas: Canvas, palette: Palette) -> None:
    """Quiet flush stone inlay, separate from every attack/range indicator."""
    quiet, brighter = palette.floor[0], palette.floor[4]
    for x, y, width, height in (
        (159, 76, 2, 30), (144, 90, 32, 2), (155, 86, 10, 10),
        (153, 88, 14, 6), (157, 82, 6, 18),
    ):
        canvas.rect(x, y, width, height, quiet)
    for x, y in ((159, 79), (159, 102), (147, 90), (171, 90)):
        canvas.rect(x, y, 2, 2, brighter)
    canvas.rect(158, 89, 4, 4, palette.floor[2])


def _terrain(canvas: Canvas, definition: dict, palette: Palette, rng: random.Random) -> None:
    fill, edge, detail = palette.terrain
    for zone in definition["zones"]:
        cx, cy = zone["center"]
        rx, ry = zone["radius"]
        canvas.parts.append(
            f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" '
            f'fill="{fill}" stroke="{edge}" stroke-width="2"/>')
        for _ in range(100):
            x = rng.randrange((cx - rx + 12) // PIXEL, (cx + rx - 12) // PIXEL)
            y = rng.randrange((cy - ry + 8) // PIXEL, (cy + ry - 8) // PIXEL)
            width = rng.choice((2, 3, 4, 5))
            corners = tuple(
                (px * PIXEL, py * PIXEL)
                for px in (x - 1, x + width + 2)
                for py in (y - 2, y + 3))
            if not all(((px - cx) / (rx - 5)) ** 2 + ((py - cy) / (ry - 5)) ** 2 < 1 for px, py in corners):
                continue
            if definition["id"] == "mire":
                canvas.rect(x, y, width, 1, detail if rng.randrange(3) == 0 else fill)
                if rng.randrange(7) == 0:
                    canvas.rect(x + 1, y - 1, 2, 1, detail)
            elif definition["id"] == "glacier":
                canvas.rect(x, y, width, 1, detail)
                canvas.rect(x + width - 1, y + 1, 1, 1, detail)
            else:
                canvas.rect(x, y, width, 1, detail if rng.randrange(3) == 0 else edge)
                if rng.randrange(4) == 0:
                    canvas.rect(x + 1, y + 1, 1, 1, detail)


def _rim(canvas: Canvas, palette: Palette, id: str) -> None:
    dark, middle, light = palette.rim
    canvas.rect(13, 31, 294, 3, dark)
    canvas.rect(13, 149, 294, 3, dark)
    canvas.rect(13, 34, 3, 115, dark)
    canvas.rect(304, 34, 3, 115, dark)
    canvas.rect(15, 33, 290, 1, light)
    canvas.rect(15, 149, 290, 1, light)
    canvas.rect(15, 34, 1, 115, middle)
    canvas.rect(304, 34, 1, 115, light)
    for x in range(18, 301, 12):
        canvas.rect(x, 31, 1, 2, middle)
        canvas.rect(x + 2, 150, 1, 2, middle)
    for y in range(36, 148, 11):
        canvas.rect(13, y, 2, 1, middle)
        canvas.rect(305, y, 2, 1, middle)
    for x in (26, 96, 222, 292):
        canvas.rect(x - 5, 29, 11, 2, middle)
        canvas.rect(x - 3, 28, 7, 1, light)
        canvas.star(x, 29, palette.accent, light)
        canvas.rect(x - 5, 152, 11, 2, middle)
        canvas.star(x, 153, palette.accent, light)
    for x in (4, 309):
        for y in (40, 75, 110, 142):
            canvas.rect(x, y, 7, 1, middle)
            canvas.rect(x + 2, y - 1, 3, 1, light)
    if id == "ashland":
        for x in range(16, 300, 19):
            canvas.rect(x, 156, 8, 1, palette.rim[0])
            canvas.rect(x + 7, 157, 1, 3, palette.rim[0])
            canvas.rect(x + 1, 156, 4, 1, palette.accent)


def _ornaments(canvas: Canvas, palette: Palette, id: str) -> None:
    leaf_dark, leaf, leaf_light = palette.foliage
    foliage = {"d": leaf_dark, "l": leaf, "h": leaf_light}
    stone = {"d": palette.rim[0], "l": palette.rim[1], "h": palette.rim[2], "u": palette.accent}
    flags = {"d": palette.wood, "l": palette.banner, "h": palette.accent}
    for x in (34, 91, 214, 270):
        canvas.sprite(x, 13, FLAG, flags, "courtyard-banner")
    if id in ("reliquary", "mire"):
        tree_colors = {**foliage, "w": palette.wood}
        for x in (0, 305):
            for y in (49, 106):
                canvas.sprite(x, y, TREE, tree_colors, "courtyard-tree")
        for x in (1, 63, 127, 187, 246, 303):
            canvas.sprite(x, 21, BUSH, foliage, "tree-canopy")
        for x in (2, 62, 127, 187, 248, 302):
            canvas.sprite(x, 159, BUSH, foliage, "tree-canopy")
        for x in (0, 308):
            for y in (43, 81, 119):
                canvas.sprite(x, y, FERN, foliage, "fern")
        if id == "reliquary":
            for x in (17, 108, 202, 292):
                canvas.sprite(x, 11, PILLAR, stone, "ruin-column")
                canvas.sprite(x, 155, PILLAR, stone, "ruin-column")
        else:
            for x in (18, 109, 202, 291):
                canvas.sprite(x, 154, FERN, foliage, "wetland-fern")
            for x in (19, 110, 203, 291):
                canvas.rect(x, 25, 6, 2, palette.wood)
                canvas.rect(x + 1, 24, 4, 1, palette.accent)
    elif id == "glacier":
        crystal_colors = {**foliage, "u": palette.accent}
        for x in (2, 62, 127, 188, 247, 306):
            canvas.sprite(x, 14, CRYSTAL, crystal_colors, "ice-cluster")
            canvas.sprite(x, 154, CRYSTAL, crystal_colors, "ice-cluster")
        for x in (0, 308):
            for y in (42, 81, 119):
                canvas.sprite(x, y, CRYSTAL, crystal_colors, "ice-cluster")
        for x in (22, 110, 200, 287):
            canvas.sprite(x, 11, PILLAR, stone, "frost-column")
            canvas.sprite(x, 155, PILLAR, stone, "frost-column")
    else:
        for x in (2, 62, 127, 188, 247, 306):
            canvas.sprite(x, 16, BASALT, stone, "basalt-pillar")
            canvas.sprite(x, 156, BASALT, stone, "basalt-pillar")
        for x in (0, 308):
            for y in (42, 81, 119):
                canvas.sprite(x, y, BASALT, stone, "basalt-pillar")
        for x in (23, 110, 201, 287):
            canvas.sprite(x, 12, PILLAR, stone, "ancient-column")
            canvas.sprite(x, 156, BASALT, stone, "basalt-pillar")
    for x, y in ((51, 27), (147, 26), (172, 27), (255, 26), (49, 154), (149, 154), (172, 156), (267, 155)):
        canvas.star(x, y, palette.accent, palette.rim[2])


def generate(save_svg: SaveSVG) -> None:
    definitions = json.loads((ROOT / "data/arenas.json").read_text(encoding="utf-8"))
    for index, definition in enumerate(definitions):
        definition = dict(definition)
        definition["zones"] = definition["zones"][:definition.get("legacy_zone_count", len(definition["zones"]))]
        id = str(definition["id"])
        if id not in PALETTES:
            raise ValueError(f"No Starfall environment palette for {id}")
        palette = PALETTES[id]
        canvas = Canvas()
        rng = random.Random(0x57A2F411 + index * 719)
        _floor(canvas, palette, rng, id)
        _terrain(canvas, definition, palette, rng)
        _rim(canvas, palette, id)
        _ornaments(canvas, palette, id)
        name = "arena.svg" if id == "reliquary" else f"maps/{id}.svg"
        save_svg(name, 1280, 720, canvas.body(), f"pixel reskin of existing {id} arena; exact walkable terrain; decorative rim")
