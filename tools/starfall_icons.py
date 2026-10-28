"""Bright pixel versions of existing inventory symbols and restrained spell art."""
from __future__ import annotations

from starfall_sprites import (
    BLUE, BLUE_LIGHT, CORAL, CORAL_DARK, CREAM, GOLD, GOLD_DARK, INK,
    PURPLE, PURPLE_DARK, TEAL, TEAL_DARK, TEAL_LIGHT, PixelCanvas, SaveSvg,
)

ICON_NAMES = (
    "bone", "frost", "ember", "scatter", "crescent", "storm", "comet", "pierce", "bounce", "blast",
    "damage", "haste", "speed", "vitality", "armor", "magnet", "moon_charm", "pilgrim", "bulwark",
    "hourglass", "soul", "return_ring", "blood_pact", "grave_candle", "fold_clasp", "echo_stone",
)
PROJECTILE_NAMES = ("bone", "frost", "ember", "scatter", "crescent", "storm", "comet", "return_ring")


def _gem(p: PixelCanvas, x: int, y: int, width: int, height: int, light: str = TEAL_LIGHT, mid: str = TEAL, dark: str = TEAL_DARK) -> None:
    half = width // 2
    p.poly(((x, y - height // 2), (x + half, y - 2), (x + half - 1, y + height // 3), (x, y + height // 2), (x - half, y + 2), (x - half, y - 2)), dark)
    p.poly(((x, y - height // 2), (x, y + 3), (x - half, y - 2)), light)
    p.poly(((x, y - height // 2), (x + half, y - 2), (x, y + 3)), mid)
    p.line((x - half + 1, y + 2), (x, y + 3), light)


def _boot(p: PixelCanvas, x: int, y: int, color: str) -> None:
    p.poly(((x, y), (x + 7, y), (x + 6, y + 10), (x + 11, y + 14), (x + 10, y + 18), (x - 3, y + 18), (x - 5, y + 15), (x - 1, y + 10)), color)
    p.rect(x - 3, y + 17, 13, 2, GOLD_DARK)
    p.line((x + 1, y + 3), (x + 5, y + 3), GOLD)
    p.line((x + 1, y + 6), (x + 5, y + 6), GOLD)
    p.rect(x, y + 1, 2, 8, TEAL_LIGHT)


def icon(name: str) -> PixelCanvas:
    p = PixelCanvas()
    if name == "bone":
        p.line((7, 26), (23, 9), GOLD_DARK, 4)
        p.line((7, 25), (22, 9), CREAM, 2)
        p.disk(21, 7, 3, CREAM)
        p.disk(25, 10, 3, CREAM)
        p.dot(22, 7, GOLD_DARK)
        p.dot(25, 9, GOLD_DARK)
        p.line((11, 20), (14, 23), TEAL_DARK, 2)
        p.line((14, 17), (17, 20), TEAL_DARK, 2)
    elif name in {"frost", "soul"}:
        _gem(p, 16, 16, 13 if name == "frost" else 16, 25,
             "#d9f8f1", "#8acbdd" if name == "frost" else TEAL, "#4f8dad" if name == "frost" else TEAL_DARK)
        p.star(25, 7, 3, CREAM)
        p.dot(5, 21, TEAL_LIGHT)
        p.dot(24, 26, BLUE_LIGHT)
    elif name == "ember":
        p.poly(((17, 3), (18, 11), (23, 8), (27, 18), (25, 25), (18, 29), (10, 27), (6, 22), (7, 16), (12, 10), (12, 18)), CORAL_DARK)
        p.poly(((17, 6), (18, 15), (22, 13), (24, 21), (20, 26), (12, 26), (9, 22), (12, 16), (13, 21)), CORAL)
        p.poly(((17, 16), (21, 22), (18, 27), (14, 25), (14, 21)), GOLD)
        p.poly(((17, 21), (19, 24), (17, 27), (16, 25)), CREAM)
    elif name == "scatter":
        _gem(p, 16, 8, 7, 12, "#e8d9fb", PURPLE, PURPLE_DARK)
        _gem(p, 7, 17, 7, 12, "#e8d9fb", PURPLE, PURPLE_DARK)
        _gem(p, 25, 17, 7, 12, "#e8d9fb", PURPLE, PURPLE_DARK)
        p.poly(((13, 20), (19, 20), (20, 26), (16, 29), (12, 26)), GOLD)
        p.rect(14, 22, 3, 3, CREAM)
        p.line((16, 15), (16, 18), PURPLE)
    elif name == "crescent":
        p.line((9, 27), (19, 9), GOLD_DARK, 3)
        p.poly(((24, 3), (17, 3), (10, 7), (5, 13), (4, 20), (8, 25), (8, 18), (12, 12), (18, 8), (27, 8)), BLUE)
        p.poly(((22, 4), (16, 5), (9, 10), (6, 15), (6, 20), (8, 15), (12, 10), (20, 6)), CREAM)
        p.line((15, 14), (20, 17), GOLD, 2)
        p.line((13, 18), (18, 21), GOLD, 2)
        p.star(25, 24, 3, TEAL_LIGHT)
    elif name == "storm":
        p.poly(((17, 3), (10, 15), (16, 14), (12, 28), (23, 12), (17, 13), (21, 3)), GOLD)
        p.line((16, 7), (13, 13), CREAM)
        p.line((8, 7), (5, 15), TEAL_LIGHT, 2)
        p.line((5, 15), (9, 23), TEAL, 2)
        p.line((25, 7), (27, 16), TEAL_LIGHT, 2)
        p.line((27, 16), (23, 25), TEAL, 2)
        p.rect(13, 27, 7, 2, GOLD_DARK)
    elif name == "comet":
        p.poly(((3, 3), (15, 8), (24, 14), (17, 23), (8, 15)), PURPLE_DARK)
        p.line((5, 5), (16, 14), PURPLE, 3)
        p.line((4, 12), (14, 19), PURPLE, 2)
        p.star(20, 20, 10, GOLD)
        p.star(20, 19, 5, CREAM)
        p.dot(20, 19, CORAL)
    elif name == "pierce":
        p.line((5, 27), (24, 8), TEAL_DARK, 3)
        p.line((5, 26), (24, 7), TEAL_LIGHT)
        p.poly(((21, 5), (28, 3), (27, 11), (24, 8)), CREAM)
        p.poly(((5, 13), (8, 10), (15, 17), (12, 20)), GOLD)
        p.poly(((12, 6), (15, 3), (22, 10), (19, 13)), GOLD)
    elif name == "bounce":
        p.line((4, 25), (12, 13), PURPLE_DARK, 3)
        p.line((12, 13), (21, 21), PURPLE_DARK, 3)
        p.line((21, 21), (28, 5), PURPLE_DARK, 3)
        p.line((4, 25), (12, 13), "#e8d9fb")
        p.line((12, 13), (21, 21), "#e8d9fb")
        p.line((21, 21), (28, 5), "#e8d9fb")
        for x, y in ((12, 13), (21, 21)):
            p.disk(x, y, 3, GOLD)
            p.dot(x, y, CREAM)
        p.poly(((23, 5), (29, 3), (29, 10), (27, 7)), CREAM)
    elif name == "blast":
        p.star(16, 16, 14, CORAL_DARK)
        p.star(16, 16, 10, CORAL)
        p.star(16, 16, 6, GOLD)
        p.rect(14, 14, 4, 4, CREAM)
        for x, y in ((6, 5), (25, 5), (6, 25), (25, 25)):
            p.rect(x, y, 2, 2, GOLD)
    elif name == "damage":
        p.poly(((16, 20), (21, 7), (28, 3), (27, 11), (19, 23)), BLUE)
        p.line((25, 7), (17, 20), CREAM, 2)
        p.line((9, 17), (22, 26), GOLD, 3)
        p.line((12, 22), (7, 28), GOLD_DARK, 3)
        p.disk(6, 28, 2, GOLD)
    elif name in {"haste", "hourglass"}:
        p.rect(8, 4, 16, 3, GOLD)
        p.rect(7, 26, 18, 3, GOLD_DARK)
        p.rect(8, 26, 15, 1, GOLD)
        p.line((10, 8), (10, 25), BLUE_LIGHT)
        p.line((22, 8), (22, 25), BLUE)
        p.poly(((11, 8), (21, 8), (20, 12), (17, 16), (20, 21), (21, 25), (11, 25), (12, 21), (15, 16), (12, 12)), BLUE_LIGHT)
        p.poly(((12, 9), (20, 9), (18, 13), (16, 15), (13, 12)), PURPLE if name == "haste" else GOLD)
        p.poly(((16, 18), (20, 24), (12, 24)), PURPLE if name == "haste" else GOLD)
        p.rect(16, 16, 1, 3, CREAM)
        if name == "hourglass":
            p.star(26, 15, 4, TEAL_LIGHT)
            p.line((7, 9), (5, 24), PURPLE, 2)
    elif name == "speed":
        _boot(p, 15, 7, TEAL_DARK)
        p.poly(((11, 12), (5, 8), (4, 14), (8, 20), (10, 17), (7, 14)), CREAM)
        p.line((3, 24), (7, 24), BLUE)
        p.line((2, 27), (5, 27), BLUE)
    elif name == "vitality":
        p.rect(12, 3, 8, 4, GOLD)
        p.rect(13, 6, 6, 3, BLUE_LIGHT)
        p.poly(((12, 9), (20, 9), (24, 15), (24, 25), (20, 28), (11, 28), (7, 24), (7, 16)), BLUE_LIGHT)
        p.poly(((9, 18), (23, 18), (23, 25), (19, 27), (12, 27), (9, 24)), CORAL)
        p.poly(((12, 16), (15, 16), (16, 18), (18, 16), (21, 16), (21, 20), (16, 24), (12, 20)), CORAL_DARK)
        p.rect(10, 13, 2, 7, CREAM)
        p.rect(15, 4, 4, 1, CREAM)
    elif name in {"armor", "bulwark"}:
        p.poly(((5, 7), (16, 3), (27, 7), (25, 20), (21, 26), (16, 30), (10, 26), (7, 20)), BLUE if name == "armor" else TEAL_DARK)
        p.poly(((8, 9), (16, 6), (24, 9), (23, 19), (19, 25), (16, 27), (12, 23), (9, 18)), TEAL_DARK if name == "armor" else BLUE)
        p.line((8, 9), (16, 6), BLUE_LIGHT)
        if name == "armor":
            p.star(16, 16, 7, GOLD)
            p.rect(15, 11, 2, 10, CREAM)
        else:
            p.line((12, 11), (12, 22), CREAM, 2)
            p.line((20, 11), (20, 22), CREAM, 2)
            p.line((10, 14), (22, 14), CREAM, 2)
            p.line((11, 19), (21, 19), CREAM, 2)
        for x, y in ((7, 8), (25, 8), (10, 22), (22, 22)):
            p.dot(x, y, GOLD)
    elif name == "magnet":
        p.disk(16, 19, 10, GOLD_DARK)
        p.disk(16, 18, 9, GOLD)
        p.disk(16, 18, 7, TEAL_DARK)
        _gem(p, 16, 18, 7, 13)
        p.rect(12, 3, 8, 4, GOLD)
        p.rect(14, 7, 4, 3, GOLD_DARK)
        p.star(16, 17, 3, CREAM)
    elif name == "moon_charm":
        p.line((6, 3), (10, 11), GOLD_DARK, 2)
        p.line((10, 11), (15, 15), GOLD, 2)
        p.line((26, 3), (23, 11), GOLD_DARK, 2)
        p.line((23, 11), (18, 15), GOLD, 2)
        p.poly(((18, 14), (12, 15), (8, 20), (10, 26), (16, 29), (23, 27), (26, 23), (19, 25), (15, 22), (15, 18)), CREAM)
        p.line((11, 24), (16, 27), GOLD)
        p.star(24, 16, 4, PURPLE)
    elif name == "pilgrim":
        _boot(p, 9, 7, TEAL_DARK)
        _boot(p, 22, 9, "#547d9e")
        p.star(25, 5, 3, GOLD)
    elif name == "return_ring":
        p.disk(16, 16, 11, GOLD_DARK, 7)
        p.disk(16, 16, 10, CREAM, 8)
        for vertices in (
            ((17, 3), (25, 5), (27, 12), (22, 9), (17, 9)),
            ((28, 20), (23, 28), (15, 28), (20, 23), (22, 19)),
            ((8, 26), (3, 19), (6, 11), (7, 18), (10, 22)),
        ):
            p.poly(vertices, CREAM)
        p.line((18, 5), (23, 6), GOLD)
        p.line((24, 23), (20, 26), GOLD)
        p.line((5, 18), (7, 22), GOLD)
    elif name == "blood_pact":
        p.poly(((7, 5), (22, 4), (26, 8), (25, 27), (9, 29), (5, 25)), CORAL_DARK)
        p.poly(((8, 6), (22, 5), (24, 9), (23, 25), (9, 27)), CORAL)
        p.line((9, 7), (9, 25), GOLD)
        p.rect(22, 11, 4, 3, GOLD_DARK)
        p.rect(22, 19, 3, 3, GOLD_DARK)
        p.disk(17, 16, 5, GOLD)
        p.star(17, 16, 3, CREAM)
        p.line((11, 25), (21, 24), "#f1c68d")
    elif name == "grave_candle":
        p.poly(((13, 11), (19, 11), (20, 25), (12, 25)), CREAM)
        p.rect(18, 12, 2, 12, "#d6c29f")
        p.rect(13, 13, 2, 5, "#fff9e3")
        p.rect(12, 25, 9, 2, GOLD_DARK)
        p.rect(9, 27, 15, 2, GOLD)
        p.poly(((17, 3), (19, 6), (18, 10), (14, 11), (13, 8), (15, 5)), TEAL)
        p.rect(15, 7, 2, 3, TEAL_LIGHT)
        p.dot(16, 6, CREAM)
    elif name == "fold_clasp":
        p.poly(((8, 6), (23, 6), (25, 26), (7, 26)), "#b9844f")
        p.rect(8, 7, 3, 18, "#e1b479")
        p.poly(((11, 10), (14, 10), (14, 21), (11, 21)), CREAM)
        p.poly(((18, 10), (21, 10), (21, 21), (18, 21)), BLUE_LIGHT)
        p.rect(9, 13, 7, 2, GOLD)
        p.rect(16, 18, 7, 2, GOLD)
        p.rect(15, 11, 2, 10, INK)
        p.rect(9, 23, 14, 2, GOLD_DARK)
    elif name == "echo_stone":
        p.disk(16, 17, 13, GOLD_DARK, 12)
        p.disk(16, 17, 10, GOLD, 9)
        p.rect(2, 13, 5, 7, "")
        p.rect(26, 13, 5, 7, "")
        _gem(p, 16, 16, 12, 20)
        p.line((12, 14), (16, 10), CREAM)
    else:
        raise ValueError(f"Unknown Starfall icon: {name}")
    p.pixels = {point: color for point, color in p.pixels.items() if color}
    p.outline()
    return p


def _projectile(name: str) -> PixelCanvas:
    p = PixelCanvas()
    if name == "bone":
        p.line((9, 18), (22, 13), GOLD, 3)
        p.line((10, 17), (22, 12), CREAM, 2)
        p.disk(10, 17, 2, CREAM)
        p.disk(22, 13, 2, CREAM)
    elif name == "frost":
        _gem(p, 16, 16, 8, 14, CREAM, "#8acbdd", "#4f8dad")
    elif name == "ember":
        p.poly(((9, 12), (16, 12), (21, 10), (24, 16), (21, 21), (12, 21), (14, 17), (8, 17)), CORAL)
        p.poly(((14, 14), (20, 12), (22, 16), (19, 19), (14, 18)), GOLD)
        p.rect(18, 14, 3, 3, CREAM)
    elif name == "scatter":
        _gem(p, 16, 16, 7, 11, CREAM, PURPLE, PURPLE_DARK)
    elif name == "crescent":
        p.poly(((22, 9), (14, 9), (10, 13), (9, 18), (13, 23), (20, 24), (16, 20), (14, 16), (17, 12)), CREAM)
        p.line((11, 17), (14, 21), TEAL_LIGHT)
    elif name == "storm":
        p.poly(((17, 8), (11, 17), (16, 16), (13, 24), (22, 13), (17, 14), (21, 8)), GOLD)
        p.line((17, 10), (14, 15), CREAM)
    elif name == "comet":
        p.star(16, 16, 8, GOLD)
        p.star(16, 16, 4, CREAM)
        p.line((8, 10), (11, 13), PURPLE, 2)
    elif name == "return_ring":
        p.disk(16, 16, 8, CREAM, 5)
        p.line((16, 8), (22, 10), GOLD, 2)
        p.line((23, 20), (18, 24), GOLD, 2)
        p.line((9, 20), (8, 14), GOLD, 2)
    p.outline()
    return p


def generate(save_svg: SaveSvg) -> None:
    """Emit inventory/FX originals, preserving source sizes and atlas ordering."""
    for name in ICON_NAMES:
        save_svg(f"icons/{name}.svg", 64, 64, icon(name).body(), f"original pixel {name} icon; transparent; 32px grid; navy outline; readable at 24–48px")
    glow = ""
    for radius, opacity in ((15, ".025"), (12, ".035"), (9, ".055"), (5, ".10")):
        p = PixelCanvas()
        p.disk(16, 16, radius, "#ffffff")
        glow += p.body(3, opacity=opacity)
    save_svg("fx/glow.svg", 96, 96, glow, "low-opacity stepped white light; runtime tint; decoration only")
    seal = PixelCanvas()
    seal.disk(16, 16, 12, CREAM, 11)
    seal.disk(16, 16, 9, GOLD, 8)
    for x, y in ((16, 2), (30, 16), (16, 30), (2, 16)):
        seal.star(x, y, 2, TEAL_LIGHT)
    save_svg("fx/seal.svg", 96, 96, seal.body(3, opacity=".6"), "stepped star-compass ground seal; transparent; decorative, no collision")
    atlas = "\n".join(_projectile(name).body(2, (index * 64, 0)) for index, name in enumerate(PROJECTILE_NAMES))
    save_svg("fx/projectile_heads.svg", 512, 64, atlas, "eight pixel projectile heads; established source ordering; 64px cells; hollow return-ring center")
    app = PixelCanvas()
    app.rect(1, 1, 30, 30, INK)
    app.rect(3, 3, 26, 26, TEAL_DARK)
    app.disk(16, 14, 11, GOLD_DARK)
    app.disk(16, 14, 10, GOLD)
    app.disk(19, 11, 8, TEAL_DARK)
    app.poly(((17, 10), (17, 16), (21, 14), (24, 21), (21, 26), (14, 28), (9, 24), (10, 19), (14, 15), (13, 21)), TEAL_LIGHT)
    app.poly(((16, 17), (20, 22), (18, 26), (14, 26), (12, 23)), CREAM)
    app.rect(12, 28, 9, 1, GOLD)
    app.rect(5, 5, 3, 1, TEAL_LIGHT)
    save_svg("icon.svg", 256, 256, app.body(8), "pixel reinterpretation of the existing eclipse and ritual-flame application emblem; navy field")
