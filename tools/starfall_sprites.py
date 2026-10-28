"""Pixel reinterpretations of the game's existing occult character identities.

The serializer receives SVG bodies made only of horizontal integer rectangles.
Each character keeps its established canvas and gameplay anchor; none of the
painted shadows or equipment define collision geometry.
"""
from __future__ import annotations

from collections.abc import Callable, Iterable

SaveSvg = Callable[[str, int, int, str, str], None]
INK = "#243752"
CREAM = "#fff1cf"
GOLD = "#ffc86b"
GOLD_DARK = "#bc7b42"
TEAL = "#41b5b2"
TEAL_LIGHT = "#91e0d1"
TEAL_DARK = "#277d90"
CORAL = "#f07d67"
CORAL_DARK = "#b34e61"
BLUE = "#7397b7"
BLUE_LIGHT = "#b6d3d6"
PURPLE = "#a08cce"
PURPLE_DARK = "#655c99"


class PixelCanvas:
    """A small deterministic raster whose SVG serialization never interpolates."""

    def __init__(self, width: int = 32, height: int = 32) -> None:
        self.width = width
        self.height = height
        self.pixels: dict[tuple[int, int], str] = {}

    def dot(self, x: int, y: int, color: str) -> None:
        if 0 <= x < self.width and 0 <= y < self.height:
            self.pixels[x, y] = color

    def rect(self, x: int, y: int, width: int, height: int, color: str) -> None:
        for row in range(y, y + height):
            for column in range(x, x + width):
                self.dot(column, row, color)

    def poly(self, vertices: Iterable[tuple[int, int]], color: str) -> None:
        points = tuple(vertices)
        for y in range(min(p[1] for p in points), max(p[1] for p in points) + 1):
            for x in range(min(p[0] for p in points), max(p[0] for p in points) + 1):
                inside = False
                previous = points[-1]
                for point in points:
                    if (point[1] > y + 0.5) != (previous[1] > y + 0.5):
                        intercept = (previous[0] - point[0]) * (y + 0.5 - point[1]) / (previous[1] - point[1]) + point[0]
                        if x + 0.5 < intercept:
                            inside = not inside
                    previous = point
                if inside:
                    self.dot(x, y, color)

    def line(self, start: tuple[int, int], end: tuple[int, int], color: str, width: int = 1) -> None:
        x, y = start
        target_x, target_y = end
        dx, dy = abs(target_x - x), -abs(target_y - y)
        step_x, step_y = 1 if x < target_x else -1, 1 if y < target_y else -1
        error = dx + dy
        while True:
            self.rect(x - width // 2, y - width // 2, width, width, color)
            if x == target_x and y == target_y:
                return
            doubled = error * 2
            if doubled >= dy:
                error += dy
                x += step_x
            if doubled <= dx:
                error += dx
                y += step_y

    def disk(self, x: int, y: int, radius: int, color: str, inner: int = -1) -> None:
        for row in range(y - radius, y + radius + 1):
            for column in range(x - radius, x + radius + 1):
                distance = (column - x) ** 2 + (row - y) ** 2
                if inner * inner < distance <= radius * radius or inner < 0 and distance <= radius * radius:
                    self.dot(column, row, color)

    def star(self, x: int, y: int, radius: int, color: str) -> None:
        self.poly(((x, y - radius), (x + 2, y - 2), (x + radius, y), (x + 2, y + 2),
                   (x, y + radius), (x - 2, y + 2), (x - radius, y), (x - 2, y - 2)), color)

    def outline(self, color: str = INK) -> None:
        occupied = set(self.pixels)
        for x, y in occupied:
            for point in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if point not in occupied:
                    self.dot(*point, color)

    def body(self, scale: int = 2, offset: tuple[int, int] = (0, 0), opacity: str = "") -> str:
        output: list[str] = []
        extra = f' opacity="{opacity}"' if opacity else ""
        for y in range(self.height):
            x = 0
            while x < self.width:
                color = self.pixels.get((x, y))
                if color is None:
                    x += 1
                    continue
                end = x + 1
                while end < self.width and self.pixels.get((end, y)) == color:
                    end += 1
                output.append(f'<rect x="{offset[0] + x * scale}" y="{offset[1] + y * scale}" width="{(end - x) * scale}" height="{scale}" fill="{color}"{extra}/>')
                x = end
        return "\n".join(output)


def _player() -> PixelCanvas:
    p = PixelCanvas()
    # The beaked mask, pointed hood and ritual chain retain the original identity.
    p.poly(((9, 17), (22, 17), (27, 26), (22, 25), (23, 28), (8, 28), (9, 24), (5, 26)), TEAL_DARK)
    p.poly(((9, 18), (16, 19), (14, 26), (7, 26)), TEAL)
    p.poly(((17, 18), (22, 18), (25, 25), (19, 26)), TEAL)
    p.line((10, 20), (8, 24), TEAL_LIGHT)
    p.rect(12, 22, 8, 6, INK)
    p.rect(11, 28, 4, 2, "#725347")
    p.rect(18, 28, 4, 2, "#725347")
    p.rect(11, 27, 4, 1, GOLD)
    p.rect(18, 27, 4, 1, GOLD)
    p.poly(((12, 18), (20, 18), (21, 23), (12, 23)), CREAM)
    p.rect(15, 21, 5, 3, "#d8bc91")
    p.line((12, 19), (19, 24), "#94644a", 2)
    p.rect(8, 22, 5, 4, "#b9844f")
    p.rect(8, 22, 5, 1, GOLD)
    p.rect(10, 23, 1, 2, CREAM)
    p.rect(22, 20, 2, 3, CREAM)
    p.poly(((8, 16), (9, 9), (12, 5), (16, 3), (21, 6), (24, 11), (24, 17), (20, 20), (11, 20)), PURPLE_DARK)
    p.poly(((10, 12), (12, 7), (16, 5), (20, 8), (20, 11), (14, 9), (12, 15)), PURPLE)
    p.line((12, 8), (15, 6), "#d3c3ed")
    p.poly(((11, 12), (15, 9), (20, 10), (22, 14), (22, 18), (18, 20), (13, 18)), INK)
    p.poly(((12, 12), (17, 11), (20, 13), (19, 16), (25, 20), (19, 19), (16, 20), (12, 17)), CREAM)
    p.poly(((17, 13), (19, 15), (25, 20), (19, 18), (17, 16)), "#c9b793")
    p.rect(12, 13, 3, 2, INK)
    p.rect(18, 13, 2, 2, INK)
    p.rect(13, 13, 2, 1, GOLD)
    p.dot(18, 13, GOLD)
    p.poly(((10, 18), (16, 21), (22, 18), (22, 21), (17, 24), (10, 21)), PURPLE)
    for x, y in ((11, 21), (13, 22), (15, 23), (18, 23), (20, 22), (22, 21)):
        p.dot(x, y, GOLD)
    p.rect(16, 22, 3, 3, GOLD_DARK)
    p.rect(16, 22, 2, 2, GOLD)
    p.dot(17, 22, CREAM)
    p.outline()
    return p


def _chaser() -> PixelCanvas:
    p = PixelCanvas()
    p.poly(((15, 4), (21, 8), (24, 16), (28, 24), (23, 22), (24, 28), (19, 25), (16, 29), (13, 25), (8, 27), (9, 22), (4, 25), (8, 16), (9, 9)), TEAL_DARK)
    p.poly(((14, 6), (18, 7), (21, 11), (23, 20), (19, 18), (20, 24), (16, 26), (13, 23), (9, 24), (11, 18), (8, 21), (10, 12)), TEAL)
    p.poly(((12, 10), (17, 8), (20, 12), (20, 18), (16, 22), (12, 19)), CREAM)
    p.poly(((17, 10), (20, 12), (19, 18), (16, 21)), "#c2cfbd")
    p.rect(12, 13, 2, 3, INK)
    p.rect(17, 12, 2, 3, INK)
    p.rect(15, 17, 2, 2, INK)
    p.line((11, 10), (14, 7), TEAL_LIGHT)
    p.line((10, 20), (9, 23), TEAL_LIGHT)
    p.outline()
    return p


def _rusher() -> PixelCanvas:
    p = PixelCanvas()
    p.poly(((14, 15), (20, 11), (24, 14), (28, 13), (27, 18), (29, 22), (23, 21), (21, 24)), PURPLE_DARK)
    p.poly(((6, 14), (15, 14), (22, 18), (22, 25), (9, 25), (6, 22)), PURPLE)
    p.poly(((10, 21), (19, 22), (22, 24), (10, 24)), PURPLE_DARK)
    p.poly(((6, 14), (6, 8), (10, 11), (16, 8), (17, 15), (19, 19), (14, 23), (7, 21), (4, 18)), CREAM)
    p.poly(((7, 10), (7, 14), (10, 14)), "#c9b793")
    p.poly(((14, 10), (12, 14), (15, 14)), "#c9b793")
    p.poly(((6, 17), (10, 18), (14, 17), (17, 18), (14, 22), (9, 22)), "#d7cba9")
    p.rect(7, 15, 2, 2, INK)
    p.rect(13, 15, 2, 2, INK)
    p.rect(9, 19, 3, 1, INK)
    p.rect(7, 24, 3, 3, PURPLE_DARK)
    p.rect(16, 24, 3, 3, PURPLE_DARK)
    p.rect(5, 27, 5, 1, CREAM)
    p.rect(15, 27, 4, 1, CREAM)
    p.line((19, 18), (21, 19), "#d3c3ed")
    p.outline()
    return p


def _tank() -> PixelCanvas:
    p = PixelCanvas()
    p.rect(6, 24, 6, 5, INK)
    p.rect(20, 24, 6, 5, INK)
    p.rect(5, 28, 8, 2, BLUE)
    p.rect(19, 28, 8, 2, BLUE)
    p.poly(((5, 10), (11, 8), (21, 8), (27, 11), (29, 20), (25, 26), (7, 26), (3, 20)), BLUE)
    p.rect(5, 12, 5, 8, BLUE_LIGHT)
    p.rect(23, 12, 4, 8, "#4f6d94")
    p.line((5, 21), (8, 24), "#4f6d94", 2)
    p.line((26, 21), (23, 24), "#4f6d94", 2)
    p.poly(((11, 8), (12, 4), (20, 4), (22, 8), (20, 13), (12, 13)), BLUE_LIGHT)
    p.rect(12, 8, 9, 3, INK)
    p.rect(13, 9, 3, 1, GOLD)
    p.rect(18, 9, 2, 1, GOLD)
    p.poly(((11, 14), (21, 14), (24, 18), (22, 24), (16, 28), (9, 24), (8, 18)), INK)
    p.poly(((12, 15), (20, 15), (22, 18), (20, 23), (16, 26), (11, 23), (10, 18)), TEAL_DARK)
    p.line((12, 16), (19, 16), TEAL_LIGHT)
    p.poly(((16, 17), (18, 20), (16, 24), (14, 20)), GOLD)
    p.dot(16, 18, CREAM)
    for x, y in ((7, 12), (25, 12), (7, 22), (25, 22)):
        p.rect(x, y, 2, 2, GOLD)
    p.outline()
    return p


def _caster() -> PixelCanvas:
    p = PixelCanvas()
    p.line((26, 11), (26, 28), GOLD_DARK, 2)
    p.poly(((23, 5), (28, 5), (29, 7), (29, 10), (27, 12), (24, 12), (22, 10), (22, 7)), CREAM)
    p.rect(23, 7, 2, 2, INK)
    p.rect(27, 7, 2, 2, INK)
    p.rect(25, 10, 1, 2, INK)
    p.dot(23, 6, "#fff9e3")
    p.poly(((10, 18), (20, 18), (24, 28), (18, 27), (15, 29), (7, 28)), PURPLE_DARK)
    p.poly(((10, 19), (14, 21), (12, 27), (8, 26)), PURPLE)
    p.poly(((17, 20), (20, 21), (21, 26), (17, 27)), "#7a74b0")
    p.line((13, 21), (13, 26), GOLD)
    p.rect(22, 21, 4, 2, CREAM)
    p.poly(((9, 15), (10, 9), (12, 9), (15, 4), (18, 9), (21, 11), (21, 17), (18, 20), (11, 19)), PURPLE)
    p.poly(((11, 13), (18, 11), (20, 15), (18, 18), (12, 18)), INK)
    p.rect(12, 14, 2, 2, TEAL_LIGHT)
    p.rect(17, 14, 2, 2, TEAL_LIGHT)
    p.poly(((7, 12), (13, 10), (20, 10), (22, 12), (20, 14), (8, 14)), PURPLE_DARK)
    p.line((10, 11), (18, 11), "#d3c3ed")
    p.rect(15, 10, 2, 2, GOLD)
    p.poly(((10, 18), (15, 21), (20, 18), (19, 21), (15, 24), (10, 21)), GOLD_DARK)
    p.line((11, 19), (15, 22), GOLD)
    p.outline()
    return p


def _boss() -> PixelCanvas:
    p = PixelCanvas(40, 40)
    p.poly(((12, 22), (28, 22), (31, 32), (26, 33), (24, 37), (19, 35), (14, 37), (10, 33)), TEAL_DARK)
    p.poly(((12, 23), (18, 25), (16, 34), (12, 34)), TEAL)
    p.poly(((25, 24), (28, 25), (29, 31), (24, 34)), "#3a618c")
    p.poly(((16, 22), (24, 22), (26, 28), (21, 33), (16, 29)), BLUE_LIGHT)
    p.poly(((19, 24), (24, 24), (24, 27), (21, 31), (19, 28)), BLUE)
    p.line((18, 25), (18, 32), GOLD)
    p.line((22, 25), (22, 32), GOLD_DARK)
    p.poly(((12, 16), (15, 13), (25, 13), (29, 17), (27, 23), (23, 25), (16, 23), (12, 21)), CREAM)
    p.poly(((22, 14), (27, 17), (26, 21), (22, 24)), "#c9b793")
    p.rect(16, 17, 3, 1, INK)
    p.rect(23, 17, 2, 1, INK)
    p.line((20, 18), (20, 23), GOLD_DARK)
    p.poly(((10, 3), (15, 6), (19, 1), (24, 6), (30, 3), (28, 8), (29, 10), (11, 10), (12, 8)), GOLD_DARK)
    p.poly(((11, 4), (15, 7), (19, 2), (23, 7), (29, 4), (27, 8), (12, 8)), GOLD)
    p.rect(12, 9, 15, 1, CREAM)
    p.rect(18, 6, 3, 3, TEAL)
    p.dot(18, 6, CREAM)
    p.rect(13, 7, 2, 1, CREAM)
    p.rect(25, 7, 2, 1, CREAM)
    p.poly(((4, 21), (7, 20), (9, 23), (8, 29), (5, 31), (2, 28), (2, 24)), CREAM)
    p.poly(((31, 23), (34, 20), (37, 22), (38, 27), (35, 31), (32, 29)), "#c9b793")
    p.rect(3, 24, 5, 2, GOLD)
    p.rect(33, 24, 4, 2, GOLD)
    p.rect(3, 27, 2, 2, "#e3e6d8")
    p.rect(33, 27, 2, 2, BLUE_LIGHT)
    p.line((13, 31), (15, 33), GOLD)
    p.line((26, 31), (24, 33), GOLD)
    p.outline()
    return p


def generate(save_svg: SaveSvg) -> None:
    """Emit six cohesive originals without changing established source canvases."""
    definitions = (
        ("player", 96, 3, (0, 0), _player, "existing beaked ivory mask, violet pointed hood, teal cape and gold ritual chain"),
        ("chaser", 64, 2, (0, 0), _chaser, "existing tattered ghost; ivory hollow face; teal shroud and separated rag strips"),
        ("rusher", 64, 2, (0, 0), _rusher, "existing low violet beast; angular bone mask and paired pale claws"),
        ("tank", 80, 2, (8, 8), _tank, "broad blue stone guardian; inset teal shield and gold star core"),
        ("caster", 72, 2, (4, 4), _caster, "existing violet ritual mage; hooded eyes; separate carved skull staff"),
        ("boss", 160, 4, (0, 0), _boss, "existing floating-crown priest; ivory idol face and detached hands; teal ceremonial robe"),
    )
    for name, size, scale, offset, author, role in definitions:
        save_svg(f"sprites/{name}.svg", size, size, author().body(scale, offset), f"original pixel sprite; {role}; centered canvas; decorative silhouette")
